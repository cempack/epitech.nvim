local plugin = assert(vim.env.EPITECH_NVIM_DIR, "EPITECH_NVIM_DIR is required")
vim.opt.runtimepath:prepend(plugin)
package.path = plugin .. "/lua/?.lua;" .. plugin .. "/lua/?/init.lua;" .. package.path

local h = dofile(plugin .. "/test/helpers.lua")
local config = require("epitech.config")
local hints = require("epitech.hints")
config.setup()

-- §9.8 hints: one fixture function per condition.
local fixture = vim.fn.readfile(plugin .. "/test/fixtures/hints/types.c")
local src = table.concat(fixture, "\n")
local found = {}
for _, d in ipairs(hints.collect(src, "types.c", { root = "/tmp" })) do
  if d.code == "C-A1" or d.code == "C-A2" then
    found[#found + 1] = { d.lnum + 1, d.message }
  end
end
h.assert_equal(found, {
  { 6, "C-A1 str is never modified → char const *str" },
  { 33, "C-A1 str is never modified → char const *str" },
  { 48, "C-A1 str is never modified → char const *str" },
  { 59, "C-A1 player is never modified → struct player const *player" },
  { 74, "C-A1 str is never modified → char const *str" },
  { 92, "C-A2 holds a length → size_t?" },
  { 93, "C-A2 holds a size → size_t?" },
  { 97, "C-A2 holds a length → size_t?" },
}, "C-A1 on read-only pointers (not on writes, calls to non-const parameters, returns, struct members copied out"
  .. " or addresses taken) and C-A2 on ints from strlen, my_strlen and sizeof")
h.assert_equal(#vim.tbl_filter(function(d)
  return d.code == "C-A1" or d.code == "C-A2"
end, hints.collect(src, "types.c", { root = "/tmp", options = config.merge({ hints = { types = false } }).hints })),
  0, "hints.types = false")

-- A call to a project function whose header prototype takes const is fine.
local root, cleanup = h.temp_project({
  ["include/my.h"] = {
    "#ifndef MY_H_", "    #define MY_H_", "", "int my_putstr(char const *str);", "int count_char(char *str, char c);",
    "", "#endif",
  },
  ["src/count.c"] = {
    '#include "my.h"', "", "int count_char(char *str, char c)", "{", "    int count = 0;", "",
    "    for (int i = 0; str[i] != '\\0'; i++) {", "        if (str[i] == c) {", "            count++;",
    "        }", "    }", "    my_putstr(str);", "    return count;", "}",
  },
})
local buf = h.buffer(root .. "/src/count.c", vim.fn.readfile(root .. "/src/count.c"))
local actions, client = h.code_actions(buf, h.rows(2))
actions = h.actions_for(actions, "C-A1")
h.assert_equal(vim.tbl_map(function(action)
  return action.title
end, actions), { "Make str const (C-A1)" }, "const action")
h.apply_action(actions[1], client)
h.assert_equal(vim.api.nvim_buf_get_lines(buf, 2, 3, false), { "int count_char(char const *str, char c)" },
  "definition rewritten")
h.assert_equal(vim.api.nvim_buf_get_lines(vim.fn.bufnr(root .. "/include/my.h"), 4, 5, false),
  { "int count_char(char const *str, char c);" }, "header prototype rewritten")
h.assert_equal(h.actions_for((h.code_actions(buf)), "C-A1"), {}, "idempotent")
local result = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
require("epitech").format_buffer(buf)
h.assert_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), result, "the formatter keeps the result")
cleanup()

print("Epitech type hint tests passed")
