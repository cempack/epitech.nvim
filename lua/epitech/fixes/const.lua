-- C-A1: make a pointer parameter point to const when the function never
-- modifies the data, in the definition and in every prototype.
local config = require("epitech.config")
local fixes = require("epitech.fixes")
local project = require("epitech.project")
local ts = require("epitech.ts")
local types = require("epitech.hints.types")

local M = { id = "const", rules = { "C-A1" } }

-- The parameter_declaration at index in a prototype's parameter list.
local function nth_param(declarator, index)
  local count = 0
  for child in declarator:field("parameters")[1]:iter_children() do
    if child:type() == "parameter_declaration" then
      count = count + 1
      if count == index then
        return child
      end
    end
  end
end

function M.actions(buf, range)
  if not config.options.hints.types then
    return {}
  end
  local tree = ts.root(buf)
  if not tree then
    return {}
  end
  local root = project.root(buf)
  local headers = ts.header_prototypes(root)
  local actions = {}
  for _, candidate in ipairs(types.const_candidates(tree, buf, { root = root, header_prototypes = headers })) do
    if fixes.touches(candidate.param, range) then
      local edits = { { range = fixes.range(candidate.param), newText = candidate.text } }
      for _, proto in ipairs(ts.prototypes(buf)) do
        local param = proto.name == candidate.fn.name and nth_param(proto.declarator, candidate.index)
        if param then
          edits[#edits + 1] = { range = fixes.range(param), newText = types.const_text(param, buf) }
        end
      end
      local changes = { [fixes.uri(buf)] = edits }
      for _, proto in ipairs(headers) do
        local param = proto.name == candidate.fn.name and nth_param(proto.declarator, candidate.index)
        if param then
          local uri = vim.uri_from_fname(root .. "/" .. proto.file)
          changes[uri] = changes[uri] or {}
          table.insert(changes[uri], { range = fixes.range(param), newText = types.const_text(param, proto.source) })
        end
      end
      local name = ts.text(candidate.name, buf)
      actions[#actions + 1] = {
        title = ("Make %s const (C-A1)"):format(name),
        kind = "quickfix",
        edit = { changes = changes },
        data = { rule = "C-A1" },
      }
    end
  end
  return actions
end

return M
