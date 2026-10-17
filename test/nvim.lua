local plugin = assert(vim.env.EPITECH_NVIM_DIR, "EPITECH_NVIM_DIR is required")
vim.opt.runtimepath:prepend(plugin)
vim.opt.runtimepath:append(plugin .. "/after")
package.path = plugin .. "/lua/?.lua;" .. plugin .. "/lua/?/init.lua;" .. package.path

local epitech = require("epitech")

local function assert_equal(actual, expected, label)
  if not vim.deep_equal(actual, expected) then
    error(("%s\nexpected: %s\nactual:   %s"):format(label, vim.inspect(expected), vim.inspect(actual)))
  end
end

local expected_header = {
  "/*",
  "** EPITECH PROJECT, " .. os.date("%Y"),
  "** Day 08",
  "** File description:",
  "** Copy string in allocated memory",
  "*/",
}

epitech.setup()
assert(vim.api.nvim_get_commands({ builtin = false }).EpitechHeader, "EpitechHeader command")
assert(vim.api.nvim_get_commands({ builtin = false }).EpitechGuard, "EpitechGuard command")
local formatter = epitech.formatter()
assert(formatter.command and formatter.args and formatter.condition, "Conform formatter definition")

local answers = { "Day 08", "Copy string in allocated memory" }
vim.bo.filetype = "c"
vim.ui.input = function(_, callback)
  callback(table.remove(answers, 1))
end
epitech.insert_header()
assert_equal(vim.api.nvim_buf_get_lines(0, 0, 6, false), expected_header, "header insertion")

-- header.lua's helpers are shared with other modules (project names, header
-- sync), so check what they return directly.
local header = require("epitech.header")
local start, style, project, description = header.existing_header(vim.api.nvim_buf_get_lines(0, 0, -1, false))
assert_equal({ start, style[1], project, description }, { 1, "/*", "Day 08", "Copy string in allocated memory" },
  "existing_header fields")
assert_equal(header.has_header(0), true, "has_header on a C header")
assert_equal(header.has_guard({ "#ifndef A_H_", "    #define A_H_", "#endif" }), true, "has_guard")
assert_equal(header.has_guard({ "#pragma once" }), false, "#pragma once is not a guard")

local before = vim.api.nvim_buf_line_count(0)
local notice
vim.notify = function(message)
  notice = message
end
epitech.insert_header()
assert_equal(vim.api.nvim_buf_line_count(0), before, "duplicate header line count")
assert_equal(notice, "This file already has an Epitech header", "duplicate header notice")

local guard_buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(guard_buf)
vim.api.nvim_buf_set_name(guard_buf, "/tmp/my_macro_abs.h")
vim.api.nvim_buf_set_lines(guard_buf, 0, -1, false, vim.list_extend(vim.deepcopy(expected_header), {
  "",
  "#define ABS(value) ((value) < 0) ? -(value) : (value)",
}))
epitech.insert_guard()
assert_equal(vim.api.nvim_buf_get_lines(guard_buf, 0, -1, false), vim.list_extend(vim.deepcopy(expected_header), {
  "",
  "#ifndef MY_MACRO_ABS_H_",
  "    #define MY_MACRO_ABS_H_",
  "",
  "    #define ABS(value) ((value) < 0) ? -(value) : (value)",
  "",
  "#endif",
}), "guard wraps content after Epitech header")
assert_equal(vim.api.nvim_win_get_cursor(0), { 10, 0 }, "cursor placed inside guard")
local guarded = vim.api.nvim_buf_get_lines(guard_buf, 0, -1, false)
epitech.insert_guard()
assert_equal(vim.api.nvim_buf_get_lines(guard_buf, 0, -1, false), guarded, "duplicate guard unchanged")
assert_equal(notice, "This file already has an include guard", "duplicate guard notice")

