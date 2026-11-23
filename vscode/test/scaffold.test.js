"use strict";

const test = require("node:test");
const assert = require("node:assert");
const fs = require("fs");
const os = require("os");
const path = require("path");
const parser = require("../src/parser");
const scaffold = require("../src/scaffold");
const { lua, hasNvim } = require("./lua");

const cases = [
  ["my_ls", []],
  ["my_hunter", ["-lcsfml-graphics", "-lcsfml-window", "-lcsfml-system", "-lcsfml-audio", "-lm", "-lncurses"]],
  ["libmy.a", ["-lm"]],
];

test("new projects match the Neovim plugin's", { skip: !hasNvim && "needs nvim" }, async () => {
  await parser.init();
  for (const [name, ldlibs] of cases) {
    const expected = lua(`require("epitech").setup()
      return require("epitech.scaffold").templates(${JSON.stringify(name)}, ${JSON.stringify(ldlibs).replace(/^\[/, "{").replace(/\]$/, "}")})`);
    assert.deepStrictEqual(scaffold.templates(name, ldlibs), expected, name);
  }
  const options = { ...scaffold.DEFAULTS, cflags: "-Wall -Wextra", debug_cflags: "", error_file: false, cc: "gcc" };
  const expected = lua(`require("epitech").setup({ scaffold = { cflags = "-Wall -Wextra", debug_cflags = "",
    error_file = false, cc = "gcc" } }) return require("epitech.scaffold").templates("demo")`);
  assert.deepStrictEqual(scaffold.templates("demo", undefined, options), expected, "options");
});

test("library flags are deduplicated in order", () => {
  assert.deepStrictEqual(scaffold.libraryFlags([1, 0]),
    ["-lcsfml-graphics", "-lcsfml-window", "-lcsfml-system", "-lcsfml-audio"]);
});

test("addSource follows the Makefile's layout", () => {
  assert.deepStrictEqual(scaffold.addSource(["SRC = a.c \\", "\t\tb.c", "", "OBJ = x"], "c.c").lines,
    ["SRC = a.c \\", "\t\tb.c \\", "\t\tc.c", "", "OBJ = x"]);
  assert.deepStrictEqual(scaffold.addSource(["SRC += a.c", "NAME = x"], "b.c").lines,
    ["SRC += a.c", "SRC += b.c", "NAME = x"]);
  assert.deepStrictEqual(scaffold.addSource(["SRC = a.c"], "a.c").lines, ["SRC = a.c"]);
  assert.match(scaffold.addSource(["SRC = $(wildcard src/*.c)"], "b.c").error, /wildcard/);
  assert.match(scaffold.addSource(["NAME = x"], "b.c").error, /No SRC/);
  assert.strictEqual(scaffold.sourceVariable("tests/t.c", ["TEST_SRC = a.c"]), "TEST_SRC");
});

test("create refuses an existing Makefile", async () => {
  await parser.init();
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "epitech-"));
  assert.ok(scaffold.create(dir, "demo", []).includes("src/main.c"));
  assert.strictEqual(scaffold.create(dir, "demo", []), undefined);
  fs.rmSync(dir, { recursive: true });
});
