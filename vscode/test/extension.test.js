// extension.js against the stand-in vscode module: activation, providers,
// commands, the sidebar, tasks and the Testing view, the way VS Code drives
// them.
"use strict";

const test = require("node:test");
const assert = require("node:assert");
const Module = require("module");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawnSync } = require("child_process");
const { create } = require("./fake-vscode");
const { formatText } = require("../src/format");
const data = require("../src/data");

const fake = create();
const resolve = Module._resolveFilename;
Module._resolveFilename = function (request, ...rest) {
  return request === "vscode" ? "vscode" : resolve.call(this, request, ...rest);
};
require.cache.vscode = { id: "vscode", filename: "vscode", loaded: true, exports: fake.vscode };
const extension = require("../src/extension");

const has = (cmd) => spawnSync("sh", ["-c", `command -v ${cmd}`]).status === 0;
const tick = () => new Promise((resolvePromise) => setTimeout(resolvePromise, 50));
async function until(condition, label) {
  for (let i = 0; i < 80 && !condition(); i++) {
    await tick();
  }
  assert.ok(condition(), label);
}

const dir = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), "epitech-ext-")));
const context = { subscriptions: [], globalState: fake.memento };
const git = (...args) => spawnSync("git", args, { cwd: dir });

test.before(async () => {
  // A fake epiclang printing a C-F6 report for main.c.
  const fakeEpiclang = path.join(dir, "fake-epiclang");
  fs.writeFileSync(fakeEpiclang, "#!/bin/sh\necho 'main.c:3:5: warning: [Banana] [Major] no void (C-F6)' >&2\n");
  fs.chmodSync(fakeEpiclang, 0o755);
  fake.settings["diagnostics.command"] = fakeEpiclang;
  fs.writeFileSync(path.join(dir, "Makefile"), "NAME = demo\n\nSRC = main.c\n\nall:\n\ttrue\n\nre: all\n");
  git("init", "-q");
  fake.registry.openDocument = (uri) => fake.readDocument(uri.fsPath);
  await extension.activate(context);
});

test.after(() => fs.rmSync(dir, { recursive: true, force: true }));

test("registers every command of package.json", () => {
  const manifest = require("../package.json");
  for (const { command } of manifest.contributes.commands) {
    assert.ok(fake.registry.commands[command], command);
  }
});

test("formats a C document like the formatter", { skip: !has("clang-format") && "needs clang-format" }, () => {
  const document = new fake.TextDocument(path.join(dir, "x.c"), "int main(){return 0;}\n");
  const edits = fake.registry.formatting[0].provideDocumentFormattingEdits(document);
  fake.apply(document, edits);
  assert.strictEqual(document.text, formatText("int main(){return 0;}\n", { styleFile: data.styleFile }));
  assert.deepStrictEqual(fake.registry.formatting[0].provideDocumentFormattingEdits(document), [], "idempotent");
});

test("Banana's reports and the hints become diagnostics, with fixes and explanations", async () => {
  const file = path.join(dir, "main.c");
  fs.writeFileSync(file, "#include <stdio.h>\n\nint main()\n{\n    int size = 4096;\n\n    return size;\n}\n");
  const document = fake.readDocument(file);
  for (const listener of fake.registry.events.open) {
    listener(document);
  }
  const banana = () => fake.registry.collections.banana.get(document.uri.toString()) || [];
  await until(() => banana().length > 0, "Banana diagnostics");
  const [diagnostic] = banana();
  assert.strictEqual(diagnostic.code.value, "C-F6");
  assert.strictEqual(diagnostic.source, "Banana");
  assert.match(String(diagnostic.code.target), /^command:epitech.explainRule/);
  const hints = fake.registry.collections.epitech.get(document.uri.toString()) || [];
  assert.deepStrictEqual(hints.map((hint) => hint.code.value), ["C-G9"]);
  assert.strictEqual(hints[0].severity, fake.vscode.DiagnosticSeverity.Hint);

  const hover = fake.registry.hovers[0].provideHover(document, new fake.vscode.Position(2, 6));
  assert.match(hover.contents.value, /C-F6 · Functions without parameters/);

  const actions = fake.registry.codeActions[0].provideCodeActions(document, new fake.vscode.Range(2, 0, 2, 0),
    { diagnostics: [diagnostic] });
  assert.deepStrictEqual(actions.map((action) => action.title),
    ["Add void (C-F6)", "Explain C-F6: Functions without parameters"]);
  assert.deepStrictEqual(actions[0].diagnostics, [diagnostic]);
  fake.apply(document, actions[0].edit.edits);
  assert.match(document.text, /int main\(void\)/);

  const macro = fake.registry.codeActions[0].provideCodeActions(document, new fake.vscode.Range(4, 0, 4, 0),
    { diagnostics: [] });
  assert.strictEqual(macro[0].title, "Extract 4096 into a macro…");
  assert.deepStrictEqual(macro[0].command.arguments.slice(1), [4, 15, "4096"]);
});

