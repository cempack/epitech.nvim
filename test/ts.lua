local plugin = assert(vim.env.EPITECH_NVIM_DIR, "EPITECH_NVIM_DIR is required")
vim.opt.runtimepath:prepend(plugin)
package.path = plugin .. "/lua/?.lua;" .. plugin .. "/lua/?/init.lua;" .. package.path

local h = dofile(plugin .. "/test/helpers.lua")
local ts = require("epitech.ts")

local fixture = vim.fn.readfile(plugin .. "/test/fixtures/ts/functions.c")
local buf = h.buffer("/tmp/epitech_ts_functions.c", fixture)
assert(ts.parser(buf), "the bundled C parser is available")

local summary = {}
for _, fn in ipairs(ts.functions(buf)) do
  summary[#summary + 1] = {
    fn.name, fn.is_static, #fn.params, fn.variadic, fn.signature_row, fn.body_lines, fn.start_row, fn.end_row,
  }
  h.assert_equal(fn.node:type(), "function_definition", fn.name .. " node")
  h.assert_equal(fn.body:type(), "compound_statement", fn.name .. " body")
  h.assert_equal(fn.param_list:type(), "parameter_list", fn.name .. " parameter list")
end
-- name, static, params, variadic, signature row, body lines, start, end (0-based)
h.assert_equal(summary, {
  { "is_separator", true, 1, false, 12, 1, 12, 15 },
  { "dup_str", false, 1, false, 17, 1, 17, 20 },
  { "sum_all", false, 1, true, 22, 3, 22, 27 },
  { "add_long_names", false, 2, false, 29, 1, 29, 33 },
  { "main", false, 0, false, 35, 1, 35, 38 },
  { "print_help", false, 0, false, 40, 1, 40, 43 },
}, "functions")

local prototypes = vim.tbl_map(function(proto)
  return { proto.name, proto.row, proto.empty_params, proto.node:type() }
end, ts.prototypes(buf))
h.assert_equal(prototypes, {
  { "print_help", 9, true, "declaration" },
  { "split_words", 10, false, "declaration" },
}, "prototypes")

-- The declarator chain of a pointer-returning function.
local split = ts.prototypes(buf)[2]
h.assert_equal(ts.function_declarator(split.node:field("declarator")[1]):id(), split.declarator:id(),
  "function_declarator walks pointer_declarator chains")
h.assert_equal(ts.text(split.declarator:field("declarator")[1], buf), "split_words", "text()")

-- Results are cached until the buffer changes.
assert(ts.functions(buf) == ts.functions(buf), "cached per changedtick")
local before = ts.functions(buf)
vim.api.nvim_buf_set_lines(buf, -1, -1, false, { "", "void extra(void)", "{", "}" })
assert(ts.functions(buf) ~= before, "cache invalidated by an edit")
h.assert_equal(#ts.functions(buf), 7, "new function found after the edit")

-- The same walk works on strings, for files that aren't open.
local src = table.concat(fixture, "\n")
h.assert_equal(#ts.collect_functions(ts.parse_string(src), src), 6, "functions in a string")

-- project_functions() covers tracked .c files.
local root, cleanup = h.temp_project({
  ["src/a.c"] = { "static int helper(void)", "{", "    return 1;", "}", "", "int run(void)", "{",
    "    return helper();", "}" },
  ["src/b.c"] = { "int helper(void)", "{", "    return 2;", "}" },
  ["include/a.h"] = { "int run(void);" },
})
h.assert_equal(ts.project_functions(root), {
  helper = { file = "src/b.c", is_static = false, row = 0 },
  run = { file = "src/a.c", is_static = false, row = 5 },
}, "project functions, non-static wins")
cleanup()

print("Epitech Treesitter tests passed")
