local plugin = assert(vim.env.EPITECH_NVIM_DIR, "EPITECH_NVIM_DIR is required")
vim.opt.runtimepath:prepend(plugin)
package.path = plugin .. "/lua/?.lua;" .. plugin .. "/lua/?/init.lua;" .. package.path

local h = dofile(plugin .. "/test/helpers.lua")
local hints = require("epitech.hints")
require("epitech.config").setup()

local TITLE = "Move declarations to the top (C-L5)"

-- §9.12 before/after fixtures.
h.check_fix("decl", "mid_init", 5, TITLE, "C-L5")
h.check_fix("decl", "multi", 2, TITLE, "C-L5")
h.check_fix("decl", "nested", 5, TITLE, "C-L5")
h.check_fix("decl", "no_leading", 3, TITLE, "C-L5")

-- A for loop initializer stays where it is.
local buf = h.buffer("/tmp/epitech_decl_for.c", {
  "int loop(int n)", "{", "    int total = 0;", "", "    for (int i = 0; i < n; i++) {", "        total = total + i;",
  "    }", "    return total;", "}",
})
h.assert_equal(h.actions_for((h.code_actions(buf)), "C-L5"), {}, "for initializer left alone")

-- Refusals: a hint saying why, and no action.
local function refused(lines)
  local b = h.buffer("/tmp/epitech_decl_refused.c", lines)
  local src = table.concat(lines, "\n")
  local found = vim.tbl_map(function(d)
    return { d.lnum, d.message }
  end, vim.tbl_filter(function(d)
    return d.code == "C-L5"
  end, hints.collect(src, "x.c", { root = "/tmp" })))
  h.assert_equal(h.actions_for((h.code_actions(b)), "C-L5"), {}, "no action: " .. lines[5])
  return found
end
h.assert_equal(refused({ "int f(int n)", "{", "    n++;", "", "    int t[3] = {1, 2, 3};", "    return t[n];", "}" }),
  { { 4, "C-L5 no automatic fix: `int t[3] = {1, 2, 3};` can't become an assignment" } }, "array initializer list")
h.assert_equal(refused({ "int f(int n)", "{", "    n++;", "", "    const int max = n;", "    return max;", "}" }),
  { { 4, "C-L5 no automatic fix: a const variable can't be assigned later" } }, "const with an initializer")
h.assert_equal(refused({ "int f(int n)", "{", "    if (n) {", "", "        int tmp = 1;", "        n = tmp;", "    } else {",
  "        int tmp = 2;", "        n = tmp;", "    }", "    return n;", "}" }),
  { { 7, "C-L5 no automatic fix: `tmp` is declared twice in this function" } }, "shadowing")
h.assert_equal(refused({ "int f(int n)", "{", "    n++;", "", "    static int calls = 0;", "    return calls + n;", "}" }),
  { { 4, "C-L5 no automatic fix: a static variable's initializer only runs once" } }, "static with an initializer")
h.assert_equal(refused({ "int f(int n)", "{", "    n++;", "", "    char buffer[n];", "    return buffer[0];", "}" }),
  { { 4, "C-L5 no automatic fix: the array's size isn't known at the top of the function" } }, "variable length array")

-- The explanation stays even when Banana reports C-L5 on the same line.
local b = h.buffer("/tmp/epitech_decl_dedup.c", { "int f(int n)", "{", "    n++;", "    const int max = n;",
  "    return max;", "}" })
vim.diagnostic.set(require("epitech.banana").ns, b, { { lnum = 3, col = 4, message = "x", code = "C-L5" } })
hints.refresh(b)
h.assert_equal(#vim.tbl_filter(function(d)
  return d.code == "C-L5"
end, vim.diagnostic.get(b, { namespace = hints.ns })), 1, "explanation kept next to Banana's C-L5")

print("Epitech declaration fix tests passed")
