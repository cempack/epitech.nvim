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
-- parameters, and a variadic, which counts as a parameter like Banana counts
-- it.
local buf = h.buffer("/tmp/epitech_budget_functions.c", vim.fn.readfile(plugin .. "/test/fixtures/budget/functions.c"))
budget.update(buf)
local OK, NEAR, OVER = "EpitechBudgetOk", "EpitechBudgetNear", "EpitechBudgetOver"
h.assert_equal(marks(buf, budget.ns), {
  { 7, { { "13/20 lines", OK }, { " · ", OK }, { "0/4 args", OK } } },
  { 24, { { "17/20 lines", NEAR }, { " · ", OK }, { "1/4 args", OK } } },
  { 45, { { "20/20 lines", NEAR }, { " · ", OK }, { "4/4 args", OK } } },
  { 69, { { "21/20 lines", OVER }, { " · ", OK }, { "5/4 args", OVER } } },
  { 94, { { "3/20 lines", OK }, { " · ", OK }, { "5/4 args (…)", OVER } } },
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

-- §9.5 depth meter, on every row of CLAUDE.md's table, a 4-branch chain and
-- a switch (counted as a level until calibrated).
config.setup()
local depth = h.buffer("/tmp/epitech_budget_depth.c", vim.fn.readfile(plugin .. "/test/fixtures/budget/depth.c"))
budget.update(depth)
local function texts(chunks)
  return table.concat(vim.tbl_map(function(chunk)
    return chunk[1] .. "|" .. chunk[2]
  end, chunks), " ")
end
local depth_marks = {}
for _, mark in ipairs(marks(depth, budget.depth_ns)) do
  depth_marks[#depth_marks + 1] = { mark[1] + 1, texts(mark[2]) }
end
h.assert_equal(depth_marks, {
  { 4, "depth 2|EpitechBudgetNear" },
  { 5, "depth 3 ✗ C-C1|EpitechBudgetOver" },
  { 18, "depth 2 (else + if)|EpitechBudgetNear" },
  { 20, "depth 3 (else + if) ✗ C-C1|EpitechBudgetOver" },
  { 30, "depth 2 (else + if)|EpitechBudgetNear" },
  { 31, "depth 3 ✗ C-C1|EpitechBudgetOver" },
  { 42, "depth 2 (else + if)|EpitechBudgetNear" },
  { 52, "depth 2|EpitechBudgetNear" },
  { 62, "4 branches ✗ C-C1|EpitechBudgetOver" },
  { 64, "depth 2 (else + if)|EpitechBudgetNear" },
  { 66, "depth 3 (else + if) ✗ C-C1|EpitechBudgetOver" },
  { 76, "depth 2|EpitechBudgetNear" },
  { 78, "depth 3 ✗ C-C1|EpitechBudgetOver" },
}, "depth labels (1-based rows)")

-- Two labels on one row are joined.
local same_row = h.buffer("/tmp/epitech_budget_same_row.c", {
  "int f(int a)", "{", "    while (a) { while (a) { if (a) { if (a) { return 1; } else if (a) { return 2; }"
    .. " else if (a) { return 3; } else { return 4; } } } }", "    return 0;", "}",
})
budget.update(same_row)
h.assert_equal(texts(marks(same_row, budget.depth_ns)[1][2]), table.concat({
  "depth 2|EpitechBudgetNear", " · |EpitechBudgetOk", "depth 3 ✗ C-C1|EpitechBudgetOver",
  " · |EpitechBudgetOk", "depth 4 ✗ C-C1|EpitechBudgetOver", " · |EpitechBudgetOk",
  "4 branches ✗ C-C1|EpitechBudgetOver", " · |EpitechBudgetOk", "depth 5 (else + if) ✗ C-C1|EpitechBudgetOver",
  " · |EpitechBudgetOk", "depth 6 (else + if) ✗ C-C1|EpitechBudgetOver",
}, " "), "labels on one row")

config.setup({ budget = { depth = false } })
budget.update(depth)
h.assert_equal(marks(depth, budget.depth_ns), {}, "no depth labels when disabled")

-- §9.4 file budget.
config.setup()
local function functions(count, static_count)
  local lines = {}
  for i = 1, count do
    if i > 1 then
      lines[#lines + 1] = ""
    end
    vim.list_extend(lines, {
      (i <= static_count and "static " or "") .. "int get_value_" .. i .. "(void)", "{", "    return " .. i .. ";", "}",
    })
  end
  return lines
end
local root, cleanup = h.temp_project({
  ["src/parser.c"] = functions(10, 4),
  ["src/small.c"] = functions(3, 1),
  ["include/types.h"] = { "int get_value(void);" },
  ["include/inline.h"] = { "static inline int get_one(void)", "{", "    return 1;", "}" },
  ["src/100%.c"] = functions(1, 0),
})

local parser = h.buffer(root .. "/src/parser.c", vim.fn.readfile(root .. "/src/parser.c"))
local win = vim.api.nvim_get_current_win()
vim.g.statusline_winid = win
h.assert_equal(budget.winbar(), "%#EpitechWinbar#src/parser.c   functions %#EpitechBudgetNear#10/10"
  .. "%#EpitechWinbar# · non-static %#EpitechBudgetOver#6/5%*", "winbar at and past the limits")
h.assert_equal(budget.file_text(parser), "functions 10/10 · non-static 6/5", "plain text")
h.buffer(root .. "/src/small.c", vim.fn.readfile(root .. "/src/small.c"))
h.assert_equal(budget.winbar(), "%#EpitechWinbar#src/small.c   functions %#EpitechWinbar#3/10"
  .. "%#EpitechWinbar# · non-static %#EpitechWinbar#2/5%*", "winbar under the limits")
h.buffer(root .. "/src/100%.c", vim.fn.readfile(root .. "/src/100%.c"))
assert(budget.winbar():find("src/100%%.c", 1, true), "% in a path is escaped")

-- Headers get a budget only when they define functions.
local types = h.buffer(root .. "/include/types.h", vim.fn.readfile(root .. "/include/types.h"))
h.assert_equal(budget.file_text(types), "", "header without functions")
local inline = h.buffer(root .. "/include/inline.h", vim.fn.readfile(root .. "/include/inline.h"))
h.assert_equal(budget.file_text(inline), "functions 1/10 · non-static 0/5", "header with a static inline function")

-- The winbar is set on C windows, cleared on others, and never replaces a
-- winbar the plugin didn't set.
budget.setup(config.options)
vim.api.nvim_set_current_buf(parser)
budget.update_winbar(win)
h.assert_equal(vim.wo[win].winbar, budget.WINBAR, "winbar set on a C window")
vim.api.nvim_set_current_buf(types)
h.assert_equal(vim.wo[win].winbar, "", "winbar cleared on a header without functions")
local text = vim.api.nvim_create_buf(true, false)
vim.bo[text].filetype = "markdown"
vim.api.nvim_set_current_buf(parser)
h.assert_equal(vim.wo[win].winbar, budget.WINBAR, "BufWinEnter sets it again")
vim.api.nvim_set_current_buf(text)
h.assert_equal(vim.wo[win].winbar, "", "winbar cleared on a non-C buffer")

-- Another plugin replaces the winbar on the C buffer: it's left alone.
vim.api.nvim_set_current_buf(parser)
vim.api.nvim_set_option_value("winbar", "%f custom", { win = win, scope = "local" })
vim.api.nvim_set_current_buf(text)
vim.api.nvim_set_current_buf(parser)
h.assert_equal(vim.wo[win].winbar, "%f custom", "a user's window winbar is kept")
vim.api.nvim_set_option_value("winbar", "", { win = win, scope = "local" })
vim.o.winbar = "%f global"
vim.cmd("split")
h.assert_equal(vim.wo.winbar, "%f global", "a user's global winbar is kept")
vim.cmd("close")
vim.o.winbar = ""

-- With budget.file = "lualine" there's no winbar, only the component.
budget.setup(config.setup({ budget = { file = "lualine" } }))
vim.api.nvim_set_current_buf(text)
vim.api.nvim_set_current_buf(parser)
h.assert_equal(vim.wo[win].winbar, "", "no winbar in lualine mode")
h.assert_equal(require("epitech").file_budget(), "functions 10/10 · non-static 6/5", "lualine component")
cleanup()

print("Epitech budget tests passed")
