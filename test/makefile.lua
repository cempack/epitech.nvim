local plugin = assert(vim.env.EPITECH_NVIM_DIR, "EPITECH_NVIM_DIR is required")
vim.opt.runtimepath:prepend(plugin)
package.path = plugin .. "/lua/?.lua;" .. plugin .. "/lua/?/init.lua;" .. package.path

local h = dofile(plugin .. "/test/helpers.lua")
local config = require("epitech.config")
local makefile = require("epitech.hints.makefile")
config.setup()

-- Tabs expand to tab_width-column stops.
h.assert_equal(makefile.width("\tab", 8), 10, "tab at the start")
h.assert_equal(makefile.width("abc\td", 8), 9, "tab after text")
h.assert_equal(makefile.width("\t\tx", 4), 9, "two tabs at width 4")
h.assert_equal(makefile.width("é", 8), 1, "multibyte characters count once")

local HEADER = { "##", "## EPITECH PROJECT, 2026", "## demo", "## File description:", "## Makefile", "##", "" }
local function check(lines, final_newline, tab_width)
  local src = table.concat(lines, "\n") .. (final_newline == false and "" or "\n")
  return vim.tbl_map(function(d)
    return { d.lnum, d.code, d.message, d.severity }
  end, makefile.run(src, "Makefile", { tab_width = tab_width }))
end
local ERROR, WARN, INFO = vim.diagnostic.severity.ERROR, vim.diagnostic.severity.WARN, vim.diagnostic.severity.INFO

h.assert_equal(check(vim.list_extend(vim.deepcopy(HEADER), { "all:", "\t@echo ok" })), {}, "a clean Makefile")
local pdf_header = { "##", "### EPITECH PROJECT, 2026", "### demo", "### File description:", "### Makefile", "##" }
h.assert_equal(check(pdf_header), {}, "the PDF's ### header is accepted")

local long = "SRC = src/main.c src/parser.c src/lexer.c src/evaluator.c src/printer.c src/env.c"
h.assert_equal(check({
  "",
  "NAME = demo",
  long,
  "OBJ = $(SRC:.c=.o)   ",
  "CFLAGS = -Wall\r",
  "all: $(NAME)",
  "\t\t\t\t\t\t\t\t\t$(CC) -o $(NAME) $(OBJ)",
  "",
  "",
}), {
  { 0, "C-G1", "C-G1 missing Epitech header", WARN },
  { 2, "C-F3", "C-F3 82/80 columns", ERROR },
  { 3, "C-G7", "C-G7 trailing whitespace", WARN },
  { 4, "C-G6", "C-G6 \\r line ending", WARN },
  { 6, "C-F3", "C-F3 96/80 columns", ERROR },
  { 0, "C-G8", "C-G8 empty line at the start of the file", WARN },
  { 8, "C-G8", "C-G8 more than one empty line at the end of the file", WARN },
}, "every problem")
h.assert_equal(check(vim.list_extend(vim.deepcopy(HEADER), { "all:", "" })), {}, "one empty line at the end is fine")
h.assert_equal(check(vim.list_extend(vim.deepcopy(HEADER), { "all:" }), false), {
  { 7, "C-A3", "C-A3 no newline at the end of the file", INFO },
}, "missing final newline")
h.assert_equal(check({ "\t\t\t\t\t\t\t\t\tx" }, true, 4), { { 0, "C-G1", "C-G1 missing Epitech header", WARN } },
  "tab_width changes the column count")

-- Buffers: diagnostics on open and edit, the file format and 'eol'.
local root, cleanup = h.temp_project({ ["Makefile"] = vim.list_extend(vim.deepcopy(HEADER), { long }) })
local buf = vim.fn.bufadd(root .. "/Makefile")
vim.fn.bufload(buf)
vim.api.nvim_set_current_buf(buf)
vim.bo[buf].filetype = "make"
makefile.refresh(buf)
h.assert_equal(vim.tbl_map(function(d)
  return d.code
end, vim.diagnostic.get(buf, { namespace = makefile.ns })), { "C-F3" }, "buffer diagnostics")
vim.bo[buf].fileformat = "dos"
vim.bo[buf].eol = false
vim.bo[buf].fixeol = false
makefile.refresh(buf)
local codes = vim.tbl_map(function(d)
  return d.code
end, vim.diagnostic.get(buf, { namespace = makefile.ns }))
table.sort(codes)
h.assert_equal(codes, { "C-A3", "C-F3", "C-G6", "C-G6", "C-G6", "C-G6", "C-G6", "C-G6", "C-G6" },
  "dos line endings and no final newline")
