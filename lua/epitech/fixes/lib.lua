-- A call to a libmy function the project doesn't have yet (my_strdup(…)
-- with no lib/my/my_strdup.c): the action copies it into lib/my, with the
-- functions it calls, and includes my.h.
local fixes = require("epitech.fixes")
local lib = require("epitech.lib")
local project = require("epitech.project")
local ts = require("epitech.ts")
local util = require("epitech.util")

local M = { id = "lib", rules = {} }

-- The libmy functions called on the range's rows: { name = node }.
local function calls(buf, range)
  local root = ts.root(buf)
  local found = {}
  if not root then
    return found
  end
  local function walk(node)
    if not fixes.touches(node, range) then
      return
    end
    if node:type() == "call_expression" then
      local fn = node:field("function")[1]
      local name = fn:type() == "identifier" and ts.text(fn, buf)
      if name and lib.catalog()[name] then
        found[name] = node
      end
    end
    for child in node:iter_children() do
      walk(child)
    end
  end
  walk(root)
  return found
end

function M.actions(buf, range)
  local found = calls(buf, range)
  if next(found) == nil then
    return {}
  end
  local defined = {}
  for _, fn in ipairs(ts.functions(buf)) do
    defined[fn.name] = true
  end
  local root = project.root(buf)
  local actions = {}
  for name in pairs(found) do
    if not defined[name] and vim.list_contains(lib.missing(root, { name }), name) then
      actions[#actions + 1] = fixes.command_action(("Add %s to lib/my"):format(name), nil, "epitech.lib",
        { fixes.uri(buf), name })
    end
  end
  table.sort(actions, function(a, b)
    return a.title < b.title
  end)
  return actions
end

-- The path that includes the project's my.h from file's directory.
function M.include_path(root, file)
  local relative = util.relative(file, root) or vim.fs.basename(file)
  local dir = relative:find("/") and vim.fs.dirname(relative) or ""
  return lib.relative_from(dir, lib.header_path(root))
end

-- Adds name to lib/my, then #include "…/my.h" to buf unless it includes a
-- my.h already.
function M.add(buf, name)
  local root = project.root(buf)
  lib.add(root, { name })
  for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    if line:match('^%s*#%s*include%s*"[^"]*my%.h"') then
      return
    end
  end
  util.ensure_include(buf, M.include_path(root, vim.api.nvim_buf_get_name(buf)))
end

M.commands = {
  ["epitech.lib"] = function(command)
    local uri, name = unpack(command.arguments)
    M.add(vim.uri_to_bufnr(uri), name)
  end,
}

return M
