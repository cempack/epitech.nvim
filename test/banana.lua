local plugin = assert(vim.env.EPITECH_NVIM_DIR, "EPITECH_NVIM_DIR is required")
vim.opt.runtimepath:prepend(plugin)
package.path = plugin .. "/lua/?.lua;" .. plugin .. "/lua/?/init.lua;" .. package.path

local h = dofile(plugin .. "/test/helpers.lua")
local banana = require("epitech.banana")
local config = require("epitech.config")
config.setup()

local ERROR, WARN, INFO = vim.diagnostic.severity.ERROR, vim.diagnostic.severity.WARN, vim.diagnostic.severity.INFO

local root, cleanup = h.temp_project({
  ["src/main.c"] = { "int main(void)", "{", "    return 0;", "}" },
  ["include/my.h"] = { "int f();" },
})
local main = root .. "/src/main.c"
local stderr = table.concat({
  "In file included from " .. main .. ":1:",
  root .. "/include/my.h:1:5: warning: [Banana] [Major] function without parameters (C-F6)",
  main .. ":3:50: warning: [Banana] [Major] multiple statements on the same line (C-L1)",
  "src/main.c:1:1: warning: [Banana] [Minor] missing Epitech header (C-G1)",
  main .. ": warning: [Banana] [Minor] the file name isn't snake_case (C-O4)",
  main .. ":2:1: warning: [Banana] [Fatal] inline assembly (C-G10)",
  main .. ":4:2: warning: [Banana] [Info] missing newline at end of file (C-A3)",
  main .. ":5:3: error: use of undeclared identifier 'x'",
  root .. "/include/my.h:1:5: warning: [Banana] [Major] function without parameters (C-F6)",
  "3 warnings and 1 error generated.",
}, "\n")

local function summary(diagnostics)
  return vim.tbl_map(function(d)
    return { d.lnum, d.col, d.severity, d.code, d.message }
  end, diagnostics)
end

h.assert_equal(summary(banana.parse(stderr, main, root)), {
  { 2, 49, ERROR, "C-L1", "multiple statements on the same line" },
  { 0, 0, WARN, "C-G1", "missing Epitech header" },
  { 0, 0, WARN, "C-O4", "the file name isn't snake_case" },
  { 1, 0, ERROR, "C-G10", "FATAL: inline assembly" },
  { 3, 1, INFO, "C-A3", "missing newline at end of file" },
}, "entries for main.c: header repeats, clang errors and summaries dropped")
local first = banana.parse(stderr, main, root)[1]
h.assert_equal(first.source, "Banana", "source")
h.assert_equal(first.user_data, { path = main, level = "major" }, "user_data")

-- Without a file, every entry is kept, and a header's repeats only once.
local all = banana.parse(stderr, nil, root)
h.assert_equal(#all, 6, "every entry, deduplicated")
h.assert_equal(all[1].user_data.path, root .. "/include/my.h", "header entry path")
h.assert_equal(banana.parse("", main, root), {}, "clean file")

-- End to end, with the fake epiclang.
local buf = h.buffer(main, vim.fn.readfile(main))
local done
h.with_fake_epiclang(vim.split(stderr, "\n"), function(calls)
  banana.run(buf, function(diagnostics)
    done = diagnostics
  end)
  assert(vim.wait(5000, function()
    return done ~= nil
  end), "epiclang run finished")
  h.assert_equal(calls(), {
    { "-x", "c", "-fsyntax-only", "-I" .. root .. "/include", "-I" .. root, main },
  }, "epiclang arguments")
end)
local shown = vim.diagnostic.get(buf, { namespace = banana.ns })
table.sort(shown, function(a, b)
  return a.lnum < b.lnum or (a.lnum == b.lnum and a.code < b.code)
end)
h.assert_equal(vim.tbl_map(function(d)
  return d.code
end, shown), { "C-G1", "C-O4", "C-G10", "C-L1", "C-A3" }, "diagnostics set on the buffer")

-- A second save kills the first run; only the last result counts.
h.with_fake_epiclang({ main .. ":1:1: warning: [Banana] [Minor] trailing space (C-G7)" }, function(calls)
  done = nil
  banana.run(buf)
  banana.run(buf, function(diagnostics)
    done = diagnostics
  end)
  assert(vim.wait(5000, function()
    return done ~= nil
  end), "second run finished")
  -- The killed run may die before the fake records it.
  assert(#calls() >= 1, "runs started")
end)
h.assert_equal(summary(vim.diagnostic.get(buf, { namespace = banana.ns })), {
  { 0, 0, WARN, "C-G7", "trailing space" },
}, "diagnostics replaced")

-- Saving runs it through the autocmds.
banana.setup(config.options)
h.with_fake_epiclang({ main .. ":2:1: warning: [Banana] [Minor] saved (C-L4)" }, function()
  vim.cmd("silent write!")
  assert(vim.wait(5000, function()
    local diagnostics = vim.diagnostic.get(buf, { namespace = banana.ns })
    return diagnostics[1] and diagnostics[1].code == "C-L4"
  end), "diagnostics after :write")
end)

-- An unnamed buffer is skipped.
local notices = {}
vim.notify = function(message)
  notices[#notices + 1] = message
end
h.with_fake_epiclang({}, function(calls)
  banana.run(vim.api.nvim_create_buf(true, false))
  h.assert_equal(calls(), {}, "unnamed buffer skipped")
end)

-- Without epiclang: one notice per session, then nothing.
config.setup({ diagnostics = { cmd = "epiclang-that-does-not-exist" } })
banana.run(buf)
banana.run(buf)
h.assert_equal(notices, { "epiclang-that-does-not-exist not found: live Banana diagnostics are off" },
  "one notice when epiclang is missing")

-- diagnostics.enabled = false installs no autocmd.
banana.setup(config.setup({ diagnostics = { enabled = false } }))
h.assert_equal(#vim.api.nvim_get_autocmds({ group = "epitech.banana" }), 0, "no autocmds when disabled")

cleanup()
print("Epitech Banana diagnostics tests passed")
