"use strict";

const test = require("node:test");
const assert = require("node:assert");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawnSync } = require("child_process");
const parser = require("../src/parser");
const banana = require("../src/banana");
const budget = require("../src/budget");
const fixes = require("../src/fixes/void");
const header = require("../src/header");
const project = require("../src/project");
const rules = require("../src/rules");
const { lua, hasNvim, repo } = require("./lua");

test("rules come from shared/rules.json", () => {
  assert.strictEqual(rules.rules.length, 42);
  assert.match(rules.markdown(rules.byCode["C-L1"], { source: "Banana", message: "two statements" }),
    /^\*\*C-L1 · Code line content\*\* — Major · 🍌👤\n\n› Banana: two statements/);
});

test("Banana's output is parsed like the plugin does", () => {
  const root = "/project";
  const stderr = [
    "src/main.c:3:50: warning: [Banana] [Major] multiple statements on the same line (C-L1)",
    "src/main.c:3:50: warning: [Banana] [Major] multiple statements on the same line (C-L1)",
    "   3 | int a; int b;",
    "src/main.c: warning: [Banana] [Minor] bad header (C-G1)",
    "src/main.c:1:1: warning: [Banana] [Fatal] inline assembly (C-G10)",
    "/project/include/x.h:2:1: warning: [Banana] [Major] something (C-H2)",
    "src/main.c:4:2: error: use of undeclared identifier",
    "1 warning generated.",
  ].join("\n");
  assert.deepStrictEqual(banana.parse(stderr, "src/main.c", root), [
    { path: "/project/src/main.c", line: 2, column: 49, level: "major", message: "multiple statements on the same line", code: "C-L1" },
    { path: "/project/src/main.c", line: 0, column: 0, level: "minor", message: "bad header", code: "C-G1" },
    { path: "/project/src/main.c", line: 0, column: 0, level: "fatal", message: "FATAL: inline assembly", code: "C-G10" },
  ]);
  assert.strictEqual(banana.parse(stderr, undefined, root).length, 4);
});

test("Banana runs through epiclang with the project's flags", async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "epitech-"));
  fs.mkdirSync(path.join(dir, "include"));
  fs.writeFileSync(path.join(dir, "Makefile"), "NAME = x\n");
  fs.writeFileSync(path.join(dir, "main.c"), "int main(void)\n{\n}\n");
  const fake = path.join(dir, "epiclang");
  fs.writeFileSync(fake, `#!/bin/sh\necho "$@" > "${dir}/args"\necho "main.c:1:1: warning: [Banana] [Minor] x (C-G1)" >&2\n`);
  fs.chmodSync(fake, 0o755);
  const entries = await banana.run(path.join(dir, "main.c"), { cmd: fake }).promise;
  assert.deepStrictEqual(entries.map((entry) => entry.code), ["C-G1"]);
  assert.strictEqual(fs.readFileSync(path.join(dir, "args"), "utf8").trim(),
    `-x c -fsyntax-only -I${dir}/include -I${dir} ${dir}/main.c`);
  await assert.rejects(banana.run(path.join(dir, "main.c"), { cmd: "no-such-epiclang" }).promise, { code: "ENOENT" });
  fs.rmSync(dir, { recursive: true });
});

test("budgets and depths match the plugin's", { skip: !hasNvim && "needs nvim" }, async () => {
  await parser.init();
  for (const fixture of ["budget/functions.c", "ts/functions.c"]) {
    const file = path.join(repo, "test", "fixtures", fixture);
    const source = fs.readFileSync(file, "utf8");
    const expected = lua(`require("epitech").setup()
      local budget, ts = require("epitech.budget"), require("epitech.ts")
      local options = require("epitech.config").options.budget
      local source = table.concat(vim.fn.readfile(${JSON.stringify(file)}), "\\n")
      local tree = ts.parse_string(source)
      local result = {}
      for _, fn in ipairs(ts.collect_functions(tree, source)) do
        local chunks = budget.function_chunks(fn, options)
        local depth = {}
        for _, entry in ipairs(budget.depths(fn.body)) do
          depth[#depth + 1] = { (entry.node:range()), budget.depth_chunks(entry, options) }
        end
        result[#result + 1] = { fn.signature_row, chunks, depth, fn.is_static }
      end
      return result`);
    const level = { EpitechBudgetOk: "ok", EpitechBudgetNear: "near", EpitechBudgetOver: "over" };
    const convert = (chunks) => chunks.map(([text, hl]) => ({ text, level: level[hl] }));
    const actual = require("../src/ts").withTree(source, (root) => require("../src/ts").functions(root).map((fn) => [
      fn.signatureRow, budget.functionChunks(fn),
      budget.depths(fn.body).map((entry) => [entry.node.startPosition.row, budget.depthChunks(entry)]),
      fn.isStatic]));
    assert.deepStrictEqual(actual, expected.map(([row, chunks, depth, isStatic]) =>
      [row, convert(chunks), depth.map(([r, c]) => [r, convert(c)]), isStatic]), fixture);
  }
});

