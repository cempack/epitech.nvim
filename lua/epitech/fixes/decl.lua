-- C-L5, C-L6: move a function's declarations to its top, one variable per
-- declaration. A declaration after the first statement leaves `type name;`
-- at the end of the leading declarations and, when it had an initializer,
-- `name = value;` where it was. for loop initializers stay. When moving
-- would change the program (or not compile), the function gets a hint
-- saying why instead of an action.
local fixes = require("epitech.fixes")
local ts = require("epitech.ts")

local M = { id = "decl", rules = { "C-L5" } }

local function has_child(node, type, source, text)
  for child in node:iter_children() do
    if child:type() == type and (not text or ts.text(child, source) == text) then
      return true
    end
  end
  return false
end

-- Whether the declared object itself is const (const int x, char *const p),
-- not just the data a pointer points to.
local function object_const(declaration, target, source)
  local const = has_child(declaration, "type_qualifier", source, "const")
  local node = target
  while node and node:type() ~= "identifier" do
    if node:type() == "pointer_declarator" then
      const = has_child(node, "type_qualifier", source, "const")
    end
    node = node:field("declarator")[1] or node:named_child(0)
  end
  return const
end

-- An array whose size can't be known at the top of the function (a VLA).
local function variable_length(target, source)
  local node = target
  while node and node:type() ~= "identifier" do
    if node:type() == "array_declarator" then
      local size = node:field("size")[1]
      if size and size:type() ~= "number_literal" and size:type() ~= "sizeof_expression"
        and not (size:type() == "identifier" and ts.text(size, source):match("^[A-Z][A-Z0-9_]*$")) then
        return true
      end
    end
    node = node:field("declarator")[1] or node:named_child(0)
  end
  return false
end

local function is_array(target)
  local node = target
  while node and node:type() ~= "identifier" do
    if node:type() == "array_declarator" then
      return true
    end
    node = node:field("declarator")[1] or node:named_child(0)
  end
  return false
end

