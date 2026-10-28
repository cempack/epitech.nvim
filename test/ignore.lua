local plugin = assert(vim.env.EPITECH_NVIM_DIR, "EPITECH_NVIM_DIR is required")
vim.opt.runtimepath:prepend(plugin)
package.path = plugin .. "/lua/?.lua;" .. plugin .. "/lua/?/init.lua;" .. package.path

local h = dofile(plugin .. "/test/helpers.lua")
local epitech = require("epitech")
local hints = require("epitech.hints")
local budget = require("epitech.budget")
local project = require("epitech.project")
local check = require("epitech.check")
epitech.setup()
local notices = {}
vim.notify = function(message)
  notices[#notices + 1] = message
end

local function c_file(name)
  return { "int " .. name .. "(void)", "{", "    return 4096;", "}" }
end
local root, cleanup = h.temp_project({
  ["src/a.c"] = c_file("get_a"),
  ["src/b.c"] = c_file("get_b"),
})
project.save_state(root, { header_synced = { "get_a" } })

local a = h.buffer(root .. "/src/a.c", c_file("get_a"))
local b = h.buffer(root .. "/src/b.c", c_file("get_b"))
local function shown(buf)
  hints.refresh(buf)
  budget.update(buf)
  return {
    hints = #vim.diagnostic.get(buf, { namespace = hints.ns }) > 0,
    meter = #vim.api.nvim_buf_get_extmarks(buf, budget.ns, 0, -1, {}) > 0,
    actions = #h.code_actions(buf, h.rows(2)) > 0,
  }
end
local on = { hints = true, meter = true, actions = true }
-- Ignored: no warnings, but the fixes (and the formatter) still apply.
local off = { hints = false, meter = false, actions = true }
h.assert_equal(shown(a), on, "a.c checked at first")

local function checked_paths()
  local result
  check.run(root, function(r)
    result = r
  end)
  assert(vim.wait(10000, function()
    return result ~= nil
  end), "check finished")
  local paths = {}
  for _, entry in ipairs(result.entries) do
    paths[entry.path] = true
  end
  return paths
end
h.assert_equal(checked_paths(), { ["src/a.c"] = true, ["src/b.c"] = true }, "the check sees both files")

-- :EpitechIgnore: this file only.
vim.api.nvim_set_current_buf(a)
vim.cmd("EpitechIgnore")
h.assert_equal(notices[#notices], "Epitech warnings off for src/a.c", "the user is told")
h.assert_equal(shown(a), off, "a.c: no hints or meters, fixes still offered")
h.assert_equal(shown(b), on, "b.c still checked")
h.assert_equal(project.state(root), { header_synced = { "get_a" }, ignored_files = { "src/a.c" } },
  "remembered in the project state, which keeps its other keys")
h.assert_equal(checked_paths(), { ["src/b.c"] = true }, "the check skips a.c")
vim.api.nvim_buf_set_lines(a, 2, 3, false, { "    return    4096 ;" })
require("epitech.format").format_buffer(a)
h.assert_equal(vim.api.nvim_buf_get_lines(a, 0, -1, false), c_file("get_a"), "the formatter still runs on a.c")
h.with_fake_epiclang({ root .. "/src/a.c:3:5: warning: [Banana] [Major] multiple statements on the same line (C-L1)" },
  function(calls)
    require("epitech.banana").run(a)
    vim.wait(300)
    h.assert_equal(#calls(), 0, "Banana isn't run on a.c")
    h.assert_equal(vim.diagnostic.get(a, { namespace = require("epitech.banana").ns }), {}, "no Banana diagnostics")
  end)

-- :EpitechIgnore project, then back.
vim.cmd("EpitechIgnore project")
h.assert_equal(shown(b), off, "the whole project is off")
h.assert_equal(checked_paths(), {}, "the check skips everything")
vim.cmd("EpitechUnignore project")
h.assert_equal(shown(b), on, "the project is back")
h.assert_equal(shown(a), off, "a.c still ignored on its own")
vim.api.nvim_set_current_buf(a)
vim.cmd("EpitechUnignore file")
h.assert_equal(shown(a), on, "a.c is back")
h.assert_equal(project.state(root), { header_synced = { "get_a" } }, "nothing left in the state")
vim.cmd("EpitechIgnore everything")
h.assert_equal(notices[#notices], "Use file or project", "a wrong scope is refused")

cleanup()
print("Epitech ignore tests passed")