local empty_buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(empty_buf)
vim.api.nvim_buf_set_name(empty_buf, "/tmp/simple.h")
epitech.insert_guard()
assert_equal(vim.api.nvim_buf_get_lines(empty_buf, 0, -1, false), {
  "#ifndef SIMPLE_H_",
  "    #define SIMPLE_H_",
  "",
  "#endif",
}, "empty header guard")

local source_buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(source_buf)
vim.api.nvim_buf_set_name(source_buf, "/tmp/simple.c")
epitech.insert_guard()
assert_equal(vim.api.nvim_buf_get_lines(source_buf, 0, -1, false), { "" }, "non-header unchanged")
assert_equal(notice, "Name this buffer as a .h file first", "non-header notice")

local existing_buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(existing_buf)
vim.api.nvim_buf_set_name(existing_buf, "/tmp/legacy.h")
vim.api.nvim_buf_set_lines(existing_buf, 0, -1, false, {
  "#ifndef LEGACY_INCLUDE_GUARD",
  "#define LEGACY_INCLUDE_GUARD",
  "",
  "#endif",
})
local existing_lines = vim.api.nvim_buf_get_lines(existing_buf, 0, -1, false)
epitech.insert_guard()
assert_equal(vim.api.nvim_buf_get_lines(existing_buf, 0, -1, false), existing_lines, "existing custom guard unchanged")

-- #pragma once is a language extension Banana does not support: it is not a
-- guard, and :EpitechGuard replaces it with #ifndef/#define/#endif.
local pragma_buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(pragma_buf)
vim.api.nvim_buf_set_name(pragma_buf, "/tmp/pragma_guard.h")
vim.api.nvim_buf_set_lines(pragma_buf, 0, -1, false, vim.list_extend(vim.deepcopy(expected_header), {
  "",
  "#pragma once",
  "",
  "int add(int a, int b);",
}))
notice = nil
epitech.insert_guard()
assert_equal(vim.api.nvim_buf_get_lines(pragma_buf, 0, -1, false), vim.list_extend(vim.deepcopy(expected_header), {
  "",
  "#ifndef PRAGMA_GUARD_H_",
  "    #define PRAGMA_GUARD_H_",
  "",
  "int add(int a, int b);",
  "",
  "#endif",
}), "#pragma once after the header becomes an include guard")
assert_equal(notice, "Replaced #pragma once with an include guard", "pragma replacement notice")

local bare_pragma_buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(bare_pragma_buf)
vim.api.nvim_buf_set_name(bare_pragma_buf, "/tmp/bare_pragma.h")
vim.api.nvim_buf_set_lines(bare_pragma_buf, 0, -1, false, { "#pragma once", "", "int sub(int a, int b);" })
epitech.insert_guard()
assert_equal(vim.api.nvim_buf_get_lines(bare_pragma_buf, 0, -1, false), {
  "#ifndef BARE_PRAGMA_H_",
  "    #define BARE_PRAGMA_H_",
  "",
  "int sub(int a, int b);",
  "",
  "#endif",
}, "#pragma once on the first line becomes an include guard")

local both_buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(both_buf)
vim.api.nvim_buf_set_name(both_buf, "/tmp/both_guards.h")
vim.api.nvim_buf_set_lines(both_buf, 0, -1, false, {
  "#ifndef BOTH_GUARDS_H_",
  "    #define BOTH_GUARDS_H_",
  "    #pragma once",
  "",
  "int mul(int a, int b);",
  "",
  "#endif",
})
notice = nil
epitech.insert_guard()
assert_equal(vim.api.nvim_buf_get_lines(both_buf, 0, -1, false), {
  "#ifndef BOTH_GUARDS_H_",
  "    #define BOTH_GUARDS_H_",
  "",
  "int mul(int a, int b);",
  "",
  "#endif",
}, "#pragma once dropped when a guard already exists")
assert_equal(notice, "Removed #pragma once: the file already has an include guard", "pragma removal notice")

local vim_config = vim.fn.tempname()
vim.fn.writefile({
  "set tabstop=4",
  "set shiftwidth=4",
  "set expandtab",
  "set autoindent",
  "set smartindent",
  "set fileformat=unix",
}, vim_config)

