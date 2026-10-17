local plugin = assert(vim.env.EPITECH_NVIM_DIR, "EPITECH_NVIM_DIR is required")
vim.opt.runtimepath:prepend(plugin)
package.path = plugin .. "/lua/?.lua;" .. plugin .. "/lua/?/init.lua;" .. package.path

-- Needs the real epiclang (gated in test/run): Banana says nothing about
-- the lines of an expanded snippet.
local h = dofile(plugin .. "/test/helpers.lua")
local expand = dofile(plugin .. "/test/snippet_expand.lua")
local banana = require("epitech.banana")

local root, cleanup = h.temp_project({})
local HEADER = { "/*", "** EPITECH PROJECT, 2026", "** snippets", "** File description:", "** Snippet check", "*/", "",
  "#include <stdlib.h>", "" }
for prefix, context in pairs(expand.contexts()) do
  local file = root .. "/snippet_" .. prefix .. ".c"
  vim.fn.writefile(vim.list_extend(vim.deepcopy(HEADER), context[1]), file)
  local result = vim.system({ "epiclang", "-x", "c", "-fsyntax-only", file }, { cwd = root, text = true }):wait()
  for _, d in ipairs(banana.parse(result.stderr, file, root)) do
    local row = d.lnum + 1 - #HEADER
    assert(row < context[2] or row > context[3], ("%s: %s (%s) on snippet line %d"):format(prefix, d.message, d.code,
      row))
  end
end
cleanup()
print("Epitech snippets pass Banana")
