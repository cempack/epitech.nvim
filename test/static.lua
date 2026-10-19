local plugin = assert(vim.env.EPITECH_NVIM_DIR, "EPITECH_NVIM_DIR is required")
vim.opt.runtimepath:prepend(plugin)
package.path = plugin .. "/lua/?.lua;" .. plugin .. "/lua/?/init.lua;" .. package.path

local h = dofile(plugin .. "/test/helpers.lua")
local config = require("epitech.config")
local hints = require("epitech.hints")
local static = require("epitech.hints.static")
config.setup()

local a_c = {
  '#include "a.h"',
  "",
  "int helper(int x)",
  "{",
  "    return x * 2;",
  "}",
  "",
  "int shared(int x)",
  "{",
  "    return helper(x) + late_helper(x);",
  "}",
  "",
  "int late_helper(int x)",
  "{",
  "    return x + 1;",
  "}",
  "",
  "int local_only(void)",
  "{",
  "    return 3;",
  "}",
  "",
  "int main(void)",
  "{",
  "    return local_only();",
  "}",
}
local a_h = {
  "#ifndef A_H_",
  "    #define A_H_",
  "",
  "int helper(int x);",
  "int shared(int x);",
  "int late_helper(int x);",
  "",
  "#endif",
}
local root, cleanup = h.temp_project({
  ["src/a.c"] = a_c,
  ["src/b.c"] = { '#include "a.h"', "", "int use_shared(void)", "{", "    return shared(1);", "}" },
  ["src/c.c"] = { "int count(void);", "", "int run(void)", "{", "    return count();", "}", "", "int count(void)",
    "{", "    return 2;", "}" },
  ["include/a.h"] = a_h,
})

-- The synchronous search, as the project check uses it.
h.assert_equal(static.used_elsewhere(root, root .. "/src/a.c", { "helper", "shared", "late_helper", "local_only" }),
  { shared = true }, "only shared is used in another .c file")

-- Async search on the buffer, then hints.
local buf = h.buffer(root .. "/src/a.c", a_c)
local done = false
static.search(buf, root, function()
  done = true
end)
assert(vim.wait(5000, function()
  return done
end), "git grep finished")
hints.refresh(buf)
local found = vim.tbl_map(function(d)
  return { d.lnum, d.col, d.message }
end, vim.tbl_filter(function(d)
  return d.code == "C-A4"
end, vim.diagnostic.get(buf, { namespace = hints.ns })))
h.assert_equal(found, {
  { 2, 4, "C-A4 only used in this file" },
  { 12, 4, "C-A4 only used in this file" },
  { 17, 4, "C-A4 only used in this file" },
}, "hints on helper, late_helper and local_only (not shared, not main)")

-- Only functions this file uses: one nothing calls would get an unused
-- function warning once static, and calling itself isn't a use.
local unused_src = table.concat({
  "int unused(void)",
  "{",
  "    return 0;",
  "}",
  "",
  "int power(int nb, int p)",
  "{",
  "    return p == 0 ? 1 : nb * power(nb, p - 1);",
  "}",
  "",
  "int print_a(void);",
  "",
  "int print_a(void)",
  "{",
  "    return 1;",
  "}",
  "",
  "int (*const PRINTERS[])(void) = {print_a};",
}, "\n")
h.assert_equal(vim.tbl_map(function(d)
  return d.lnum
end, static.run(unused_src, "x.c", { tree = require("epitech.ts").parse_string(unused_src), static_used = {} })),
  { 12 }, "unused and recursion-only functions get no hint, one in a table does")
h.assert_equal(static.run("int f(void)\n{\n}", "x.h", { tree = require("epitech.ts").parse_string("int f(void)\n{\n}"),
  static_used = {} }), {}, "headers get no C-A4 hint")

-- Code actions.
local function titles(row)
  return vim.tbl_map(function(action)
    return action.title
  end, h.actions_for((h.code_actions(buf, h.rows(row))), "C-A4"))
end
h.assert_equal(titles(17), { "Add static (C-A4)" }, "no header prototype: add static")
h.assert_equal(titles(2), { "Add static and remove the prototype from include/a.h" },
  "header prototype, defined before every use")
h.assert_equal(titles(12), {}, "used before its definition: no safe fix")
h.assert_equal(titles(7), {}, "used elsewhere: no action")

local actions, client = h.code_actions(buf, h.rows(2))
h.apply_action(h.actions_for(actions, "C-A4")[1], client)
h.assert_equal(vim.api.nvim_buf_get_lines(buf, 2, 3, false), { "static int helper(int x)" }, "static added")
h.assert_equal(vim.api.nvim_buf_get_lines(vim.fn.bufnr(root .. "/include/a.h"), 0, -1, false), {
  "#ifndef A_H_", "    #define A_H_", "", "int shared(int x);", "int late_helper(int x);", "", "#endif",
}, "prototype removed from the header")
h.assert_equal(titles(2), {}, "idempotent")
local result = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
require("epitech").format_buffer(buf)
h.assert_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), result, "the formatter keeps the result")

-- A prototype in the file itself becomes static too.
local c = h.buffer(root .. "/src/c.c", vim.fn.readfile(root .. "/src/c.c"))
done = false
static.search(c, root, function()
  done = true
end)
assert(vim.wait(5000, function()
  return done
end), "second search")
actions, client = h.code_actions(c, h.rows(7))
h.apply_action(h.actions_for(actions, "C-A4")[1], client)
h.assert_equal(vim.api.nvim_buf_get_lines(c, 0, -1, false), { "static int count(void);", "", "int run(void)", "{",
  "    return count();", "}", "", "static int count(void)", "{", "    return 2;", "}" }, "file prototype made static")

-- hints.static = false: no hint, no action.
config.setup({ hints = { static = false } })
hints.refresh(c)
h.assert_equal(#vim.tbl_filter(function(d)
  return d.code == "C-A4"
end, vim.diagnostic.get(c, { namespace = hints.ns })), 0, "static hints off")

-- No git, no repository or no directory: nothing is known, so no hint
-- (an empty answer would make every function look unused elsewhere), and
-- no error on every pause in typing.
local plain = vim.fn.tempname()
vim.fn.mkdir(plain, "p")
h.assert_equal(static.used_elsewhere(plain, plain .. "/a.c", { "helper" }), nil, "outside a repository")
h.assert_equal(static.used_elsewhere(plain .. "/missing", plain .. "/missing/a.c", { "helper" }), nil,
  "a directory that doesn't exist yet")
h.assert_equal(require("epitech.project").files(plain .. "/missing", { "*.c" }), nil, "files: no directory")
local path = vim.env.PATH
vim.env.PATH = plain
local answer = "pending"
static.used_elsewhere(root, root .. "/src/a.c", { "helper" }, function(used)
  answer = used
end)
assert(vim.wait(5000, function()
  return answer ~= "pending"
end), "async search answered")
h.assert_equal(answer, nil, "git missing: the async search answers nil")
h.assert_equal(require("epitech.project").files(root, { "*.c" }, { untracked = true }), nil, "files: git missing")
vim.env.PATH = path
local new_file = h.buffer(plain .. "/missing/new.c", { "static int f(char *s)", "{", "    return s[0];", "}", "",
  "int g(void)", "{", "    return f(\"a\");", "}" })
hints.refresh(new_file)
static.search(new_file, require("epitech.project").root(new_file))
vim.wait(200)
vim.fn.delete(plain, "rf")

cleanup()
print("Epitech static hint tests passed")