-- The formatter subprocess loads format.lua with dofile() outside the plugin's
-- runtimepath, so a require there would break format-on-save.
local format_source = table.concat(vim.fn.readfile(plugin .. "/lua/epitech/format.lua"), "\n")
assert(not format_source:find("require%s*%(?%s*[\"']"), "format.lua must not require anything")

local formatter = epitech.formatter({ vim_config = vim_config })
assert(formatter.condition(), "formatter should be available")
local input = table.concat({
  "/*",
  " ** EPITECH PROJECT, 2026",
  " ** Day 08",
  " ** File description:",
  " ** Copy string in allocated memory",
  " */",
  "",
  "int main(void){",
  "return 0;",
  "}",
  "",
}, "\n")
local command = vim.list_extend({ formatter.command }, formatter.args)
local result = vim.system(command, { stdin = input, text = true }):wait()
vim.uv.fs_unlink(vim_config)
assert_equal(result.code, 0, "formatter exit code")
assert_equal(result.stderr, "", "formatter stderr")
assert_equal(result.stdout, table.concat({
  "/*",
  "** EPITECH PROJECT, 2026",
  "** Day 08",
  "** File description:",
  "** Copy string in allocated memory",
  "*/",
  "",
  "int main(void)",
  "{",
  "    return 0;",
  "}",
  "",
}, "\n"), "formatter output")

-- format_buffer() formats any buffer, not only the current one, including the
-- Treesitter passes (here the C-L6 blank line after the declarations).
local current_buf = vim.api.nvim_get_current_buf()
local current_lines = vim.api.nvim_buf_get_lines(current_buf, 0, -1, false)
local other_buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_lines(other_buf, 0, -1, false, { "int get_one(void){int one = 1;return one;}" })
epitech.format_buffer(other_buf)
assert_equal(vim.api.nvim_buf_get_lines(other_buf, 0, -1, false), {
  "int get_one(void)",
  "{",
  "    int one = 1;",
  "",
  "    return one;",
  "}",
}, "format_buffer on another buffer")
assert_equal(vim.api.nvim_get_current_buf(), current_buf, "format_buffer keeps the current buffer")
assert_equal(vim.api.nvim_buf_get_lines(current_buf, 0, -1, false), current_lines, "current buffer untouched")

vim.cmd("filetype plugin on")
vim.bo.filetype = "c"
assert_equal(vim.bo.tabstop, 4, "C tabstop")
assert_equal(vim.bo.shiftwidth, 4, "C shiftwidth")
assert_equal(vim.bo.expandtab, true, "C expandtab")
assert_equal(vim.bo.comments, "s:/*,m:**,ex:*/", "C comments")

vim.api.nvim_create_user_command("EpitechHeader", "echo 'custom'", {
  desc = "Custom header command",
  force = true,
})
vim.keymap.set("n", "<leader>cH", function() end, { desc = "Custom header mapping" })
vim.api.nvim_create_user_command("EpitechGuard", "echo 'custom guard'", {
  desc = "Custom guard command",
  force = true,
})
vim.keymap.set("n", "<leader>cG", function() end, { desc = "Custom guard mapping" })
epitech.setup()
assert_equal(
  vim.api.nvim_get_commands({ builtin = false }).EpitechHeader.definition,
  "echo 'custom'",
  "existing header command"
)
local custom_mapping = vim.fn.maparg("<leader>cH", "n", false, true)
assert_equal(custom_mapping.desc, "Custom header mapping", "existing header mapping")
assert_equal(
  vim.api.nvim_get_commands({ builtin = false }).EpitechGuard.definition,
  "echo 'custom guard'",
  "existing guard command"
)
local custom_guard_mapping = vim.fn.maparg("<leader>cG", "n", false, true)
assert_equal(custom_guard_mapping.desc, "Custom guard mapping", "existing guard mapping")

print("Epitech Neovim tests passed")