test("file budget text", async () => {
  await parser.init();
  const result = budget.analyze("static int a(void)\n{\n    return 0;\n}\n\nint b(void)\n{\n    return 0;\n}\n");
  assert.deepStrictEqual(budget.fileText(result), { text: "functions 2/10 · non-static 1/5", level: "ok" });
});

test("(void) edits skip function pointers", async () => {
  await parser.init();
  const edits = fixes.edits("int f();\nchar *g()\n{\n    return 0;\n}\ntypedef int (*h_t)();\nint (*p)();\n");
  assert.deepStrictEqual(edits.map((edit) => edit.start.row), [0, 1]);
});

test("(void) edits land at the right place after non-ASCII text", async () => {
  await parser.init();
  const source = 'char const *s = "é€😀"; int f();\n';
  const [edit] = fixes.edits(source);
  const { line, character } = require("../src/ts").position([], edit.start);
  assert.strictEqual(source.split("\n")[line].slice(character, character + 2), "()");
});

test("headers and guards", async () => {
  await parser.init();
  const lines = header.headerLines(header.styles.c, "demo", "Main", "2026");
  assert.deepStrictEqual(header.existingHeader(lines.concat([""])), { start: 0, style: header.styles.c, project: "demo", description: "Main" });
  assert.deepStrictEqual(header.newHeader(["#!/bin/sh", "echo"], header.styleFor("shellscript"), "p", "d", "2026"),
    { at: 1, lines: ["##", "## EPITECH PROJECT, 2026", "## p", "## File description:", "## d", "##", ""] });
  const guarded = header.guard(lines.concat(["", "#pragma once", "", "int f(void);"]), "include/my_lib.h");
  assert.strictEqual(guarded.result, "pragma");
  assert.deepStrictEqual(guarded.lines.slice(6), ["", "#ifndef MY_LIB_H_", "    #define MY_LIB_H_", "", "int f(void);", "", "#endif"]);
  assert.strictEqual(header.guard(guarded.lines, "my_lib.h").result, "present");
});

test("headers and guards match the plugin's", { skip: !hasNvim && "needs nvim" }, () => {
  const expected = lua(`local h = require("epitech.header")
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, "/tmp/epitech_guard_test.h")
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "#pragma once", "", "int f(void);", "#if A", "#define B", "#endif" })
    h.insert_guard()
    return vim.api.nvim_buf_get_lines(buf, 0, -1, false)`);
  const actual = header.guard(["#pragma once", "", "int f(void);", "#if A", "#define B", "#endif"], "/tmp/epitech_guard_test.h");
  assert.deepStrictEqual(actual.lines, expected);
});

test("project root, name and include directories", () => {
  const dir = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), "epitech-")));
  const write = (file, text) => {
    fs.mkdirSync(path.dirname(path.join(dir, file)), { recursive: true });
    fs.writeFileSync(path.join(dir, file), text);
  };
  write("bootstrap/Makefile", "NAME = boot\nCPPFLAGS = -I./include -I$(X)\n");
  write("bootstrap/src/a.c", "");
  write("bootstrap/lib/my/Makefile", "NAME = libmy.a\n");
  write("bootstrap/lib/my/b.c", "");
  write("sudo/Makefile", "all:\n\t$(MAKE) -C tools/gen\n");
  write("sudo/tools/gen/Makefile", "NAME = gen\n");
  write("notes/x.c", "");
  spawnSync("git", ["init", "-q"], { cwd: dir });
  assert.strictEqual(project.root(path.join(dir, "bootstrap/src/a.c")), path.join(dir, "bootstrap"));
  assert.strictEqual(project.root(path.join(dir, "bootstrap/lib/my/b.c")), path.join(dir, "bootstrap"));
  assert.strictEqual(project.root(path.join(dir, "sudo/tools/gen/g.c")), path.join(dir, "sudo"));
  assert.strictEqual(project.root(path.join(dir, "notes/x.c")), dir);
  assert.strictEqual(project.name(path.join(dir, "bootstrap")), "boot");
  assert.deepStrictEqual(project.buildIncludeDirs(path.join(dir, "bootstrap")), [path.join(dir, "bootstrap/include")]);
  write("bootstrap/compile_commands.json", JSON.stringify([{ directory: path.join(dir, "bootstrap"), file: "src/a.c",
    command: "cc -I../include -DNAME=\\\"x\\\" -c -o a.o src/a.c" }]));
  assert.deepStrictEqual(project.includeFlags(path.join(dir, "bootstrap"), path.join(dir, "bootstrap/src/a.c")),
    [`-I${dir}/include`, '-DNAME="x"']);
  fs.rmSync(dir, { recursive: true });
});
