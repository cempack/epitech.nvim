-- The formatter. formatter() in init.lua runs this file with dofile() inside
-- `nvim --clean`, where the plugin is on neither runtimepath nor package.path,
-- so this file must never require anything.
local M = {}

local module_path = debug.getinfo(1, "S").source:sub(2)
local plugin_dir = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(module_path)))
local style_file = plugin_dir .. "/epitech.clang-format"

M.path = module_path
M.style_file = style_file

-- The formatter keeps its own C header check because it can't require one.
local function has_header(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, 6, false)
  return lines[6] ~= nil
    and lines[1] == "/*"
    and lines[2]:match("^ ?%*%* EPITECH PROJECT, %d%d%d%d$") ~= nil
    and lines[3]:match("^ ?%*%* .*$") ~= nil
    and lines[4]:match("^ ?%*%* File description:$") ~= nil
    and lines[5]:match("^ ?%*%* .*$") ~= nil
    and lines[6]:match("^ ?%*/$") ~= nil
end

-- Vim's C indent treats preprocessor lines as column-zero. Banana C-G3 instead
-- counts conditional preprocessor nesting independently of C block nesting.
local function indent_preprocessor(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local depth = 0
  local changed = false

  for i, line in ipairs(lines) do
    local directive = line:match("^%s*#%s*([%a_][%w_]*)")
    if directive then
      local branch = directive == "else" or directive == "elif" or directive == "elifdef" or directive == "elifndef"
      local closing = directive == "endif"
      if branch or closing then
        depth = math.max(depth - 1, 0)
      end

      local normalized = string.rep("    ", depth) .. line:gsub("^%s*", "")
      if normalized ~= line then
        lines[i] = normalized
        changed = true
      end

      if directive == "if" or directive == "ifdef" or directive == "ifndef" or branch then
        depth = depth + 1
      end
    end
  end

  if changed then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  end
end

-- C-L3 also applies inside #define bodies, which the main pass leaves untouched
-- so it never wraps them with backslashes (C-G6). Format them without a column
-- limit instead; a define that is still too long has to be shortened by hand.
local function format_macros(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local rows, defines = {}, {}
  for i, line in ipairs(lines) do
    if line:match("^%s*#%s*define%s") and not line:match("\\$") then
      rows[#rows + 1] = i
      defines[#defines + 1] = line:gsub("^%s+", "")
    end
  end
  if #rows == 0 then
    return
  end

  local style = {}
  for _, line in ipairs(vim.fn.readfile(style_file)) do
    if not line:match("^OneLineFormatOffRegex:") and not line:match("^SkipMacroDefinitionBody:")
      and not line:match("^ColumnLimit:") then
      style[#style + 1] = line
    end
  end
  style[#style + 1] = "ColumnLimit: 0"
  local style_path = vim.fn.tempname()
  vim.fn.writefile(style, style_path)
  local result = vim.system({
    "clang-format",
    "--style=file:" .. style_path,
    "--assume-filename=epitech.c",
  }, { stdin = table.concat(defines, "\n") .. "\n", text = true }):wait()
  vim.fn.delete(style_path)
  if result.code ~= 0 then
    error("clang-format failed on macros: " .. (result.stderr or ""))
  end

  local formatted = vim.split(result.stdout:gsub("\n$", ""), "\n", { plain = true })
  if #formatted ~= #rows then
    return
  end
  for i, row in ipairs(rows) do
    lines[row] = formatted[i]
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
end

-- header.lua reuses it so include guards follow C-G3 too.
M.indent_preprocessor = indent_preprocessor

-- Rows (1-based) covered by comments, or nil when no C parser is available.
local function comment_rows(buf)
  local ok, parser = pcall(vim.treesitter.get_parser, buf, "c")
  if not ok or not parser then
    return nil
  end
  local rows = {}
  local root = parser:parse()[1]:root()
  local query = vim.treesitter.query.parse("c", "(comment) @comment")
  for _, node in query:iter_captures(root, buf) do
    local start_row, _, end_row = node:range()
    for row = start_row + 1, end_row + 1 do
      rows[row] = true
    end
  end
  return rows, root
end

-- clang-format aligns adjacent string literals, and the ':' of a wrapped
-- ternary, under the line above, so they land on arbitrary columns (C-L2).
-- Indent such lines one level from the line they continue instead.
local function indent_continuations(buf, comments)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local changed = false
  local previous, previous_new, previous_aligned

  for i, line in ipairs(lines) do
    if line ~= "" and not comments[i] and not line:match("^%s*#") then
      local indent = #line:match("^ *")
      local first = line:sub(indent + 1, indent + 1)
      local above = previous and previous:sub(indent + 1, indent + 1)
      local aligned = (first == '"' and above == '"') or (first == ":" and above == "?")
      local new = indent
      if aligned then
        new = previous_aligned and previous_new or previous_new + 4
        if new ~= indent then
          lines[i] = string.rep(" ", new) .. line:sub(indent + 1)
          changed = true
        end
      end
      previous, previous_new, previous_aligned = line, new, aligned
    end
  end

  if changed then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  end
end

-- The control statements whose header (condition, or a for's three parts)
-- is a unit of its own, apart from the body.
local CONTROL = {
  if_statement = true,
  while_statement = true,
  for_statement = true,
  do_statement = true,
  switch_statement = true,
}

-- Statements whose wrapped lines continue one line.
local SIMPLE = {
  expression_statement = true,
  return_statement = true,
  declaration = true,
  field_declaration = true,
}

-- Lines starting with one of these operators are joined to the line above
-- when they fit: clang-format moves a comparison down when its left side
-- was wrapped (`file_arguments)` then `== -1) {`), which reads badly. Lines
-- starting with &&, || or an arithmetic operator stay: the style's own
-- examples break before them.
local JOINED_OPERATORS = { "==", "!=", "<=", ">=", "<", ">" }

local function has_type(node, types)
  if types[node:type()] then
    return true
  end
  for child in node:iter_children() do
    if has_type(child, types) then
      return true
    end
  end
  return false
end

-- The units of continued lines: { first, last } rows (1-based) of each
-- statement, control header or function signature, outermost first.
local function continuation_units(root)
  local units = {}
  local function add(first, last)
    if last > first then
      units[#units + 1] = { first = first + 1, last = last + 1 }
    end
  end
  local function visit(node)
    local kind = node:type()
    if CONTROL[kind] then
      local first = node:range()
      local last = first
      local condition = node:field("condition")[1]
      if kind == "do_statement" and condition then
        first = condition:range()
        last = select(3, condition:range())
      elseif kind == "for_statement" then
        for child in node:iter_children() do
          if child:type() == ")" then
            last = child:range()
          end
        end
      elseif condition then
        last = select(3, condition:range())
      end
      add(first, last)
      for child in node:iter_children() do
        if not condition or child:id() ~= condition:id() then
          visit(child)
        end
      end
    elseif kind == "function_definition" then
      local declarator = node:field("declarator")[1]
      if declarator then
        add(node:range(), select(3, declarator:range()))
      end
      local body = node:field("body")[1]
      if body then
        visit(body)
      end
    elseif SIMPLE[kind] and not has_type(node, {
      field_declaration_list = true,
      enumerator_list = true,
      initializer_list = true,
      compound_statement = true,
    }) then
      add(node:range(), select(3, node:range()))
    else
      for child in node:iter_children() do
        visit(child)
      end
    end
  end
  visit(root)
  return units
end

local function starts_with_operator(text, operators)
  for _, operator in ipairs(operators) do
    if vim.startswith(text, operator .. " ") then
      return true
    end
  end
  return false
end

-- C-L2: Banana wants every wrapped line of a statement one level (4 spaces)
-- deeper than the statement's first line, however deep clang-format nests
-- it (`level 4 indentation (should be 3)`). Wrapped lines are moved there,
-- then a line is joined to the one above when it fits in 79 columns (C-F3)
-- and either starts with a comparison or `)`, or follows a line ending with
-- `,` or `(`: once flat, arguments clang-format pushed down for lack of room
-- often fit back. Returns whether the rows changed.
local function flatten_continuations(buf, comments, root)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local claimed, units = {}, {}
  for _, unit in ipairs(continuation_units(root)) do
    local usable = true
    for row = unit.first, unit.last do
      if claimed[row] or comments[row] or lines[row]:match("^%s*#") then
        usable = false
      end
    end
    if usable then
      for row = unit.first, unit.last do
        claimed[row] = true
      end
      units[#units + 1] = unit
    end
  end

  local changed, joined = false, false
  -- Bottom-up, so joining lines keeps the rows of the units above valid.
  table.sort(units, function(a, b)
    return a.first > b.first
  end)
  for _, unit in ipairs(units) do
    local indent = lines[unit.first]:match("^ *") .. "    "
    local rows = {}
    for row = unit.first + 1, unit.last do
      rows[#rows + 1] = indent .. vim.trim(lines[row])
    end
    local i = 1
    while i < #rows do
      local previous, text = rows[i], vim.trim(rows[i + 1])
      local glue = (previous:match("[%(%[]$") or text:match("^[%)%],;]")) and "" or " "
      local fits = #previous + #glue + #text <= 79
      local wanted = starts_with_operator(text, JOINED_OPERATORS) or text:match("^%)")
        or previous:match("[,%(]$")
      if fits and wanted then
        rows[i] = previous .. glue .. text
        table.remove(rows, i + 1)
        joined = true
      else
        i = i + 1
      end
    end
    -- The statement's first line may take a joined line too.
    local head = lines[unit.first]
    while rows[1] do
      local text = vim.trim(rows[1])
      local glue = (head:match("[%(%[]$") or text:match("^[%)%],;]")) and "" or " "
      if #head + #glue + #text <= 79 and (starts_with_operator(text, JOINED_OPERATORS) or text:match("^%)")
        or head:match("[,%(]$")) then
        head = head .. glue .. text
        table.remove(rows, 1)
        joined = true
      else
        break
      end
    end
    local new = vim.list_extend({ head }, rows)
    local old = vim.list_slice(lines, unit.first, unit.last)
    if not vim.deep_equal(new, old) then
      changed = true
      for _ = unit.first, unit.last do
        table.remove(lines, unit.first)
      end
      for k, line in ipairs(new) do
        table.insert(lines, unit.first + k - 1, line)
      end
    end
  end

  if changed then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  end
  return joined
end

-- Comment reflow continues "**" comments with a single "*"; keep the Epitech
-- "**" prefix on every line of a comment that uses it.
local function keep_comment_prefix(buf, comments)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local changed = false
  local i = 1

  while i <= #lines do
    if comments[i] and lines[i]:match("^%s*/%*") then
      local last = i
      local double = false
      while comments[last + 1] and not lines[last]:match("%*/%s*$") do
        last = last + 1
        double = double or lines[last]:match("^%s*%*%*") ~= nil
      end
      if double then
        for row = i + 1, last do
          local indent, rest = lines[row]:match("^(%s*)%*( .*)$")
          if indent and not lines[row]:match("^%s*%*%*") then
            lines[row] = indent .. "**" .. rest
            changed = true
          end
        end
      end
      i = last + 1
    else
      i = i + 1
    end
  end

  if changed then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  end
end

-- C-L6: inside a function, the only blank line separates the variable
-- declarations at the top of the body from the rest of it.
local function normalize_function_blank_lines(buf, comments, root)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local drop, blank_after = {}, {}
  local query = vim.treesitter.query.parse("c", "(function_definition body: (compound_statement) @body)")

  for _, body in query:iter_captures(root, buf) do
    local first_row, _, last_row = body:range()
    for row = first_row + 2, last_row do
      if lines[row]:match("^%s*$") and not comments[row] then
        drop[row] = true
      end
    end

    local last_declaration, has_statement
    for child in body:iter_children() do
      if child:named() and child:type() ~= "comment" then
        if child:type() == "declaration" and not has_statement then
          last_declaration = select(3, child:range()) + 1
        else
          has_statement = true
        end
      end
    end
    if last_declaration and has_statement then
      blank_after[last_declaration] = true
    end
  end

  local result = {}
  for row, line in ipairs(lines) do
    if not drop[row] then
      result[#result + 1] = line
    end
    if blank_after[row] then
      result[#result + 1] = ""
    end
  end
  if #result ~= #lines or not vim.deep_equal(result, lines) then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, result)
  end
end

-- Formats buf in place; the current buffer when buf is nil or 0.
function M.format_buffer(buf)
  if buf == nil or buf == 0 then
    buf = vim.api.nvim_get_current_buf()
  end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local header = {}
  local body_start = 1

  -- C-G7 and C-G8, before looking for the header: trailing spaces or leading
  -- blank lines would otherwise hide it from the check below.
  for i, line in ipairs(lines) do
    lines[i] = line:gsub("%s+$", "")
  end
  while #lines > 1 and lines[1] == "" do
    table.remove(lines, 1)
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  if has_header(buf) then
    vim.list_extend(header, lines, 1, 6)
    for i = 2, 6 do
      header[i] = header[i]:gsub("^ ", "")
    end
    body_start = 7
  end

  local body = {}
  vim.list_extend(body, lines, body_start)
  local result = vim.system({
    "clang-format",
    "--style=file:" .. style_file,
    "--assume-filename=epitech.c",
  }, { stdin = table.concat(body, "\n") .. "\n", text = true }):wait()
  if result.code ~= 0 then
    error("clang-format failed: " .. (result.stderr or ""))
  end

  body = vim.split(result.stdout:gsub("\n$", ""), "\n", { plain = true })
  while body[1] == "" do
    table.remove(body, 1)
  end
  while body[#body] == "" do
    table.remove(body)
  end

  local formatted = header
  if #header > 0 and #body > 0 then
    formatted[#formatted + 1] = ""
  end
  vim.list_extend(formatted, body)
  if #formatted == 0 then
    formatted[1] = ""
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, formatted)
  format_macros(buf)
  indent_preprocessor(buf)

  local comments, root = comment_rows(buf)
  if comments then
    indent_continuations(buf, comments)
    keep_comment_prefix(buf, comments)
    if flatten_continuations(buf, comments, root) then
      comments, root = comment_rows(buf)
    end
    normalize_function_blank_lines(buf, comments, root)
  end
end

function M.format_stdout()
  local ok, err = pcall(M.format_buffer)
  if not ok then
    io.stderr:write("Epitech formatter: " .. tostring(err) .. "\n")
    vim.cmd("cquit 1")
    return
  end
  io.stdout:write(table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n") .. "\n")
end

return M
