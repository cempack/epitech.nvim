local plugin = assert(vim.env.EPITECH_NVIM_DIR, "EPITECH_NVIM_DIR is required")
vim.opt.runtimepath:prepend(plugin)
package.path = plugin .. "/lua/?.lua;" .. plugin .. "/lua/?/init.lua;" .. package.path

local h = dofile(plugin .. "/test/helpers.lua")
local project = require("epitech.project")
require("epitech.config").setup()
vim.notify = function() end

local HEADER = { "/*", "** EPITECH PROJECT, 2026", "** my_ls", "** File description:", "** Listing", "*/", "" }
local ls_c = vim.list_extend(vim.deepcopy(HEADER), {
  "#include <stdio.h>", '#include "ls.h"', "",
  "static int is_hidden(char const *name)", "{", "    return name[0] == '.';", "}", "",
  "/*", "** Pads a column", "*/", "static int pad(int width)", "{", "    return width + 1;", "}", "",
  "int print_long(char const *name)", "{", "    return is_hidden(name) + pad(2);", "}", "",
  "int print_short(char const *name)", "{", "    return is_hidden(name);", "}", "",
  "int main(void)", "{", "    return print_long(\"a\") + print_short(\"b\");", "}",
})
local function project_files()
  return {
    ["Makefile"] = { "NAME = my_ls", "", "SRC += src/ls.c", "", "OBJ = $(SRC:.c=.o)" },
    ["include/ls.h"] = { "#ifndef LS_H_", "    #define LS_H_", "", "#endif" },
    ["src/ls.c"] = ls_c,
  }
end

local function row_of(buf, text)
  for i, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    if line == text then
      return i - 1
    end
  end
end

-- The shared helper case asks first; cancelling changes nothing.
local root, cleanup = h.temp_project(project_files())
project.save_state(root, { header = "include/ls.h", header_dirs = { "src" } })
local buf = h.buffer(root .. "/src/ls.c", ls_c)
local asked
vim.ui.select = function(items, opts, on_choice)
  asked = { items = items, prompt = opts.prompt }
  on_choice("Cancel")
end
local row = row_of(buf, "int print_long(char const *name)")
require("epitech.split").move_to("src/print_long.c", row, row + 3, buf)
h.assert_equal(asked, {
  items = { "Make is_hidden non-static", "Cancel" },
  prompt = "is_hidden would be used by both files, so it can't stay static (C-O3 allows 5 non-static functions per"
    .. " file)",
}, "asked about the shared helper")
h.assert_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), ls_c, "cancel changes nothing")
h.assert_equal(vim.fn.filereadable(root .. "/src/print_long.c"), 0, "no file created")

-- Accepting: print_long moves with pad (only it uses pad); is_hidden stays
-- and loses static.
vim.ui.select = function(items, _, on_choice)
  on_choice(items[1])
end
vim.ui.input = function(_, on_confirm)
  on_confirm("Long listing")
end
local done
require("epitech.split").move_to("src/print_long.c", row, row + 3, buf, function(target)
  done = target
end)
h.assert_equal(done, root .. "/src/print_long.c", "finished")
h.assert_equal(vim.fn.readfile(root .. "/src/print_long.c"), {
  "/*", "** EPITECH PROJECT, " .. os.date("%Y"), "** my_ls", "** File description:", "** Long listing", "*/", "",
  "#include <stdio.h>", '#include "ls.h"', "",
  "/*", "** Pads a column", "*/", "static int pad(int width)", "{", "    return width + 1;", "}", "",
  "int print_long(char const *name)", "{", "    return is_hidden(name) + pad(2);", "}",
}, "new file: header, includes, the functions one blank line apart")
h.assert_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), vim.list_extend(vim.deepcopy(HEADER), {
  "#include <stdio.h>", '#include "ls.h"', "",
  "int is_hidden(char const *name)", "{", "    return name[0] == '.';", "}", "",
  "int print_short(char const *name)", "{", "    return is_hidden(name);", "}", "",
  "int main(void)", "{", "    return print_long(\"a\") + print_short(\"b\");", "}",
}), "source: moved functions gone, the shared helper non-static")
h.assert_equal(vim.fn.readfile(root .. "/Makefile")[4], "SRC += src/print_long.c", "Makefile updated")
local header_lines = vim.fn.readfile(root .. "/include/ls.h")
for _, prototype in ipairs({ "int is_hidden(char const *name);", "int print_long(char const *name);",
  "int print_short(char const *name);" }) do
  assert(vim.list_contains(header_lines, prototype), "header has " .. prototype)
end
local result = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
require("epitech").format_buffer(buf)
h.assert_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), result, "the formatter keeps the source")
cleanup()

-- Moving into an existing file appends; a function with no shared helper
-- doesn't ask.
root, cleanup = h.temp_project(project_files())
project.save_state(root, { header = "include/ls.h", header_dirs = { "src" } })
vim.fn.writefile(vim.list_extend(vim.deepcopy(HEADER), { '#include "ls.h"', "", "int other(void)", "{",
  "    return 0;", "}" }), root .. "/src/other.c")
buf = h.buffer(root .. "/src/ls.c", ls_c)
asked = nil
vim.ui.select = function(_, _, on_choice)
  asked = true
  on_choice(nil)
end
row = row_of(buf, "int main(void)")
require("epitech.split").move_to("src/other.c", row, row, buf)
h.assert_equal(asked, nil, "no question")
h.assert_equal(vim.list_slice(vim.fn.readfile(root .. "/src/other.c"), 8), { '#include "ls.h"', "#include <stdio.h>",
  "", "int other(void)", "{", "    return 0;", "}", "", "int main(void)", "{",
  "    return print_long(\"a\") + print_short(\"b\");", "}" }, "appended, with the missing include")
cleanup()

print("Epitech split tests passed")
