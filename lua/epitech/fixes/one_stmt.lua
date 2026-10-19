-- C-L1: one statement per line. Each pattern is its own action: a chained
-- assignment, an increment buried in a statement, an assignment inside an
-- if condition, and `a && f();` used as an if. Where a rewrite could change
-- the program, a hint says why there's no fix.
local fixes = require("epitech.fixes")
local ts = require("epitech.ts")

local M = { id = "one_stmt", rules = { "C-L1" } }

local PURE = {
  identifier = true, number_literal = true, char_literal = true, string_literal = true, concatenated_string = true,
  null = true, ["true"] = true, ["false"] = true, field_expression = true, subscript_expression = true,
  parenthesized_expression = true, pointer_expression = true, binary_expression = true, unary_expression = true,
  cast_expression = true, sizeof_expression = true, type_descriptor = true, field_identifier = true,
  primitive_type = true, type_identifier = true, sized_type_specifier = true, abstract_pointer_declarator = true,
}

-- Whether evaluating node twice, or not at all, changes nothing.
local function pure(node)
  if not PURE[node:type()] then
    return false
  end
  for child in node:iter_children() do
    if child:named() and not pure(child) then
      return false
    end
  end
  return true
end

-- A literal, identifier or constant: the same value wherever it's written.
local function constant(node)
  local type = node:type()
  return type == "number_literal" or type == "char_literal" or type == "string_literal" or type == "null"
    or type == "true" or type == "false" or type == "identifier"
end

local function operator(node, source)
  for child in node:iter_children() do
    if not child:named() then
      return ts.text(child, source)
    end
  end
end

-- Whether node only runs under a condition inside `stop`: the right side of
-- && or ||, or a branch of a ternary.
local function conditional(node, stop)
  local child, parent = node, node:parent()
  while parent and parent:id() ~= stop:id() do
    if parent:type() == "binary_expression" then
      local right = parent:field("right")[1]
      local op = parent:child(1):type()
      if (op == "&&" or op == "||") and right:id() == child:id() then
        return true
      end
    elseif parent:type() == "conditional_expression" and parent:field("condition")[1]:id() ~= child:id() then
      return true
    end
    child, parent = parent, parent:parent()
  end
  return false
end

local function line_indent(src_lines, row)
  return src_lines[row + 1]:match("^%s*")
end

-- The text of `outer` with some of its nodes replaced: { node, text }.
local function rewrite(src, outer, replacements)
  local outer_start = select(3, outer:start())
  local text = src:sub(outer_start + 1, select(3, outer:end_()))
  table.sort(replacements, function(a, b)
    return select(3, a[1]:start()) > select(3, b[1]:start())
  end)
  for _, replacement in ipairs(replacements) do
    local first = select(3, replacement[1]:start()) - outer_start
    local last = select(3, replacement[1]:end_()) - outer_start
    text = text:sub(1, first) .. replacement[2] .. text:sub(last + 1)
  end
  return text
end

-- Control statements whose body can be a single statement without braces.
local BODY_PARENTS = { if_statement = true, else_clause = true, while_statement = true, for_statement = true,
  do_statement = true }

-- The edit replacing statement with lines. In a block, they take its place.
-- As the brace-less body of an if, else or loop, they would leave that
-- body: they get braces (the house style anyway), from the end of the
-- header to the else or do's while that follows. nil when a comment sits in
-- the way or the statement is a label's.
local function replace_statement(statement, lines, src, src_lines)
  local parent = statement:parent()
  local type = parent and parent:type()
  if type == "compound_statement" or type == "case_statement" then
    local indent = line_indent(src_lines, statement:range())
    return { range = fixes.range(statement), newText = table.concat(lines, "\n" .. indent) }
  elseif not BODY_PARENTS[type] then
    return nil
  end
  local before = statement:prev_sibling()
  local after = (type == "if_statement" or type == "do_statement") and statement:next_sibling() or nil
  local _, _, before_end = before:end_()
  local _, _, stop = statement:end_()
  if src:sub(before_end + 1, select(3, statement:start())):match("%S")
    or (after and src:sub(stop + 1, select(3, after:start())):match("%S")) then
    return nil
  end
  local outer = line_indent(src_lines, parent:range())
  local inner = outer .. "    "
  local end_row, end_col = statement:end_()
  if after then
    end_row, end_col = after:start()
  end
  local start_row, start_col = before:end_()
  return {
    range = fixes.position_range(start_row, start_col, end_row, end_col),
    newText = " {\n" .. inner .. table.concat(lines, "\n" .. inner) .. "\n" .. outer .. "}" .. (after and " " or ""),
  }
