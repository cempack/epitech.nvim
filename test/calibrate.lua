local plugin = assert(vim.env.EPITECH_NVIM_DIR, "EPITECH_NVIM_DIR is required")
vim.opt.runtimepath:prepend(plugin)
package.path = plugin .. "/lua/?.lua;" .. plugin .. "/lua/?/init.lua;" .. package.path

-- Calibration against the real epiclang (§10 of CLAUDE.md), gated in
-- test/run. It prints what Banana does in each case, and fails where the
-- plugin's meters disagree with it: record the answer in rules.lua `notes`
-- and adjust the code until it passes.
local h = dofile(plugin .. "/test/helpers.lua")
local banana = require("epitech.banana")
local ts = require("epitech.ts")
local config = require("epitech.config")
config.setup()

local root, cleanup = h.temp_project({})
local HEADER = { "/*", "** EPITECH PROJECT, 2026", "** calibrate", "** File description:", "** Calibration", "*/", "" }

-- Banana's diagnostics for a file with these lines (the header is added).
local function check(name, lines)
  local file = root .. "/" .. name
  vim.fn.writefile(vim.list_extend(vim.deepcopy(HEADER), lines), file)
  local result = vim.system({ "epiclang", "-x", "c", "-fsyntax-only", file }, { cwd = root, text = true }):wait()
  return banana.parse(result.stderr, file, root), file
end

local function has(diagnostics, code)
  for _, diagnostic in ipairs(diagnostics) do
    if diagnostic.code == code then
      return true
    end
  end
  return false
end

