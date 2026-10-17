-- C-G9: extract a number into a macro. C-H1 puts macros in headers, so the
-- #define goes into the project header, inside its include guard.
local config = require("epitech.config")
local fixes = require("epitech.fixes")
local format = require("epitech.format")
local header = require("epitech.header")
local magic = require("epitech.hints.magic")
local project = require("epitech.project")
local ts = require("epitech.ts")
local util = require("epitech.util")

local M = { id = "macro", rules = { "C-G9" } }

local DEFINE = "^%s*#%s*define%s+([%a_][%w_]*)%s+(.-)%s*$"

local function literals(buf)
  return ts.cached(buf, "magic_literals", function()
    local root = ts.root(buf)
    return root and magic.literals(root, buf, config.options.hints.magic_numbers.allow) or {}
  end)
end

function M.actions(buf, range)
  if not config.options.hints.magic_numbers.enabled then
    return {}
  end
  local actions, seen = {}, {}
  for _, literal in ipairs(literals(buf)) do
    local key = literal.row .. ":" .. literal.text
    if fixes.touches(literal.node, range) and not seen[key] then
      seen[key] = true
      actions[#actions + 1] = fixes.command_action(("Extract %s into a macro…"):format(literal.text), "C-G9",
        "epitech.macro", { fixes.uri(buf), literal.row, literal.col, literal.text })
    end
  end
  return actions
end

-- The obvious name for the literal at row, col, or "": BUFFER_SIZE for
-- `char buffer[4096]`, WIDTH for `width = 1920`.
function M.suggest(buf, row, col)
  local root = ts.root(buf)
  local node = root and root:named_descendant_for_range(row, col, row, col)
  local parent = node and node:parent()
  if not parent then
    return ""
  end
  local name
  if parent:type() == "array_declarator" and parent:field("size")[1] and parent:field("size")[1]:id() == node:id() then
    local declared = ts.declared_name(parent)
    name = declared and ts.text(declared, buf) .. "_size"
  elseif parent:type() == "init_declarator" then
    local declared = ts.declared_name(parent)
    name = declared and ts.text(declared, buf)
  elseif parent:type() == "assignment_expression" and parent:field("left")[1]:type() == "identifier" then
    name = ts.text(parent:field("left")[1], buf)
  end
  if not name or #name < 3 then
    return ""
  end
  return name:upper()
end

-- Macros in the project's headers whose value is this number:
-- { name, path }.
function M.existing(root, text)
  local value = magic.value(text)
  local result = {}
  for _, file in ipairs(project.files(root, { "*.h" }) or {}) do
    local path = root .. "/" .. file
    for _, line in ipairs(util.read_lines(path)) do
      local name, body = line:match(DEFINE)
      body = body and body:gsub("^%((.*)%)$", "%1")
      if name and body and (body == text or (body:match("^[%w.']+$") and magic.value(body) == value)) then
        result[#result + 1] = { name = name, path = path }
      end
    end
  end
  return result
end

-- The value a macro already has in the project's headers, if any.
local function defined_value(root, name)
  for _, file in ipairs(project.files(root, { "*.h" }) or {}) do
    for _, line in ipairs(util.read_lines(root .. "/" .. file)) do
      local defined, body = line:match(DEFINE)
      if defined == name then
        return body
      end
    end
  end
end

-- Adds `#define name value` to the header at path, inside its guard after
-- the last #define (the guard's own one at least), indented for C-G3. A
-- missing header is created with an Epitech header and a guard.
function M.insert_define(root, path, name, value)
  util.edit_file(path, function(buf)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    if #lines == 0 or (#lines == 1 and lines[1] == "") then
      local project_name = project.name(root)
      lines = header.new_header(path, project_name, "Declarations for " .. project_name)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    end
    local _, define, endif = header.guard_rows(lines)
    local at = define or 0
    for i = (define or 0) + 1, (endif or #lines + 1) - 1 do
      if lines[i]:match("^%s*#%s*define%s") then
        at = i
      end
    end
    if at == 0 then
      at = #lines
    end
    -- A negative value is parenthesized so `x - NAME` can't become x--5.
    if value:sub(1, 1) == "-" then
      value = "(" .. value .. ")"
    end
    vim.api.nvim_buf_set_lines(buf, at, at, false, { "#define " .. name .. " " .. value })
    format.indent_preprocessor(buf)
  end)
end

-- Replaces the literal at row, col (or every identical one in the buffer's
-- function bodies) with name, defines it in header_path when `define` is
-- set, and includes that header.
local function apply(buf, row, col, text, name, header_path, define, all)
  local root = project.root(buf)
  local edits = {}
  for _, literal in ipairs(literals(buf)) do
    if literal.text == text and (all or (literal.row == row and literal.col == col)) then
      edits[#edits + 1] = {
        range = fixes.position_range(literal.row, literal.col, literal.row, literal.end_col),
        newText = name,
      }
    end
  end
  fixes.apply(buf, edits)
  if define then
    M.insert_define(root, header_path, name, text)
  end
  local file = vim.api.nvim_buf_get_name(buf)
  if util.normalize(file) ~= util.normalize(header_path) then
    util.ensure_include(buf, project.include_name(root, file, header_path))
  end
  util.notify(("%s: %d %s replaced"):format(name, #edits, #edits == 1 and "number" or "numbers"))
end

-- Asks whether to replace this literal or all identical ones, then applies.
local function choose_scope(buf, row, col, text, name, header_path, define)
  local count = 0
  for _, literal in ipairs(literals(buf)) do
    if literal.text == text then
      count = count + 1
    end
  end
  if count < 2 then
    return apply(buf, row, col, text, name, header_path, define, false)
  end
  local all = ("All %d occurrences"):format(count)
  vim.ui.select({ "This one", all }, { prompt = "Replace " .. text }, function(choice)
    if choice then
      apply(buf, row, col, text, name, header_path, define, choice == all)
    end
  end)
end

-- The epitech.macro command: asks for the macro (an existing one with the
-- same value first) and applies.
function M.extract(buf, row, col, text)
  local root = project.root(buf)
  project.project_header(root, function(header_path)
    if not header_path then
      return
    end
    local function ask_name()
      vim.ui.input({ prompt = "Macro name: ", default = M.suggest(buf, row, col) }, function(name)
        if not name or name == "" then
          return
        end
        if not name:match("^[A-Z][A-Z0-9_]*$") then
          return util.notify(name .. " isn't a macro name: use UPPER_SNAKE_CASE (C-V1)", vim.log.levels.ERROR)
        end
        local existing = defined_value(root, name)
        if existing and existing ~= text then
          return util.notify(name .. " is already defined as " .. existing, vim.log.levels.ERROR)
        end
        choose_scope(buf, row, col, text, name, header_path, existing == nil)
      end)
    end

    local existing = M.existing(root, text)
    if #existing == 0 then
      return ask_name()
    end
    local items = vim.list_extend(vim.deepcopy(existing), { { new = true } })
    vim.ui.select(items, {
      prompt = "Name " .. text,
      format_item = function(item)
        return item.new and "New macro…" or ("%s (%s)"):format(item.name, util.relative(item.path, root) or item.path)
      end,
    }, function(choice)
      if not choice then
        return
      elseif choice.new then
        ask_name()
      else
        choose_scope(buf, row, col, text, choice.name, choice.path, false)
      end
    end)
  end)
end

M.commands = {
  ["epitech.macro"] = function(command)
    local uri, row, col, text = unpack(command.arguments)
    M.extract(vim.uri_to_bufnr(uri), row, col, text)
  end,
}

return M
