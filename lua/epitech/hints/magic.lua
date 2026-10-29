-- C-G9 (grader): numbers inside function bodies that deserve a name.
-- Macros, enums and global constants live outside bodies, so they're never
-- flagged.
local ts = require("epitech.ts")

local M = { id = "magic" }

function M.enabled(options)
  return options.magic_numbers.enabled
end

-- The value of a C number literal (12, 0x1F, 010, 0b11, 1.5f, 42UL), or nil.
function M.value(text)
  local literal = text:lower():gsub("'", "")
  if literal:match("^0x") then
    return tonumber((literal:sub(3):gsub("[ul]+$", "")), 16)
  elseif literal:match("^0b") then
    return tonumber((literal:sub(3):gsub("[ul]+$", "")), 2)
  elseif literal:match("^0%d+[ul]*$") then
    return tonumber((literal:gsub("[ul]+$", "")), 8)
  end
  return tonumber((literal:gsub("[ulf]+$", "")))
end

local function inside_preprocessor(node, stop)
  local parent = node:parent()
  while parent and parent:id() ~= stop:id() do
    if parent:type():match("^preproc_") then
      return true
    end
    parent = parent:parent()
  end
  return false
end

local COMPARISONS = { ["=="] = true, ["!="] = true, ["<"] = true, [">"] = true, ["<="] = true, [">="] = true }
local ARGUMENTS = { ac = true, argc = true, av = true, argv = true }
local FACTORS = { [2] = true, [10] = true }
-- Calls whose first argument is a file descriptor.
local FD_CALLS = { write = true, read = true, close = true, dup = true, dup2 = true, isatty = true, fstat = true }

-- Numbers every program writes that a grader reads as they are: argument
-- counts and positions (ac != 2, av[1]), 2 and 10 as a factor, divisor or
-- modulus (halving, parity, decimal digits: nb % 10), the standard file
-- descriptors 0 to 2 given to write() and the like, and the value of a
-- const variable, which names it already.
local function obvious(node, value, source)
  local child, parent = node, node:parent()
  if parent:type() == "unary_expression" then
    child, parent = parent, parent:parent()
  end
  local type = parent:type()
  if type == "binary_expression" or type == "assignment_expression" then
    local op = ts.text(parent:child(1), source)
    local left, right = parent:field("left")[1], parent:field("right")[1]
    local other = left:id() == child:id() and right or left
    if COMPARISONS[op] and other:type() == "identifier" and ARGUMENTS[ts.text(other, source)] then
      return true
    end
    local is_right = right:id() == child:id()
    return FACTORS[value] == true and (op == "*" or op == "*=" or (is_right and vim.list_contains({ "/", "%", "/=",
      "%=" }, op)))
  elseif type == "subscript_expression" then
    local argument = parent:field("argument")[1]
    return argument:id() ~= child:id() and argument:type() == "identifier" and ARGUMENTS[ts.text(argument, source)]
  elseif type == "argument_list" then
    local fn = parent:parent():field("function")[1]
    return value >= 0 and value <= 2 and parent:named_child(0):id() == child:id() and fn:type() == "identifier"
      and FD_CALLS[ts.text(fn, source)] == true
  elseif type == "init_declarator" and parent:field("value")[1]:id() == child:id() then
    for qualifier in parent:parent():iter_children() do
      if qualifier:type() == "type_qualifier" and ts.text(qualifier, source) == "const" then
        return true
      end
    end
  end
  return false
end

-- The number literals of the function bodies under tree whose value isn't
-- in allow and that aren't obvious (above): { node, text, value, row, col,
-- end_col }. A literal under a unary minus counts as negative (-1 is
-- allowed), but only the literal itself is reported.
function M.literals(tree, source, allow)
  local allowed = {}
  for _, value in ipairs(allow) do
    allowed[value] = true
  end
  local result = {}
  local function walk(node, body)
    for child in node:iter_children() do
      if child:type() == "number_literal" then
        local text = ts.text(child, source)
        local value = M.value(text)
        local parent = child:parent()
        if value and parent:type() == "unary_expression" and ts.text(parent:child(0), source) == "-" then
          value = -value
        end
        if value and not allowed[value] and not inside_preprocessor(child, body)
          and not obvious(child, value, source) then
          local row, col, _, end_col = child:range()
          result[#result + 1] = { node = child, text = text, value = value, row = row, col = col, end_col = end_col }
        end
      elseif child:named_child_count() > 0 then
        walk(child, body)
      end
    end
  end
  for _, fn in ipairs(ts.collect_functions(tree, source)) do
    walk(fn.body, fn.body)
  end
  return result
end

function M.run(src, _, ctx)
  local result = {}
  for _, literal in ipairs(M.literals(ctx.tree, src, ctx.options.magic_numbers.allow)) do
    result[#result + 1] = {
      lnum = literal.row,
      col = literal.col,
      end_lnum = literal.row,
      end_col = literal.end_col,
      message = "C-G9 name this number?",
      code = "C-G9",
    }
  end
  return result
end

return M
