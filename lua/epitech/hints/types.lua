-- C-A1 and C-A2 (grader, Info): pointer parameters whose data is never
-- modified could point to const, and an int holding strlen() or sizeof
-- would be a size_t. The C-A1 check is conservative: any use it can't
-- classify for sure means no hint.
local ts = require("epitech.ts")

local M = { id = "types" }

function M.enabled(options)
  return options.types
end

-- Library functions whose pointer parameters at these positions are const.
M.const_params = {
  write = { 2 }, strlen = { 1 }, strcmp = { 1, 2 }, strncmp = { 1, 2 }, strdup = { 1 }, strndup = { 1 },
  strchr = { 1 }, strrchr = { 1 }, strstr = { 1, 2 }, strcpy = { 2 }, strncpy = { 2 }, strcat = { 2 },
  strncat = { 2 }, memcmp = { 1, 2 }, memcpy = { 2 }, memmove = { 2 }, printf = { 1 }, dprintf = { 2 },
  puts = { 1 }, fputs = { 1 }, atoi = { 1 }, atol = { 1 }, open = { 1 }, access = { 1 }, stat = { 1 },
  opendir = { 1 }, execve = { 1 }, getenv = { 1 }, perror = { 1 },
}

local function operator(node, source)
  local first = node:child(0)
  return first and ts.text(first, source)
end

local function has_const(param, source)
  for child in param:iter_children() do
    if child:type() == "type_qualifier" and ts.text(child, source) == "const" then
      return true
    end
  end
  return false
end

-- The parent of node, skipping parentheses, and the child on the way.
local function up(node)
  local parent = node:parent()
  while parent and parent:type() == "parenthesized_expression" do
    node = parent
    parent = parent:parent()
  end
  return parent, node
end

local function same(a, b)
  return a ~= nil and b ~= nil and a:id() == b:id()
end

-- Whether a call passes `arg` where the callee takes a pointer to const.
local function const_argument(call, arg, source, lookup)
  local name = call:field("function")[1]
  if not name or name:type() ~= "identifier" then
    return false
  end
  local index = 0
  for child in call:field("arguments")[1]:iter_children() do
    if child:named() and child:type() ~= "comment" then
      index = index + 1
      if same(child, arg) then
        break
      end
    end
  end
  local fname = ts.text(name, source)
  if M.const_params[fname] then
    return vim.list_contains(M.const_params[fname], index)
  end
  return lookup(fname, index) == true
end

-- The stdarg macros modify the va_list they're given.
local VA_MACROS = { va_arg = true, va_start = true, va_end = true, va_copy = true }

-- What happens to pointed-to data designated by node (*p, p[i], p->f):
-- "write", "unclear" or "read". `decays` is set when the data might be an
-- array (a struct member, a va_list…): used as a value, it then becomes a
-- pointer to the caller's data instead of a copy.
local function access(node, source, lookup, decays)
  while true do
    local parent, child = up(node)
    local type = parent and parent:type()
    if type == "assignment_expression" then
      if same(parent:field("left")[1], child) then
        return "write"
      end
      return decays and "unclear" or "read"
    elseif type == "update_expression" then
      return "write"
    elseif type == "pointer_expression" and operator(parent, source) == "&" then
      return "unclear"
    elseif (type == "field_expression" or type == "subscript_expression") and same(parent:field("argument")[1], child) then
      decays = decays or type == "field_expression"
      node = parent
    elseif type == "pointer_expression" then
      node = parent
    elseif type == "argument_list" then
      local fn = parent:parent():field("function")[1]
      if fn and VA_MACROS[ts.text(fn, source)] then
        return "write"
      elseif not decays then
        return "read"
      end
      return const_argument(parent:parent(), child, source, lookup) and "read" or "unclear"
    elseif decays and (type == "init_declarator" or type == "return_statement" or type == "cast_expression"
      or type == "conditional_expression") then
      return "unclear"
    else
      return "read"
    end
  end
end

