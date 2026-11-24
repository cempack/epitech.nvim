// The hints and the Makefile checks against the Neovim plugin's, on every C
// file of the repository.
"use strict";

const test = require("node:test");
const assert = require("node:assert");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawnSync } = require("child_process");
const parser = require("../src/parser");
const hints = require("../src/hints");
const staticHint = require("../src/hints/static");
const makefile = require("../src/makefile");
const { lua, hasNvim, repo } = require("./lua");

function files(dir) {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const full = path.join(dir, entry.name);
    return entry.isDirectory() ? files(full) : /\.[ch]$/.test(entry.name) ? [full] : [];
  });
}

const key = (hint) => [hint.line, hint.column, hint.endColumn, hint.code, hint.message].join("|");

test("hints match the Neovim plugin's", { skip: !hasNvim && "needs nvim" }, async () => {
  await parser.init();
  const inputs = [...files(path.join(repo, "test", "fixtures")), ...files(path.join(repo, "templates")),
    ...files(path.join(__dirname, "fixtures"))];
  const expected = lua(`require("epitech").setup({ fixes = { enabled = false } })
    local hints = require("epitech.hints")
    local result = {}
    for _, file in ipairs(vim.json.decode(${JSON.stringify(JSON.stringify(inputs))})) do
      local src = table.concat(vim.fn.readfile(file), "\\n")
      local list = {}
      for _, d in ipairs(hints.collect(src, file, { static_used = {} })) do
        list[#list + 1] = table.concat({ d.lnum, d.col, d.end_col or d.col, d.code, d.message }, "|")
      end
      table.sort(list)
      result[file] = list
    end
    return result`);
  let total = 0;
  for (const file of inputs) {
    const source = fs.readFileSync(file, "utf8").replace(/\n$/, "");
    const actual = hints.collect(source, file, { staticUsed: new Set() }).map(key).sort();
    assert.deepStrictEqual(actual, expected[file] || [], path.relative(repo, file));
    total += actual.length;
  }
  assert.ok(total > 50, `only ${total} hints compared`);
});

test("Makefile checks match the plugin's", { skip: !hasNvim && "needs nvim" }, () => {
  const header = "##\n## EPITECH PROJECT, 2026\n## demo\n## File description:\n## Makefile\n##\n";
  const texts = [
    header + "NAME = demo\n",
    "NAME = demo  \nSRC = " + "a.c ".repeat(25) + "\n\n\n",
    "\n" + header + "all:\r\n\t$(CC) -o x " + "y.c ".repeat(18) + "\n",
    header + "NAME = x",
    "",
  ];
  const expected = lua(`local m = require("epitech.hints.makefile")
    local result = {}
    for i, text in ipairs(vim.json.decode(${JSON.stringify(JSON.stringify(texts))})) do
      local list = {}
      for _, d in ipairs(m.run(text, "Makefile", { tab_width = 8 })) do
        local level = ({ "major", "minor", "info" })[d.severity]
        list[#list + 1] = table.concat({ d.lnum, d.col, d.end_col, level, d.code, d.message }, "|")
      end
      result[i] = list
    end
    return result`);
  texts.forEach((text, i) => {
    const actual = makefile.check(text).map((d) => [d.line, d.column, d.endColumn, d.level, d.code, d.message].join("|"));
    assert.deepStrictEqual(actual, expected[i], JSON.stringify(text.slice(0, 30)));
  });
});

test("the static hint asks git which functions other files use", async () => {
  await parser.init();
  const dir = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), "epitech-")));
  fs.writeFileSync(path.join(dir, "a.c"), "int helper(void)\n{\n    return 1;\n}\n\nint run(void)\n{\n    return helper();\n}\n");
  fs.writeFileSync(path.join(dir, "b.c"), "int run(void);\n\nint main(void)\n{\n    return run();\n}\n");
  spawnSync("git", ["init", "-q"], { cwd: dir });
  spawnSync("git", ["add", "-A"], { cwd: dir });
  const used = await staticHint.usedElsewhere(dir, path.join(dir, "a.c"), ["helper", "run"]);
  assert.deepStrictEqual([...used], ["run"]);
  const found = hints.collect(fs.readFileSync(path.join(dir, "a.c"), "utf8"), path.join(dir, "a.c"),
    { root: dir, staticUsed: used }).filter((hint) => hint.code === "C-A4");
  assert.deepStrictEqual(found.map((hint) => hint.line), [0]);
  assert.strictEqual(await staticHint.usedElsewhere(os.tmpdir(), path.join(os.tmpdir(), "x.c"), ["f"]), undefined);
  fs.rmSync(dir, { recursive: true });
});

test("dedup drops what Banana reports on the same line", () => {
  const list = [{ line: 2, code: "C-V1" }, { line: 3, code: "C-V1" }, { line: 2, code: "C-F2", keep: true }];
  assert.deepStrictEqual(hints.dedup(list, [{ line: 2, code: "C-V1" }, { line: 2, code: "C-F2" }]),
    [{ line: 3, code: "C-V1" }, { line: 2, code: "C-F2", keep: true }]);
});