test("extracting a macro defines it in the project header and includes it", async () => {
  fs.mkdirSync(path.join(dir, "include"), { recursive: true });
  fs.writeFileSync(path.join(dir, "include", "demo.h"), "#ifndef DEMO_H_\n    #define DEMO_H_\n\n#endif\n");
  fs.writeFileSync(path.join(dir, "Makefile"), "NAME = demo\nCPPFLAGS = -I./include\n\nSRC = main.c\n\nall:\n\ttrue\n");
  git("add", "-A");
  const file = path.join(dir, "main.c");
  fs.writeFileSync(file, "int main(void)\n{\n    char buffer[4096];\n\n    return buffer[0];\n}\n");
  fake.registry.inputs.push("BUFFER_SIZE");
  fake.registry.applied = [];
  await fake.registry.commands["epitech.extractMacro"](fake.vscode.Uri.file(file), 2, 16, "4096");
  const [edit] = fake.registry.applied;
  const texts = edit.edits.map((change) => `${path.basename(change.uri.fsPath)}:${change.text}`);
  assert.deepStrictEqual(texts, ["main.c:BUFFER_SIZE",
    "demo.h:#ifndef DEMO_H_\n    #define DEMO_H_\n    #define BUFFER_SIZE 4096\n\n#endif\n",
    'main.c:#include "demo.h"\n']);
});

test("Makefiles get their checks and fixes", () => {
  const document = new fake.TextDocument(path.join(dir, "Makefile"), "NAME = demo  \n", "makefile");
  for (const listener of fake.registry.events.open) {
    listener(document);
  }
  const codes = (fake.registry.collections.epitech.get(document.uri.toString()) || []).map((d) => d.code.value || d.code);
  assert.deepStrictEqual(codes, ["C-G1", "C-G7"]);
  const titles = fake.registry.codeActions[0].provideCodeActions(document, new fake.vscode.Range(0, 0, 0, 0),
    { diagnostics: [] }).map((action) => action.title);
  assert.deepStrictEqual(titles, ["Remove trailing spaces (C-G7)", "Add the Epitech header (C-G1)"]);
});

test("meters and the file budget follow the active editor", () => {
  const document = new fake.TextDocument(path.join(dir, "meter.c"),
    "static int f(int a, int b)\n{\n    if (a) {\n        while (b) {\n            b--;\n        }\n    }\n    return a;\n}\n");
  const editor = fake.editor(document);
  fake.vscode.window.activeTextEditor = editor;
  for (const listener of fake.registry.events.active) {
    listener(editor);
  }
  const texts = fake.registry.decorations.get(document.fileName).map((item) => item.renderOptions.after.contentText);
  assert.deepStrictEqual(texts, ["6/20 lines", " · ", "2/4 args", "depth 2"]);
  assert.strictEqual(fake.status.text, "$(symbol-function) functions 1/10 · non-static 0/5");
});

test("ignoring a file silences it", async () => {
  const file = path.join(dir, "meter.c");
  const editor = fake.vscode.window.activeTextEditor;
  assert.strictEqual(editor.document.fileName, file);
  await fake.registry.commands["epitech.ignoreFile"]();
  fake.registry.events.active.forEach((listener) => listener(editor));
  assert.deepStrictEqual(fake.registry.decorations.get(file), []);
  await fake.registry.commands["epitech.unignoreFile"]();
  fake.registry.events.active.forEach((listener) => listener(editor));
  assert.ok(fake.registry.decorations.get(file).length > 0);
});

