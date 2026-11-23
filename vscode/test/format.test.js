// The JS formatter against the Lua one (lua/epitech/format.lua, run through
// nvim) on every C fixture of the repository, as is and scrambled. Skipped
// without nvim or clang-format.
"use strict";

const test = require("node:test");
const assert = require("node:assert");
const { spawnSync } = require("child_process");
const fs = require("fs");
const path = require("path");
const parser = require("../src/parser");
const { formatText } = require("../src/format");

const repo = path.join(__dirname, "..", "..");
const styleFile = path.join(repo, "epitech.clang-format");
const formatLua = path.join(repo, "lua", "epitech", "format.lua");
const has = (cmd) => spawnSync("sh", ["-c", `command -v ${cmd}`]).status === 0;

function files(dir) {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      return files(full);
    }
    return /\.[ch]$/.test(entry.name) ? [full] : [];
  });
}

// Indentation stripped, trailing spaces, doubled blank lines.
function scramble(text) {
  return text.split("\n").map((line) => line.replace(/^\s+/, "") + (line ? "  " : "\n")).join("\n");
}

function luaFormat(text) {
  const result = spawnSync("nvim", ["--clean", "--headless", "-u", "NONE", "-c", "set filetype=c",
    "-c", `lua dofile(${JSON.stringify(formatLua)}).format_stdout()`, "-c", "qa!", "-"],
  { input: text, encoding: "utf8" });
  assert.strictEqual(result.status, 0, result.stderr);
  return result.stdout;
}

const inputs = [
  ...files(path.join(repo, "test", "fixtures")),
  ...files(path.join(repo, "templates")),
  ...files(path.join(__dirname, "fixtures")),
];

test("formats like the Neovim plugin", { skip: !(has("nvim") && has("clang-format")) && "needs nvim and clang-format" },
  async (t) => {
    await parser.init();
    for (const file of inputs) {
      const text = fs.readFileSync(file, "utf8");
      for (const [label, input] of [["as is", text], ["scrambled", scramble(text)]]) {
        await t.test(`${path.relative(repo, file)} (${label})`, () => {
          assert.strictEqual(formatText(input, { styleFile }), luaFormat(input));
        });
      }
    }
  });

test("formatting is idempotent", { skip: !has("clang-format") && "needs clang-format" }, async () => {
  await parser.init();
  const text = fs.readFileSync(path.join(__dirname, "fixtures", "stress.c"), "utf8");
  const once = formatText(scramble(text), { styleFile });
  assert.strictEqual(formatText(once, { styleFile }), once);
});
