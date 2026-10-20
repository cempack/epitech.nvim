-- C-F4, C-F1: move the selected statements into a new static function,
-- placed above the current one, and call it where they were. clangd's
-- "Extract to function" only works on C++, since it passes the variables
-- the code changes by reference; in C they become pointers instead.
--
-- Each variable the statements use that's declared outside them is:
-- * moved into the new function, when nothing else uses it, it's declared
--   at the top with a literal (or no) value, and no loop repeats the code;
-- * passed as a pointer when it's an array (it decays anyway);
-- * passed by pointer (`int *count`, `(*count)++`, `p->hp`) when it's a
--   struct (C-F7), its address is taken, or the code changes it and
--   something reads it afterwards;
-- * passed by value otherwise.
-- A selection that runs to the end of the function keeps its returns: the
-- call becomes `return name(…);`. Anything else that would change what the
-- program does is refused with the reason.
local fixes = require("epitech.fixes")
local project = require("epitech.project")
local ts = require("epitech.ts")
local util = require("epitech.util")

local M = { id = "extract", rules = { "C-F4" } }

local LOOPS = { for_statement = true, while_statement = true, do_statement = true }
-- The stdarg macros change the va_list they're given.
local VA_MACROS = { va_arg = true, va_start = true, va_end = true, va_copy = true }
local KEYWORDS = {
  "auto", "break", "case", "char", "const", "continue", "default", "do", "double", "else", "enum", "extern", "float",
  "for", "goto", "if", "inline", "int", "long", "register", "restrict", "return", "short", "signed", "sizeof",
  "static", "struct", "switch", "typedef", "union", "unsigned", "void", "volatile", "while", "bool", "true", "false",
}
local LITERALS = {
  number_literal = true, char_literal = true, string_literal = true, concatenated_string = true, null = true,
  ["true"] = true, ["false"] = true,
}

local function same(a, b)
  return a ~= nil and b ~= nil and a:id() == b:id()
end

local function operator(node, source)
  for child in node:iter_children() do
    if not child:named() then
      return ts.text(child, source), child
    end
  end
end

local function start_byte(node)
  return select(3, node:start())
end

local function end_byte(node)
  return select(3, node:end_())
end

local function line_indent(lines, row)
  return lines[row + 1]:match("^%s*")
end

-- Whether node is alone on its lines.
local function alone(node, lines)
  local start_row, start_col, end_row, end_col = node:range()
  return not lines[start_row + 1]:sub(1, start_col):match("%S") and not lines[end_row + 1]:sub(end_col + 1):match("%S")
end

-- A value that's the same wherever it's computed: a literal, -1, {0, 'a'}.
local function literal(node)
  local type = node:type()
  if LITERALS[type] then
    return true
  elseif type == "unary_expression" or type == "initializer_list" or type == "parenthesized_expression" then
    for child in node:iter_children() do
      if child:named() and not literal(child) then
        return false
      end
    end
    return true
  end
  return false
end