test("inserts a header and a guard", async () => {
  const document = new fake.TextDocument(path.join(dir, "include", "my_lib.h"), "#pragma once\n\nint f(void);\n");
  fake.vscode.window.activeTextEditor = fake.editor(document);
  fake.registry.inputs.push("demo", "Library");
  await fake.registry.commands["epitech.insertHeader"]();
  assert.deepStrictEqual(document.text.split("\n").slice(0, 7), ["/*", `** EPITECH PROJECT, ${new Date().getFullYear()}`,
    "** demo", "** File description:", "** Library", "*/", ""]);
  await fake.registry.commands["epitech.insertGuard"]();
  assert.deepStrictEqual(document.text.split("\n").slice(6), ["", "#ifndef MY_LIB_H_", "    #define MY_LIB_H_", "",
    "int f(void);", "", "#endif", ""]);
});

test("the project check fills the sidebar by rule", async () => {
  fs.writeFileSync(path.join(dir, "main.o"), "");
  fs.writeFileSync(path.join(dir, "BadName.c"), "int f(void)\n{\n    return 0;\n}\n");
  git("add", "-A");
  fake.vscode.window.activeTextEditor = undefined;
  fake.vscode.workspace.workspaceFolders = [{ uri: fake.vscode.Uri.file(dir) }];
  await fake.registry.commands["epitech.checkProject"]();
  const tree = fake.registry.trees["epitech.checkView"];
  const rulesShown = tree.getChildren().map((node) => node.code);
  for (const code of ["C-O1", "C-F6", "C-O4"]) {
    assert.ok(rulesShown.includes(code), `${code} in ${rulesShown}`);
  }
  const o1 = tree.getChildren().find((node) => node.code === "C-O1");
  const item = tree.getTreeItem(tree.getChildren(o1)[0]);
  assert.strictEqual(item.description, "main.o:1");
  assert.match(fake.registry.checkStatus.text, /major/);
});

test("make targets become tasks", () => {
  fs.writeFileSync(path.join(dir, "Makefile"), "NAME = demo\n\nall:\n\ttrue\n\nre: fclean all\n\nfclean:\n\ttrue\n");
  const tasks = fake.registry.taskProviders.epitech.provideTasks();
  assert.deepStrictEqual(tasks.map((task) => task.name), ["make", "make re", "make fclean"]);
  assert.deepStrictEqual(tasks[1].execution.args, ["re"]);
  assert.deepStrictEqual(tasks[1].problemMatchers, ["$gcc"]);
});

test("Criterion tests show up in the Testing view and run", async () => {
  const project = path.join(dir, "tested");
  fs.mkdirSync(path.join(project, "tests"), { recursive: true });
  const testFile = path.join(project, "tests", "test_demo.c");
  fs.writeFileSync(testFile, "#include <criterion/criterion.h>\n\nTest(demo, works)\n{\n}\n\nTest(demo, breaks)\n{\n}\n");
  // A stand-in for a Criterion binary: one failure, one pass.
  fs.writeFileSync(path.join(project, "Makefile"), [
    "unit_tests:", "\tprintf '#!/bin/sh\\n' > unit_tests",
    "\tprintf 'echo \"[RUN ] demo::works\"\\necho \"[PASS] demo::works: (0.00s)\"\\n' >> unit_tests",
    "\tprintf 'echo \"[----] tests/test_demo.c:8: Assertion Failed\"\\necho \"[FAIL] demo::breaks: (0.00s)\"\\n' >> unit_tests",
    "\tprintf 'echo \"[====] Synthesis: Tested: 2 | Passing: 1 | Failing: 1 | Crashing: 0\"\\n' >> unit_tests",
    "\tchmod +x unit_tests", "", "fclean:", "\trm -f unit_tests", ""].join("\n"));
  fake.registry.files = [testFile];
  const [controller] = fake.registry.controllers;
  await controller.resolveHandler();
  const [fileItem] = [...controller.items].map(([, item]) => item);
  assert.deepStrictEqual([...fileItem.children].map(([, item]) => item.label), ["demo::works", "demo::breaks"]);
  const run = controller.profiles.find((profile) => profile.name === "Run");
  await run.handler({ include: [fileItem] }, { isCancellationRequested: false });
  const results = fake.registry.lastRun.results;
  assert.strictEqual(results["demo::works"], "passed");
  const [message] = results["demo::breaks"].failed;
  assert.strictEqual(message.message, "Assertion Failed");
  assert.strictEqual(message.location.range.line, 7);
  assert.ok(!fs.existsSync(path.join(project, "unit_tests")), "make fclean ran after the tests");
});

