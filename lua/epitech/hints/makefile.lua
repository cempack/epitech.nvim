-- Checks for Makefiles, which the coding style covers too: the header
-- (C-G1), 80 columns (C-F3), line endings (C-G6), trailing spaces (C-G7),
-- leading and trailing empty lines (C-G8) and the final newline (C-A3).
-- They aren't guesses, so they use the rule's own severity, in their own
-- namespace.
local config = require("epitech.config")
local header = require("epitech.header")

local M = {}

M.ns = vim.api.nvim_create_namespace("epitech.makefile")

local ERROR, WARN, INFO = vim.diagnostic.severity.ERROR, vim.diagnostic.severity.WARN, vim.diagnostic.severity.INFO

-- The visible width of a line, tabs expanded to tab_width-column stops.
function M.width(line, tab_width)
  local width = 0
  for char in line:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    if char == "\t" then
      width = width + tab_width - width % tab_width
    else
      width = width + vim.fn.strdisplaywidth(char)
    end
  end
  return width
end

local function diagnostic(row, col, end_col, severity, code, message)
  return {
    lnum = row,
    col = col,
    end_lnum = row,
    end_col = end_col,
    severity = severity,
    code = code,
    message = code .. " " .. message,
    source = "epitech.nvim",
  }
end

-- The diagnostics for a Makefile's text (as on disk: a final newline ends
-- the last line).
function M.run(src, _, ctx)
  local tab_width = (ctx and ctx.tab_width) or config.options.makefile.tab_width
  local final_newline = src == "" or src:sub(-1) == "\n"
  local lines = vim.split(final_newline and src:sub(1, -2) or src, "\n", { plain = true })
  if src == "" then
    lines = {}
  end
  local result = {}

  local plain = vim.tbl_map(function(line)
    return (line:gsub("\r$", ""))
  end, lines)
  if not header.existing_header(vim.list_slice(plain, 1, 8)) then
    result[#result + 1] = diagnostic(0, 0, 0, WARN, "C-G1", "missing Epitech header")
  end

  for i, line in ipairs(lines) do
    local row = i - 1
    if line:find("\r", 1, true) then
      result[#result + 1] = diagnostic(row, #line - 1, #line, WARN, "C-G6", "\\r line ending")
      line = line:gsub("\r", "")
    end
    local width = M.width(line, tab_width)
    if width + 1 > 80 then
      result[#result + 1] = diagnostic(row, 0, #line, ERROR, "C-F3", ("%d/80 columns"):format(width + 1))
    end
    local trailing = line:find("%s+$")
    if trailing then
      result[#result + 1] = diagnostic(row, trailing - 1, #line, WARN, "C-G7", "trailing whitespace")
    end
  end

  if #lines > 1 and lines[1]:match("^%s*$") then
    result[#result + 1] = diagnostic(0, 0, 0, WARN, "C-G8", "empty line at the start of the file")
  end
  local last = #lines
  while last > 0 and lines[last] == "" do
    last = last - 1
  end
  if #lines - last > 1 then
    result[#result + 1] = diagnostic(last + 1, 0, 0, WARN, "C-G8", "more than one empty line at the end of the file")
  end
  if not final_newline then
    result[#result + 1] = diagnostic(#lines - 1, #lines[#lines], #lines[#lines], INFO, "C-A3",
      "no newline at the end of the file")
  end
  return result
end

-- A buffer's text as it will be written: \r line endings for dos format,
-- and a final newline unless 'eol' and 'fixeol' are both off.
function M.buffer_text(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local cr = vim.bo[buf].fileformat == "dos" and "\r" or ""
  local text = table.concat(lines, cr .. "\n")
  if vim.bo[buf].eol or vim.bo[buf].fixeol then
    text = text .. cr .. "\n"
  end
  return text
end

function M.refresh(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  if not config.options.makefile.enabled or vim.bo[buf].filetype ~= "make"
    or require("epitech.ignore").ignored(buf) then
    vim.diagnostic.reset(M.ns, buf)
    return
  end
  vim.diagnostic.set(M.ns, buf, M.run(M.buffer_text(buf), vim.api.nvim_buf_get_name(buf)))
end

local timers = {}

function M.schedule(buf)
  local timer = timers[buf]
  if not timer then
    timer = assert(vim.uv.new_timer())
    timers[buf] = timer
  end
  timer:stop()
  timer:start(250, 0, vim.schedule_wrap(function()
    M.refresh(buf)
  end))
end

function M.setup(options)
  local group = vim.api.nvim_create_augroup("epitech.makefile", { clear = true })
  if not options.makefile.enabled then
    return
  end
  vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost" }, {
    group = group,
    callback = function(args)
      if vim.bo[args.buf].filetype == "make" then
        M.refresh(args.buf)
      end
    end,
  })
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "InsertLeave" }, {
    group = group,
    callback = function(args)
      if vim.bo[args.buf].filetype == "make" then
        M.schedule(args.buf)
      end
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    callback = function(args)
      if timers[args.buf] then
        timers[args.buf]:close()
        timers[args.buf] = nil
      end
    end,
  })
end

return M
