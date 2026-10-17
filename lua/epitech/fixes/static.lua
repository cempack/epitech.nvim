-- C-A4: make a function static when no other file uses it. A non-static
-- prototype seen before a static definition doesn't compile, so the file's
-- own prototypes become static too, and a prototype in a header is removed
-- in the same action (only when nothing in the file uses the function
-- before its definition). With a header prototype that can't go, nothing
-- is offered.
local config = require("epitech.config")
local fixes = require("epitech.fixes")
local project = require("epitech.project")
local static = require("epitech.hints.static")
local ts = require("epitech.ts")

local M = { id = "static", rules = { "C-A4" } }

-- Whether every mention of fn's name in the file, other than its
-- prototypes, comes after the definition starts.
local function used_after_definition(tree, buf, fn)
  local fn_row, fn_col = fn.node:range()
  local prototypes = {}
  for _, proto in ipairs(ts.collect_prototypes(tree, buf)) do
    if proto.name == fn.name then
      prototypes[#prototypes + 1] = proto.node
    end
  end
  local function in_prototype(node)
    for _, proto in ipairs(prototypes) do
      if vim.treesitter.node_contains(proto, { node:range() }) then
        return true
      end
    end
    return false
  end
  local ok = true
  local function walk(node)
    for child in node:iter_children() do
      if child:type() == "identifier" and ts.text(child, buf) == fn.name and not in_prototype(child) then
        local row, col = child:range()
        if row < fn_row or (row == fn_row and col < fn_col) then
          ok = false
        end
      elseif child:named_child_count() > 0 then
        walk(child)
      end
    end
  end
  walk(tree)
  return ok
end

-- An edit deleting a prototype's whole lines, when it's alone on them.
local function delete_prototype(proto)
  local lines = vim.split(proto.source, "\n", { plain = true })
  local start_row, start_col, end_row, end_col = proto.node:range()
  if lines[start_row + 1]:sub(1, start_col):match("%S") or lines[end_row + 1]:sub(end_col + 1):match("%S") then
    return nil
  end
  return { range = fixes.position_range(start_row, 0, end_row + 1, 0), newText = "" }
end

function M.actions(buf, range)
  local path = vim.api.nvim_buf_get_name(buf)
  local used = static.cached_used(buf)
  if not config.options.hints.static or not used or not path:match("%.c$") then
    return {}
  end
  local tree = ts.root(buf)
  if not tree then
    return {}
  end
  local root = project.root(buf)
  local headers
  local actions = {}
  for _, fn in ipairs(static.candidates(tree, buf)) do
    if not used[fn.name] and fixes.touches(fn.declarator, range) then
      local start_row, start_col = fn.node:range()
      local edits = { { range = fixes.position_range(start_row, start_col), newText = "static " } }
      for _, proto in ipairs(ts.prototypes(buf)) do
        if proto.name == fn.name and not ts.has_storage_class(proto.node, buf, "static") then
          local row, col = proto.node:range()
          table.insert(edits, 1, { range = fixes.position_range(row, col), newText = "static " })
        end
      end

      headers = headers or ts.header_prototypes(root)
      local changes, files, removable = {}, {}, true
      for _, proto in ipairs(headers) do
        if proto.name == fn.name then
          local deletion = delete_prototype(proto)
          local uri = vim.uri_from_fname(root .. "/" .. proto.file)
          if not deletion then
            removable = false
          else
            changes[uri] = changes[uri] or {}
            table.insert(changes[uri], deletion)
            if not vim.list_contains(files, proto.file) then
              files[#files + 1] = proto.file
            end
          end
        end
      end

      if #files == 0 and removable then
        actions[#actions + 1] = fixes.action("Add static (C-A4)", "C-A4", buf, edits)
      elseif removable and used_after_definition(tree, buf, fn) then
        changes[fixes.uri(buf)] = edits
        actions[#actions + 1] = {
          title = "Add static and remove the prototype from " .. table.concat(files, ", "),
          kind = "quickfix",
          edit = { changes = changes },
          data = { rule = "C-A4" },
        }
      end
    end
  end
  return actions
end

return M
