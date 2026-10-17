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
