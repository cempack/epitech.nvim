local plugin = assert(vim.env.EPITECH_NVIM_DIR, "EPITECH_NVIM_DIR is required")
vim.opt.runtimepath:prepend(plugin)
package.path = plugin .. "/lua/?.lua;" .. plugin .. "/lua/?/init.lua;" .. package.path

local h = dofile(plugin .. "/test/helpers.lua")
local hints = require("epitech.hints")
require("epitech.config").setup()
vim.notify = function() end

local HEADER = { "/*", "** EPITECH PROJECT, 2026", "** demo", "** File description:", "** Points", "*/", "" }
local function with_header(lines)
  return vim.list_extend(vim.deepcopy(HEADER), lines)
end
local root, cleanup = h.temp_project({
  ["Makefile"] = { "NAME = demo" },
  ["include/point.h"] = { "#ifndef POINT_H_", "    #define POINT_H_", "", "int other(void);", "", "#endif" },
  ["src/point.c"] = with_header({
    "#include <stdlib.h>", "",
    "#define ORIGIN 0", "",
    "typedef struct point_s {", "    int x;", "    int y;", "} point_t;", "",
    "int sum_point(point_t const *point);", "",
    "static int helper(int x);", "",
    "int sum_point(point_t const *point)", "{", "    return helper(point->x) + point->y + ORIGIN;", "}", "",
    "/*", "** Doubles x", "*/", "static int helper(int x)", "{", "    return x * 2;", "}",
  }),
})

local buf = h.buffer(root .. "/src/point.c", vim.fn.readfile(root .. "/src/point.c"))
local src = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
h.assert_equal(vim.tbl_map(function(d)
  return { d.lnum, d.message }
end, vim.tbl_filter(function(d)
  return d.code == "C-H1"
end, hints.collect(src, root .. "/src/point.c", { root = root }))), {
  { 9, "C-H1 belongs in a header" },
  { 11, "C-H1 belongs in a header" },
  { 16, "C-H1 belongs in a header" },
  { 18, "C-H1 define this static function before its first use instead" },
}, "C-H1 hints on the macro, the typedef, the prototype and the static prototype")
h.assert_equal(#vim.tbl_filter(function(d)
  return d.code == "C-H1"
end, hints.collect("#define X 1", root .. "/include/x.h", { root = root })), 0, "nothing in headers")

-- Banana's C-H1 on the same line replaces the hint.
vim.diagnostic.set(require("epitech.banana").ns, buf, { { lnum = 9, col = 0, message = "x", code = "C-H1" } })
hints.refresh(buf)
h.assert_equal(vim.tbl_map(function(d)
  return d.lnum
end, vim.tbl_filter(function(d)
  return d.code == "C-H1"
end, vim.diagnostic.get(buf, { namespace = hints.ns }))), { 11, 16, 18 }, "deduplicated against Banana")

local function row_of(text)
  for i, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    if line == text then
      return i - 1
    end
  end
  error("no line " .. text)
end

local function run(text)
  local actions, client = h.code_actions(buf, h.rows(row_of(text)))
  actions = h.actions_for(actions, "C-H1")
  assert(#actions == 1, vim.inspect(actions))
  if actions[1].command then
    client:exec_cmd(actions[1].command, { bufnr = buf })
  else
    h.apply_action(actions[1], client)
  end
  return actions[1].title
end

-- include/point.h exists for src/point.c, so it's the target.
h.assert_equal(run("typedef struct point_s {"), "Move to include/point.h (C-H1)", "struct typedef action")
h.assert_equal(run("#define ORIGIN 0"), "Move to include/point.h (C-H1)", "macro action")
h.assert_equal(vim.fn.readfile(root .. "/include/point.h"), {
  "#ifndef POINT_H_", "    #define POINT_H_", "",
  "typedef struct point_s {", "    int x;", "    int y;", "} point_t;", "",
  "    #define ORIGIN 0", "",
  "int other(void);", "", "#endif",
}, "typedef and macro inside the guard, before the first prototype, the macro indented for C-G3")

run("int sum_point(point_t const *point);")
h.assert_equal(vim.list_slice(vim.fn.readfile(root .. "/include/point.h"), 9, 13), {
  "    #define ORIGIN 0", "", "int sum_point(point_t const *point);", "", "int other(void);",
}, "prototype moved with the other prototypes")

h.assert_equal(run("static int helper(int x);"), "Move the definition above its first use (C-H1)",
  "static prototype action")
h.assert_equal(vim.api.nvim_buf_get_lines(buf, 7, -1, false), {
  "#include <stdlib.h>", '#include "point.h"', "",
  "/*", "** Doubles x", "*/", "static int helper(int x)", "{", "    return x * 2;", "}", "",
  "int sum_point(point_t const *point)", "{", "    return helper(point->x) + point->y + ORIGIN;", "}",
}, "everything moved out, include added, helper defined before its use")
h.assert_equal(h.actions_for((h.code_actions(buf)), "C-H1"), {}, "idempotent")
local result = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
require("epitech").format_buffer(buf)
h.assert_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), result, "the formatter keeps the result")

-- A static prototype whose definition already comes first is just removed.
local early = h.buffer(root .. "/src/early.c", { "static int one(void)", "{", "    return 1;", "}", "",
  "static int one(void);", "", "int two(void)", "{", "    return one() + 1;", "}" })
local actions, client = h.code_actions(early, h.rows(5))
actions = h.actions_for(actions, "C-H1")
h.assert_equal(actions[1].title, "Remove the static prototype (C-H1)", "remove action")
h.apply_action(actions[1], client)
h.assert_equal(vim.api.nvim_buf_get_lines(early, 0, -1, false), { "static int one(void)", "{", "    return 1;", "}",
  "", "int two(void)", "{", "    return one() + 1;", "}" }, "prototype removed")

-- Without include/<name>.h nor a remembered header, the project header is asked for.
local other = h.buffer(root .. "/src/other.c", { "#define LIMIT 3", "", "int other(void)", "{", "    return LIMIT;",
  "}" })
actions, client = h.code_actions(other, h.rows(0))
actions = h.actions_for(actions, "C-H1")
h.assert_equal(actions[1].title, "Move to the project header… (C-H1)", "unknown target")
vim.ui.select = function(items, _, on_choice)
  on_choice(items[1])
end
client:exec_cmd(actions[1].command, { bufnr = other })
h.assert_equal(vim.api.nvim_buf_get_lines(other, 0, 2, false), { '#include "point.h"', "" }, "include added")
assert(vim.list_contains(vim.fn.readfile(root .. "/include/point.h"), "    #define LIMIT 3"), "moved to the chosen header")

cleanup()
print("Epitech move to header tests passed")
