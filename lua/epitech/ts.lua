-- Treesitter helpers for C, built on the parser bundled with Neovim, and the
-- function finder that budgets, hints and fixes share.
local M = {}

---@class epitech.Function
---@field name string
---@field node TSNode            function_definition
---@field is_static boolean
---@field params TSNode[]        parameter_declaration nodes, (void) excluded
---@field variadic boolean
---@field param_list TSNode
---@field declarator TSNode      the function_declarator
---@field signature_row integer  0-based row holding the function name
---@field body TSNode            compound_statement
---@field body_lines integer     lines strictly between { and }, as C-F4 counts them
---@field start_row integer
---@field end_row integer

-- The buffer's C parser, or nil when no C parser is available.
function M.parser(buf)
  local ok, parser = pcall(vim.treesitter.get_parser, buf, "c")
  if ok and parser then
    return parser
  end
end

-- The root node of a buffer's syntax tree, or nil without a C parser.
function M.root(buf)
  local parser = M.parser(buf)
  if not parser then
    return nil
  end
  return parser:parse()[1]:root()
end

-- The root node of a C source string, or nil without a C parser.
function M.parse_string(src)
  local ok, parser = pcall(vim.treesitter.get_string_parser, src, "c")
  if not ok or not parser then
    return nil
  end
  return parser:parse()[1]:root()
end

-- source is a buffer number or the string the tree was parsed from.
function M.text(node, source)
  return vim.treesitter.get_node_text(node, source)
end

-- Walks down a declarator chain to its function_declarator: pointer-returning
-- functions wrap it in pointer_declarator nodes.
function M.function_declarator(node)
  while node do
    local type = node:type()
    if type == "function_declarator" then
      return node
    elseif type == "pointer_declarator" or type == "parenthesized_declarator" or type == "attributed_declarator" then
      node = node:field("declarator")[1] or node:named_child(0)
    else
      return nil
    end
  end
end

-- The identifier a declarator declares (int *const a[4] -> a), or nil.
function M.declared_name(node)
  while node do
    local type = node:type()
    if type == "identifier" or type == "field_identifier" or type == "type_identifier" then
      return node
    end
    node = node:field("declarator")[1] or (node:named_child_count() > 0 and node:named_child(0)) or nil
  end
end

-- (void) is a parameter_declaration too, but declares no parameter.
function M.is_void_param(param, source)
  local type = param:field("type")[1]
  return param:field("declarator")[1] == nil and type ~= nil and type:type() == "primitive_type"
    and M.text(type, source) == "void"
end

function M.has_storage_class(node, source, word)
  for child in node:iter_children() do
    if child:type() == "storage_class_specifier" and M.text(child, source) == word then
      return true
    end
  end
  return false
end

