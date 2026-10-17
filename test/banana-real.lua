local plugin = assert(vim.env.EPITECH_NVIM_DIR, "EPITECH_NVIM_DIR is required")
vim.opt.runtimepath:prepend(plugin)
package.path = plugin .. "/lua/?.lua;" .. plugin .. "/lua/?/init.lua;" .. package.path

-- Needs the real epiclang (gated in test/run).
local h = dofile(plugin .. "/test/helpers.lua")
local banana = require("epitech.banana")
require("epitech.config").setup()

local root, cleanup = h.temp_project({ ["bad.c"] = vim.fn.readfile(plugin .. "/test/fixtures/banana/bad.c") })
local file = root .. "/bad.c"
local buf = h.buffer(file, vim.fn.readfile(file))
local done
banana.run(buf, function(diagnostics)
  done = diagnostics
end)
assert(vim.wait(30000, function()
  return done ~= nil
end), "epiclang run finished")

local direct = vim.system({ "epiclang", "-x", "c", "-fsyntax-only", file }, { cwd = root, text = true }):wait()
print(direct.stderr)
local expected = banana.parse(direct.stderr, file, root)
local function key(d)
  return ("%d:%d %s"):format(d.lnum, d.col, d.code)
end
local shown = vim.tbl_map(key, vim.diagnostic.get(buf, { namespace = banana.ns }))
table.sort(shown)
local wanted = vim.tbl_map(key, expected)
table.sort(wanted)
h.assert_equal(shown, wanted, "the diagnostics are exactly what epiclang prints")

local codes = {}
for _, d in ipairs(expected) do
  codes[d.code] = true
end
assert(codes["C-L1"], "bad.c triggers C-L1")
assert(codes["C-F2"], "bad.c triggers C-F2")

cleanup()
print("Epitech Banana diagnostics pass against the real epiclang")