-- Whether one use of the parameter (an identifier node) keeps the pointed-to
-- data untouched for sure. `copyable` says *p is a plain value (a number, a
-- struct, an enum) that a call or an assignment copies.
local function safe_use(id, source, lookup, copyable)
  local parent, child = up(id)
  local type = parent and parent:type()
  if type == "pointer_expression" then
    return operator(parent, source) == "*" and access(parent, source, lookup, not copyable) == "read"
  elseif type == "subscript_expression" and same(parent:field("argument")[1], child) then
    return access(parent, source, lookup, not copyable) == "read"
  elseif type == "field_expression" and same(parent:field("argument")[1], child) then
    return ts.text(parent:child(1), source) == "->" and access(parent, source, lookup, true) == "read"
  elseif type == "update_expression" or type == "sizeof_expression" then
    return true
  elseif type == "assignment_expression" then
    return same(parent:field("left")[1], child)
  elseif type == "unary_expression" then
    return operator(parent, source) == "!"
  elseif type == "binary_expression" then
    local op = ts.text(parent:child(1), source)
    if vim.list_contains({ "==", "!=", "<", ">", "<=", ">=", "&&", "||" }, op) then
      return true
    elseif op == "+" or op == "-" then
      -- pointer arithmetic: what matters is what's done with the result
      local outer = up(parent)
      if outer and outer:type() == "pointer_expression" and operator(outer, source) == "*" then
        return access(outer, source, lookup, not copyable) == "read"
      elseif outer and outer:type() == "argument_list" then
        return const_argument(outer:parent(), select(2, up(parent)), source, lookup)
      end
    end
    return false
  elseif type == "argument_list" then
    return const_argument(parent:parent(), child, source, lookup)
  elseif type == "if_statement" or type == "while_statement" or type == "do_statement" then
    return true
  elseif type == "conditional_expression" then
    return same(parent:field("condition")[1], child)
  end
  return false
end

-- A parameter declared as `T *name`, one pointer level, data not const yet.
local function pointer_param(param, source)
  local declarator = param:field("declarator")[1]
  local name = declarator and declarator:type() == "pointer_declarator" and declarator:field("declarator")[1]
  if not name or name:type() ~= "identifier" or has_const(param, source) then
    return nil
  end
  for child in declarator:iter_children() do
    if child:type() == "type_qualifier" then
      return nil
    end
  end
  return name
end

local PLAIN_TYPES = {
  primitive_type = true,
  sized_type_specifier = true,
  struct_specifier = true,
  union_specifier = true,
  enum_specifier = true,
}
local PLAIN_TYPEDEFS = { struct = true, union = true, enum = true, scalar = true }

-- Whether what a pointer parameter points to is a plain value. A typedef
-- the project doesn't define (va_list, jmp_buf) may be an array, so it isn't.
local function copyable(param, source, typedefs)
  local type = param:field("type")[1]
  if not type then
    return false
  elseif PLAIN_TYPES[type:type()] then
    return true
  end
  return type:type() == "type_identifier" and PLAIN_TYPEDEFS[typedefs()[ts.text(type, source)]] == true
end

-- `char *str` rewritten with const after the type, as the PDF writes it.
function M.const_text(param, source)
  local type = param:field("type")[1]
  local declarator = param:field("declarator")[1]
  return ts.text(type, source) .. " const " .. (declarator and ts.text(declarator, source) or "*")
end

