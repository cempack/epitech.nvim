local plugin = assert(vim.env.EPITECH_NVIM_DIR, "EPITECH_NVIM_DIR is required")
vim.opt.runtimepath:prepend(plugin)
package.path = plugin .. "/lua/?.lua;" .. plugin .. "/lua/?/init.lua;" .. package.path

local epitech = require("epitech")

local function header_for(name, filetype, first_line)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_name(buf, name)
  vim.bo[buf].filetype = filetype
  if first_line then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { first_line, "echo body" })
  end
  local answers = { "Day10", "Makefile" }
  vim.ui.input = function(_, callback)
    callback(table.remove(answers, 1))
  end
  epitech.insert_header()
  return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
end

local function equal(actual, expected, label)
  assert(vim.deep_equal(actual, expected), label .. ":\nexpected " .. vim.inspect(expected) .. "\nactual " .. vim.inspect(actual))
end

local year = os.date("%Y")
equal(header_for("/tmp/Makefile", "make"), {
  "##", "## EPITECH PROJECT, " .. year, "## Day10", "## File description:", "## Makefile", "##",
  "",
}, "Makefile Epitech header")

equal(header_for("/tmp/script.sh", "sh", "#!/bin/sh"), {
  "#!/bin/sh", "##", "## EPITECH PROJECT, " .. year, "## Day10", "## File description:", "## Makefile", "##",
  "", "echo body",
}, "shell header preserves existing shebang")

equal(header_for("/tmp/example.lua", "lua"), {
  "--", "-- EPITECH PROJECT, " .. year, "-- Day10", "-- File description:", "-- Makefile", "--",
  "",
}, "Lua Epitech header")

equal(header_for("/tmp/example.html", "html"), {
  "<!--", "  -- EPITECH PROJECT, " .. year, "  -- Day10", "  -- File description:", "  -- Makefile", "-->",
  "",
}, "HTML Epitech header")

equal(header_for("/tmp/example.ts", "typescript"), {
  "//", "// EPITECH PROJECT, " .. year, "// Day10", "// File description:", "// Makefile", "//",
  "",
}, "TypeScript Epitech header")

equal(header_for("/tmp/example.py", "python"), {
  "#!/usr/bin/env python3", "##", "## EPITECH PROJECT, " .. year, "## Day10", "## File description:", "## Makefile", "##",
  "",
}, "Python Epitech header")

local replace_buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(replace_buf)
vim.api.nvim_buf_set_name(replace_buf, "/tmp/Makefile.old")
vim.bo[replace_buf].filetype = "make"
vim.api.nvim_buf_set_lines(replace_buf, 0, -1, false, {
  "/*", "** EPITECH PROJECT, 2024", "** Legacy", "** File description:", "** Build", "*/", "", "all:", "\t@true",
})
vim.ui.select = function(_, _, callback)
  callback("Replace")
end
epitech.insert_header()
equal(vim.api.nvim_buf_get_lines(replace_buf, 0, -1, false), {
  "##", "## EPITECH PROJECT, " .. year, "## Legacy", "## File description:", "## Build", "##", "", "all:", "\t@true",
}, "wrong-style header replacement preserves Makefile body")

local existing = vim.api.nvim_buf_get_lines(replace_buf, 0, -1, false)
epitech.insert_header()
equal(vim.api.nvim_buf_get_lines(replace_buf, 0, -1, false), existing, "same-style header is not duplicated")

local old_formatted_buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(old_formatted_buf)
vim.api.nvim_buf_set_name(old_formatted_buf, "/tmp/example.c")
vim.bo[old_formatted_buf].filetype = "c"
vim.api.nvim_buf_set_lines(old_formatted_buf, 0, -1, false, {
  "/*", " ** EPITECH PROJECT, 2026", " ** Day10", " ** File description:", " ** Legacy", " */", "",
})
local old_formatted = vim.api.nvim_buf_get_lines(old_formatted_buf, 0, -1, false)
epitech.insert_header()
equal(vim.api.nvim_buf_get_lines(old_formatted_buf, 0, -1, false), old_formatted,
  "previously clang-formatted C header is not duplicated")

print("Epitech filetype header tests passed")
