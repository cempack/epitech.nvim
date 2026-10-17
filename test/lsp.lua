local plugin = assert(vim.env.EPITECH_NVIM_DIR, "EPITECH_NVIM_DIR is required")
vim.opt.runtimepath:prepend(plugin)
package.path = plugin .. "/lua/?.lua;" .. plugin .. "/lua/?/init.lua;" .. package.path

local h = dofile(plugin .. "/test/helpers.lua")
local fixes = require("epitech.fixes")
local ts = require("epitech.ts")

-- Only the stand-in fix below: this tests the server, not the real fixes.
fixes.modules = {}

-- A stand-in fix: C-F6 on every empty parameter list, like §8.3's skeleton.
local commands_run = {}
fixes.register({
  id = "test_void",
  rules = { "C-F6" },
  actions = function(buf, range)
    local actions = {}
    for _, proto in ipairs(ts.prototypes(buf)) do
      local params = proto.declarator:field("parameters")[1]
      if proto.empty_params and fixes.touches(params, range) then
        local _, _, row, col = params:range()
        actions[#actions + 1] = fixes.action("Add void (C-F6)", "C-F6", buf, {
          { range = fixes.position_range(row, col - 1), newText = "void" },
        })
        actions[#actions + 1] = fixes.command_action("Run a command", "C-F6", "epitech.test_void", { proto.name })
      end
    end
    return actions
  end,
  commands = {
    ["epitech.test_void"] = function(command)
      commands_run[#commands_run + 1] = command.arguments[1]
    end,
  },
})

local root, cleanup = h.temp_project({ ["include/help.h"] = { "int print_help();", "int other(void);" } })
local buf = h.buffer(root .. "/include/help.h", vim.fn.readfile(root .. "/include/help.h"))
local actions, client = h.code_actions(buf, h.rows(0))
h.assert_equal(client.name, "epitech", "client name")
h.assert_equal(client.offset_encoding, "utf-8", "byte-based positions")
h.assert_equal(client.root_dir, root, "client root is the project root")
h.assert_equal(vim.tbl_map(function(action)
  return action.title
end, actions), { "Add void (C-F6)", "Run a command" }, "actions on the line")
h.assert_equal(#h.code_actions(buf, h.rows(1)), 0, "no action on a line without a problem")

h.apply_action(actions[1], client)
h.assert_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), { "int print_help(void);", "int other(void);" },
  "edit applied")
h.assert_equal(#h.code_actions(buf), 0, "idempotent")

-- Command actions run client-side through vim.lsp.commands.
client:exec_cmd(actions[2].command, { bufnr = buf })
h.assert_equal(commands_run, { "print_help" }, "client-side command")

-- One client per project root.
local second = h.buffer(root .. "/include/other.h", {})
h.assert_equal(require("epitech.lsp").start(second), client.id, "same client for the same root")
h.assert_equal(require("epitech.lsp").start(vim.api.nvim_create_buf(true, false)), nil, "unnamed buffers are skipped")

-- A failing fix reports an error instead of breaking the menu silently.
fixes.register({
  id = "test_broken",
  rules = {},
  actions = function()
    error("broken fix")
  end,
})
local response = client:request_sync("textDocument/codeAction", {
  textDocument = { uri = vim.uri_from_bufnr(buf) },
  range = h.rows(0),
  context = { diagnostics = {} },
}, 1000, buf)
assert(response.err and response.err.message:find("broken fix", 1, true), vim.inspect(response))

-- setup() starts the server for C and Makefile buffers only when fixes are on.
client:stop(true)
vim.wait(1000, function()
  return #vim.lsp.get_clients({ name = "epitech" }) == 0
end)
local config = require("epitech.config")
require("epitech.lsp").setup(config.setup({ fixes = { enabled = false } }))
h.buffer(root .. "/src/off.c", {})
h.assert_equal(#vim.lsp.get_clients({ name = "epitech" }), 0, "no server when fixes are off")
require("epitech.lsp").setup(config.setup())
local make = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(make, root .. "/Makefile")
vim.bo[make].filetype = "make"
-- Clients attach once the (scheduled) initialize response arrives.
vim.wait(1000, function()
  return #vim.lsp.get_clients({ name = "epitech", bufnr = make }) == 1
end)
h.assert_equal(#vim.lsp.get_clients({ name = "epitech", bufnr = make }), 1, "server on a Makefile")
h.assert_equal(#vim.lsp.get_clients({ name = "epitech", bufnr = vim.fn.bufnr(root .. "/src/off.c") }), 1,
  "setup() attaches to buffers already open")
config.setup({ fixes = { enabled = false } })
h.assert_equal(fixes.actions(buf, h.rows(0)), {}, "fixes.enabled = false offers nothing")

cleanup()
print("Epitech language server tests passed")
