-- C-C1: an if chain with too many branches, or whose else ifs nest too deep,
-- becomes a switch when every condition compares the same expression with
-- constants. A break or continue in a branch would act on the new switch,
-- and a declaration can't follow a case label, so those chains get a hint
-- instead.
local budget = require("epitech.budget")
local config = require("epitech.config")
local fixes = require("epitech.fixes")
local magic = require("epitech.hints.magic")
local ts = require("epitech.ts")

local M = { id = "switch", rules = { "C-C1" } }

local function unwrap(node)
  while node and node:type() == "parenthesized_expression" do
    node = node:named_child(0)
  end
  return node
end

-- The switched expression: an identifier or a field access on one.
local function subject(node)
  node = unwrap(node)
  if not node then
    return false
  elseif node:type() == "identifier" then
    return true
  elseif node:type() == "field_expression" then
    return subject(node:field("argument")[1])
  end
  return false
end

local function constant(node, source)
  node = unwrap(node)
  local type = node and node:type()
  return type == "number_literal" or type == "char_literal"
    or (type == "identifier" and ts.text(node, source):match("^[A-Z][A-Z0-9_]*$") ~= nil)
end

local function squeeze(text)
  return (text:gsub("%s+", ""))
end

-- The constants a condition compares `x` with: x == K, K == x, or several of
-- those joined with ||. Returns the subject's text and the constants, or nil.
local function comparisons(node, source)
  node = unwrap(node)
  if not node or node:type() ~= "binary_expression" then
    return nil
  end
  local op = node:child(1):type()
  local left, right = node:field("left")[1], node:field("right")[1]
  if op == "||" then
    local x1, ks1 = comparisons(left, source)
    local x2, ks2 = comparisons(right, source)
    if not x1 or not x2 or x1 ~= x2 then
      return nil
    end
    return x1, vim.list_extend(ks1, ks2)
  elseif op == "==" then
    if subject(left) and constant(right, source) then
      return squeeze(ts.text(unwrap(left), source)), { unwrap(right) }
    elseif subject(right) and constant(left, source) then
      return squeeze(ts.text(unwrap(right), source)), { unwrap(left) }
    end
  end
  return nil
end