local failures = {}
local function report(label, measured, ours)
  print(("%-48s Banana: %-5s plugin: %s"):format(label, tostring(measured), tostring(ours)))
  if ours ~= nil and measured ~= ours then
    failures[#failures + 1] = label
  end
end

local function body_kind(kind, n)
  local lines
  if kind == "statements" then
    lines = {}
    for _ = 1, n - 1 do
      lines[#lines + 1] = "    x = x + 1;"
    end
  elseif kind == "declarations" then
    lines = { "    int y = 0;", "    int z = 0;", "" }
    for _ = 1, n - 4 do
      lines[#lines + 1] = "    x = x + y + z;"
    end
  elseif kind == "continuation" then
    lines = { "    x = x", "        + 1;" }
    for _ = 1, n - 3 do
      lines[#lines + 1] = "    x = x + 1;"
    end
  elseif kind == "comment" then
    lines = { "    /* a comment line */" }
    for _ = 1, n - 2 do
      lines[#lines + 1] = "    x = x + 1;"
    end
  end
  lines[#lines + 1] = "    return x;"
  return vim.list_extend({ "int count_lines(int x)", "{" }, vim.list_extend(lines, { "}" }))
end

-- 1. C-F4: which lines count toward the 20.
for _, kind in ipairs({ "statements", "declarations", "continuation", "comment" }) do
  for _, n in ipairs({ 20, 21 }) do
    local lines = body_kind(kind, n)
    local diagnostics, file = check("count_lines.c", lines)
    local fn = ts.collect_functions(ts.parse_string(table.concat(vim.fn.readfile(file), "\n")),
      table.concat(vim.fn.readfile(file), "\n"))[1]
    report(("C-F4 %s, %d lines"):format(kind, n), has(diagnostics, "C-F4"),
      fn.body_lines > config.options.budget.max_lines)
  end
end

-- 2. C-F5: does `...` count as a fifth parameter?
local variadic = check("variadic.c", {
  "int sum_all(int a, int b, int c, int d, ...)",
  "{",
  "    return a + b + c + d;",
  "}",
})
local four = check("four.c", { "int sum_four(int a, int b, int c, int d)", "{", "    return a + b + c + d;", "}" })
local budget_chunks = require("epitech.budget").function_chunks
local function meter_over(lines)
  local src = table.concat(lines, "\n")
  local fn = ts.collect_functions(ts.parse_string(src), src)[1]
  return budget_chunks(fn, config.options.budget)[3][2] == "EpitechBudgetOver"
end
report("C-F5 four parameters and ...", has(variadic, "C-F5"), meter_over({
  "int sum_all(int a, int b, int c, int d, ...)", "{", "}" }))
report("C-F5 four parameters", has(four, "C-F5"), meter_over({ "int sum_four(int a, int b, int c, int d)", "{", "}" }))

-- 3. and 4. C-C1: nesting depth (switch, do while, a plain else block) and
-- branch counts, compared with the depth meter's verdict.
local budget = require("epitech.budget")
local function meter_says(lines)
  local src = table.concat(lines, "\n")
  local fn = ts.collect_functions(ts.parse_string(src), src)[1]
  for _, entry in ipairs(budget.depths(fn.body)) do
    if entry.depth >= config.options.budget.max_depth
      or (entry.branches or 0) > config.options.budget.max_branches then
      return true
    end
  end
  return false
end
local function wrap(body)
  return vim.list_extend(vim.list_extend({ "int check_depth(int a)", "{" }, body), { "    return a;", "}" })
end
local nesting = {
  ["while { for { if } }"] = {
    "    while (a > 0) {", "        for (int i = 0; i < a; i++) {", "            if (i == 2) {",
    "                a--;", "            }", "        }", "        a--;", "    }",
  },
  ["if / else if / else if"] = {
    "    if (a == 1) {", "        a = 2;", "    } else if (a == 2) {", "        a = 3;",
    "    } else if (a == 3) {", "        a = 4;", "    }",
  },
  ["if {} else if { while {} }"] = {
    "    if (a == 1) {", "        a = 2;", "    } else if (a == 2) {", "        while (a > 0) {",
    "            a--;", "        }", "    }",
  },
  ["if / else if / else"] = {
    "    if (a == 1) {", "        a = 2;", "    } else if (a == 2) {", "        a = 3;", "    } else {",
    "        a = 4;", "    }",
  },
  ["while { if }"] = { "    while (a > 0) {", "        if (a == 2) {", "            a = 0;", "        }", "    }" },
  ["while { switch { case: if } }"] = {
    "    while (a > 0) {", "        switch (a) {", "            case 1:", "                if (a == 1) {",
    "                    a = 0;", "                }", "                break;", "            default:",
    "                a--;", "                break;", "        }", "    }",
  },
  ["do { for { if } } while"] = {
    "    do {", "        for (int i = 0; i < a; i++) {", "            if (i == 2) {", "                a--;",
    "            }", "        }", "        a--;", "    } while (a > 0);",
  },
  ["if {} else { if { while } }"] = {
    "    if (a == 1) {", "        a = 2;", "    } else {", "        if (a == 2) {", "            while (a > 0) {",
    "                a--;", "            }", "        }", "    }",
  },
  ["4 branches: if / else if / else if / else"] = {
    "    if (a == 1) {", "        a = 2;", "    } else if (a == 2) {", "        a = 3;", "    } else if (a == 3) {",
    "        a = 4;", "    } else {", "        a = 5;", "    }",
  },
}
local labels = vim.tbl_keys(nesting)
table.sort(labels)
for _, label in ipairs(labels) do
  local lines = wrap(nesting[label])
  report("C-C1 " .. label, has(check("check_depth.c", lines), "C-C1"), meter_says(lines))
end

-- 7. Grader-only rules: Banana should print nothing for C-G9, C-A1, C-A2
-- and C-A4, or the hints would duplicate it.
local grader = check("grader_only.c", {
  "#include <string.h>",
  "",
  "int count_chars(char *str)",
  "{",
  "    int len = strlen(str);",
  "",
  "    return len * 4096;",
  "}",
})
for _, code in ipairs({ "C-G9", "C-A1", "C-A2", "C-A4" }) do
  report(code .. " is grader-only", has(grader, code), false)
end

-- 5. Header repeats: a .c including a bad header. The plugin keeps the
-- header's entries off the .c and attributes them to the header.
vim.fn.mkdir(root .. "/include", "p")
vim.fn.writefile(vim.list_extend(vim.deepcopy(HEADER), {
  "#ifndef BAD_H_", "    #define BAD_H_", "", "int print_help();", "", "#endif",
}), root .. "/include/bad.h")
vim.fn.writefile(vim.list_extend(vim.deepcopy(HEADER), {
  '#include "bad.h"', "", "int main(void)", "{", "    return 0;", "}",
}), root .. "/uses_bad.c")
local repeated = vim.system({ "epiclang", "-x", "c", "-fsyntax-only", "-I" .. root .. "/include", root .. "/uses_bad.c" },
  { cwd = root, text = true }):wait()
print("Header repeat output:\n" .. repeated.stderr)
local header_entries = vim.tbl_filter(function(d)
  return d.user_data.path == vim.uv.fs_realpath(root .. "/include/bad.h")
end, banana.parse(repeated.stderr, nil, root))
report("header entries attributed to the header", #header_entries > 0, true)
report("header entries kept off the .c", has(banana.parse(repeated.stderr, root .. "/uses_bad.c", root), "C-F6"),
  false)

-- 6. File-level messages: epiclang doesn't report C-O4 at all (the project
-- check does it on the repository's file names).
local _, bad_name = check("BadName.c", { "int main(void)", "{", "    return 0;", "}" })
local file_level = vim.system({ "epiclang", "-x", "c", "-fsyntax-only", bad_name }, { cwd = root, text = true }):wait()
report("C-O4 reported by epiclang", file_level.stderr:find("C-O4", 1, true) ~= nil, false)

-- C-F3 counts a tab as 4 columns: a tab and 96 characters are reported as a
-- 100-character line (recorded in rules.lua; the formatter never writes tabs).
local tabbed = check("tabbed.c", { "int get_long(void)", "{", "\treturn " .. string.rep("1", 88) .. ";", "}" })
local tab_message = ""
for _, d in ipairs(tabbed) do
  if d.code == "C-F3" then
    tab_message = d.message
  end
end
report("C-F3 counts a tab as 4 columns", tab_message:find("100", 1, true) ~= nil, true)

-- 8. Makefiles: epiclang reads one as C code (C-G4 on `all:`, C-L2 on the
-- recipe's tab), so it can't check Makefiles. The plugin's own Makefile
-- checks stay, with the cautious makefile.tab_width = 8.
vim.fn.writefile({ "all:", "\t@echo " .. string.rep("x", 90) }, root .. "/Makefile")
local make = vim.system({ "epiclang", "-x", "c", "-fsyntax-only", root .. "/Makefile" }, { cwd = root, text = true }):wait()
report("epiclang reads a Makefile as C", has(banana.parse(make.stderr, root .. "/Makefile", root), "C-G4"), true)

cleanup()
if #failures > 0 then
  error("Banana disagrees with the plugin on:\n  " .. table.concat(failures, "\n  "))
end
-- C-L2 on wrapped lines: one level per parenthesis open at the line's start
-- (Elliot's report on `|| g(a,` / `b) == -1)`), and the formatter's guess for
-- a wrapped line outside any parenthesis: one level down.
local function wrapped_l2(name, lines)
  local helper = { "static int g(int x)", "{", "    return x;", "}", "" }
  return has(check(name, vim.list_extend(helper, lines)), "C-L2")
end
local function condition(indent)
  return { "int f(int a, int b)", "{", "    if (g(a) == -1", "        || g(a", indent .. "+ b) == -1) {", "        return 1;",
    "    }", "    return 0;", "}" }
end
report("C-L2 inside two parentheses, two levels down", wrapped_l2("wrap_two.c", condition("            ")), false)
report("C-L2 inside two parentheses, one level down", wrapped_l2("wrap_one.c", condition("        ")), true)
local function sum(indent)
  return { "int f(int a, int b)", "{", "    int x = 0;", "", "    x = a", indent .. "+ b;", "    return x;", "}" }
end
report("C-L2 outside parentheses, one level down", wrapped_l2("wrap_plus.c", sum("        ")), false)
report("C-L2 outside parentheses, same level", wrapped_l2("wrap_same.c", sum("    ")), nil)

print("Calibration matches Banana")
