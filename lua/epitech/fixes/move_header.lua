-- C-H1: types, struct, enum and union declarations, macros and non-static
-- prototypes belong in a header. In a .c file they get a hint and the
-- action "Move to include/x.h": into the header's guard, before its first
-- prototype when there is one (types come before the prototypes using
-- them), with the #include added to the .c. A static function's
-- prototype can't go in a header: the action moves the definition above its
-- first use and deletes the prototype. Non-const globals are C-G4, which
-- Banana reports; they're left alone.
local format = require("epitech.format")
local header = require("epitech.header")
local fixes = require("epitech.fixes")
local project = require("epitech.project")
local ts = require("epitech.ts")
local util = require("epitech.util")

local M = { id = "move_header", rules = { "C-H1" } }

local MOVABLE = {
  type_definition = "type",
  struct_specifier = "type",
  enum_specifier = "type",
  union_specifier = "type",
  preproc_def = "macro",
  preproc_function_def = "macro",
}

-- The top-level items of a .c file that belong in a header:
-- { node, kind ("type", "macro", "prototype", "static_prototype"), name }.
function M.items(tree, source)
  local prototypes = {}
  for _, proto in ipairs(ts.collect_prototypes(tree, source)) do
    prototypes[proto.node:id()] = proto
  end
  local result = {}
  for child in tree:iter_children() do
    local kind = MOVABLE[child:type()]
    local proto = prototypes[child:id()]
    if kind then
      result[#result + 1] = { node = child, kind = kind }
    elseif proto and proto.node:parent():id() == tree:id() then
      local static = ts.has_storage_class(child, source, "static")
      result[#result + 1] = { node = child, kind = static and "static_prototype" or "prototype", name = proto.name }
    end
  end
  return result
end

-- The header items move to, when it's known without asking:
-- include/<basename>.h, else the remembered project header.
function M.target(root, file)
  local own = root .. "/include/" .. vim.fn.fnamemodify(file, ":t:r") .. ".h"
  if vim.fn.filereadable(own) == 1 then
    return own
  end
  local remembered = project.state(root).header
  if remembered and vim.fn.filereadable(root .. "/" .. remembered) == 1 then
    return root .. "/" .. remembered
  end
end

local function source_lines(source)
  if type(source) == "number" then
    return vim.api.nvim_buf_get_lines(source, 0, -1, false)
  end
  return vim.split(source, "\n", { plain = true })
end

-- The first and last rows a node covers. A directive's node ends at column
-- 0 of the next row, its newline included.
local function rows(node)
  local start_row, _, end_row, end_col = node:range()
  if end_col == 0 and end_row > start_row then
    end_row = end_row - 1
  end
  return start_row, end_row
end

-- Whole rows an item covers, with the blank line after it when it sits
-- between blank lines (so removing it doesn't leave two in a row).
local function item_rows(node, lines)
  local start_row, end_row = rows(node)
  if (lines[end_row + 2] or "x"):match("^%s*$") and (start_row == 0 or lines[start_row]:match("^%s*$")) then
    end_row = end_row + 1
  end
  return start_row, end_row
end

-- For a static prototype: the definition and the first top-level item
-- using the function, or nil when there's no definition or use to move it
-- above.
local function definition_and_first_use(tree, source, name)
  local definition, first_use
  for child in tree:iter_children() do
    if child:type() == "function_definition" then
      local fn = ts.describe(child, source)
      if fn and fn.name == name then
        definition = child
      elseif not first_use then
        local function uses(node)
          for c in node:iter_children() do
            if c:type() == "identifier" and ts.text(c, source) == name then
              return true
            elseif c:named_child_count() > 0 and uses(c) then
              return true
            end
          end
          return false
        end
        if uses(child) then
          first_use = child
        end
      end
    end
  end
  return definition, first_use
end

-- Comments right above a node (an Epitech function comment) move with it.
local function with_comments(node)
  local first = node
  local previous = node:prev_sibling()
  while previous and previous:type() == "comment" and select(3, previous:range()) + 1 >= first:range() do
    first = previous
    previous = previous:prev_sibling()
  end
  return first
end

-- The edits for a static prototype: delete it, and move the definition
-- (with its comment) above its first use when it comes after it.
function M.static_edits(tree, buf, item)
  local lines = source_lines(buf)
  local definition, first_use = definition_and_first_use(tree, buf, item.name)
  if not definition then
    return nil
  end
  local edits = {}
  local proto_start, proto_end = item_rows(item.node, lines)
  edits[#edits + 1] = { range = fixes.position_range(proto_start, 0, proto_end + 1, 0), newText = "" }
  if not first_use or first_use:range() > definition:range() then
    return edits, "Remove the static prototype (C-H1)"
  end
  local top = with_comments(definition)
  local start_row = top:range()
  local _, _, end_row = definition:range()
  local moved = vim.list_slice(lines, start_row + 1, end_row + 1)
  local remove_start, remove_end = start_row, end_row
  if (lines[remove_start] or "x"):match("^%s*$") then
    remove_start = remove_start - 1
  end
  edits[#edits + 1] = { range = fixes.position_range(remove_start, 0, remove_end + 1, 0), newText = "" }
  local use_row = with_comments(first_use):range()
  edits[#edits + 1] = {
    range = fixes.position_range(use_row, 0),
    newText = table.concat(moved, "\n") .. "\n\n",
  }
  return edits, "Move the definition above its first use (C-H1)"
end

-- Inserts lines into the header at path: before its first prototype when
-- there is one, else before the guard's #endif.
function M.insert(path, lines)
  util.edit_file(path, function(buf)
    local current = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    if #current <= 1 and (current[1] or "") == "" then
      local root = project.root(path)
      local name = project.name(root)
      current = header.new_header(path, name, "Declarations for " .. name)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, current)
    end
    -- Types and macros go before the first prototype that uses them.
    local at
    local src = table.concat(current, "\n")
    local tree = ts.parse_string(src)
    local prototypes = tree and ts.collect_prototypes(tree, src) or {}
    if prototypes[1] then
      at = prototypes[1].node:start()
    end
    if not at then
      local _, _, endif = header.guard_rows(current)
      at = endif and endif - 1 or #current
    end
    local block = vim.deepcopy(lines)
    if at > 0 and not current[at]:match("^%s*$") then
      table.insert(block, 1, "")
    end
    if current[at + 1] and not current[at + 1]:match("^%s*$") then
      block[#block + 1] = ""
    end
    vim.api.nvim_buf_set_lines(buf, at, at, false, block)
    format.indent_preprocessor(buf)
  end)
end

-- Moves the item at row of buf into the header at path.
function M.move(buf, row, path)
  local tree = ts.root(buf)
  local item
  for _, candidate in ipairs(tree and M.items(tree, buf) or {}) do
    if candidate.node:range() == row and candidate.kind ~= "static_prototype" then
      item = candidate
    end
  end
  if not item then
    return util.notify("Nothing to move here anymore", vim.log.levels.WARN)
  end
  local lines = source_lines(buf)
  local start_row, end_row = rows(item.node)
  -- Directives get their C-G3 indentation in the header; code keeps its own.
  local moved = vim.tbl_map(function(line)
    return line:match("^%s*#") and (line:gsub("^%s+", "")) or line
  end, vim.list_slice(lines, start_row + 1, end_row + 1))
  local remove_start, remove_end = item_rows(item.node, lines)
  M.insert(path, moved)
  vim.api.nvim_buf_set_lines(buf, remove_start, remove_end + 1, false, {})
  local root = project.root(buf)
  util.ensure_include(buf, project.include_name(root, vim.api.nvim_buf_get_name(buf), path))
  util.notify("Moved to " .. (util.relative(path, root) or path))
end

function M.actions(buf, range)
  local file = vim.api.nvim_buf_get_name(buf)
  local tree = ts.root(buf)
  if not file:match("%.c$") or not tree then
    return {}
  end
  local root = project.root(buf)
  local target = M.target(root, file)
  local title = target and "Move to " .. (util.relative(target, root) or target) .. " (C-H1)"
    or "Move to the project header… (C-H1)"
  local actions = {}
  for _, item in ipairs(M.items(tree, buf)) do
    if fixes.touches(item.node, range) then
      if item.kind == "static_prototype" then
        local edits, static_title = M.static_edits(tree, buf, item)
        if edits then
          actions[#actions + 1] = fixes.action(static_title, "C-H1", buf, edits)
        end
      else
        actions[#actions + 1] = fixes.command_action(title, "C-H1", "epitech.move_header",
          { fixes.uri(buf), (item.node:range()) })
      end
    end
  end
  return actions
end

-- The C-H1 hints. They guess at the rule like any hint, so Banana's C-H1
-- on the same line replaces them (keep = false).
function M.hints(src, path, ctx)
  if not path:match("%.c$") then
    return {}
  end
  local result = {}
  for _, item in ipairs(M.items(ctx.tree, src)) do
    local row, col, _, end_col = item.node:range()
    local message = item.kind == "static_prototype"
      and "C-H1 define this static function before its first use instead"
      or "C-H1 belongs in a header"
    local first_line = vim.split(src, "\n", { plain = true })[row + 1] or ""
    result[#result + 1] = {
      lnum = row,
      col = col,
      end_lnum = row,
      end_col = math.min(end_col, #first_line),
      message = message,
      code = "C-H1",
      user_data = { keep = false },
    }
  end
  return result
end

M.commands = {
  ["epitech.move_header"] = function(command)
    local uri, row = unpack(command.arguments)
    local buf = vim.uri_to_bufnr(uri)
    local root = project.root(buf)
    local target = M.target(root, vim.api.nvim_buf_get_name(buf))
    if target then
      return M.move(buf, row, target)
    end
    project.project_header(root, function(path)
      if path then
        M.move(buf, row, path)
      end
    end)
  end,
}

return M
