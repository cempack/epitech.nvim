// The fixes against the Neovim plugin's: for every row of every C file of
// the repository, the same actions with the same results; and each fixture's
// expected output.
"use strict";

const test = require("node:test");
const assert = require("node:assert");
const fs = require("fs");
const path = require("path");
const parser = require("../src/parser");
const fixes = require("../src/fixes");
const { apply } = require("../src/fixes/edits");
const { formatText } = require("../src/format");
const data = require("../src/data");
const { lua, hasNvim, repo } = require("./lua");

const formatOptions = { styleFile: data.styleFile };
const RULES = ["C-L5", "C-L1", "C-C1", "C-F6", "C-A4", "C-A1"];

function files(dir) {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const full = path.join(dir, entry.name);
    return entry.isDirectory() ? files(full) : /\.[ch]$/.test(entry.name) ? [full] : [];
  });
}

const inputs = [...files(path.join(repo, "test", "fixtures")), ...files(path.join(__dirname, "fixtures"))];

test("every action matches the Neovim plugin's", { skip: !hasNvim && "needs nvim" }, async () => {
  await parser.init();
  const expected = lua(`require("epitech").setup()
    require("epitech.project").root = function() return ${JSON.stringify(repo)} end
    local fixes, static = require("epitech.fixes"), require("epitech.hints.static")
    local wanted = vim.json.decode(${JSON.stringify(JSON.stringify(RULES))})
    local result = {}
    for _, file in ipairs(vim.json.decode(${JSON.stringify(JSON.stringify(inputs))})) do
      local lines = vim.fn.readfile(file)
      local buf = vim.api.nvim_create_buf(true, false)
      vim.api.nvim_buf_set_name(buf, file)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      vim.bo[buf].filetype = "c"
      static.cache[file] = { tick = vim.api.nvim_buf_get_changedtick(buf), used = {} }
      local list = {}
      for row = 0, #lines - 1 do
        local range = { start = { line = row, character = 0 }, ["end"] = { line = row, character = 0 } }
        for _, action in ipairs(fixes.actions(buf, range)) do
          if action.edit and vim.list_contains(wanted, action.data.rule) then
            local scratch = vim.api.nvim_create_buf(false, true)
            vim.api.nvim_buf_set_lines(scratch, 0, -1, false, lines)
            vim.lsp.util.apply_text_edits(action.edit.changes[vim.uri_from_bufnr(buf)], scratch, "utf-8")
            list[#list + 1] = row .. "|" .. action.title .. "|" .. table.concat(vim.api.nvim_buf_get_lines(scratch, 0, -1, false), "\\n")
            vim.api.nvim_buf_delete(scratch, { force = true })
          end
        end
      end
      vim.api.nvim_buf_delete(buf, { force = true })
      result[file] = list
    end
    return result`);
  let total = 0;
  for (const file of inputs) {
    const source = fs.readFileSync(file, "utf8").replace(/\n$/, "");
    const rows = source.split("\n").length;
    const actual = [];
    for (let row = 0; row < rows; row++) {
      for (const action of fixes.actions(source, { start: row, end: row },
        { file, projectRoot: repo, staticUsed: new Set(), formatOptions })) {
        if (RULES.includes(action.rule)) {
          actual.push(`${row}|${action.title}|${apply(source, action.edits)}`);
        }
      }
    }
    assert.deepStrictEqual(actual, expected[file] || [], path.relative(repo, file));
    total += actual.length;
  }
  assert.ok(total > 25, `only ${total} actions compared`);
});

test("refused fixes explain themselves like the plugin's", { skip: !hasNvim && "needs nvim" }, async () => {
  await parser.init();
  const expected = lua(`require("epitech").setup()
    local fixes, ts = require("epitech.fixes"), require("epitech.ts")
    local result = {}
    for _, file in ipairs(vim.json.decode(${JSON.stringify(JSON.stringify(inputs))})) do
      local src = table.concat(vim.fn.readfile(file), "\\n")
      local list = {}
      for _, d in ipairs(fixes.hints(src, file, { tree = ts.parse_string(src) })) do
        if d.code ~= "C-H1" then
          list[#list + 1] = table.concat({ d.lnum, d.col, d.end_col, d.code, d.message }, "|")
        end
      end
      table.sort(list)
      result[file] = list
    end
    return result`);
  for (const file of inputs) {
    const source = fs.readFileSync(file, "utf8").replace(/\n$/, "");
    const actual = fixes.hints(source, { file }).map((d) => [d.line, d.column, d.endColumn, d.code, d.message].join("|"))
      .sort();
    assert.deepStrictEqual(actual, expected[file] || [], path.relative(repo, file));
  }
});

test("fixture results are what the fixtures expect, and stay formatted", async () => {
  await parser.init();
  const dir = path.join(repo, "test", "fixtures", "fixes");
  let checked = 0;
  for (const fix of ["decl", "one_stmt", "switch", "void"]) {
    for (const name of fs.readdirSync(path.join(dir, fix)).filter((f) => f.endsWith(".before.c"))) {
      const before = fs.readFileSync(path.join(dir, fix, name), "utf8").replace(/\n$/, "");
      const after = fs.readFileSync(path.join(dir, fix, name.replace(".before.", ".after.")), "utf8");
      const results = [];
      for (let row = 0; row < before.split("\n").length; row++) {
        fixes.actions(before, { start: row, end: row }, { formatOptions })
          .filter((action) => action.edits).forEach((action) => results.push(apply(before, action.edits) + "\n"));
      }
      assert.ok(results.includes(after), `${fix}/${name}: no action gives the .after.c`);
      assert.strictEqual(formatText(after, formatOptions), after, `${fix}/${name}: formatter changes the result`);
      checked++;
    }
  }
  assert.ok(checked >= 20);
});