test("explains a rule in a preview", async () => {
  fake.vscode.window.activeTextEditor = undefined;
  fake.registry.picks.push((items) => items.find((item) => item.label === "C-L1"));
  await fake.registry.commands["epitech.explainRule"]();
  assert.strictEqual(fake.registry.executed[0], "markdown.showPreviewToSide");
  assert.match(fake.registry.content["epitech-rule"].provideTextDocumentContent(fake.registry.executed[1]),
    /^\*\*C-L1 · Code line content/);
  await fake.registry.commands["epitech.explainRule"]("C-F4");
  assert.strictEqual(fake.registry.executed[1].path, "C-F4.md");
});

test("creates a new project and a new file", async () => {
  const project = path.join(dir, "fresh");
  fs.mkdirSync(project);
  fake.vscode.window.activeTextEditor = undefined;
  fake.vscode.workspace.workspaceFolders = [{ uri: fake.vscode.Uri.file(project) }];
  fake.registry.inputs.push("my_ls");
  fake.registry.picks.push((items) => [items[4]]);
  await fake.registry.commands["epitech.newProject"]();
  assert.match(fs.readFileSync(path.join(project, "Makefile"), "utf8"), /LDLIBS = -lmy -lm/);
  assert.ok(fs.existsSync(path.join(project, ".git")), "git init");
  assert.strictEqual(fake.registry.shown.fsPath, path.join(project, "src", "main.c"));
  fake.registry.inputs.push("src/parse_args.c", "Argument parsing");
  await fake.registry.commands["epitech.newFile"]();
  assert.match(fs.readFileSync(path.join(project, "Makefile"), "utf8"), /src\/print_error.c \\\n\t\tsrc\/parse_args.c\n/);
});

test("a new file goes to the project it's typed into, in a repository holding several", async () => {
  const repo = path.join(dir, "mysudo");
  for (const sub of ["bootstrap", "sudo"]) {
    fs.mkdirSync(path.join(repo, sub, "src"), { recursive: true });
    fs.writeFileSync(path.join(repo, sub, "Makefile"), `NAME = ${sub}\n\nSRC = src/main.c\n`);
  }
  spawnSync("git", ["init", "-q"], { cwd: repo });
  fake.vscode.window.activeTextEditor = undefined;
  fake.vscode.workspace.workspaceFolders = [{ uri: fake.vscode.Uri.file(repo) }];
  // Two projects and no file open: it asks which one.
  fake.registry.picks.push((items) => {
    assert.deepStrictEqual(items.map((item) => item.label), ["bootstrap", "sudo"]);
    return items[0];
  });
  fake.registry.inputs.push("src/exec.c", "Execution");
  await fake.registry.commands["epitech.newFile"]();
  assert.ok(fs.existsSync(path.join(repo, "bootstrap", "src", "exec.c")));
  assert.match(fs.readFileSync(path.join(repo, "bootstrap", "Makefile"), "utf8"), /src\/exec.c/);
  assert.match(fs.readFileSync(path.join(repo, "bootstrap", "src", "exec.c"), "utf8"), /\*\* bootstrap\n/);
  // A file of one project open, a path typed into the other: the other's.
  fake.vscode.window.activeTextEditor = fake.editor(fake.readDocument(path.join(repo, "bootstrap", "Makefile")));
  fake.registry.inputs.push("../sudo/src/run.c", "Run");
  await fake.registry.commands["epitech.newFile"]();
  assert.match(fs.readFileSync(path.join(repo, "sudo", "Makefile"), "utf8"), /SRC = src\/main.c \\\n\t\tsrc\/run.c/);
  assert.doesNotMatch(fs.readFileSync(path.join(repo, "bootstrap", "Makefile"), "utf8"), /run.c/);
});
