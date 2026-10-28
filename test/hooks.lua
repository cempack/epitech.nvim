local plugin = assert(vim.env.EPITECH_NVIM_DIR, "EPITECH_NVIM_DIR is required")
vim.opt.runtimepath:prepend(plugin)
package.path = plugin .. "/lua/?.lua;" .. plugin .. "/lua/?/init.lua;" .. package.path

local h = dofile(plugin .. "/test/helpers.lua")
local hooks = require("epitech.hooks")
require("epitech.config").setup()
local notices = {}
vim.notify = function(message)
  notices[#notices + 1] = message
end

local function c_file(name)
  return { "/*", "** EPITECH PROJECT, 2026", "** demo", "** File description:", "** Demo", "*/", "",
    "int " .. name .. "(void)", "{", "    return 0;", "}" }
end
local root, cleanup = h.temp_project({ ["src/main.c"] = c_file("main") })
local dir = hooks.hooks_dir(root)
h.assert_equal(dir, root .. "/.git/hooks", "hooks directory")
local hook = dir .. "/pre-push"

-- A fresh install: executable, with the marker and absolute paths.
local outcome
hooks.install(root, function(result)
  outcome = result
end)
h.assert_equal(outcome, "installed", "installed")
local lines = vim.fn.readfile(hook)
h.assert_equal(lines[1], "#!/bin/sh", "shebang")
h.assert_equal(lines[2], hooks.MARKER, "marker")
h.assert_equal(lines[3], 'root="$(git rev-parse --show-toplevel)" || exit 0', "root line")
h.assert_equal(lines[4], ("exec '%s' --clean --headless -l '%s' --ci --hook \"$root\""):format(vim.v.progpath,
  plugin .. "/scripts/check.lua"), "exec line with absolute paths")
assert(vim.uv.fs_stat(hook).mode % 512 >= 448, "executable by its owner")
h.assert_equal(vim.fn.executable(hook), 1, "executable")
h.assert_equal(vim.system({ "git", "status", "--porcelain" }, { cwd = root, text = true }):wait().stdout,
  "A  src/main.c\n", "nothing new in the repository")

-- Running the hook: a Major stops the push, a clean project passes.
h.with_fake_epiclang({ root .. "/src/main.c:9:5: warning: [Banana] [Major] fake problem (C-L1)" }, function()
  local result = vim.system({ hook, "origin", "url" }, { cwd = root, text = true, stdin = "" }):wait()
  h.assert_equal(result.code, 1, "a Major stops the push")
  h.assert_equal(result.stderr, "epitech.nvim: 1 Major left, push stopped. Run :EpitechCheck to see them, or git"
    .. " push --no-verify to skip.\n", "the message")
end)
h.with_fake_epiclang({}, function()
  local result = vim.system({ hook, "origin", "url" }, { cwd = root, text = true, stdin = "" }):wait()
  h.assert_equal(result.code, 0, "a clean project pushes")
end)

-- An existing foreign hook: chain, then remove (it comes back), replace, cancel.
local foreign = { "#!/bin/sh", "echo foreign >> \"$(git rev-parse --show-toplevel)/.git/foreign.log\"", "exit 0" }
local function reset_foreign()
  vim.fn.delete(dir .. "/pre-push.local")
  vim.fn.writefile(foreign, hook)
  vim.uv.fs_chmod(hook, 493)
end
local answer
vim.ui.select = function(items, opts, on_choice)
  h.assert_equal(vim.tbl_map(opts.format_item, items), { "Chain: run the existing hook, then the check",
    "Replace it with the check", "Cancel" }, "choices")
  on_choice(answer)
end

reset_foreign()
answer = "Chain"
hooks.install(root, function(result)
  outcome = result
end)
h.assert_equal(outcome, "chained", "chained")
h.assert_equal(vim.fn.readfile(dir .. "/pre-push.local"), foreign, "the foreign hook kept as pre-push.local")
h.assert_equal(vim.fn.readfile(hook)[4], '"$(dirname "$0")/pre-push.local" "$@" || exit $?', "it runs first")
h.with_fake_epiclang({}, function()
  h.assert_equal(vim.system({ hook }, { cwd = root, stdin = "" }):wait().code, 0, "chained hook passes")
end)
h.assert_equal(vim.fn.readfile(root .. "/.git/foreign.log"), { "foreign" }, "the foreign hook ran")
hooks.install(root)
h.assert_equal(vim.fn.readfile(hook)[4], '"$(dirname "$0")/pre-push.local" "$@" || exit $?',
  "reinstalling keeps the chain")
h.assert_equal(hooks.remove(root), true, "removed")
h.assert_equal(vim.fn.readfile(hook), foreign, "the foreign hook is back")
h.assert_equal(vim.fn.filereadable(dir .. "/pre-push.local"), 0, "no leftover")

answer = "Replace"
hooks.install(root, function(result)
  outcome = result
end)
h.assert_equal({ outcome, vim.fn.readfile(hook)[2] }, { "replaced", hooks.MARKER }, "replaced")

reset_foreign()
answer = nil
hooks.install(root, function(result)
  outcome = result
end)
h.assert_equal({ outcome, vim.fn.readfile(hook) }, { nil, foreign }, "cancelled")
h.assert_equal(hooks.remove(root), false, "a foreign hook isn't removed")

-- A hook pointing to a plugin path that's gone is stale.
answer = "Replace"
hooks.install(root)
h.assert_equal(hooks.stale(root), false, "fresh hook")
local stale = vim.fn.readfile(hook)
stale[#stale] = stale[#stale]:gsub("scripts/check.lua", "gone/check.lua")
vim.fn.writefile(stale, hook)
h.assert_equal(hooks.stale(root), true, "stale hook")
vim.fn.chdir(root)
notices = {}
require("epitech").setup()
vim.wait(1000, function()
  return #notices > 0
end)
h.assert_equal(notices, { "The epitech.nvim pre-push hook points to an old install: run :EpitechHooks to update it" },
  "setup() warns once")

-- lazygit: the key for the installed version.
local yaml = hooks.lazygit_yaml({ 0, 51 })
h.assert_equal(yaml, {
  "customCommands:", '  - key: "B"', '    context: "files"', '    description: "Banana check"',
  ('    command: "nvim --clean --headless -l %s --ci ."'):format(plugin .. "/scripts/check.lua"),
  "    output: terminal",
}, "lazygit 0.51 and later")
h.assert_equal(hooks.lazygit_yaml({ 0, 50 })[6], "    subprocess: true", "older lazygit")
h.assert_equal(hooks.lazygit_yaml(nil)[6], "    output: terminal", "unknown version")

-- :EpitechLazygit edits lazygit's config, keeping everything else.
local command = ('    command: "nvim --clean --headless -l %s --ci ."'):format(plugin .. "/scripts/check.lua")
local entry = { "  " .. hooks.LAZYGIT_MARKER, '  - key: "B"', '    context: "files"',
  '    description: "Banana check"', command, "    output: terminal" }
local version = { 0, 55 }
h.assert_equal(hooks.lazygit_add({}, version), vim.list_extend({ "customCommands:" }, entry), "empty config")
h.assert_equal(hooks.lazygit_add({ "gui:", "  theme:", "    lightTheme: false" }, version),
  vim.list_extend({ "gui:", "  theme:", "    lightTheme: false", "", "customCommands:" }, vim.deepcopy(entry)),
  "no customCommands: appended")
h.assert_equal(hooks.lazygit_remove(hooks.lazygit_add({ "gui:", "  theme:", "    lightTheme: false" }, version)),
  { "gui:", "  theme:", "    lightTheme: false" }, "removing gives the config back as it was")
h.assert_equal(hooks.lazygit_add({ "customCommands: []", "gui:", "  nerdFontsVersion: \"3\"" }, version),
  vim.list_extend(vim.list_extend({ "customCommands:" }, vim.deepcopy(entry)), { "gui:", '  nerdFontsVersion: "3"' }),
  "customCommands: [] becomes a list")
local existing = { "customCommands:", "- key: 'C'", "  context: 'global'", "  command: 'git cz'", "os:",
  "  editPreset: nvim" }
local added = hooks.lazygit_add(existing, version)
h.assert_equal(added, { "customCommands:", hooks.LAZYGIT_MARKER, '- key: "B"', '  context: "files"',
  '  description: "Banana check"', command:sub(3), "  output: terminal", "- key: 'C'", "  context: 'global'",
  "  command: 'git cz'", "os:", "  editPreset: nvim" }, "an existing list keeps its items and indentation")
h.assert_equal(hooks.lazygit_add(added, version), added, "already there: unchanged")
local moved = vim.deepcopy(added)
moved[6] = "  command: \"nvim --clean --headless -l /old/epitech.nvim/scripts/check.lua --ci .\""
h.assert_equal(hooks.lazygit_add(moved, version), added, "an old path is updated in place")
h.assert_equal(hooks.lazygit_remove(added), existing, "removed")
h.assert_equal({ hooks.lazygit_add({ "customCommands:", "  - key: B", "    command: make" }, version) },
  { nil, "another lazygit custom command already uses B" }, "B taken")
h.assert_equal({ hooks.lazygit_add({ "customCommands: [{key: C, command: make}]" }, version) },
  { nil, "lazygit's customCommands is written on one line; add the entry by hand" }, "inline list")

-- The command, on the file $LG_CONFIG_FILE names.
local lazygit_dir = vim.fn.tempname()
vim.env.LG_CONFIG_FILE = lazygit_dir .. "/config.yml"
h.assert_equal(hooks.lazygit_config(), lazygit_dir .. "/config.yml", "LG_CONFIG_FILE")
notices = {}
vim.cmd("EpitechLazygit")
assert(vim.list_contains(vim.fn.readfile(lazygit_dir .. "/config.yml"), "  " .. hooks.LAZYGIT_MARKER),
  ":EpitechLazygit wrote the entry")
h.assert_equal(notices, { "lazygit: B in the files panel now runs the Banana check (" .. lazygit_dir
  .. "/config.yml)" }, ":EpitechLazygit says so")
vim.cmd("EpitechLazygit remove")
h.assert_equal(vim.fn.readfile(lazygit_dir .. "/config.yml"), {}, ":EpitechLazygit remove")
vim.env.LG_CONFIG_FILE = nil
vim.fn.delete(lazygit_dir, "rf")

vim.fn.chdir("/")
cleanup()
print("Epitech push guard tests passed")
