local plugin = assert(vim.env.EPITECH_NVIM_DIR, "EPITECH_NVIM_DIR is required")
vim.opt.runtimepath:prepend(plugin)
package.path = plugin .. "/lua/?.lua;" .. plugin .. "/lua/?/init.lua;" .. package.path

local h = dofile(plugin .. "/test/helpers.lua")
require("epitech.config").setup()

-- §9.11 before/after fixtures: result, idempotence, formatter.
h.check_fix("void", "definition", 0, "Add void (C-F6)", "C-F6")
h.check_fix("void", "prototype", 0, "Add void (C-F6)", "C-F6")
h.check_fix("void", "pointer", 0, "Add void (C-F6)", "C-F6")
h.check_fix("void", "main", 0, "Add void (C-F6)", "C-F6")

-- A function pointer keeps its () (no action on that line).
local buf = h.buffer("/tmp/epitech_void_pointer.c", { "int (*handler)();" })
h.assert_equal(h.actions_for((h.code_actions(buf)), "C-F6"), {}, "function pointers are left alone")

-- :EpitechFixAll C-F6 over the project.
local root, cleanup = h.temp_project({
  ["src/a.c"] = { "int one()", "{", "    return 1;", "}", "", "int two()", "{", "    return 2;", "}" },
  ["include/a.h"] = { "int one();", "int two(void);" },
  ["src/clean.c"] = { "int three(void)", "{", "    return 3;", "}" },
  ["src/open.c"] = { "int four()", "{", "    return 4;", "}" },
  ["src/dirty.c"] = { "int five()", "{", "    return 5;", "}" },
})
local open = h.buffer(root .. "/src/open.c", vim.fn.readfile(root .. "/src/open.c"))
vim.bo[open].modified = false
local dirty = h.buffer(root .. "/src/dirty.c", { "int five()", "{", "    return 50;", "}" })
vim.bo[dirty].modified = true
local notices = {}
vim.notify = function(message)
  notices[#notices + 1] = message
end
require("epitech").setup()
vim.cmd("EpitechFixAll c-f6")
h.assert_equal(notices[#notices], "4 functions fixed in 3 files; skipped (unsaved changes): src/dirty.c",
  ":EpitechFixAll summary")
h.assert_equal(vim.fn.readfile(root .. "/src/a.c")[1], "int one(void)", "file on disk fixed")
h.assert_equal(vim.fn.readfile(root .. "/src/a.c")[6], "int two(void)", "every function in it")
h.assert_equal(vim.fn.readfile(root .. "/include/a.h"), { "int one(void);", "int two(void);" }, "header fixed")
h.assert_equal(vim.api.nvim_buf_get_lines(open, 0, 1, false), { "int four(void)" }, "loaded buffer edited")
h.assert_equal(vim.fn.readfile(root .. "/src/open.c")[1], "int four()", "its file is left for the user to save")
h.assert_equal(vim.api.nvim_buf_get_lines(dirty, 0, 1, false), { "int five()" }, "modified buffer skipped")
h.assert_equal(require("epitech.fixes").fix_all("C-F6", root), "0 functions fixed in 0 files; skipped (unsaved changes): "
  .. "src/dirty.c, src/open.c", "nothing left to fix")
cleanup()

-- C-F3: `void` pushing the file's last line past 79 columns gets it wrapped
-- like the formatter does; an unformatted file keeps its other lines.
local function add_void(name, lines)
  local buf = h.buffer("/tmp/epitech_void_" .. name .. ".h", lines)
  local actions, client = h.code_actions(buf, h.rows(#lines - 1))
  h.apply_action(h.actions_for(actions, "C-F6")[1], client)
  return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
end
local long = "char *get_the_name_of_the_configuration_file_from_the_environment_variable();"
h.assert_equal(add_void("short", { "int f(void);", "char *get_the_configuration_file_name();" }),
  { "int f(void);", "char *get_the_configuration_file_name(void);" }, "short enough: the plain edit")
h.assert_equal(add_void("last", { "int f(void);", long }), { "int f(void);",
  "char *get_the_name_of_the_configuration_file_from_the_environment_variable(", "    void);" }, "last line wrapped")
h.assert_equal(add_void("unformatted", { "int   f( void );", long }), { "int   f( void );",
  "char *get_the_name_of_the_configuration_file_from_the_environment_variable(void);" },
  "a file the formatter would change elsewhere keeps the plain edit")

print("Epitech void fix tests passed")