-- Whether parameter `index` of function `name` takes a pointer to const,
-- according to the definitions and prototypes visible to this file and the
-- project's headers.
local function make_lookup(tree, source, ctx)
  local signatures
  return function(name, index)
    if not signatures then
      signatures = {}
      local function add(fname, param_list, src)
        local params = {}
        for child in param_list:iter_children() do
          if child:type() == "parameter_declaration" then
            params[#params + 1] = has_const(child, src)
          end
        end
        signatures[fname] = signatures[fname] or params
      end
      for _, proto in ipairs(ts.collect_prototypes(tree, source)) do
        add(proto.name, proto.declarator:field("parameters")[1], source)
      end
      for _, fn in ipairs(ts.collect_functions(tree, source)) do
        add(fn.name, fn.param_list, source)
      end
      if ctx.root then
        for _, proto in ipairs(ctx.header_prototypes or ts.header_prototypes(ctx.root)) do
          add(proto.name, proto.declarator:field("parameters")[1], proto.source)
        end
      end
    end
    return signatures[name] and signatures[name][index]
  end
end

-- C-A1 candidates: { fn, param, index, name (identifier node), text }.
-- path is the file's, to tell which functions other files store as
-- function pointers: those keep their parameter types.
function M.const_candidates(tree, source, ctx, path)
  ctx = ctx or {}
  local lookup = make_lookup(tree, source, ctx)
  local pointer = ts.pointer_uses(ctx.root, path, tree, source)
  local known
  local function typedefs()
    known = known or ts.typedefs(ctx.root, tree, source)
    return known
  end
  local result = {}
  for _, fn in ipairs(ts.collect_functions(tree, source)) do
    for index, param in ipairs(fn.params) do
      local name = pointer_param(param, source)
      if name and not pointer(fn) then
        local text = ts.text(name, source)
        local plain = copyable(param, source, typedefs)
        local uses, safe = 0, true
        local function walk(node)
          for child in node:iter_children() do
            if not safe then
              return
            end
            if child:type() == "identifier" and ts.text(child, source) == text then
              uses = uses + 1
              safe = safe_use(child, source, lookup, plain)
            elseif child:named_child_count() > 0 then
              walk(child)
            end
          end
        end
        walk(fn.body)
        if safe and uses > 0 then
          result[#result + 1] = { fn = fn, param = param, index = index, name = name, text = M.const_text(param, source) }
        end
      end
    end
  end
  return result
end

local LENGTH_FUNCTIONS = { strlen = "length", my_strlen = "length" }

-- "length" or "size" when value is strlen(…), my_strlen(…) or sizeof.
local function measure(value, source)
  while value and value:type() == "parenthesized_expression" do
    value = value:named_child(0)
  end
  if not value then
    return nil
  elseif value:type() == "sizeof_expression" then
    return "size"
  elseif value:type() == "call_expression" then
    local fn = value:field("function")[1]
    return fn and fn:type() == "identifier" and LENGTH_FUNCTIONS[ts.text(fn, source)]
  end
end

local function is_plain_int(declaration, source)
  local type = declaration:field("type")[1]
  return type and type:type() == "primitive_type" and ts.text(type, source) == "int"
end

-- C-A2: { node, what } for int variables set from strlen, my_strlen or sizeof.
function M.int_lengths(tree, source)
  local result = {}
  for _, fn in ipairs(ts.collect_functions(tree, source)) do
    local ints = {}
    for _, param in ipairs(fn.params) do
      local declarator = param:field("declarator")[1]
      if is_plain_int(param, source) and declarator and declarator:type() == "identifier" then
        ints[ts.text(declarator, source)] = true
      end
    end
    local function walk(node)
      for child in node:iter_children() do
        local type = child:type()
        if type == "declaration" and is_plain_int(child, source) then
          for _, declarator in ipairs(child:field("declarator")) do
            if declarator:type() == "identifier" then
              ints[ts.text(declarator, source)] = true
            elseif declarator:type() == "init_declarator" then
              local name = declarator:field("declarator")[1]
              if name:type() == "identifier" then
                ints[ts.text(name, source)] = true
                local what = measure(declarator:field("value")[1], source)
                if what then
                  result[#result + 1] = { node = name, what = what }
                end
              end
            end
          end
        elseif type == "assignment_expression" and ts.text(child:child(1), source) == "=" then
          local left = child:field("left")[1]
          local what = left:type() == "identifier" and ints[ts.text(left, source)] and measure(child:field("right")[1], source)
          if what then
            result[#result + 1] = { node = left, what = what }
          end
        end
        if child:named_child_count() > 0 then
          walk(child)
        end
      end
    end
    walk(fn.body)
  end
  return result
end

local function diagnostic(node, message, code)
  local row, col, end_row, end_col = node:range()
  return { lnum = row, col = col, end_lnum = end_row, end_col = end_col, message = message, code = code }
end

function M.run(src, path, ctx)
  local result = {}
  for _, candidate in ipairs(M.const_candidates(ctx.tree, src, ctx, path)) do
    local name = ts.text(candidate.name, src)
    result[#result + 1] = diagnostic(candidate.name, ("C-A1 %s is never modified → %s"):format(name, candidate.text),
      "C-A1")
  end
  for _, int in ipairs(M.int_lengths(ctx.tree, src)) do
    result[#result + 1] = diagnostic(int.node, ("C-A2 holds a %s → size_t?"):format(int.what), "C-A2")
  end
  return result
end

return M