end

-- a = b = c = v;
local function chained(statement, src, src_lines)
  local expression = statement:named_child(0)
  if not expression or expression:type() ~= "assignment_expression" then
    return nil
  end
  local targets, node = {}, expression
  while node:type() == "assignment_expression" and operator(node, src) == "=" do
    targets[#targets + 1] = node:field("left")[1]
    node = node:field("right")[1]
  end
  if #targets < 2 or node:type() == "assignment_expression" then
    return nil
  end
  for _, target in ipairs(targets) do
    if not pure(target) then
      return nil
    end
  end
  local value = ts.text(node, src)
  local lines = {}
  if constant(node) then
    for _, target in ipairs(targets) do
      lines[#lines + 1] = ts.text(target, src) .. " = " .. value .. ";"
    end
  else
    for i = #targets, 1, -1 do
      local from = i == #targets and value or ts.text(targets[i + 1], src)
      lines[#lines + 1] = ts.text(targets[i], src) .. " = " .. from .. ";"
    end
  end
  local edit = replace_statement(statement, lines, src, src_lines)
  return edit and { title = "Split the chained assignment (C-L1)", edits = { edit } }
end

-- str[i++] = x;
local function increments(statement, src, src_lines)
  local updates = {}
  local function walk(node)
    for child in node:iter_children() do
      if child:type() == "update_expression" then
        updates[#updates + 1] = child
      elseif child:named_child_count() > 0 then
        walk(child)
      end
    end
  end
  walk(statement)
  local expression = statement:named_child(0)
  while expression and expression:type() == "parenthesized_expression" do
    expression = expression:named_child(0)
  end
  if #updates == 0 or (#updates == 1 and expression and updates[1]:id() == expression:id()) then
    return nil
  end
  local names = {}
  for _, update in ipairs(updates) do
    local argument = update:field("argument")[1]
    if argument:type() ~= "identifier" or conditional(update, statement) then
      return nil
    end
    names[#names + 1] = ts.text(argument, src)
  end
  local counts = {}
  local function count(node)
    for child in node:iter_children() do
      if child:type() == "identifier" then
        counts[ts.text(child, src)] = (counts[ts.text(child, src)] or 0) + 1
      elseif child:named_child_count() > 0 then
        count(child)
      end
    end
  end
  count(statement)
  for _, name in ipairs(names) do
    if counts[name] > 1 then
      return { refused = ("%s is used twice on this line, so its behaviour is undefined"):format(name) }
    end
  end

  local before, after, replacements = {}, {}, {}
  for i, update in ipairs(updates) do
    local prefix = update:child(0):type() == "++" or update:child(0):type() == "--"
    local op = prefix and update:child(0):type() or update:child(1):type()
    table.insert(prefix and before or after, names[i] .. op .. ";")
    replacements[#replacements + 1] = { update, names[i] }
  end
  local moved = vim.list_extend(vim.deepcopy(before), after)
  local lines = vim.list_extend(vim.deepcopy(before), { rewrite(src, statement, replacements) })
  vim.list_extend(lines, after)
  local edit = replace_statement(statement, lines, src, src_lines)
  return edit and { title = "Move " .. table.concat(moved, " ") .. " to its own line (C-L1)", edits = { edit } }
end

-- if ((x = f()) != NULL)
local function if_assignment(statement, src, src_lines)
  local condition = statement:field("condition")[1]
  local assignments = {}
  local function walk(node)
    for child in node:iter_children() do
      if child:type() == "assignment_expression" then
        assignments[#assignments + 1] = child
      elseif child:named_child_count() > 0 then
        walk(child)
      end
    end
  end
  walk(condition)
  if #assignments == 0 then
    return nil
  end
  if statement:parent():type() == "else_clause" then
    return { refused = "in an else if, the assignment would run before the earlier conditions" }
  end
  local row, col = statement:range()
  if col ~= #line_indent(src_lines, row) then
    return nil
  end
  local before, replacements = {}, {}
  for _, assignment in ipairs(assignments) do
    if conditional(assignment, condition) then
      return { refused = "the assignment only runs when the condition before it allows" }
    end
    local left = assignment:field("left")[1]
    if not pure(left) then
      return nil
    end
    before[#before + 1] = (ts.text(assignment, src):gsub("%s*\n%s*", " ")) .. ";"
    local node = assignment
    while node:parent():type() == "parenthesized_expression" and node:parent():id() ~= condition:id() do
      node = node:parent()
    end
    replacements[#replacements + 1] = { node, ts.text(left, src) }
  end
  before[#before + 1] = rewrite(src, statement, replacements)
  local edit = replace_statement(statement, before, src, src_lines)
  return edit and { title = "Move the assignment out of the condition (C-L1)", edits = { edit } }
end

local LOOPS = { while_statement = true, do_statement = true, for_statement = true }

-- while ((c = getchar()) != EOF): a hint only.
local function loop_assignment(statement)
  local condition = statement:field("condition")[1]
  if not condition then
    return nil
  end
  local found = false
  local function walk(node)
    for child in node:iter_children() do
      if child:type() == "assignment_expression" then
        found = true
      elseif child:named_child_count() > 0 then
        walk(child)
      end
    end
  end
  walk(condition)
  if found then
    return { refused = "the assignment would have to be repeated before the loop and at the end of its body,"
      .. " and a continue would skip it" }
  end
end

local SIMPLE = { identifier = true, call_expression = true, field_expression = true, subscript_expression = true,
  parenthesized_expression = true }

-- a && f(); and a || f();
local function logical(statement, src, src_lines)
  local expression = statement:named_child(0)
  if not expression or expression:type() ~= "binary_expression" then
    return nil
  end
  local op = expression:child(1):type()
  if op ~= "&&" and op ~= "||" then
    return nil
  end
  local left, right = expression:field("left")[1], expression:field("right")[1]
  local condition = ts.text(left, src):gsub("%s*\n%s*", " ")
  -- if ((a = b)): an assignment keeps its parentheses, as compilers ask.
  if op == "&&" and left:type() == "parenthesized_expression"
    and left:named_child(0):type() ~= "assignment_expression" then
    condition = ts.text(left:named_child(0), src):gsub("%s*\n%s*", " ")
  elseif op == "||" then
    condition = SIMPLE[left:type()] and "!" .. condition or "!(" .. condition .. ")"
  end
  -- One if statement replaces one statement: no braces needed around it.
  local indent = line_indent(src_lines, statement:range())
  return {
    title = ("Turn the %s into an if (C-L1)"):format(op),
    edits = { { range = fixes.range(statement), newText = table.concat({
      "if (" .. condition .. ") {",
      "    " .. ts.text(right, src):gsub("%s*\n%s*", " ") .. ";",
      "}",
    }, "\n" .. indent) } },
  }
end

-- Every C-L1 finding in the function bodies under tree:
-- { node, title, edits } or { node, refused }.
function M.findings(tree, source)
  local src = type(source) == "number" and table.concat(vim.api.nvim_buf_get_lines(source, 0, -1, false), "\n")
    or source
  local src_lines = vim.split(src, "\n", { plain = true })
  local result = {}
  local function add(node, finding)
    if finding then
      finding.node = node
      result[#result + 1] = finding
    end
  end
  local function walk(node)
    for child in node:iter_children() do
      local type = child:type()
      if type == "expression_statement" then
        add(child, chained(child, src, src_lines))
        add(child, increments(child, src, src_lines))
        add(child, logical(child, src, src_lines))
      elseif type == "if_statement" then
        add(child, if_assignment(child, src, src_lines))
      elseif LOOPS[type] then
        add(child, loop_assignment(child))
      end
      if child:named_child_count() > 0 then
        walk(child)
      end
    end
  end
  for _, fn in ipairs(ts.collect_functions(tree, src)) do
    walk(fn.body)
  end
  return result
end

-- The row a finding is reported and offered on: its first line.
local function anchor_row(finding)
  return (finding.node:range())
end

function M.actions(buf, range)
  local tree = ts.root(buf)
  if not tree then
    return {}
  end
  local actions = {}
  for _, finding in ipairs(M.findings(tree, buf)) do
    local row = anchor_row(finding)
    if finding.edits and row >= range.start.line and row <= range["end"].line then
      actions[#actions + 1] = fixes.action(finding.title, "C-L1", buf, finding.edits)
    end
  end
  return actions
end

function M.hints(src, _, ctx)
  local result = {}
  for _, finding in ipairs(M.findings(ctx.tree, src)) do
    if finding.refused then
      local row, col = finding.node:range()
      result[#result + 1] = {
        lnum = row,
        col = col,
        end_lnum = row,
        end_col = #(vim.split(src, "\n", { plain = true })[row + 1] or ""),
        message = "C-L1 no automatic fix: " .. finding.refused,
        code = "C-L1",
      }
    end
  end
  return result
end

return M
