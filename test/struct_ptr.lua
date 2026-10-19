local plugin = assert(vim.env.EPITECH_NVIM_DIR, "EPITECH_NVIM_DIR is required")
vim.opt.runtimepath:prepend(plugin)
package.path = plugin .. "/lua/?.lua;" .. plugin .. "/lua/?/init.lua;" .. package.path

local h = dofile(plugin .. "/test/helpers.lua")
local hints = require("epitech.hints")
require("epitech.config").setup()

local root, cleanup = h.temp_project({
  ["include/point.h"] = {
    "#ifndef POINT_H_", "    #define POINT_H_", "", "typedef struct point_s {", "    int x;", "    int y;", "} point_t;",
    "", "int sum_point(point_t point);", "point_t make_point(int x, int y);", "", "#endif",
  },
  ["src/point.c"] = {
    '#include "point.h"', "", "int sum_point(point_t point)", "{", "    return point.x + point.y + get_weight(point);",
    "}", "", "void move_point(point_t point)", "{", "    point.x++;", "    show(point);", "}", "",
    "int width(struct point_s point)", "{", "    return point.x;", "}", "",
    "int show_point(point_t point)", "{", "    return point.y;", "}",
  },
  ["src/table.c"] = { '#include "point.h"', "", "int (*const SHOW[])(point_t) = {&show_point};" },
  ["src/main.c"] = {
    '#include "point.h"', "", "int main(void)", "{", "    point_t origin = make_point(0, 0);",
    "    point_t *ptr = &origin;", "",
    "    return sum_point(origin) + sum_point(make_point(1, 2)) + sum_point(*ptr);", "}",
  },
})

local buf = h.buffer(root .. "/src/point.c", vim.fn.readfile(root .. "/src/point.c"))
local function titles(row)
  return vim.tbl_map(function(action)
    return action.title
  end, h.actions_for((h.code_actions(buf, h.rows(row))), "C-F7"))
end
h.assert_equal(titles(2), { "Pass point by pointer (C-F7)" }, "typedef'd struct parameter")
h.assert_equal(titles(13), { "Pass point by pointer (C-F7)" }, "struct parameter")
h.assert_equal(titles(7), {}, "a function modifying its copy gets no action")
local refused = vim.tbl_map(function(d)
  return { d.lnum, d.message }
end, vim.tbl_filter(function(d)
  return d.code == "C-F7"
end, hints.collect(table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n"), root .. "/src/point.c",
  { root = root })))
h.assert_equal(refused, {
  { 7, "C-F7 no automatic fix: the function modifies its copy of point, which a pointer would make the caller's" },
  { 18, "C-F7 no automatic fix: show_point is used as a function pointer, whose type sets its parameters" },
}, "the reason is a hint")
h.assert_equal(titles(18), {}, "a function stored as a function pointer gets no action")

local notices = {}
vim.notify = function(message)
  notices[#notices + 1] = message
end
local actions, client = h.code_actions(buf, h.rows(2))
client:exec_cmd(h.actions_for(actions, "C-F7")[1].command, { bufnr = buf })

h.assert_equal(vim.api.nvim_buf_get_lines(buf, 2, 5, false), {
  "int sum_point(point_t const *point)", "{", "    return point->x + point->y + get_weight(*point);",
}, "definition and body")
local header = vim.fn.bufnr(root .. "/include/point.h")
h.assert_equal(vim.api.nvim_buf_get_lines(header, 8, 9, false), { "int sum_point(point_t const *point);" },
  "header prototype")
local main = vim.fn.bufnr(root .. "/src/main.c")
h.assert_equal(vim.api.nvim_buf_get_lines(main, 7, 8, false), {
  "    return sum_point(&origin) + sum_point(make_point(1, 2)) + sum_point(ptr);",
}, "call sites: & on a variable, * dropped from a dereference, a returned struct left alone")
local quickfix = vim.fn.getqflist()
h.assert_equal(#quickfix, 1, "one call site to fix by hand")
h.assert_equal({ vim.fn.bufname(quickfix[1].bufnr), quickfix[1].lnum, quickfix[1].text },
  { root .. "/src/main.c", 8, "pass a pointer here: the argument isn't a variable" }, "quickfix entry")
h.assert_equal(notices[#notices], "point is passed by pointer; 1 place to fix by hand in the quickfix list",
  "the user is told")
h.assert_equal(titles(2), {}, "idempotent")
local result = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
require("epitech").format_buffer(buf)
h.assert_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), result, "the formatter keeps the result")

cleanup()
print("Epitech struct pointer fix tests passed")
