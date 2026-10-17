local plugin = assert(vim.env.EPITECH_NVIM_DIR, "EPITECH_NVIM_DIR is required")
vim.opt.runtimepath:prepend(plugin)
package.path = plugin .. "/lua/?.lua;" .. plugin .. "/lua/?/init.lua;" .. package.path

local h = dofile(plugin .. "/test/helpers.lua")
local explain = require("epitech.explain")
local rules = require("epitech.rules")

local c_l1 = rules.by_code["C-L1"]
h.assert_equal(explain.lines(c_l1), {
  "C-L1 · Code line content                    Major · 🍌👤",
  "One statement per line; a for loop's three parts are the",
  "only exception. No assignment inside a condition, no",
  "`a && f();` shortcuts.",
  "✗",
  "```c",
  "a++; b++;",
  "if ((fd = open(path, O_RDONLY)) == -1) {",
  "```",
  "✓",
  "```c",
  "a++;",
  "b++;",
  "fd = open(path, O_RDONLY);",
  "if (fd == -1) {",
  "```",
}, "float lines without a diagnostic")

local diagnostic = { source = "Banana", message = "multiple statements on the same line", code = "C-L1" }
local with_diagnostic = explain.lines(c_l1, diagnostic)
h.assert_equal(with_diagnostic[2], "› Banana: multiple statements on the same line", "diagnostic line")
h.assert_equal(#with_diagnostic, 17, "one more line with a diagnostic")
h.assert_equal(explain.lines(rules.by_code["C-O2"])[4], "```text", "examples in their own language")
h.assert_equal(explain.lines(rules.by_code["C-G10"])[1], "C-G10 · Inline assembly                       Fatal · 🍌",
  "fatal Banana rule header")

-- :EpitechRules lists all 42 rules.
local picked
vim.ui.select = function(items, opts, on_choice)
  picked = { items = items, opts = opts }
  on_choice(nil)
end
explain.pick()
h.assert_equal(#picked.items, 42, "the picker gets every rule")
h.assert_equal(picked.opts.format_item(c_l1), "C-L1   Code line content  (Major)", "picker item text")
h.assert_equal(picked.opts.format_item(rules.by_code["C-G10"]), "C-G10  Inline assembly  (Fatal)", "two-digit code")

local function float_lines()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(win).relative ~= "" then
      local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false)
      vim.api.nvim_win_close(win, true)
      return lines
    end
  end
end

-- Inline code is never split across lines.
h.assert_equal(explain.lines(c_l1)[4], "`a && f();` shortcuts.", "inline code kept whole")

-- Explaining from the cursor.
local buf = h.buffer("/tmp/epitech_explain.c", { "int a; int b;", "int main();", "", "int c;" })
local ns = vim.api.nvim_create_namespace("epitech.test")
vim.diagnostic.set(ns, buf, {
  { lnum = 0, col = 0, end_col = 6, message = "multiple statements", code = "C-L1", source = "Banana" },
  { lnum = 0, col = 7, end_col = 13, message = "global variable", code = "C-G4", source = "Banana" },
  { lnum = 1, col = 0, message = "empty parameter list", code = "C-F6", source = "Banana" },
  { lnum = 3, col = 0, message = "not a rule", code = "unused-variable", source = "clangd" },
})

vim.api.nvim_win_set_cursor(0, { 2, 4 })
explain.explain()
h.assert_equal(float_lines(), explain.lines(rules.by_code["C-F6"], { source = "Banana", message = "empty parameter list" }),
  "the only code on the line")

vim.api.nvim_win_set_cursor(0, { 1, 9 })
explain.explain()
h.assert_equal(float_lines()[1]:sub(1, 4), "C-G4", "the code under the cursor")

local offered
vim.ui.select = function(items, opts, on_choice)
  offered = vim.tbl_map(opts.format_item, items)
  on_choice(items[1])
end
vim.diagnostic.set(ns, buf, {
  { lnum = 0, col = 0, end_col = 2, message = "multiple statements", code = "C-L1", source = "Banana" },
  { lnum = 0, col = 0, end_col = 2, message = "global variable", code = "C-G4", source = "Banana" },
})
vim.api.nvim_win_set_cursor(0, { 1, 9 })
explain.explain()
h.assert_equal(offered, {
  "C-L1   Code line content  (Major) · multiple statements",
  "C-G4   Global variables  (Major) · global variable",
}, "a choice between the codes on the line")
h.assert_equal(float_lines()[1]:sub(1, 4), "C-L1", "the chosen rule")

-- No rule on the line: the picker. Other tools' codes are ignored.
picked = nil
vim.ui.select = function(items, opts, on_choice)
  picked = items
  on_choice(nil)
end
vim.api.nvim_win_set_cursor(0, { 4, 0 })
explain.explain()
h.assert_equal(#picked, 42, "picker when no rule is on the line")

-- :EpitechExplain with a code, and the setup() wiring.
require("epitech").setup()
vim.cmd("EpitechExplain c-f6")
h.assert_equal(float_lines()[1]:sub(1, 4), "C-F6", ":EpitechExplain <code>")
h.assert_equal(explain.complete("C-G1"), { "C-G1", "C-G10" }, "code completion")
assert(vim.api.nvim_get_commands({ builtin = false }).EpitechRules, ":EpitechRules")
h.assert_equal(vim.fn.maparg("<leader>cE", "n", false, true).desc, "Epitech Explain Rule", "<leader>cE")

print("Epitech explainer tests passed")
