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

-- The number literals of the function bodies under tree whose value isn't
-- in allow: { node, text, value, row, col, end_col }. A literal under a
-- unary minus counts as negative (-1 is allowed), but only the literal
-- itself is reported.
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
        if value and not allowed[value] and not inside_preprocessor(child, body) then
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
