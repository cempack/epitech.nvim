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
-- Typedefs belong in headers (C-H1): those snippets are checked in a .h,
-- inside an include guard.
local IN_HEADER = { tdef = true, tenum = true }
for prefix, context in pairs(expand.contexts()) do
  local header = IN_HEADER[prefix]
  local file = root .. "/snippet_" .. prefix .. (header and ".h" or ".c")
  local before = vim.deepcopy(HEADER)
  local after = {}
  if header then
    local guard = "SNIPPET_" .. prefix:upper() .. "_H_"
    vim.list_extend(before, { "#ifndef " .. guard, "    #define " .. guard, "" })
    after = { "", "#endif" }
  end
  vim.fn.writefile(vim.list_extend(vim.list_extend(vim.deepcopy(before), context[1]), after), file)
  local result = vim.system({ "epiclang", "-x", "c", "-fsyntax-only", file }, { cwd = root, text = true }):wait()
  for _, d in ipairs(banana.parse(result.stderr, file, root)) do
    local row = d.lnum + 1 - #before
    assert(row < context[2] or row > context[3], ("%s: %s (%s) on snippet line %d"):format(prefix, d.message, d.code,
      row))
  end
end
cleanup()
print("Epitech snippets pass Banana")
