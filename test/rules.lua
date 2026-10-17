local plugin = assert(vim.env.EPITECH_NVIM_DIR, "EPITECH_NVIM_DIR is required")
vim.opt.runtimepath:prepend(plugin)
package.path = plugin .. "/lua/?.lua;" .. plugin .. "/lua/?/init.lua;" .. package.path

local h = dofile(plugin .. "/test/helpers.lua")
local rules = require("epitech.rules")

-- §5 of CLAUDE.md, in the PDF's order: code = { severity, checker }.
local expected = {
  { "C-O1", "major", "banana" }, { "C-O2", "major", "grader" }, { "C-O3", "major", "both" },
  { "C-O4", "minor", "both" }, { "C-G1", "minor", "banana" }, { "C-G2", "minor", "banana" },
  { "C-G3", "minor", "banana" }, { "C-G4", "major", "banana" }, { "C-G5", "major", "banana" },
  { "C-G6", "minor", "banana" }, { "C-G7", "minor", "banana" }, { "C-G8", "minor", "banana" },
  { "C-G9", "minor", "grader" }, { "C-G10", "fatal", "banana" }, { "C-F1", "minor", "grader" },
  { "C-F2", "minor", "both" }, { "C-F3", "major", "banana" }, { "C-F4", "major", "banana" },
  { "C-F5", "major", "banana" }, { "C-F6", "major", "banana" }, { "C-F7", "major", "banana" },
  { "C-F8", "minor", "banana" }, { "C-F9", "major", "banana" }, { "C-L1", "major", "both" },
  { "C-L2", "minor", "both" }, { "C-L3", "minor", "banana" }, { "C-L4", "minor", "banana" },
  { "C-L5", "major", "banana" }, { "C-L6", "minor", "banana" }, { "C-V1", "minor", "both" },
  { "C-V2", "major", "grader" }, { "C-V3", "minor", "banana" }, { "C-C1", "major", "banana" },
  { "C-C2", "major", "both" }, { "C-C3", "major", "banana" }, { "C-H1", "major", "both" },
  { "C-H2", "major", "banana" }, { "C-H3", "major", "banana" }, { "C-A1", "info", "grader" },
  { "C-A2", "info", "grader" }, { "C-A3", "info", "banana" }, { "C-A4", "info", "grader" },
}

h.assert_equal(#rules.rules, 42, "42 rules")
local seen, counts = {}, { banana = 0, both = 0, grader = 0 }
for i, rule in ipairs(rules.rules) do
  local code, severity, checker = unpack(expected[i])
  h.assert_equal({ rule.code, rule.severity, rule.checker }, { code, severity, checker }, "rule " .. i)
  assert(not seen[rule.code], "duplicate code " .. rule.code)
  seen[rule.code] = true
  counts[rule.checker] = counts[rule.checker] + 1
  assert(type(rule.title) == "string" and rule.title ~= "", rule.code .. " title")
  assert(type(rule.summary) == "string" and rule.summary ~= "", rule.code .. " summary")
  assert(type(rule.bad) == "table" and #rule.bad > 0, rule.code .. " bad example")
  assert(type(rule.good) == "table" and #rule.good > 0, rule.code .. " good example")
  h.assert_equal(rules.by_code[rule.code], rule, rule.code .. " by_code")
end
h.assert_equal(counts, { banana = 27, both = 8, grader = 7 }, "27 Banana rules, 8 shared, 7 for graders")

h.assert_equal(#rules.extensions, 3, "three unsupported extensions")
for _, extension in ipairs(rules.extensions) do
  assert(extension.construct ~= "" and extension.replacement ~= "", "extension fields")
end
h.assert_equal(rules.severity_rank, { fatal = 1, major = 2, minor = 3, info = 4 }, "severity ranks")

print("Epitech rules tests passed")
