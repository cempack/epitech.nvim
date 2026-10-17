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
report("C-F5 four parameters and ...", has(variadic, "C-F5"), nil)

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

cleanup()
if #failures > 0 then
  error("Banana disagrees with the plugin on:\n  " .. table.concat(failures, "\n  "))
end
print("Calibration matches Banana")
