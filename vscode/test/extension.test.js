// extension.js against the stand-in vscode module: activation, providers
// and commands, the way VS Code drives them.
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

const hasClangFormat = spawnSync("sh", ["-c", "command -v clang-format"]).status === 0;
const tick = () => new Promise((resolvePromise) => setTimeout(resolvePromise, 50));

const dir = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), "epitech-ext-")));
const context = { subscriptions: [] };

test.before(async () => {
  // A fake epiclang printing a C-F6 report for main.c.
  const fakeEpiclang = path.join(dir, "fake-epiclang");
  fs.writeFileSync(fakeEpiclang, "#!/bin/sh\necho 'main.c:3:5: warning: [Banana] [Major] no void (C-F6)' >&2\n");
  fs.chmodSync(fakeEpiclang, 0o755);
  fake.settings["diagnostics.command"] = fakeEpiclang;
  fs.writeFileSync(path.join(dir, "Makefile"), "NAME = demo\n\nSRC = main.c\n");
  await extension.activate(context);
});

test.after(() => fs.rmSync(dir, { recursive: true, force: true }));

test("registers every command of package.json", () => {
  const manifest = require("../package.json");
  for (const { command } of manifest.contributes.commands) {
    assert.ok(fake.registry.commands[command], command);
  }
});

test("formats a C document like the formatter", { skip: !hasClangFormat && "needs clang-format" }, () => {
  const document = new fake.TextDocument(path.join(dir, "x.c"), "int main(){return 0;}\n");
  const edits = fake.registry.formatting[0].provideDocumentFormattingEdits(document);
  fake.apply(document, edits);
  assert.strictEqual(document.text, formatText("int main(){return 0;}\n", { styleFile: data.styleFile }));
  assert.deepStrictEqual(fake.registry.formatting[0].provideDocumentFormattingEdits(document), [], "idempotent");
});

test("Banana's reports become diagnostics with a hover and a (void) fix", async () => {
  const file = path.join(dir, "main.c");
  fs.writeFileSync(file, "#include <stdio.h>\n\nint main()\n{\n    return 0;\n}\n");
  const document = fake.readDocument(file);
  for (const listener of fake.registry.events.open) {
    listener(document);
  }
  for (let i = 0; i < 40 && fake.vscode.languages.getDiagnostics(document.uri).length === 0; i++) {
    await tick();
  }
  const [diagnostic] = fake.vscode.languages.getDiagnostics(document.uri);
  assert.strictEqual(diagnostic.code, "C-F6");
  assert.strictEqual(diagnostic.source, "Banana");
  assert.deepStrictEqual([diagnostic.range.start.line, diagnostic.range.start.character], [2, 4]);

  const hover = fake.registry.hovers[0].provideHover(document, new fake.vscode.Position(2, 6));
  assert.match(hover.contents.value, /C-F6 · Functions without parameters/);

  const [action] = fake.registry.codeActions[0].provideCodeActions(document, new fake.vscode.Range(2, 0, 2, 0));
  assert.strictEqual(action.title, "Add void (C-F6)");
  assert.deepStrictEqual(action.diagnostics, [diagnostic]);
  fake.apply(document, action.edit.edits);
  assert.match(document.text, /int main\(void\)/);
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
  assert.ok(fake.status.visible);
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

test("creates a new project and a new file", async () => {
  const project = path.join(dir, "fresh");
  fs.mkdirSync(project);
  fake.vscode.window.activeTextEditor = undefined;
  fake.vscode.workspace.workspaceFolders = [{ uri: fake.vscode.Uri.file(project) }];
  fake.registry.inputs.push("my_ls");
  fake.registry.picks.push((items) => [items[4]]);
  await fake.registry.commands["epitech.newProject"]();
  assert.match(fs.readFileSync(path.join(project, "Makefile"), "utf8"), /LDLIBS = -lmy -lm/);
  assert.ok(fs.existsSync(path.join(project, "src", "print_error.c")));
  assert.strictEqual(fake.registry.shown.fsPath, path.join(project, "src", "main.c"));

  fake.registry.inputs.push("src/parse_args.c", "Argument parsing");
  await fake.registry.commands["epitech.newFile"]();
  assert.match(fs.readFileSync(path.join(project, "Makefile"), "utf8"), /src\/print_error.c \\\n\t\tsrc\/parse_args.c\n/);
  assert.match(fs.readFileSync(path.join(project, "src", "parse_args.c"), "utf8"), /\*\* my_ls\n\*\* File description:\n\*\* Argument parsing/);
});

test("explains a rule in a preview", async () => {
  fake.vscode.window.activeTextEditor = undefined;
  fake.registry.picks.push((items) => items.find((item) => item.label === "C-L1"));
  await fake.registry.commands["epitech.explainRule"]();
  assert.strictEqual(fake.registry.executed[0], "markdown.showPreviewToSide");
  const uri = fake.registry.executed[1];
  assert.match(fake.registry.content["epitech-rule"].provideTextDocumentContent(uri), /^\*\*C-L1 · Code line content/);
});
