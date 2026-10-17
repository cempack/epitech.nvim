local plugin = assert(vim.env.EPITECH_NVIM_DIR, "EPITECH_NVIM_DIR is required")
vim.opt.runtimepath:prepend(plugin)
package.path = plugin .. "/lua/?.lua;" .. plugin .. "/lua/?/init.lua;" .. package.path

local h = dofile(plugin .. "/test/helpers.lua")
local check = require("epitech.check")
require("epitech.config").setup()
vim.notify = function() end

local function c_file(name, value)
  return { "int " .. name .. "(void)", "{", "    return " .. value .. ";", "}" }
end
local root, cleanup = h.temp_project({
  ["Makefile"] = { "##", "## EPITECH PROJECT, 2026", "## demo", "## File description:", "## Makefile", "##", "",
    "all:" },
  ["src/a.c"] = c_file("main", 0),
  ["src/b.c"] = c_file("get_value", 4096),
  ["src/Parser.c"] = c_file("get_two", 2),
  ["include/my.h"] = { "#ifndef MY_H_", "    #define MY_H_", "int get_value(void);", "#endif" },
  ["main.o"] = { "binary" },
  ["x.cpp"] = { "int x;" },
})
-- The same canned output for every file: the header's entries come back
-- each time and must be kept once.
local canned = {
  root .. "/src/a.c:3:5: warning: [Banana] [Major] multiple statements on the same line (C-L1)",
  root .. "/src/b.c:1:1: warning: [Banana] [Fatal] inline assembly (C-G10)",
  root .. "/include/my.h:2:1: warning: [Banana] [Minor] guard problem (C-H2)",
  root .. "/include/my.h:2:1: warning: [Banana] [Minor] guard problem (C-H2)",
  "1 warning generated.",
}

local function run()
  local result
  check.run(root, function(r)
    result = r
  end)
  assert(vim.wait(20000, function()
    return result ~= nil
  end), "check finished")
  return result
end

h.with_fake_epiclang(canned, function(calls)
  local result = run()
  h.assert_equal(#calls(), 4, "epiclang ran on every tracked .c and .h")
  h.assert_equal(vim.tbl_map(check.format_entry, result.entries), {
    "src/b.c:1:1: [Fatal] inline assembly (C-G10)",
    "main.o:1:1: [Major] compiled or temporary file in the repository (C-O1)",
    "src/a.c:3:5: [Major] multiple statements on the same line (C-L1)",
    "x.cpp:1:1: [Major] C sources use the .c and .h extensions (C-O2)",
    "include/my.h:2:1: [Minor] guard problem (C-H2)",
    "src/Parser.c:1:1: [Minor] Parser.c isn't snake_case (C-O4)",
    "src/Parser.c:1:5: [Hint] only used in this file (C-A4)",
    "src/Parser.c:3:12: [Hint] name this number? (C-G9)",
    "src/b.c:1:5: [Hint] only used in this file (C-A4)",
    "src/b.c:3:12: [Hint] name this number? (C-G9)",
  }, "entries deduplicated and sorted by severity, file and line")
  h.assert_equal(result.title, "Epitech check: 1 fatal · 3 major · 2 minor · 0 info · 4 hints", "title")
  h.assert_equal(check.failures(result), { "1 Fatal", "3 Major" }, "failing levels")

  -- :EpitechCheck fills the quickfix list (Trouble isn't installed here).
  require("epitech").setup()
  vim.fn.chdir(root)
  vim.cmd("EpitechCheck")
  assert(vim.wait(20000, function()
    return vim.fn.getqflist({ title = 1 }).title:find("Epitech check", 1, true) ~= nil
  end), "quickfix list filled")
  local qf = vim.fn.getqflist({ title = 1, items = 1 })
  h.assert_equal(qf.title, result.title, "quickfix title")
  h.assert_equal({ #qf.items, qf.items[1].text, qf.items[1].type }, { 10, "[Fatal] inline assembly (C-G10)", "E" },
    "quickfix items")
  h.assert_equal(vim.fn.maparg("<leader>cB", "n", false, true).desc, "Epitech Check Project", "<leader>cB")

  -- --ci: lines, summary and exit code, through the real script.
  local function script(args)
    local cmd = { vim.v.progpath, "--clean", "--headless", "-l", plugin .. "/scripts/check.lua" }
    vim.list_extend(cmd, args)
    return vim.system(cmd, { text = true }):wait()
  end
  local ci = script({ "--ci", "--hook", root })
  h.assert_equal(ci.code, 1, "--ci fails on Fatal and Major")
  local out = vim.split(vim.trim(ci.stdout), "\n")
  h.assert_equal(out[1], "src/b.c:1:1: [Fatal] inline assembly (C-G10)", "--ci lines")
  h.assert_equal(out[#out], result.title, "--ci summary")
  h.assert_equal(ci.stderr, "epitech.nvim: 1 Fatal and 3 Major left, push stopped. Run :EpitechCheck to see them, or"
    .. " git push --no-verify to skip.\n", "hook message")
  h.assert_equal(script({ root }).code, 0, "without --ci it never fails")
end)

-- A clean project passes --ci even with hints and Minor problems.
local clean, cleanup_clean = h.temp_project({ ["src/main.c"] = c_file("main", 0), ["src/Big.c"] = c_file("get_big",
  4096) })
h.with_fake_epiclang({}, function()
  local result = vim.system({ vim.v.progpath, "--clean", "--headless", "-l", plugin .. "/scripts/check.lua", "--ci",
    clean }, { text = true }):wait()
  h.assert_equal(result.code, 0, "hints and Minor don't fail the check")
end)
cleanup_clean()

-- Without epiclang, the repository rules and hints still run.
require("epitech.config").setup({ diagnostics = { cmd = "epiclang-that-does-not-exist" } })
local result = run()
h.assert_equal({ result.banana, result.counts.fatal, result.counts.major }, { false, 0, 2 }, "no Banana")
require("epitech.config").setup()

-- :EpitechCheck untrack removes the C-O1 files from git and ignores them.
vim.ui.select = function(items, _, on_choice)
  on_choice(items[1])
end
local untracked
check.untrack(root, function(ok)
  untracked = ok
end)
h.assert_equal(untracked, true, "untracked")
h.assert_equal(vim.system({ "git", "ls-files", "main.o" }, { cwd = root, text = true }):wait().stdout, "",
  "main.o no longer tracked")
h.assert_equal(vim.fn.filereadable(root .. "/main.o"), 1, "the file itself stays")
h.assert_equal(vim.fn.readfile(root .. "/.gitignore"), { "*.o" }, ".gitignore updated")
h.assert_equal(check.unwanted_pattern("#notes.c#"), "#*#", "emacs autosave pattern")

vim.fn.chdir("/")
cleanup()
print("Epitech project check tests passed")
