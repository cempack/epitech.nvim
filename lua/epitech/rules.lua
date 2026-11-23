-- The Epitech C Coding Style v7.1 rules, in the PDF's order. The data lives
-- in shared/rules.json, which the VS Code extension (vscode/) reads too:
-- edit it there. The summaries and examples are short paraphrases, never the
-- PDF's own text. `notes` holds what calibration against the real epiclang
-- measured (§10 of CLAUDE.md, test/calibrate.lua), absent when nothing was.
-- `lang` is the examples' language when they aren't C.
local M = {}

local module_path = debug.getinfo(1, "S").source:sub(2)
local plugin_dir = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(module_path)))
local data = vim.json.decode(table.concat(vim.fn.readfile(plugin_dir .. "/shared/rules.json"), "\n"))

M.rules = data.rules

M.by_code = {}
for _, rule in ipairs(M.rules) do
  M.by_code[rule.code] = rule
end

-- The constructs the coding style lists as unsupported by Banana.
M.extensions = data.extensions

M.severity_rank = data.severity_rank

return M