-- The branches of the chain starting at if_node: { condition?, body }.
local function branches(if_node)
  local result, node = {}, if_node
  while node do
    result[#result + 1] = { condition = node:field("condition")[1], body = node:field("consequence")[1], node = node }
    local alternative = node:field("alternative")[1]
    local inner = alternative and alternative:named_child(0)
    if inner and inner:type() == "if_statement" then
      node = inner
    else
      if inner then
        result[#result + 1] = { body = inner }
      end
      node = nil
    end
  end
  return result
end

local function statements(body)
  if body:type() ~= "compound_statement" then
    return { body }
  end
  local result = {}
  for child in body:iter_children() do
    if child:named() then
      result[#result + 1] = child
    end
  end
  return result
end

-- A break or continue that would bind to the new switch: not inside a loop
-- or switch of the branch itself.
local function loose_jump(body)
  local found
  local function walk(node)
    for child in node:iter_children() do
      local type = child:type()
      if type == "break_statement" or type == "continue_statement" then
        found = found or child
      elseif type ~= "while_statement" and type ~= "for_statement" and type ~= "do_statement"
        and type ~= "switch_statement" and child:named_child_count() > 0 then
        walk(child)
      end
    end
  end
  if body:type() == "break_statement" or body:type() == "continue_statement" then
    return body
  end
  walk(body)
  return found
end

local function ends_flow(last, source)
  if not last then
    return false
  end
  local type = last:type()
  if type == "return_statement" or type == "break_statement" or type == "continue_statement" then
    return true
  end
  local call = type == "expression_statement" and last:named_child(0)
  local fn = call and call:type() == "call_expression" and call:field("function")[1]
  return fn and ts.text(fn, source) == "exit" or false
end

local function source_lines(source)
  if type(source) == "number" then
    return vim.api.nvim_buf_get_lines(source, 0, -1, false)
  end
  return vim.split(source, "\n", { plain = true })
end

-- The lines of a statement, reindented from `from` to `to`.
local function reindent(node, lines, from, to)
  local start_row, _, end_row = node:range()
  local result = {}
  for row = start_row, end_row do
    local line = lines[row + 1]
    if vim.startswith(line, from) then
      line = line:sub(#from + 1)
    else
      line = line:gsub("^%s+", "")
    end
    result[#result + 1] = line == "" and "" or to .. line
  end
  return result
end

-- What converting the chain at if_node means: nil when it isn't a candidate
-- (not a C-C1 problem, or conditions that aren't comparisons with
-- constants); { refused, node } or { lines } otherwise.
function M.plan(if_node, depth, source)
  if if_node:parent():type() == "else_clause" then
    return nil
  end
  local options = config.options.budget
  local chain = branches(if_node)
  local ifs = #chain - (chain[#chain].condition and 0 or 1)
  if #chain <= options.max_branches and depth + ifs - 1 < options.max_depth then
    return nil
  end

  local x, seen = nil, {}
  for _, branch in ipairs(chain) do
    if branch.condition then
      local subject_text, ks = comparisons(branch.condition, source)
      if not subject_text or (x and x ~= subject_text) then
        return nil
      end
      x = subject_text
      branch.constants = ks
      for _, k in ipairs(ks) do
        local text = ts.text(k, source)
        local key = k:type() == "number_literal" and tostring(magic.value(text)) or text
        if seen[key] then
          return nil
        end
        seen[key] = true
      end
    end
  end
  if ifs < 2 then
    return nil
  end

  for _, branch in ipairs(chain) do
    local jump = loose_jump(branch.body)
    if jump then
      return { refused = "a " .. (jump:type():gsub("_statement", "")) .. " in a branch would act on the switch",
        node = if_node }
    end
    for _, statement in ipairs(statements(branch.body)) do
      if statement:type() == "declaration" then
        return { refused = "a branch declares a variable, which can't follow a case label", node = if_node }
      end
    end
  end

  local lines = source_lines(source)
  local row = if_node:range()
  local indent = lines[row + 1]:match("^%s*")
  local result = { "switch (" .. x .. ") {" }
  for _, branch in ipairs(chain) do
    if branch.constants then
      for _, k in ipairs(branch.constants) do
        result[#result + 1] = indent .. "    case " .. ts.text(k, source) .. ":"
      end
    else
      result[#result + 1] = indent .. "    default:"
    end
    local body = statements(branch.body)
    local from
    if body[1] then
      from = lines[body[1]:range() + 1]:match("^%s*")
    end
    for _, statement in ipairs(body) do
      vim.list_extend(result, reindent(statement, lines, from, indent .. "        "))
    end
    if not ends_flow(body[#body], source) then
      result[#result + 1] = indent .. "        break;"
    end
  end
  result[#result + 1] = indent .. "}"
  return { lines = result, node = if_node, subject = x }
end

-- Every chain plan in the function bodies under tree.
function M.plans(tree, source)
  local result = {}
  for _, fn in ipairs(ts.collect_functions(tree, source)) do
    for _, entry in ipairs(budget.depths(fn.body)) do
      if entry.node:type() == "if_statement" and not entry.else_if then
        local plan = M.plan(entry.node, entry.depth, source)
        if plan then
          result[#result + 1] = plan
        end
      end
    end
  end
  return result
end

function M.actions(buf, range)
  local tree = ts.root(buf)
  if not tree then
    return {}
  end
  local actions = {}
  for _, plan in ipairs(M.plans(tree, buf)) do
    local row = plan.node:range()
    if plan.lines and row >= range.start.line and row <= range["end"].line then
      actions[#actions + 1] = fixes.action("Convert to switch (C-C1)", "C-C1", buf, {
        { range = fixes.range(plan.node), newText = table.concat(plan.lines, "\n") },
      }, "refactor.rewrite")
    end
  end
  return actions
end

function M.hints(src, _, ctx)
  local result = {}
  for _, plan in ipairs(M.plans(ctx.tree, src)) do
    if plan.refused then
      local row, col = plan.node:range()
      result[#result + 1] = {
        lnum = row,
        col = col,
        end_lnum = row,
        end_col = col + 2,
        message = "C-C1 no automatic switch: " .. plan.refused,
        code = "C-C1",
      }
    end
  end
  return result
end

return M