vim.bo[buf].fileformat = "unix"
vim.bo[buf].eol = true
vim.bo[buf].fixeol = true

-- Fixes.
local actions, client = h.code_actions(buf, h.rows(7))
h.assert_equal(vim.tbl_map(function(action)
  return action.title
end, actions), { "Split into SRC += lines (C-F3)" }, "split action")
h.apply_action(actions[1], client)
local split = {
  "SRC = src/main.c", "SRC += src/parser.c", "SRC += src/lexer.c", "SRC += src/evaluator.c", "SRC += src/printer.c",
  "SRC += src/env.c",
}
h.assert_equal(vim.api.nvim_buf_get_lines(buf, 7, -1, false), split, "SRC split, the first line keeping its operator")
h.assert_equal(#h.code_actions(buf, h.rows(7, 12)), 0, "idempotent")

vim.api.nvim_buf_set_lines(buf, 7, -1, false, {
  "TESTS_SRC += tests/test_a.c \\", "\ttests/test_b.c \\", "\ttests/test_c.c", "OBJ = $(SRC:.c=.o)  ",
  "LIBS = $(wildcard lib/*.c) \\", "\tlib/x.c",
})
h.assert_equal(#h.code_actions(buf, h.rows(7, 9)), 0, "a short backslash-continued list is left as it is")
vim.api.nvim_buf_set_lines(buf, 8, 9, false, { "\ttests/test_b.c tests/test_with_a_very_long_name_for_this_line.c "
  .. "tests/test_d.c \\" })
actions, client = h.code_actions(buf, h.rows(8))
h.apply_action(actions[1], client)
h.assert_equal(vim.api.nvim_buf_get_lines(buf, 7, 13, false), {
  "TESTS_SRC += tests/test_a.c", "TESTS_SRC += tests/test_b.c",
  "TESTS_SRC += tests/test_with_a_very_long_name_for_this_line.c", "TESTS_SRC += tests/test_d.c",
  "TESTS_SRC += tests/test_c.c", "OBJ = $(SRC:.c=.o)  ",
}, "a continued list with a line over 80 columns is split")
vim.api.nvim_buf_set_lines(buf, 7, 12, false, { "TESTS_SRC += tests/test_a.c \\", "\ttests/test_b.c \\",
  "\ttests/test_c.c" })
actions, client = h.code_actions(buf, h.rows(10))
h.assert_equal(vim.tbl_map(function(action)
  return action.title
end, actions), { "Remove trailing spaces (C-G7)" }, "trailing spaces action")
h.apply_action(actions[1], client)
h.assert_equal(vim.api.nvim_buf_get_lines(buf, 10, 11, false), { "OBJ = $(SRC:.c=.o)" }, "trailing spaces removed")
h.assert_equal(#h.code_actions(buf, h.rows(11, 12)), 0, "no split for $(wildcard …)")

-- The header action runs the header insertion with the make comment style.
local bare = vim.fn.bufadd(root .. "/lib/Makefile")
vim.fn.bufload(bare)
vim.api.nvim_set_current_buf(bare)
vim.bo[bare].filetype = "make"
vim.api.nvim_buf_set_lines(bare, 0, -1, false, { "all:" })
actions, client = h.code_actions(bare, h.rows(0))
h.assert_equal(vim.tbl_map(function(action)
  return action.title
end, actions), { "Add the Epitech header (C-G1)" }, "header action")
local answers = { "demo", "Library Makefile" }
vim.ui.input = function(_, on_confirm)
  on_confirm(table.remove(answers, 1))
end
client:exec_cmd(actions[1].command, { bufnr = bare })
h.assert_equal(vim.api.nvim_buf_get_lines(bare, 0, -1, false), {
  "##", "## EPITECH PROJECT, " .. os.date("%Y"), "## demo", "## File description:", "## Library Makefile", "##", "",
  "all:",
}, "header added")
h.assert_equal(#h.code_actions(bare, h.rows(0)), 0, "idempotent header action")

-- makefile.enabled = false: no diagnostics, no actions.
config.setup({ makefile = { enabled = false } })
makefile.refresh(buf)
h.assert_equal(#vim.diagnostic.get(buf, { namespace = makefile.ns }), 0, "checks off")
cleanup()

print("Epitech Makefile tests passed")
