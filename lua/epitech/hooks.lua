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

-- :EpitechLazygit: the YAML in a float, to paste into lazygit's config.
function M.show_lazygit()
  local lines = { "Add this to lazygit's config.yml (`lazygit --print-config-dir`):", "", "```yaml" }
  vim.list_extend(lines, M.lazygit_yaml(M.lazygit_version()))
  lines[#lines + 1] = "```"
  return vim.lsp.util.open_floating_preview(lines, "markdown", { border = "rounded", focus_id = "epitech_lazygit" })
end

return M
