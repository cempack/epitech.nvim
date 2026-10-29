-- Small helpers shared by the features that edit files other than the
-- current buffer.
local M = {}

-- vim.system, with a program or working directory that doesn't exist
-- reported as a failed run ({ code = -1, stdout = "", stderr = reason })
-- instead of an error: hints run git on every pause in typing, and git may
-- be missing, or a new file's directory not created yet. on_exit then runs
-- before this returns.
function M.system(cmd, opts, on_exit)
  local ok, handle = pcall(vim.system, cmd, opts, on_exit)
  if ok then
    return handle
  end
  local result = { code = -1, signal = 0, stdout = "", stderr = tostring(handle) }
  if on_exit then
    on_exit(result)
  end
  return {
    wait = function()
      return result
    end,
    kill = function() end,
    is_closing = function()
      return true
    end,
  }
end

function M.normalize(path)
  return vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
end

-- The loaded buffer showing path, if any.
function M.loaded_buffer(path)
  path = M.normalize(path)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.api.nvim_buf_get_name(buf) ~= ""
      and M.normalize(vim.api.nvim_buf_get_name(buf)) == path then
      return buf
    end
  end
end

-- Runs fn(buf) to edit path: on its buffer when it's loaded, so undo works
-- and the user saves it, else on a scratch copy whose result is written to
-- the file (created with its directories when missing). Returns the loaded
-- buffer, or nil when the file was written.
function M.edit_file(path, fn)
  local buf = M.loaded_buffer(path)
  if buf then
    fn(buf)
    return buf
  end
  local scratch = vim.api.nvim_create_buf(false, true)
  if vim.fn.filereadable(path) == 1 then
    vim.api.nvim_buf_set_lines(scratch, 0, -1, false, vim.fn.readfile(path))
  end
  local ok, err = pcall(fn, scratch)
  if ok then
    vim.fn.mkdir(vim.fs.dirname(path), "p")
    vim.fn.writefile(vim.api.nvim_buf_get_lines(scratch, 0, -1, false), path)
  end
  vim.api.nvim_buf_delete(scratch, { force = true })
  if not ok then
    error(err, 0)
  end
end

-- The lines of path: from its loaded buffer when there is one (it may hold
-- unsaved changes), else from disk.
function M.read_lines(path)
  local buf = M.loaded_buffer(path)
  if buf then
    return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  end
  return vim.fn.filereadable(path) == 1 and vim.fn.readfile(path) or {}
end

-- path relative to dir when it's inside it, else nil.
function M.relative(path, dir)
  path, dir = M.normalize(path), M.normalize(dir):gsub("/$", "")
  if vim.startswith(path, dir .. "/") then
    return path:sub(#dir + 2)
  end
end

-- Adds #include "name" to a C buffer unless it's already there: after the
-- last #include, else after the Epitech header, keeping one blank line
-- around it. Returns whether it added the line.
function M.ensure_include(buf, name)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local last
  for i, line in ipairs(lines) do
    if line:match('^%s*#%s*include%s*"' .. vim.pesc(name) .. '"') then
      return false
    end
    if line:match("^%s*#%s*include") then
      last = i
    end
  end
  local include = '#include "' .. name .. '"'
  if last then
    vim.api.nvim_buf_set_lines(buf, last, last, false, { include })
    return true
  end
  local at = require("epitech.header").existing_header(lines) == 1 and 6 or 0
  local new = { include }
  if at > 0 then
    if lines[at + 1] == "" then
      at = at + 1
    else
      table.insert(new, 1, "")
    end
  end
  if lines[at + 1] ~= nil and lines[at + 1] ~= "" then
    new[#new + 1] = ""
  end
  vim.api.nvim_buf_set_lines(buf, at, at, false, new)
  return true
end

-- Runs the formatter on a piece of C; returns it unchanged when the
-- formatter can't run (clang-format missing).
function M.format_lines(lines)
  local scratch = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(scratch, 0, -1, false, lines)
  local ok = pcall(require("epitech.format").format_buffer, scratch)
  local result = ok and vim.api.nvim_buf_get_lines(scratch, 0, -1, false) or lines
  vim.api.nvim_buf_delete(scratch, { force = true })
  return result
end

function M.notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "Epitech" })
end

return M
