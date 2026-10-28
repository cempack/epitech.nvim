-- :EpitechHooks installs a git pre-push hook that runs the project check and
-- stops the push while a Fatal or Major is left. The hook file sits in
-- .git/hooks, which git never tracks, so nothing lands in the repository.
-- :EpitechLazygit shows a lazygit key for the same check; the plugin never
-- edits lazygit's config itself.
local format = require("epitech.format")
local project = require("epitech.project")
local util = require("epitech.util")

local M = {}

M.MARKER = "# Installed by epitech.nvim (:EpitechHooks). Delete this file to remove it."

function M.script_path()
  return vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(format.path))) .. "/scripts/check.lua"
end

-- The repository's hooks directory (worktrees and core.hooksPath
-- included), or nil outside git.
function M.hooks_dir(root)
  local result = util.system({ "git", "rev-parse", "--git-path", "hooks" }, { cwd = root, text = true }):wait()
  if result.code ~= 0 then
    return nil
  end
  local dir = vim.trim(result.stdout)
  if dir:sub(1, 1) ~= "/" then
    dir = root .. "/" .. dir
  end
  return vim.fs.normalize(dir)
end

-- The hook's lines. With chain, the previous hook (pre-push.local) runs
-- first, with the same arguments and the refs git sends on stdin.
function M.content(chain)
  local lines = {
    "#!/bin/sh",
    M.MARKER,
    'root="$(git rev-parse --show-toplevel)" || exit 0',
  }
  if chain then
    lines[#lines + 1] = '"$(dirname "$0")/pre-push.local" "$@" || exit $?'
  end
  -- Absolute paths: git clients started without the user's PATH still work.
  local nvim = vim.v.progpath ~= "" and vim.v.progpath or vim.fn.exepath("nvim")
  lines[#lines + 1] = ("exec %s --clean --headless -l %s --ci --hook \"$root\""):format(vim.fn.shellescape(nvim),
    vim.fn.shellescape(M.script_path()))
  return lines
end

local function is_ours(path)
  return vim.fn.filereadable(path) == 1 and vim.list_contains(vim.fn.readfile(path, "", 5), M.MARKER)
end

local function write_hook(path, chain)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  vim.fn.writefile(M.content(chain), path)
  vim.uv.fs_chmod(path, 493)
end

-- Installs the hook in the repository at root. An existing hook that isn't
-- the plugin's is chained, replaced or kept, as the user picks. on_done
-- (optional) receives the outcome: "installed", "chained", "replaced",
-- "updated" or nil.
function M.install(root, on_done)
  root = root or project.root(0)
  on_done = on_done or function() end
  local dir = M.hooks_dir(root)
  if not dir then
    util.notify("Not a git repository: " .. root, vim.log.levels.WARN)
    return on_done(nil)
  end
  local path = dir .. "/pre-push"
  local chained = dir .. "/pre-push.local"
  if vim.fn.filereadable(path) == 0 then
    write_hook(path, false)
    util.notify("Pre-push hook installed: pushes stop while a Fatal or Major is left")
    return on_done("installed")
  end
  if is_ours(path) then
    write_hook(path, vim.fn.filereadable(chained) == 1)
    util.notify("Pre-push hook updated")
    return on_done("updated")
  end
  vim.ui.select({ "Chain", "Replace", "Cancel" }, {
    prompt = "This repository already has a pre-push hook",
    format_item = function(item)
      return ({
        Chain = "Chain: run the existing hook, then the check",
        Replace = "Replace it with the check",
        Cancel = "Cancel",
      })[item]
    end,
  }, function(choice)
    if choice == "Chain" then
      vim.uv.fs_rename(path, chained)
      write_hook(path, true)
      util.notify("Pre-push hook installed; the existing one now runs first (pre-push.local)")
      on_done("chained")
    elseif choice == "Replace" then
      write_hook(path, false)
      util.notify("Pre-push hook replaced")
      on_done("replaced")
    else
      on_done(nil)
    end
  end)
end

-- :EpitechHooks remove: deletes the plugin's hook and puts a chained one
-- back.
function M.remove(root)
  root = root or project.root(0)
  local dir = M.hooks_dir(root)
  local path = dir and dir .. "/pre-push"
  if not path or not is_ours(path) then
    util.notify("No epitech.nvim pre-push hook here", vim.log.levels.WARN)
    return false
  end
  vim.fn.delete(path)
  if vim.fn.filereadable(dir .. "/pre-push.local") == 1 then
    vim.uv.fs_rename(dir .. "/pre-push.local", path)
  end
  util.notify("Pre-push hook removed")
  return true
end

-- Whether root's hook is the plugin's but runs an nvim or a check script
-- that no longer exists (the plugin was reinstalled elsewhere).
function M.stale(root)
  local dir = M.hooks_dir(root)
  local path = dir and dir .. "/pre-push"
  if not path or not is_ours(path) then
    return false
  end
  for _, line in ipairs(vim.fn.readfile(path)) do
    if vim.startswith(line, "exec ") then
      local quoted = {}
      for value in line:gmatch("'(.-)'") do
        quoted[#quoted + 1] = value
      end
      return vim.fn.executable(quoted[1] or "") == 0 or vim.fn.filereadable(quoted[2] or "") == 0
    end
  end
  return false
end

local warned = false

-- Called from setup(): warns once when the current repository's hook is
-- stale. Runs after startup so it never slows it down.
function M.check_stale()
  vim.defer_fn(function()
    local root = vim.fs.root(vim.fn.getcwd(), ".git")
    if root and not warned and M.stale(root) then
      warned = true
      util.notify("The epitech.nvim pre-push hook points to an old install: run :EpitechHooks to update it",
        vim.log.levels.WARN)
    end
  end, 100)
end

-- lazygit 0.51 replaced `subprocess: true` with `output: terminal`.
function M.lazygit_version()
  if vim.fn.executable("lazygit") == 0 then
    return nil
  end
  local result = vim.system({ "lazygit", "--version" }, { text = true }):wait()
  local major, minor = (result.stdout or ""):match("version=(%d+)%.(%d+)")
  return major and { tonumber(major), tonumber(minor) } or nil
end

-- The YAML for a lazygit key running the check, for the installed version
-- (the current key when it can't tell).
function M.lazygit_yaml(version)
  local old = version and (version[1] == 0 and version[2] < 51)
  return {
    "customCommands:",
    '  - key: "B"',
    '    context: "files"',
    '    description: "Banana check"',
    ('    command: "nvim --clean --headless -l %s --ci ."'):format(M.script_path()),
    old and "    subprocess: true" or "    output: terminal",
  }
end

-- Marks the plugin's entry in lazygit's config, so it can be updated or
-- removed later.
M.LAZYGIT_MARKER = "# epitech.nvim: Banana check (:EpitechLazygit)"

-- lazygit's config.yml: the first file of $LG_CONFIG_FILE, else
-- `lazygit --print-config-dir`, else the XDG default.
function M.lazygit_config()
  if vim.env.LG_CONFIG_FILE and vim.env.LG_CONFIG_FILE ~= "" then
    return vim.split(vim.env.LG_CONFIG_FILE, ",", { plain = true })[1]
  end
  local dir
  if vim.fn.executable("lazygit") == 1 then
    local result = util.system({ "lazygit", "--print-config-dir" }, { text = true }):wait()
    dir = result.code == 0 and vim.trim(result.stdout or "") or nil
  end
  if not dir or dir == "" then
    dir = (vim.env.XDG_CONFIG_HOME or (vim.env.HOME .. "/.config")) .. "/lazygit"
  end
  return dir .. "/config.yml"
end

local function indent_of(line)
  return #line:match("^%s*")
end

-- The rows (1-based, inclusive) of the plugin's entry in config lines, or nil.
local function lazygit_entry(lines)
  for i, line in ipairs(lines) do
    if vim.trim(line) == M.LAZYGIT_MARKER then
      local dash = lines[i + 1] and lines[i + 1]:match("^(%s*)%- ")
      if not dash then
        return i, i
      end
      local last = i + 1
      while lines[last + 1] and (lines[last + 1]:match("^%s*$") == nil and indent_of(lines[last + 1]) > #dash) do
        last = last + 1
      end
      return i, last
    end
  end
end

-- lines with the plugin's entry removed, and the customCommands key when
-- nothing is left in it.
function M.lazygit_remove(lines)
  local first, last = lazygit_entry(lines)
  local result = vim.deepcopy(lines)
  if not first then
    return result
  end
  for _ = first, last do
    table.remove(result, first)
  end
  local header = first - 1
  local next_line = result[first]
  if result[header] and vim.trim(result[header]) == "customCommands:"
    and (not next_line or (next_line:match("^%S") and not next_line:match("^%- "))) then
    table.remove(result, header)
    if result[header - 1] == "" and (not result[header] or result[header] == "") then
      table.remove(result, header - 1)
    end
  end
  return result
end

-- lines with the plugin's entry added or brought up to date, or nil and why
-- not. Everything else in the config stays as it is.
function M.lazygit_add(lines, version)
  local item = vim.list_slice(M.lazygit_yaml(version), 2)
  local result = M.lazygit_remove(lines)
  local first = lazygit_entry(lines)
  local header
  for i, line in ipairs(result) do
    if line:match("^customCommands:") then
      header = i
    end
  end
  if not header then
    if #result > 0 and result[#result] ~= "" then
      result[#result + 1] = ""
    end
    vim.list_extend(result, { "customCommands:", "  " .. M.LAZYGIT_MARKER })
    vim.list_extend(result, item)
    return result
  end
  local rest = vim.trim(result[header]:match("^customCommands:(.*)$"):gsub("%s+#.*$", ""))
  if rest == "[]" then
    result[header] = "customCommands:"
  elseif rest ~= "" then
    return nil, "lazygit's customCommands is written on one line; add the entry by hand"
  end
  -- The list's own indentation, and no other command already on B.
  local dash
  local i = header + 1
  while result[i] and (result[i]:match("^%s*$") or result[i]:match("^%s*#") or indent_of(result[i]) > 0
    or result[i]:match("^%- ")) do
    dash = dash or result[i]:match("^(%s*)%- ")
    local key = result[i]:match("^%s*%-?%s*key:%s*[\"']?([^\"'%s]+)[\"']?%s*$")
    if key == "B" then
      return nil, "another lazygit custom command already uses B"
    end
    i = i + 1
  end
  dash = dash or "  "
  local entry = { dash .. M.LAZYGIT_MARKER }
  for _, line in ipairs(item) do
    entry[#entry + 1] = dash .. line:sub(3)
  end
  -- Where it was, when it's updated; first in the list otherwise.
  local at = first and first or header + 1
  for k, line in ipairs(entry) do
    table.insert(result, at + k - 1, line)
  end
  return result
end

-- :EpitechLazygit [remove]: adds the Banana check on B in lazygit's files
-- panel (or updates it, when the plugin moved), or removes it.
function M.lazygit(remove)
  local path = M.lazygit_config()
  local lines = vim.fn.filereadable(path) == 1 and vim.fn.readfile(path) or {}
  local result, reason
  if remove then
    result = M.lazygit_remove(lines)
  else
    result, reason = M.lazygit_add(lines, M.lazygit_version())
  end
  if not result then
    return util.notify("lazygit: " .. reason, vim.log.levels.WARN)
  elseif vim.deep_equal(result, lines) then
    return util.notify(remove and "lazygit: no Banana check to remove" or "lazygit: the Banana check is already on B")
  end
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  if #lines > 0 then
    vim.fn.writefile(lines, path .. ".bak")
  end
  vim.fn.writefile(result, path)
  util.notify(remove and ("lazygit: Banana check removed from " .. path)
    or ("lazygit: B in the files panel now runs the Banana check (" .. path .. ")"))
end

return M
