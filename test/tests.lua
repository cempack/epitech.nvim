local plugin = assert(vim.env.EPITECH_NVIM_DIR, "EPITECH_NVIM_DIR is required")
vim.opt.runtimepath:prepend(plugin)
package.path = plugin .. "/lua/?.lua;" .. plugin .. "/lua/?/init.lua;" .. package.path

local h = dofile(plugin .. "/test/helpers.lua")
local tests = require("epitech.tests")
require("epitech").setup()
local notices = {}
vim.notify = function(message)
  notices[#notices + 1] = message
end

-- Criterion's output: a failed assert with its message, one without, a
-- crash, and the synthesis (colors included, as on a terminal).
local CRITERION = {
  "\27[0;34m[----] \27[0mtests/test_even.c:12: Assertion Failed",
  "[----]   ",
  "[----]   The expression is_even(3) == 1 is false.",
  "[----]   ",
  "[FAIL] even::odd: (0.00s)",
  "[----] tests/test_even.c:20: Assertion Failed",
  "[FAIL] even::message: (0.01s)",
  "[----] tests/test_even.c:25: Unexpected signal caught below this line!",
  "[FAIL] even::crash: CRASH!",
  "[FAIL] even::slow: Timed out. (1.00s)",
  "[====] Synthesis: Tested: 6 | Passing: 2 | Failing: 3 | Crashing: 1 ",
}
local parsed = tests.parse(CRITERION, "/project")
h.assert_equal(vim.tbl_map(function(item)
  return ("%s:%d %s"):format(item.filename or "-", item.lnum or 0, item.text)
end, parsed.items), {
  "/project/tests/test_even.c:12 even::odd: The expression is_even(3) == 1 is false.",
  "/project/tests/test_even.c:20 even::message: Assertion Failed",
  "/project/tests/test_even.c:25 even::crash: crashed below this line",
  "-:0 even::slow: Timed out.",
}, "failures")
h.assert_equal(parsed.synthesis, { tested = 6, passing = 2, failing = 3, crashing = 1 }, "synthesis")

-- gcovr's JSON report (gcovr 8): test files and non-code lines left out.
local coverage = tests.parse_coverage(vim.json.encode({
  files = {
    { file = "src/even.c", lines = { { line_number = 1, count = 1 }, { line_number = 3, count = 2 },
      { line_number = 6, count = 0 }, { line_number = 7, count = 0, ["gcovr/noncode"] = true } } },
    { file = "tests/test_even.c", lines = { { line_number = 3, count = 1 } } },
  },
}), "/project")
h.assert_equal(coverage, { files = { ["/project/src/even.c"] = { hit = { 1, 3 }, missed = { 6 } } }, lines = 3,
  covered = 2 }, "coverage")
h.assert_equal(tests.parse_coverage("not json", "/project"), nil, "a broken report")

-- A real run: unit_tests is built with --coverage and prints Criterion's
-- format (Criterion itself isn't needed), then make fclean cleans up.
local root, cleanup = h.temp_project({
  ["Makefile"] = { "NAME = even", "", "unit_tests: fclean",
    "\tcc --coverage -o unit_tests src/even.c tests/runner.c", "", "tests_run: unit_tests", "\t./unit_tests", "",
    "clean:", "\trm -f *.gcno *.gcda", "", "fclean: clean", "\trm -f unit_tests", "\ttouch fcleaned", "",
    ".PHONY: unit_tests tests_run clean fclean" },
  ["src/even.c"] = { "int is_even(int n)", "{", "    if (n % 2 == 0) {", "        return 1;", "    }", "    return 0;",
    "}" },
  ["tests/runner.c"] = { "#include <stdio.h>", "", "int is_even(int n);", "", "int main(void)", "{",
    "    if (is_even(2) != 1) {", "        return 1;", "    }",
    '    printf("[----] tests/runner.c:7: Assertion Failed\\n");',
    '    printf("[----]   The expression is_even(4) == 0 is false.\\n");',
    '    printf("[FAIL] even::four: (0.00s)\\n");',
    '    printf("[====] Synthesis: Tested: 2 | Passing: 1 | Failing: 1 | Crashing: 0\\n");', "    return 1;", "}" },
})
local even = h.buffer(root .. "/src/even.c", vim.fn.readfile(root .. "/src/even.c"))
local result
tests.run(root, function(r)
  result = r
end)
assert(vim.wait(30000, function()
  return result ~= nil
end), "tests finished")
h.assert_equal(vim.tbl_map(function(item)
  return ("%s:%d %s"):format(vim.fs.basename(item.filename), item.lnum, item.text)
end, result.items), { "runner.c:7 even::four: The expression is_even(4) == 0 is false." }, "the failure")
h.assert_equal(vim.fn.getqflist({ title = 1 }).title:match("^Tests: 1 passed · 1 failed") ~= nil, true,
  "quickfix title")
h.assert_equal(vim.fn.filereadable(root .. "/fcleaned"), 1, "make fclean ran")
h.assert_equal(#vim.fs.find(function(name)
  return name:match("%.gc[dn][ao]$") ~= nil
end, { path = root, limit = math.huge }), 0, "no coverage files left")

local function signs(buf)
  return vim.tbl_map(function(mark)
    return { mark[2] + 1, mark[4].sign_hl_group }
  end, vim.api.nvim_buf_get_extmarks(buf, tests.ns, 0, -1, { details = true }))
end
if vim.fn.executable("gcovr") == 1 then
  h.assert_equal(result.coverage.lines > 0, true, "coverage read")
  h.assert_equal(signs(even), { { 1, "EpitechCoverageHit" }, { 3, "EpitechCoverageHit" },
    { 4, "EpitechCoverageHit" }, { 6, "EpitechCoverageMissed" } }, "signs on the open file")
  assert(notices[#notices]:match("75%% of lines covered"), notices[#notices])
  vim.cmd("EpitechCoverage off")
  h.assert_equal(signs(even), {}, ":EpitechCoverage off")
  vim.cmd("EpitechCoverage on")
  h.assert_equal(#signs(even), 4, ":EpitechCoverage on")
else
  print("Skipping the coverage signs: gcovr is missing")
  h.assert_equal(result.coverage, nil, "no coverage without gcovr")
end

-- A build error is shown instead of test results.
vim.fn.writefile({ "int is_even(int n)", "{", "    return n %", "}" }, root .. "/src/even.c")
result = nil
notices = {}
tests.run(root, function(r)
  result = r
end)
assert(vim.wait(30000, function()
  return notices[#notices] == "The unit tests don't build"
end), "build failure reported")
assert(vim.fn.getqflist({ title = 1 }).title == "make unit_tests failed")
-- gcc points at the `}` after the missing operand, clang at the `%`.
h.assert_equal(vim.list_contains({ 3, 4 }, vim.fn.getqflist()[1].lnum), true, "the build error")
cleanup()

-- Without a unit_tests rule, make tests_run.
root, cleanup = h.temp_project({
  ["Makefile"] = { "tests_run:", '\t@echo "[----] tests/a.c:3: Assertion Failed"', '\t@echo "[FAIL] a::b: (0.00s)"',
    '\t@echo "[====] Synthesis: Tested: 1 | Passing: 0 | Failing: 1 | Crashing: 0"', "\t@false" },
})
result = nil
tests.run(root, function(r)
  result = r
end)
assert(vim.wait(20000, function()
  return result ~= nil
end), "tests_run finished")
h.assert_equal(result.items[1].text, "a::b: Assertion Failed", "tests_run's failure")
cleanup()

h.assert_equal(vim.fn.maparg("<leader>cT", "n", false, true).desc, "Epitech Test", "<leader>cT")
print("Epitech test runner tests passed")