-- A declaration's parts: its type text (everything before the first
-- declarator) and, per declarator, the declarator text without the
-- initializer, the identifier and the initializer.
local function parts(declaration, source)
  local declarators = declaration:field("declarator")
  local start_row, start_col = declaration:range()
  local first_row, first_col = declarators[1]:range()
  local text = ts.text(declaration, source)
  local lines = vim.split(text, "\n", { plain = true })
  local type_lines = vim.list_slice(lines, 1, first_row - start_row + 1)
  type_lines[#type_lines] = type_lines[#type_lines]:sub(1, first_col - (first_row == start_row and start_col or 0))
  local result = { type = vim.trim(table.concat(type_lines, " "):gsub("%s+", " ")), declarators = {} }
  for _, declarator in ipairs(declarators) do
    local target, value = declarator, nil
    if declarator:type() == "init_declarator" then
      target, value = declarator:field("declarator")[1], declarator:field("value")[1]
    end
    result.declarators[#result.declarators + 1] = {
      target = target,
      text = ts.text(target, source),
      name = ts.declared_name(target),
      value = value,
    }
  end
  return result
end

local function collapse(text)
  return (text:gsub("%s*\n%s*", " "))
end

-- Why a moved declaration can't be moved, or nil when it can.
local function refusal(declaration, decl, source)
  if has_child(declaration, "storage_class_specifier", source, "extern") then
    return "an extern declaration has to stay where it is"
  end
  for _, d in ipairs(decl.declarators) do
    if variable_length(d.target, source) then
      return "the array's size isn't known at the top of the function"
    end
    if d.value then
      if d.value:type() == "initializer_list" or is_array(d.target) then
        return ("`%s` can't become an assignment"):format(collapse(ts.text(declaration, source)))
      elseif object_const(declaration, d.target, source) then
        return "a const variable can't be assigned later"
      elseif has_child(declaration, "storage_class_specifier", source, "static") then
        return "a static variable's initializer only runs once"
      end
    end
  end
end

-- What fixing fn means: nil when its declarations are fine; else
-- { refused = { node, reason } } or { leading, moved, indent, insert_row }.
function M.plan(fn, source)
  local leading, leading_ids = {}, {}
  for child in fn.body:iter_children() do
    if child:type() == "declaration" then
      leading[#leading + 1] = child
      leading_ids[child:id()] = true
    elseif child:named() then
      break
    end
  end
  local moved = {}
  local function walk(node)
    for child in node:iter_children() do
      if child:type() == "declaration" and not leading_ids[child:id()] then
        if node:type() ~= "for_statement" then
          moved[#moved + 1] = child
        end
      elseif child:named_child_count() > 0 and child:type() ~= "function_definition" then
        walk(child)
      end
    end
  end
  walk(fn.body)

  local needed = #moved > 0
  for _, declaration in ipairs(leading) do
    needed = needed or #declaration:field("declarator") > 1
  end
  if not needed then
    return nil
  end

  -- Comments between the leading declarations would be lost.
  if #leading > 0 then
    local first_row = leading[1]:range()
    local _, _, last_row = leading[#leading]:range()
    for child in fn.body:iter_children() do
      local row = child:range()
      if child:type() == "comment" and row >= first_row and row <= last_row then
        return { refused = { node = child, reason = "a comment sits between the declarations" } }
      end
    end
  end

  local names = {}
  for _, param in ipairs(fn.params) do
    local name = ts.declared_name(param:field("declarator")[1])
    if name then
      names[ts.text(name, source)] = true
    end
  end
  local plan = { leading = {}, moved = {} }
  for _, declaration in ipairs(leading) do
    local decl = parts(declaration, source)
    decl.node = declaration
    plan.leading[#plan.leading + 1] = decl
    for _, d in ipairs(decl.declarators) do
      if d.name then
        names[ts.text(d.name, source)] = true
      end
    end
  end
  for _, declaration in ipairs(moved) do
    local decl = parts(declaration, source)
    decl.node = declaration
    local reason = refusal(declaration, decl, source)
    for _, d in ipairs(decl.declarators) do
      local name = d.name and ts.text(d.name, source)
      if not reason and (not name or names[name]) then
        reason = ("`%s` is declared twice in this function"):format(name or d.text)
      end
      if name then
        names[name] = true
      end
    end
    if reason then
      return { refused = { node = declaration, reason = reason } }
    end
    plan.moved[#plan.moved + 1] = decl
  end

  local first = fn.body:named_child(0)
  while first and first:type() == "comment" do
    first = first:next_named_sibling()
  end
  local _, indent_col = (first or fn.body):range()
  plan.indent = string.rep(" ", first and indent_col or 4)
  return plan
end

local function lines_of(source, start_row, end_row)
  if type(source) == "number" then
    return vim.api.nvim_buf_get_lines(source, start_row, end_row + 1, false)
  end
  return vim.list_slice(vim.split(source, "\n", { plain = true }), start_row + 1, end_row + 1)
end

-- The text edits that carry out a plan.
function M.edits(fn, plan, source)
  local block = {}
  for _, decl in ipairs(plan.leading) do
    local start_row, _, end_row = decl.node:range()
    if #decl.declarators == 1 then
      vim.list_extend(block, lines_of(source, start_row, end_row))
    else
      for _, d in ipairs(decl.declarators) do
        local value = d.value and " = " .. collapse(ts.text(d.value, source)) or ""
        block[#block + 1] = plan.indent .. decl.type .. " " .. d.text .. value .. ";"
      end
    end
  end
  for _, decl in ipairs(plan.moved) do
    for _, d in ipairs(decl.declarators) do
      block[#block + 1] = plan.indent .. decl.type .. " " .. d.text .. ";"
    end
  end

  local edits = {}
  local after_row
  if #plan.leading > 0 then
    local first_row = plan.leading[1].node:range()
    local _, _, last_row = plan.leading[#plan.leading].node:range()
    after_row = last_row + 1
    edits[#edits + 1] = { first_row, last_row + 1, block }
  else
    after_row = fn.body:range() + 1
    edits[#edits + 1] = { after_row, after_row, block }
  end
  -- C-L6: one blank line after the declarations.
  local next_line = lines_of(source, after_row, after_row)[1]
  if next_line and not next_line:match("^%s*$") and not next_line:match("^%s*}") then
    table.insert(block, "")
  end

  for _, decl in ipairs(plan.moved) do
    local start_row, _, end_row = decl.node:range()
    local indent = lines_of(source, start_row, start_row)[1]:match("^%s*")
    -- A blank line after it was the block's own C-L6 line; inside a
    -- function, only the one after the top declarations may stay.
    while (lines_of(source, end_row + 1, end_row + 1)[1] or "x"):match("^%s*$") do
      end_row = end_row + 1
    end
    local assignments = {}
    for _, d in ipairs(decl.declarators) do
      if d.value then
        assignments[#assignments + 1] = indent .. ts.text(d.name, source) .. " = " .. collapse(ts.text(d.value, source))
          .. ";"
      end
    end
    edits[#edits + 1] = { start_row, end_row + 1, assignments }
  end

  return vim.tbl_map(function(edit)
    local text = table.concat(edit[3], "\n")
    return { range = fixes.position_range(edit[1], 0, edit[2], 0), newText = #edit[3] > 0 and text .. "\n" or "" }
  end, edits)
end

-- The declarations an action or a hint is shown on.
local function anchors(plan)
  local result = {}
  for _, decl in ipairs(plan.moved) do
    result[#result + 1] = decl.node
  end
  for _, decl in ipairs(plan.leading) do
    if #decl.declarators > 1 then
      result[#result + 1] = decl.node
    end
  end
  return result
end

function M.actions(buf, range)
  local actions = {}
  for _, fn in ipairs(ts.functions(buf)) do
    local plan = M.plan(fn, buf)
    if plan and not plan.refused then
      for _, node in ipairs(anchors(plan)) do
        if fixes.touches(node, range) then
          actions[#actions + 1] = fixes.action("Move declarations to the top (C-L5)", "C-L5", buf, M.edits(fn, plan, buf))
          break
        end
      end
    end
  end
  return actions
end

function M.hints(src, _, ctx)
  local result = {}
  for _, fn in ipairs(ts.collect_functions(ctx.tree, src)) do
    local plan = M.plan(fn, src)
    if plan and plan.refused then
      local row, col, end_row, end_col = plan.refused.node:range()
      result[#result + 1] = {
        lnum = row,
        col = col,
        end_lnum = end_row,
        end_col = end_col,
        message = "C-L5 no automatic fix: " .. plan.refused.reason,
        code = "C-L5",
      }
    end
  end
  return result
end

return M
