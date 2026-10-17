local plugin = assert(vim.env.EPITECH_NVIM_DIR, "EPITECH_NVIM_DIR is required")
vim.opt.runtimepath:prepend(plugin)
package.path = plugin .. "/lua/?.lua;" .. plugin .. "/lua/?/init.lua;" .. package.path

local h = dofile(plugin .. "/test/helpers.lua")
local config = require("epitech.config")

local notices = {}
vim.notify = function(message, level)
  notices[#notices + 1] = { message = message, level = level }
end

local function expect_error(opts, fragment, label)
  local ok, err = pcall(config.merge, opts)
  assert(not ok, label .. ": no error")
  assert(tostring(err):find(fragment, 1, true), label .. ": " .. tostring(err))
end

-- The §7 defaults, with no argument and with an empty table.
h.assert_equal(config.merge(), config.defaults, "merge() returns the defaults")
h.assert_equal(config.merge({}), config.defaults, "merge({}) returns the defaults")
h.assert_equal(config.defaults.budget.max_lines, 20, "budget.max_lines default")
h.assert_equal(config.defaults.hints.magic_numbers.allow, { 0, 1, -1, 84 }, "magic number allow list")
h.assert_equal(config.defaults.hints.severity, vim.diagnostic.severity.HINT, "hint severity")
h.assert_equal(config.defaults.check.fail_on, { "fatal", "major" }, "check.fail_on default")
local merged = config.merge()
merged.budget.max_lines = 99
h.assert_equal(config.defaults.budget.max_lines, 20, "the result doesn't alias the defaults")

-- Deep merge: nested keys keep their siblings' defaults.
merged = config.merge({ budget = { max_lines = 25 }, hints = { naming = { enabled = false } } })
h.assert_equal(merged.budget.max_lines, 25, "nested override")
h.assert_equal(merged.budget.warn_lines, 17, "sibling default kept")
h.assert_equal(merged.hints.naming.enabled, false, "deeper override")
h.assert_equal(merged.hints.static, true, "deeper sibling default kept")

-- Lists replace the default instead of merging into it.
merged = config.merge({ hints = { magic_numbers = { allow = { 0 } } }, diagnostics = { args = { "-fsyntax-only" } } })
h.assert_equal(merged.hints.magic_numbers.allow, { 0 }, "allow list replaced")
h.assert_equal(merged.diagnostics.args, { "-fsyntax-only" }, "args list replaced")

-- Optional lists default to nil.
h.assert_equal(config.merge().hints.naming.verbs, nil, "verbs default to the built-in list")
merged = config.merge({ hints = { naming = { verbs = { "get" }, vague_files = { "utils" } } } })
h.assert_equal(merged.hints.naming.verbs, { "get" }, "custom verbs")
h.assert_equal(merged.hints.naming.vague_files, { "utils" }, "custom vague file names")

-- `feature = false` turns a feature with an `enabled` key off.
merged = config.merge({ diagnostics = false, hints = { magic_numbers = false } })
h.assert_equal(merged.diagnostics.enabled, false, "diagnostics = false")
h.assert_equal(merged.diagnostics.cmd, "epiclang", "diagnostics = false keeps the other keys")
h.assert_equal(merged.hints.magic_numbers, { enabled = false, allow = { 0, 1, -1, 84 } }, "magic_numbers = false")

-- Keymaps take a key sequence or false.
merged = config.merge({ explain = { keymap = false }, check = { keymap = "<leader>xb" } })
h.assert_equal(merged.explain.keymap, false, "keymap disabled")
h.assert_equal(merged.check.keymap, "<leader>xb", "keymap changed")
expect_error({ explain = { keymap = 1 } }, "explain.keymap", "keymap number")

-- budget.file takes one of its choices.
h.assert_equal(config.merge({ budget = { file = "lualine" } }).budget.file, "lualine", "budget.file lualine")
h.assert_equal(config.merge({ budget = { file = false } }).budget.file, false, "budget.file false")
expect_error({ budget = { file = "statusline" } }, "budget.file", "budget.file choice")

-- A wrong type raises an error naming the key path.
expect_error({ budget = { max_lines = "20" } }, "option budget.max_lines must be a number", "number as string")
expect_error({ hints = { naming = "yes" } }, "hints.naming", "table as string")
expect_error({ hints = { magic_numbers = { allow = 0 } } }, "hints.magic_numbers.allow", "list as number")
expect_error({ hints = { magic_numbers = { allow = { "0" } } } }, "hints.magic_numbers.allow", "list item type")
expect_error({ hints = { naming = { verbs = "get" } } }, "hints.naming.verbs", "optional list as string")
expect_error({ check = { fail_on = { "fatal", "huge" } } }, "check.fail_on", "fail_on level")
expect_error("x", "setup(opts) expects a table", "opts as string")
h.assert_equal(#notices, 0, "no warning for valid options")

-- Unknown keys are dropped with one warning listing them.
merged = config.merge({ hint = true, budget = { max_line = 25 } })
h.assert_equal(#notices, 1, "one warning for unknown keys")
h.assert_equal(notices[1].message, "epitech.nvim: unknown options ignored: budget.max_line, hint", "unknown keys warning")
h.assert_equal(notices[1].level, vim.log.levels.WARN, "unknown keys warning level")
h.assert_equal(merged, config.defaults, "unknown keys dropped")

-- setup() stores the options and honours the keymap settings.
local epitech = require("epitech")
epitech.setup({ header = { keymap = false }, guard = { keymap = "<leader>xg" } })
h.assert_equal(config.options.guard.keymap, "<leader>xg", "setup stores the options")
h.assert_equal(vim.fn.maparg("<leader>cH", "n"), "", "disabled header keymap")
h.assert_equal(vim.fn.maparg("<leader>cG", "n"), "", "moved guard keymap")
h.assert_equal(vim.fn.maparg("<leader>xg", "n", false, true).desc, "Epitech Include Guard", "custom guard keymap")
assert(vim.api.nvim_get_commands({ builtin = false }).EpitechHeader, "commands still defined")

print("Epitech config tests passed")
