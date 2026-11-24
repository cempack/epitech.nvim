-- C-F2, C-O4, C-V1 (partly Banana, partly a grader): function names without
-- a verb, vague file names, typedef names without _t, and macros, enum
-- values and global constants that aren't UPPER_SNAKE_CASE. What Banana
-- already reports on a line is dropped by the hint runner.
local ts = require("epitech.ts")

local M = { id = "naming" }

function M.enabled(options)
  return options.naming.enabled
end

-- The word lists live in shared/naming.json, which the VS Code extension
-- reads too: verbs (from the spec, then from student projects; words that
-- begin common nouns, like play for player, win for window, map, link,
-- hash, hit or use for user, stay out, since a name holding the noun would
-- pass for one holding a verb), vague file names, and the lib/my classics
-- students write in their first weeks, whose names the subjects set.
local plugin_dir = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2)))))
local lists = vim.json.decode(table.concat(vim.fn.readfile(plugin_dir .. "/shared/naming.json"), "\n"))
M.verbs = lists.verbs
M.vague_files = lists.vague_files
M.classics = lists.classics

-- Whether a function name contains a verb: split on _, a leading "my"
-- ignored, one word being a verb or starting with one (putstr). A
-- conversion, x_to_y (str_to_int), says what it does too.
function M.has_verb(name, verbs)
  local words = vim.split(name:lower(), "_", { trimempty = true })
  if words[1] == "my" then
    table.remove(words, 1)
  end
  for i = 2, #words - 1 do
    if words[i] == "to" then
      return true
    end
  end
  for _, word in ipairs(words) do
    for _, verb in ipairs(verbs) do
      if vim.startswith(word, verb) then
        return true
      end
    end
  end
  return false
end

function M.is_upper_snake(name)
  return name:match("^_*[A-Z][A-Z0-9_]*$") ~= nil
end

-- bufferSize -> BUFFER_SIZE, max_len -> MAX_LEN
function M.upper_snake(name)
  return (name:gsub("(%l)(%u)", "%1_%2"):gsub("(%d)(%u)", "%1_%2"):upper())
end

local function diagnostic(node, message, code)
  local row, col, end_row, end_col = node:range()
  return { lnum = row, col = col, end_lnum = end_row, end_col = end_col, message = message, code = code }
end

local function returns_value(fn, source)
  local type = fn.node:field("type")[1]
  return fn.node:field("declarator")[1]:type() == "pointer_declarator" or ts.text(type, source) ~= "void"
end

local function upper_hint(node, source, what)
  local name = ts.text(node, source)
  if M.is_upper_snake(name) then
    return nil
  end
  return diagnostic(node, ("C-V1 %s in UPPER_SNAKE_CASE → %s?"):format(what, M.upper_snake(name)), "C-V1")
end

-- Whether a top-level declaration declares a constant object (const int
-- MAX = 4;), not a pointer to const data (const char *name;).
local function constant_declarators(declaration, source)
  local const = false
  for child in declaration:iter_children() do
    if child:type() == "type_qualifier" and ts.text(child, source) == "const" then
      const = true
    end
  end
  local result = {}
  for _, declarator in ipairs(declaration:field("declarator")) do
    local node, object_const = declarator, const
    if node:type() == "init_declarator" then
      node = node:field("declarator")[1]
    end
    while node and node:type() ~= "identifier" do
      if node:type() == "pointer_declarator" then
        object_const = false
        for child in node:iter_children() do
          if child:type() == "type_qualifier" and ts.text(child, source) == "const" then
            object_const = true
          end
        end
      elseif node:type() == "function_declarator" then
        node = nil
        break
      end
      node = node:field("declarator")[1] or node:named_child(0)
    end
    if node and object_const then
      result[#result + 1] = node
    end
  end
  return result
end

function M.run(src, path, ctx)
  local options = ctx.options.naming
  local verbs = options.verbs or M.verbs
  local result = {}

  local base, extension = vim.fs.basename(path):match("^(.*)%.([ch])$")
  if base and vim.list_contains(options.vague_files or M.vague_files, base:lower()) then
    result[#result + 1] = {
      lnum = 0,
      col = 0,
      message = ("C-O4 vague name: %s.%s"):format(base, extension),
      code = "C-O4",
    }
  end

  for _, fn in ipairs(ts.collect_functions(ctx.tree, src)) do
    if not vim.list_contains(M.classics, fn.name) and not M.has_verb(fn.name, verbs) then
      local name = fn.declarator:field("declarator")[1]
      local message = returns_value(fn, src) and ("C-F2 no verb → get_%s?"):format(fn.name)
        or ("C-F2 no verb in %s"):format(fn.name)
      result[#result + 1] = diagnostic(name, message, "C-F2")
    end
  end

  local function walk(node, top)
    for child in node:iter_children() do
      local type = child:type()
      if type == "type_definition" then
        for _, declarator in ipairs(child:field("declarator")) do
          local name = ts.declared_name(declarator)
          local text = name and ts.text(name, src)
          if text and not text:match("_t$") then
            result[#result + 1] = diagnostic(name, ("C-V1 typedef names end in _t → %s_t?"):format(
              text:gsub("_[se]$", ""):lower()), "C-V1")
          end
        end
      elseif type == "preproc_def" or type == "preproc_function_def" then
        result[#result + 1] = upper_hint(child:field("name")[1], src, "macros")
      elseif type == "enumerator" then
        result[#result + 1] = upper_hint(child:field("name")[1], src, "enum values")
      elseif type == "declaration" and top then
        for _, name in ipairs(constant_declarators(child, src)) do
          result[#result + 1] = upper_hint(name, src, "global constants")
        end
      end
      if type ~= "function_definition" and child:named_child_count() > 0 then
        walk(child, top and (type:match("^preproc_") ~= nil or type == "declaration_list"))
      end
    end
  end
  walk(ctx.tree, true)
  return result
end

return M
