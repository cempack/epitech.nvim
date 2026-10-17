local plugin = assert(vim.env.EPITECH_NVIM_DIR, "EPITECH_NVIM_DIR is required")
vim.opt.runtimepath:prepend(plugin)
package.path = plugin .. "/lua/?.lua;" .. plugin .. "/lua/?/init.lua;" .. package.path

local h = dofile(plugin .. "/test/helpers.lua")

assert(not pcall(h.assert_equal, { 1 }, { 2 }, "different"), "assert_equal raises on a mismatch")
h.assert_equal({ a = { 1, 2 } }, { a = { 1, 2 } }, "assert_equal on equal tables")

local root, cleanup = h.temp_project({
  ["src/main.c"] = { "int main(void)", "{", "    return 0;", "}" },
  ["include/my.h"] = {},
  ["Makefile"] = { "NAME = demo" },
})
h.assert_equal(vim.fn.readfile(root .. "/src/main.c")[1], "int main(void)", "temp_project writes files")
local tracked = vim.system({ "git", "ls-files" }, { cwd = root, text = true }):wait().stdout
h.assert_equal(vim.split(vim.trim(tracked), "\n"), { "Makefile", "include/my.h", "src/main.c" },
  "temp_project tracks every file")
cleanup()
h.assert_equal(vim.fn.isdirectory(root), 0, "cleanup removes the project")

local path = vim.env.PATH
h.with_fake_epiclang({ "a.c:1:1: warning: [Banana] [Minor] fake (C-G1)" }, function(calls)
  local result = vim.system({ "epiclang", "-x", "c", "a.c" }, { text = true }):wait()
  h.assert_equal(result.code, 0, "fake epiclang exit code")
  h.assert_equal(result.stderr, "a.c:1:1: warning: [Banana] [Minor] fake (C-G1)\n", "fake epiclang stderr")
  h.assert_equal(calls(), { { "-x", "c", "a.c" } }, "fake epiclang records its arguments")
end)
h.assert_equal(vim.env.PATH, path, "with_fake_epiclang restores PATH")
local failed = not pcall(h.with_fake_epiclang, {}, function()
  error("boom")
end)
assert(failed, "with_fake_epiclang re-raises errors")
h.assert_equal(vim.env.PATH, path, "with_fake_epiclang restores PATH after an error")

local buf = h.buffer("/tmp/helpers_check.c", { "int x;" })
h.assert_equal(vim.api.nvim_get_current_buf(), buf, "buffer is current")
h.assert_equal(vim.bo[buf].filetype, "c", "buffer filetype")
h.assert_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), { "int x;" }, "buffer lines")
local again = h.buffer("/tmp/helpers_check.c", {})
assert(again ~= buf and not vim.api.nvim_buf_is_valid(buf), "buffer replaces a buffer with the same name")

print("Test helpers passed")
