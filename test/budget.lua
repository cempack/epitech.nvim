local plugin = assert(vim.env.EPITECH_NVIM_DIR, "EPITECH_NVIM_DIR is required")
vim.opt.runtimepath:prepend(plugin)
package.path = plugin .. "/lua/?.lua;" .. plugin .. "/lua/?/init.lua;" .. package.path

local h = dofile(plugin .. "/test/helpers.lua")
local budget = require("epitech.budget")
local config = require("epitech.config")
config.setup()

local function marks(buf, ns)
  local result = {}
  for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
    result[#result + 1] = { mark[2], mark[4].virt_text }
  end
  return result
end

-- §9.3 function budget: 13-, 17-, 20- and 21-line bodies, 0, 1, 4 and 5
-- parameters, and a variadic.
local buf = h.buffer("/tmp/epitech_budget_functions.c", vim.fn.readfile(plugin .. "/test/fixtures/budget/functions.c"))
budget.update(buf)
local OK, NEAR, OVER = "EpitechBudgetOk", "EpitechBudgetNear", "EpitechBudgetOver"
h.assert_equal(marks(buf, budget.ns), {
  { 7, { { "13/20 lines", OK }, { " · ", OK }, { "0/4 args", OK } } },
  { 24, { { "17/20 lines", NEAR }, { " · ", OK }, { "1/4 args", OK } } },
  { 45, { { "20/20 lines", NEAR }, { " · ", OK }, { "4/4 args", OK } } },
  { 69, { { "21/20 lines", OVER }, { " · ", OK }, { "5/4 args", OVER } } },
  { 94, { { "3/20 lines", OK }, { " · ", OK }, { "4/4 args + …", NEAR } } },
}, "function meters")

-- The highlight groups exist and link to standard groups by default.
budget.highlights()
h.assert_equal(vim.api.nvim_get_hl(0, { name = "EpitechBudgetOver" }).link, "DiagnosticError", "EpitechBudgetOver")
h.assert_equal(vim.api.nvim_get_hl(0, { name = "EpitechWinbar" }).link, "WinBar", "EpitechWinbar")

-- Edits update the meter after the debounce.
budget.setup(config.options)
vim.api.nvim_buf_set_lines(buf, 9, 10, false, {})
vim.api.nvim_exec_autocmds("TextChanged", { buffer = buf })
assert(vim.wait(2000, function()
  return marks(buf, budget.ns)[1][2][1][1] == "12/20 lines"
end), "meter updated after an edit")

-- budget.functions = false clears and stops them.
config.setup({ budget = { functions = false } })
budget.update(buf)
h.assert_equal(marks(buf, budget.ns), {}, "no meters when disabled")

print("Epitech budget tests passed")
