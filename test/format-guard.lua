local plugin = assert(vim.env.EPITECH_NVIM_DIR, "EPITECH_NVIM_DIR is required")
vim.opt.runtimepath:prepend(plugin)
package.path = plugin .. "/lua/?.lua;" .. plugin .. "/lua/?/init.lua;" .. package.path

local epitech = require("epitech")
local tempdir = vim.fn.tempname()
vim.fn.mkdir(tempdir, "p")

local ok, err = pcall(function()
  local filename = tempdir .. "/my_macro_abs.h"
  vim.api.nvim_buf_set_name(0, filename)
  local formatter = epitech.formatter()
  assert(formatter.condition(), "installed Epitech Vim config is required")
  local command = vim.list_extend({ formatter.command }, formatter.args)
  local cases = {
    { name = "empty", lines = { "" } },
    {
      name = "macro and nested conditionals",
      lines = {
        "/*",
        "** EPITECH PROJECT, " .. os.date("%Y"),
        "** Day 08",
        "** File description:",
        "** Absolute-value macro",
        "*/",
        "",
        "#define ABS(value) (((value) < 0) ? -(value) : (value))",
        "#if defined(__x86_64__)",
        "#define ARCH_BITS 64",
        "#else",
        "#define ARCH_BITS 32",
        "#endif",
      },
    },
  }

  for _, case in ipairs(cases) do
    vim.api.nvim_buf_set_lines(0, 0, -1, false, case.lines)
    epitech.insert_guard()
    local input = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n") .. "\n"
    local formatted = vim.system(command, { stdin = input, text = true }):wait()
    assert(formatted.code == 0, case.name .. ": " .. formatted.stderr)
    local twice = vim.system(command, { stdin = formatted.stdout, text = true }):wait()
    assert(twice.stdout == formatted.stdout, case.name .. ": formatter is not idempotent")
    vim.fn.writefile(vim.split(formatted.stdout:gsub("\n$", ""), "\n", { plain = true }), filename)

    local checked = vim.system({ "epiclang", "-x", "c", "-fsyntax-only", filename }, { text = true }):wait()
    assert(checked.code == 0, case.name .. ": " .. checked.stderr)
    assert(not checked.stderr:find("C%-G3"), case.name .. ": " .. checked.stderr)
    if case.name ~= "empty" then
      assert(checked.stderr == "", case.name .. ": " .. checked.stderr)
    end
  end
end)

vim.fn.delete(tempdir, "rf")
assert(ok, err)
print("Epitech guard formatting passes Banana C-G3")
