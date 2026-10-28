-- :EpitechIgnore and :EpitechUnignore: turn the plugin off for a file or a
-- whole project (a school project in another language, a lib from
-- elsewhere). The choice lives in the project state, outside the
-- repository (C-O1): nothing is written into the project.
local project = require("epitech.project")
local util = require("epitech.util")

local M = {}

-- Project state read once per root; save() keeps it current.
local cache = {}

local function state(root)
  cache[root] = cache[root] or project.state(root)
  return cache[root]
end

local function save(root, tbl)
  cache[root] = tbl
  project.save_state(root, tbl)
end

local function path_of(source)
  if type(source) == "number" then
    local buf = source == 0 and vim.api.nvim_get_current_buf() or source
    return vim.api.nvim_buf_get_name(buf), buf
  end
  return source
end

-- Answers per buffer (the winbar asks on every redraw), until the buffer's
-- name or the ignore list changes.
local answers, generation = {}, 0

-- Whether the plugin leaves a buffer (or a file path) alone: its project
-- or the file itself is ignored.
function M.ignored(source)
  local path, buf = path_of(source)
  if not path or path == "" then
    return false
  end
  if buf then
    local answer = answers[buf]
    if answer and answer.generation == generation and answer.path == path then
      return answer.value
    end
    local value = M.ignored(path)
    answers[buf] = { generation = generation, path = path, value = value }
    return value
  end
  local root = project.root(buf or path)
  local tbl = state(root)
  if tbl.ignored then
    return true
  end
  local relative = util.relative(path, root)
  return relative ~= nil and vim.list_contains(tbl.ignored_files or {}, relative)
end

-- Whether a project-relative path is ignored in the project at root.
function M.ignored_path(root, relative)
  local tbl = state(root)
  return tbl.ignored == true or vim.list_contains(tbl.ignored_files or {}, relative)
end

-- Clears or redraws everything the plugin shows in the loaded buffers.
local function refresh_all()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      local ignored = M.ignored(buf)
      for _, ns in ipairs({ require("epitech.banana").ns, require("epitech.hints").ns,
        require("epitech.hints.makefile").ns }) do
        if ignored then
          vim.diagnostic.reset(ns, buf)
        end
      end
      if not ignored and vim.bo[buf].filetype == "c" then
        require("epitech.banana").run(buf)
        require("epitech.hints").refresh(buf)
      elseif not ignored and vim.bo[buf].filetype == "make" then
        require("epitech.hints.makefile").refresh(buf)
      end
      require("epitech.budget").update(buf)
    end
  end
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    require("epitech.budget").update_winbar(win)
  end
end

-- :EpitechIgnore [file|project] (ignore = true) and :EpitechUnignore
-- (ignore = false), for the current buffer's file or project.
function M.set(scope, ignore, buf)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  scope = (scope == nil or scope == "") and "file" or scope
  local name = vim.api.nvim_buf_get_name(buf)
  local root = project.root(buf)
  -- Fresh from disk: other features keep their own keys in the state.
  local tbl = project.state(root)
  local message
  if scope == "project" then
    tbl.ignored = ignore or nil
    message = (ignore and "Epitech rules off for the project " or "Epitech rules back on for the project ")
      .. vim.fs.basename(root)
  elseif scope == "file" then
    local relative = name ~= "" and util.relative(name, root)
    if not relative then
      return util.notify("Save the file first: it has no path in the project", vim.log.levels.WARN)
    end
    local files = vim.tbl_filter(function(file)
      return file ~= relative
    end, tbl.ignored_files or {})
    if ignore then
      files[#files + 1] = relative
      table.sort(files)
    end
    tbl.ignored_files = #files > 0 and files or nil
    message = (ignore and "Epitech rules off for " or "Epitech rules back on for ") .. relative
    if not ignore and tbl.ignored then
      message = message .. " (the whole project is still ignored: :EpitechUnignore project)"
    end
  else
    return util.notify("Use file or project", vim.log.levels.WARN)
  end
  save(root, tbl)
  generation = generation + 1
  refresh_all()
  util.notify(message)
end

function M.complete()
  return { "file", "project" }
end

return M