-- Describes a function_definition node; nil for the shapes it doesn't handle
-- (function-pointer declarators, for instance).
function M.describe(node, source)
  local declarator = M.function_declarator(node:field("declarator")[1])
  local name = declarator and declarator:field("declarator")[1]
  local body = node:field("body")[1]
  if not name or name:type() ~= "identifier" or not body then
    return nil
  end

  local param_list = declarator:field("parameters")[1]
  local params, variadic = {}, false
  for child in param_list:iter_children() do
    if child:type() == "parameter_declaration" and not M.is_void_param(child, source) then
      params[#params + 1] = child
    elseif child:type() == "variadic_parameter" then
      variadic = true
    end
  end

  local start_row, _, end_row = node:range()
  local body_start, _, body_end = body:range()
  return {
    name = M.text(name, source),
    node = node,
    is_static = M.has_storage_class(node, source, "static"),
    params = params,
    variadic = variadic,
    param_list = param_list,
    declarator = declarator,
    signature_row = (name:range()),
    body = body,
    -- C-F4: Banana counts every line between the braces, blank, comment and
    -- continuation lines included (measured, §10 of CLAUDE.md).
    body_lines = math.max(body_end - body_start - 1, 0),
    start_row = start_row,
    end_row = end_row,
  }
end

-- Every function definition under root (functions don't nest in C, except
-- the GNU extension C-F9 forbids).
function M.collect_functions(root, source)
  local result = {}
  local function walk(node)
    for child in node:iter_children() do
      if child:type() == "function_definition" then
        result[#result + 1] = M.describe(child, source)
      elseif child:named_child_count() > 0 then
        walk(child)
      end
    end
  end
  walk(root)
  return result
end

-- Every declaration of a function (a prototype) under root, outside function
-- bodies: { name, node, declarator, row, empty_params }.
function M.collect_prototypes(root, source)
  local result = {}
  local function walk(node)
    for child in node:iter_children() do
      if child:type() == "declaration" then
        for _, declarator in ipairs(child:field("declarator")) do
          local fn = declarator
          while fn and fn:type() == "pointer_declarator" do
            fn = fn:field("declarator")[1]
          end
          local name = fn and fn:type() == "function_declarator" and fn:field("declarator")[1]
          if name and name:type() == "identifier" then
            result[#result + 1] = {
              name = M.text(name, source),
              node = child,
              declarator = fn,
              row = (name:range()),
              empty_params = fn:field("parameters")[1]:named_child_count() == 0,
            }
          end
        end
      elseif child:type() ~= "function_definition" and child:named_child_count() > 0 then
        walk(child)
      end
    end
  end
  walk(root)
  return result
end

-- Results computed from a buffer are cached until its next change, so the
-- budgets, hints and fixes share one walk per edit.
local cache = {}

function M.cached(buf, key, compute)
  buf = buf == 0 and vim.api.nvim_get_current_buf() or buf
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  local entry = cache[buf]
  if not entry or entry.tick ~= tick then
    entry = { tick = tick }
    cache[buf] = entry
  end
  if entry[key] == nil then
    entry[key] = compute() or false
  end
  return entry[key] or nil
end

---@return epitech.Function[]
function M.functions(buf)
  return M.cached(buf, "functions", function()
    local root = M.root(buf)
    return root and M.collect_functions(root, buf) or {}
  end)
end

function M.prototypes(buf)
  return M.cached(buf, "prototypes", function()
    local root = M.root(buf)
    return root and M.collect_prototypes(root, buf) or {}
  end)
end

local file_cache = {}

-- { src, root } for a file on disk, cached by modification time.
function M.parse_file(path)
  local stat = vim.uv.fs_stat(path)
  if not stat then
    return nil
  end
  local cached = file_cache[path]
  if cached and cached.mtime == stat.mtime.sec and cached.nsec == stat.mtime.nsec and cached.size == stat.size then
    return cached
  end
  local fd = io.open(path, "rb")
  if not fd then
    return nil
  end
  local src = fd:read("*a")
  fd:close()
  local root = M.parse_string(src)
  if not root then
    return nil
  end
  cached = { src = src, root = root, mtime = stat.mtime.sec, nsec = stat.mtime.nsec, size = stat.size }
  file_cache[path] = cached
  return cached
end

-- The prototypes in the project's tracked headers, read from their buffers
-- when loaded: collect_prototypes() entries plus `file` (relative to root)
-- and `source` (the header's text).
local header_cache, cached_headers = {}, 0

function M.header_prototypes(root)
  local result = {}
  local util = require("epitech.util")
  for _, file in ipairs(require("epitech.project").files(root, { "*.h" }) or {}) do
    local src = table.concat(util.read_lines(root .. "/" .. file), "\n")
    -- Hints call this on every pause in typing: each header text is parsed
    -- once.
    if not header_cache[src] then
      if cached_headers > 200 then
        header_cache, cached_headers = {}, 0
      end
      local tree = M.parse_string(src)
      header_cache[src] = tree and M.collect_prototypes(tree, src) or {}
      cached_headers = cached_headers + 1
    end
    for _, proto in ipairs(header_cache[src]) do
      result[#result + 1] = vim.tbl_extend("force", proto, { file = file, source = src })
    end
  end
  return result
end

local TYPE_KINDS = {
  struct_specifier = "struct",
  union_specifier = "union",
  enum_specifier = "enum",
  primitive_type = "scalar",
  sized_type_specifier = "scalar",
}

-- Adds to `into` what each typedef under node names: "struct", "union",
-- "enum", "scalar", "alias:<other typedef>", or "other" for array, pointer
-- and function types.
local function scan_typedefs(node, src, into)
  for child in node:iter_children() do
    if child:type() == "type_definition" then
      local type = child:field("type")[1]
      local kind = type and TYPE_KINDS[type:type()]
      if not kind and type and type:type() == "type_identifier" then
        kind = "alias:" .. M.text(type, src)
      end
      for _, declarator in ipairs(child:field("declarator")) do
        if declarator:type() == "type_identifier" then
          into[M.text(declarator, src)] = kind or "other"
        else
          local name = M.declared_name(declarator)
          if name then
            into[M.text(name, src)] = "other"
          end
        end
      end
    elseif child:type() ~= "function_definition" and child:named_child_count() > 0 then
      scan_typedefs(child, src, into)
    end
  end
end

-- Hints run this on every pause in typing: each header text is parsed once.
local typedef_cache, cached_typedef_headers = {}, 0

-- { [name] = kind } for the typedefs of the project's tracked headers and of
-- tree: "struct", "union", "enum", "scalar", or "other" for array, pointer
-- and function types and for aliases of types that aren't known here (a
-- system header's va_list or jmp_buf).
function M.typedefs(root, tree, source)
  local raw = {}
  local util = require("epitech.util")
  for _, file in ipairs(root and require("epitech.project").files(root, { "*.h" }) or {}) do
    local src = table.concat(util.read_lines(root .. "/" .. file), "\n")
    if not typedef_cache[src] then
      if cached_typedef_headers > 200 then
        typedef_cache, cached_typedef_headers = {}, 0
      end
      local names = {}
      local header_tree = M.parse_string(src)
      if header_tree then
        scan_typedefs(header_tree, src, names)
      end
      typedef_cache[src] = names
      cached_typedef_headers = cached_typedef_headers + 1
    end
    for name, kind in pairs(typedef_cache[src]) do
      raw[name] = kind
    end
  end
  if tree then
    scan_typedefs(tree, source, raw)
  end
  local result = {}
  for name, kind in pairs(raw) do
    local steps = 0
    while vim.startswith(kind, "alias:") and steps < 10 do
      kind = raw[kind:sub(7)] or "other"
      steps = steps + 1
    end
    result[name] = vim.startswith(kind, "alias:") and "other" or kind
  end
  return result
end

-- Parents under which an identifier is declared rather than used.
local DECLARING = {
  declaration = true, init_declarator = true, parameter_declaration = true, pointer_declarator = true,
  array_declarator = true, function_declarator = true, parenthesized_declarator = true, attributed_declarator = true,
}

-- The names used as values under node: neither called nor declared. A
-- function among them is stored as a function pointer ({'c', print_char},
-- &handler), so its parameter types are set by the pointer's type.
function M.value_names(node, source)
  local result = {}
  local function walk(parent)
    for child in parent:iter_children() do
      if child:type() == "identifier" then
        local type = parent:type()
        local called = type == "call_expression" and parent:field("function")[1]:id() == child:id()
        local value = parent:field("value")[1]
        local declared = DECLARING[type] and not (type == "init_declarator" and value and value:id() == child:id())
        if not called and not declared then
          result[M.text(child, source)] = true
        end
      elseif child:named_child_count() > 0 then
        walk(child)
      end
    end
  end
  walk(node)
  return result
end

-- value_names() over the project's tracked .c and .h files other than
-- `except` (an absolute path), as saved on disk.
function M.project_value_names(root, except)
  local result = {}
  for _, file in ipairs(require("epitech.project").files(root, { "*.c", "*.h" }) or {}) do
    local path = root .. "/" .. file
    local parsed = path ~= except and M.parse_file(path)
    if parsed then
      parsed.values = parsed.values or M.value_names(parsed.root, parsed.src)
      for name in pairs(parsed.values) do
        result[name] = true
      end
    end
  end
  return result
end

-- A predicate telling whether a function of the file at path (tree and
-- source being its current text) is used as a function pointer: in that
-- file, or, unless it's static, in another file of the project at root.
-- Changing such a function's parameter types breaks the pointer's type.
function M.pointer_uses(root, path, tree, source)
  local here, elsewhere
  return function(fn)
    here = here or M.value_names(tree, source)
    if here[fn.name] then
      return true
    elseif fn.is_static or not root then
      return false
    end
    elsewhere = elsewhere or M.project_value_names(root, path and vim.fs.normalize(path))
    return elsewhere[fn.name] == true
  end
end

-- { [name] = { file, is_static, row } } over the project's tracked .c files.
-- When several files define the same name, the non-static one wins.
function M.project_functions(root)
  local result = {}
  for _, file in ipairs(require("epitech.project").files(root, { "*.c" }) or {}) do
    local parsed = M.parse_file(root .. "/" .. file)
    if parsed then
      for _, fn in ipairs(M.collect_functions(parsed.root, parsed.src)) do
        local known = result[fn.name]
        if not known or (known.is_static and not fn.is_static) then
          result[fn.name] = { file = file, is_static = fn.is_static, row = fn.signature_row }
        end
      end
    end
  end
  return result
end

return M