-- The block of fn the rows first..last fall in (a compound statement or a
-- case), the deepest one, and its statements on those rows.
local function selection(fn, first, last)
  local best
  local function inside(node)
    local start_row, _, end_row = node:range()
    if node:type() == "case_statement" then
      return start_row < first and end_row >= last
    end
    return start_row < first and end_row > last
  end
  local function visit(node)
    for child in node:iter_children() do
      local type = child:type()
      if (type == "compound_statement" or type == "case_statement") and inside(child) then
        best = child
      end
      if child:named_child_count() > 0 then
        visit(child)
      end
    end
  end
  if not inside(fn.body) then
    return nil
  end
  best = fn.body
  visit(fn.body)
  local statements = {}
  for child, field in best:iter_children() do
    local start_row, _, end_row = child:range()
    if child:named() and field ~= "value" and end_row >= first and start_row <= last then
      statements[#statements + 1] = child
    end
  end
  if #statements == 0 then
    return nil
  end
  return best, statements
end

-- Every variable the function declares: { [name] = { { id, decl, declarator } } },
-- decl being the declaration or parameter, declarator the variable's own
-- part of it without its initializer. add(declarator, decl) fills it.
local function declarations(src)
  local result = {}
  local function add(declarator, decl)
    local id = declarator and ts.declared_name(declarator)
    if id and id:type() == "identifier" and not ts.function_declarator(declarator) then
      local name = ts.text(id, src)
      result[name] = result[name] or {}
      table.insert(result[name], { id = id, decl = decl, declarator = declarator })
    end
  end
  return result, add
end

-- How one use of a variable treats it: "write", "address" or "read", and
-- whether a `.` is applied to it (then it's a struct or a union).
local function use_kind(id, source)
  local node, member = id, false
  local first = id:parent()
  while first and first:type() == "parenthesized_expression" do
    first = first:parent()
  end
  local dotted = first and first:type() == "field_expression" and operator(first, source) == "."
  while true do
    local parent = node:parent()
    local type = parent:type()
    if type == "parenthesized_expression" then
      node = parent
    elseif type == "field_expression" and same(parent:field("argument")[1], node) and operator(parent, source) == "." then
      member = true
      node = parent
    elseif type == "subscript_expression" and member and same(parent:field("argument")[1], node) then
      -- an array inside a struct is part of the struct
      node = parent
    elseif type == "assignment_expression" and same(parent:field("left")[1], node) then
      return "write", dotted
    elseif type == "update_expression" then
      return "write", dotted
    elseif type == "pointer_expression" and operator(parent, source) == "&" then
      return "address", dotted
    elseif type == "argument_list" then
      local callee = parent:parent():field("function")[1]
      return (callee and VA_MACROS[ts.text(callee, source)]) and "write" or "read", dotted
    else
      return "read", dotted
    end
  end
end

-- The text of node with some of its descendants replaced ({ node, text }).
local function rewrite(source, node, replacements)
  local base = start_byte(node)
  local text = ts.text(node, source)
  local inner = vim.tbl_filter(function(r)
    return start_byte(r[1]) >= base and end_byte(r[1]) <= end_byte(node)
  end, replacements)
  table.sort(inner, function(a, b)
    return start_byte(a[1]) > start_byte(b[1])
  end)
  for _, r in ipairs(inner) do
    text = text:sub(1, start_byte(r[1]) - base) .. r[2] .. text:sub(end_byte(r[1]) - base + 1)
  end
  return text
end

-- The type part of a declaration or parameter (`char const`), without its
-- storage class.
local function type_prefix(decl, declarator, src)
  local first = decl:type() == "parameter_declaration" and declarator or decl:field("declarator")[1]
  local prefix = src:sub(start_byte(decl) + 1, start_byte(first))
  for _, word in ipairs({ "static", "register", "extern", "auto", "inline" }) do
    prefix = prefix:gsub("%f[%w_]" .. word .. "%f[^%w_]", "")
  end
  return vim.trim((prefix:gsub("%s+", " ")))
end

-- declarator's text with `replace` put in place of the node `target` in it.
local function declarator_text(declarator, target, replace, src)
  local text = ts.text(declarator, src)
  local from = start_byte(target) - start_byte(declarator)
  return text:sub(1, from) .. replace .. text:sub(end_byte(target) - start_byte(declarator) + 1)
end

local function refuse(reason)
  return { refused = reason }
end

-- What extracting rows first..last of buf (0-based) would do: nil when the
-- rows aren't statements of a function body, { refused = reason }, or a plan
-- for apply().
function M.plan(buf, first, last)
  local tree = ts.root(buf)
  if not tree then
    return nil
  end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local src = table.concat(lines, "\n")
  local fn
  for _, candidate in ipairs(ts.functions(buf)) do
    local start_row, _, end_row = candidate.body:range()
    if start_row < first and end_row > last then
      fn = candidate
    end
  end
  if not fn then
    return nil
  end
  local block, statements = selection(fn, first, last)
  if not block then
    return nil
  end
  if block:parent():type() == "switch_statement" then
    return refuse("select statements inside one case")
  end
  local first_statement, last_statement = statements[1], statements[#statements]
  local span_start, span_end = start_byte(first_statement), end_byte(last_statement)
  do
    local start_row, start_col = first_statement:range()
    local _, _, end_row, end_col = last_statement:range()
    if lines[start_row + 1]:sub(1, start_col):match("%S") or lines[end_row + 1]:sub(end_col + 1):match("%S") then
      return refuse("the selection shares a line with other code")
    end
  end
  local function in_span(node)
    return start_byte(node) >= span_start and end_byte(node) <= span_end
  end

  -- C-L5: the declarations at the top of the function move all together or
  -- stay, so the call never lands among them.
  local leading = {}
  for child in fn.body:iter_children() do
    if child:named() and child:type() ~= "comment" then
      if child:type() ~= "declaration" then
        break
      end
      leading[#leading + 1] = child
    end
  end
  if block:id() == fn.body:id() then
    local taken = 0
    for _, decl in ipairs(leading) do
      if in_span(decl) then
        taken = taken + 1
      end
    end
    if taken > 0 and (taken < #leading or not same(first_statement, leading[1])) then
      return refuse("select all the declarations at the top of the function, or none")
    end
  end
  local runs = false
  for _, statement in ipairs(statements) do
    if statement:type() ~= "declaration" and statement:type() ~= "comment" then
      runs = true
    end
  end
  if not runs then
    return refuse("the selection only declares variables")
  end

  local tail = block:id() == fn.body:id()
  for child in fn.body:iter_children() do
    if child:named() and child:type() ~= "comment" and start_byte(child) > span_end then
      tail = false
    end
  end

  -- Statements that would change meaning in another function.
  local decls, add = declarations(src)
  for _, param in ipairs(fn.params) do
    add(param:field("declarator")[1], param)
  end
  local identifiers, returns = {}, false
  local reason
  local function check(node)
    for child in node:iter_children() do
      if reason then
        return
      end
      local type = child:type()
      if type == "declaration" then
        for _, declarator in ipairs(child:field("declarator")) do
          add(declarator:type() == "init_declarator" and declarator:field("declarator")[1] or declarator, child)
        end
      elseif type == "identifier" then
        identifiers[#identifiers + 1] = child
      end
      if child:named() and in_span(child) then
        if type == "return_statement" then
          returns = true
        elseif type == "goto_statement" or type == "labeled_statement" then
          reason = "goto and labels can't move to another function"
        elseif type:match("^preproc_") then
          reason = "preprocessor lines can't move to another function"
        elseif type == "break_statement" or type == "continue_statement" then
          local parent, ok = child:parent(), false
          while parent and not ok and parent:id() ~= block:id() do
            ok = LOOPS[parent:type()] or (type == "break_statement" and parent:type() == "switch_statement")
            parent = parent:parent()
          end
          if not ok then
            reason = ("a %s would leave the selection"):format(type == "break_statement" and "break" or "continue")
          end
        end
      end
      if child:named_child_count() > 0 then
        check(child)
      end
    end
  end
  check(fn.body)
  if reason then
    return refuse(reason)
  end
  if returns and not tail then
    return refuse("a return would leave the new function instead of this one; select up to the end of the function"
      .. " to keep it")
  end

  -- The selection runs again when a loop around it does: what it changes
  -- is then read by its next run.
  local in_loop = false
  local parent = block
  while parent and parent:id() ~= fn.body:id() do
    in_loop = in_loop or LOOPS[parent:type()] == true
    parent = parent:parent()
  end

  -- The declaration an identifier refers to: the innermost one in scope.
  local function scope_of(entry)
    return entry.decl:type() == "parameter_declaration" and fn.body or entry.decl:parent()
  end
  local function resolve(id)
    local best
    for _, entry in ipairs(decls[ts.text(id, src)] or {}) do
      local scope = scope_of(entry)
      if vim.treesitter.node_contains(scope, { id:range() }) and start_byte(entry.id) <= start_byte(id)
        and (not best or start_byte(scope) >= start_byte(scope_of(best))) then
        best = entry
      end
    end
    return best
  end

  -- Each variable used in the selection and declared outside it.
  local typedefs
  local root = project.root(buf)
  local variables, order = {}, {}
  for _, id in ipairs(identifiers) do
    local entry = resolve(id)
    if entry and not same(entry.id, id) then
      local name = ts.text(id, src)
      if in_span(entry.decl) then
        if start_byte(id) > span_end then
          return refuse(("%s is declared in the selection and used after it"):format(name))
        end
      else
        local key = entry.id:id()
        local variable = variables[key]
        if not variable then
          variable = { name = name, entry = entry, uses = {}, outside = {} }
          variables[key] = variable
        end
        if in_span(id) then
          if #variable.uses == 0 then
            for _, other in ipairs(order) do
              if other.name == name then
                return refuse(("two variables named %s are used"):format(name))
              end
            end
            order[#order + 1] = variable
          end
          table.insert(variable.uses, id)
          local kind, dotted = use_kind(id, src)
          variable.written = variable.written or kind == "write"
          variable.address = variable.address or kind == "address"
          variable.dotted = variable.dotted or dotted
          local up = id:parent()
          while up and up:type() == "parenthesized_expression" do
            up = up:parent()
          end
          variable.sized = variable.sized or (up ~= nil and up:type() == "sizeof_expression")
        else
          table.insert(variable.outside, id)
        end
      end
    end
  end

  local params, moved, replacements = {}, {}, {}
  for _, variable in ipairs(order) do
    local entry, name = variable.entry, variable.name
    local live_after = in_loop or vim.iter(variable.outside):any(function(id)
      return start_byte(id) > span_end
    end)
    local decl = entry.decl
    local declarators = decl:type() == "declaration" and decl:field("declarator") or {}
    local value = declarators[1] and declarators[1]:type() == "init_declarator" and declarators[1]:field("value")[1]
    local prefix = type_prefix(decl, entry.declarator, src)
    if prefix:find("{", 1, true) then
      return refuse(("%s has a type without a name"):format(name))
    end
    local array = entry.id:parent():type() == "array_declarator" and decl:type() == "declaration"
    typedefs = typedefs or ts.typedefs(root, tree, buf)
    local type = decl:field("type")[1]
    local struct = entry.id:parent():id() == decl:id()
      or (entry.id:parent():type() == "init_declarator" and entry.id:parent():parent():id() == decl:id())
    struct = struct and type and (type:type() == "struct_specifier" or type:type() == "union_specifier"
      or (type:type() == "type_identifier" and (typedefs[ts.text(type, src)] == "struct"
      or typedefs[ts.text(type, src)] == "union")))
    if not in_loop and #variable.outside == 0 and vim.list_contains(leading, decl) and #declarators == 1
      and (not value or literal(value)) and alone(decl, lines) then
      moved[#moved + 1] = decl
    elseif array then
      if entry.id:parent():parent():type() == "array_declarator" then
        return refuse(("%s is an array of arrays"):format(name))
      elseif variable.sized then
        return refuse(("sizeof %s would measure a pointer in the new function"):format(name))
      elseif variable.address then
        return refuse(("the address of the array %s is taken"):format(name))
      end
      params[#params + 1] = { name = name, argument = name,
        text = prefix .. " " .. declarator_text(entry.declarator, entry.id:parent(), "*" .. name, src) }
    elseif struct or variable.dotted or variable.address or (variable.written and live_after) then
      if ts.has_storage_class(decl, src, "register") then
        return refuse(("%s is a register variable, which has no address"):format(name))
      end
      params[#params + 1] = { name = name, argument = "&" .. name,
        text = prefix .. " " .. declarator_text(entry.declarator, entry.id, "*" .. name, src) }
      for _, id in ipairs(variable.uses) do
        local use_parent = id:parent()
        local type_name = use_parent:type()
        if type_name == "field_expression" and same(use_parent:field("argument")[1], id) then
          local op, token = operator(use_parent, src)
          if op == "." then
            replacements[#replacements + 1] = { token, "->" }
          else
            replacements[#replacements + 1] = { id, "(*" .. name .. ")" }
          end
        elseif type_name == "pointer_expression" and operator(use_parent, src) == "&" then
          replacements[#replacements + 1] = { use_parent, name }
        elseif (type_name == "subscript_expression" and same(use_parent:field("argument")[1], id))
          or (type_name == "call_expression" and same(use_parent:field("function")[1], id))
          or type_name == "update_expression" then
          replacements[#replacements + 1] = { id, "(*" .. name .. ")" }
        else
          replacements[#replacements + 1] = { id, "*" .. name }
        end
      end
    else
      params[#params + 1] = { name = name, argument = name,
        text = prefix .. " " .. ts.text(entry.declarator, src) }
    end
  end
  -- In file order: they keep it in the new function, and apply() deletes
  -- them from the bottom up.
  table.sort(moved, function(a, b)
    return start_byte(a) < start_byte(b)
  end)
  if #params > 4 then
    return refuse(("the new function would take %d parameters (C-F5 allows 4)"):format(#params))
  end

  local return_type = "void"
  if tail and returns then
    local prefix = src:sub(start_byte(fn.node) + 1, start_byte(fn.declarator))
    for _, word in ipairs({ "static", "inline", "extern" }) do
      prefix = prefix:gsub("%f[%w_]" .. word .. "%f[^%w_]", "")
    end
    return_type = vim.trim((prefix:gsub("%s+", " ")))
  end
  local locals = {}
  for name, entries in pairs(decls) do
    for _, entry in ipairs(entries) do
      if in_span(entry.decl) then
        locals[name] = true
      end
    end
  end
  return {
    fn = fn,
    statements = statements,
    params = params,
    moved = moved,
    leading = leading,
    replacements = replacements,
    return_type = return_type,
    returns_value = return_type ~= "void" and return_type ~= "",
    locals = locals,
    src = src,
    lines = lines,
  }
end

-- Statement text re-indented for the new function's body (4 spaces).
local function body_lines(text, base_indent)
  local result = {}
  for i, line in ipairs(vim.split(text, "\n", { plain = true })) do
    if i > 1 and vim.startswith(line, base_indent) then
      line = line:sub(#base_indent + 1)
    end
    if line:match("%S") then
      result[#result + 1] = "    " .. line
    end
  end
  return result
end

-- Runs the formatter on a piece of C; returns it unchanged when the
-- formatter can't run (clang-format missing).
local function format_lines(lines)
  local scratch = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(scratch, 0, -1, false, lines)
  local ok = pcall(require("epitech.format").format_buffer, scratch)
  local result = ok and vim.api.nvim_buf_get_lines(scratch, 0, -1, false) or lines
  vim.api.nvim_buf_delete(scratch, { force = true })
  return result
end

-- The new function's lines and the call's, for a plan and a name.
function M.texts(plan, name)
  local src, lines = plan.src, plan.lines
  local declarations, statements = {}, {}
  for _, decl in ipairs(plan.moved) do
    vim.list_extend(declarations, body_lines(ts.text(decl, src), line_indent(lines, decl:range())))
  end
  local taking_declarations = true
  for _, statement in ipairs(plan.statements) do
    local text = body_lines(rewrite(src, statement, plan.replacements), line_indent(lines, statement:range()))
    if taking_declarations and statement:type() == "declaration" then
      vim.list_extend(declarations, text)
    else
      taking_declarations = false
      vim.list_extend(statements, text)
    end
  end
  local params = #plan.params == 0 and "void" or table.concat(vim.tbl_map(function(param)
    return param.text
  end, plan.params), ", ")
  local return_type = plan.return_type
  local signature = ("static %s%s%s(%s)"):format(return_type, return_type:match("%*$") and "" or " ", name, params)
  local fn = { signature, "{" }
  vim.list_extend(fn, declarations)
  if #declarations > 0 then
    fn[#fn + 1] = ""
  end
  vim.list_extend(fn, statements)
  fn[#fn + 1] = "}"

  local call = ("%s(%s);"):format(name, table.concat(vim.tbl_map(function(param)
    return param.argument
  end, plan.params), ", "))
  if plan.returns_value then
    call = "return " .. call
  end
  local indent = line_indent(lines, plan.statements[1]:range())
  local call_lines = { indent .. call }
  if #call_lines[1] > 79 then
    -- C-F3: let the formatter wrap it, inside as many blocks as it's deep.
    local depth = math.max(math.floor(#indent / 4), 1)
    local wrapper = { "void epitech_extract(void)", "{" }
    for level = 1, depth - 1 do
      wrapper[#wrapper + 1] = string.rep("    ", level - 1) .. "    {"
    end
    wrapper[#wrapper + 1] = indent .. call
    for level = depth - 1, 1, -1 do
      wrapper[#wrapper + 1] = string.rep("    ", level - 1) .. "    }"
    end
    wrapper[#wrapper + 1] = "}"
    local formatted = format_lines(wrapper)
    local inner = vim.list_slice(formatted, depth + 2, #formatted - depth)
    if #inner > 0 and vim.startswith(inner[1], indent .. (plan.returns_value and "return " or "") .. name) then
      call_lines = inner
    end
  end
  return format_lines(fn), call_lines
end

-- Why name can't be the new function's, or nil.
function M.check_name(plan, buf, name)
  if not name:match("^[a-z_][a-z0-9_]*$") then
    return "use snake_case (C-F2, C-V1)"
  elseif vim.list_contains(KEYWORDS, name) then
    return name .. " is a C keyword"
  elseif plan.locals[name] or vim.iter(plan.params):any(function(param)
    return param.name == name
  end) then
    return name .. " is a variable here"
  end
  for _, fn in ipairs(ts.functions(buf)) do
    if fn.name == name then
      return name .. " already exists"
    end
  end
  for _, proto in ipairs(ts.prototypes(buf)) do
    if proto.name == name then
      return name .. " already exists"
    end
  end
  if ts.project_functions(project.root(buf))[name] then
    return name .. " already exists in the project"
  end
end

-- Extracts rows first..last of buf into a function called name.
function M.apply(buf, plan, name)
  local fn_lines, call_lines = M.texts(plan, name)
  local first = plan.statements[1]:range()
  local _, _, last = plan.statements[#plan.statements]:range()
  vim.api.nvim_buf_set_lines(buf, first, last + 1, false, call_lines)

  -- Moved declarations leave the top of the function, with the C-L6 blank
  -- line when none is left.
  local remaining = #plan.leading - #plan.moved
  for i = #plan.moved, 1, -1 do
    local decl = plan.moved[i]
    local start_row, _, end_row = decl:range()
    local delete_to = end_row + 1
    if remaining == 0 and decl:id() == plan.leading[#plan.leading]:id()
      and (plan.lines[end_row + 2] or "x"):match("^%s*$") then
      delete_to = end_row + 2
    end
    vim.api.nvim_buf_set_lines(buf, start_row, delete_to, false, {})
  end

  -- Above the function and the comment right above it, one blank line
  -- apart (C-G2).
  local insert_at = plan.fn.start_row
  local previous = plan.fn.node:prev_named_sibling()
  while previous and previous:type() == "comment" and select(3, previous:range()) == insert_at - 1 do
    insert_at = previous:range()
    previous = previous:prev_named_sibling()
  end
  vim.list_extend(fn_lines, { "" })
  vim.api.nvim_buf_set_lines(buf, insert_at, insert_at, false, fn_lines)
end

-- The command behind the action and :EpitechExtract: plans rows
-- first..last (0-based), asks for a name unless given, then extracts.
function M.extract(buf, first, last, name)
  buf = buf == 0 and vim.api.nvim_get_current_buf() or buf
  local plan = M.plan(buf, first, last)
  if not plan then
    return util.notify("Select whole statements inside a function to extract them", vim.log.levels.WARN)
  elseif plan.refused then
    return util.notify("Can't extract to a function: " .. plan.refused, vim.log.levels.WARN)
  end
  local function run(chosen)
    if not chosen or chosen == "" then
      return
    end
    local problem = M.check_name(plan, buf, chosen)
    if problem then
      return util.notify("Can't name it " .. chosen .. ": " .. problem, vim.log.levels.WARN)
    end
    M.apply(buf, plan, chosen)
  end
  if name and name ~= "" then
    return run(name)
  end
  vim.ui.input({ prompt = "Name of the new function: " }, run)
end

-- Rows first..last from an LSP range; a range ending at the start of a
-- line doesn't take that line.
local function rows(range)
  local first, last = range.start.line, range["end"].line
  if last > first and range["end"].character == 0 then
    last = last - 1
  end
  return first, last
end

function M.actions(buf, range)
  -- Only on a selection: the cursor alone would offer it on every line.
  if range.start.line == range["end"].line and range.start.character == range["end"].character then
    return {}
  end
  local first, last = rows(range)
  local plan = M.plan(buf, first, last)
  if not plan then
    return {}
  end
  local title = plan.refused and ("Can't extract to a function: %s"):format(plan.refused)
    or "Extract to a function… (C-F4)"
  return { fixes.command_action(title, "C-F4", "epitech.extract", { fixes.uri(buf), first, last }, "refactor.extract") }
end

M.commands = {
  ["epitech.extract"] = function(command)
    local uri, first, last = unpack(command.arguments)
    M.extract(vim.uri_to_bufnr(uri), first, last)
  end,
}

return M
