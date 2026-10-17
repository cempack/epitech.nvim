-- C-F6: `()` becomes `(void)` on function definitions and prototypes,
-- main() and pointer-returning functions included. Function pointers and
-- function typedefs are left alone: (void) would change which functions
-- they accept.
local fixes = require("epitech.fixes")
local ts = require("epitech.ts")

local M = { id = "void", rules = { "C-F6" } }

-- The edits for every empty parameter list of a named function under tree.
function M.edits(tree, source)
  local edits = {}
  local query = vim.treesitter.query.parse("c", "(function_declarator parameters: (parameter_list) @params)")
  for _, params in query:iter_captures(tree, source) do
    local name = params:parent():field("declarator")[1]
    if params:named_child_count() == 0 and name and name:type() == "identifier" then
      edits[#edits + 1] = { range = fixes.range(params), newText = "(void)", node = params }
    end
  end
  return edits
end

local function strip(edit)
  return { range = edit.range, newText = edit.newText }
end

function M.actions(buf, range)
  local tree = ts.root(buf)
  if not tree then
    return {}
  end
  local actions = {}
  for _, edit in ipairs(M.edits(tree, buf)) do
    if fixes.touches(edit.node, range) then
      actions[#actions + 1] = fixes.action("Add void (C-F6)", "C-F6", buf, { strip(edit) })
    end
  end
  return actions
end

-- Every edit for :EpitechFixAll C-F6.
function M.fix_all(buf)
  local tree = ts.root(buf)
  return tree and vim.tbl_map(strip, M.edits(tree, buf)) or {}
end

M.fix_all_noun = { "function", "functions" }

return M
