local plugin = assert(vim.env.EPITECH_NVIM_DIR, "EPITECH_NVIM_DIR is required")
vim.opt.runtimepath:prepend(plugin)
package.path = plugin .. "/lua/?.lua;" .. plugin .. "/lua/?/init.lua;" .. package.path

local h = dofile(plugin .. "/test/helpers.lua")
local lib = require("epitech.lib")
local hints = require("epitech.hints")
require("epitech").setup({ scaffold = { cc = "gcc" } })
local notices = {}
vim.notify = function(message)
  notices[#notices + 1] = message
end
local year = os.date("%Y")

-- The catalog: the Pool's libmy, with its prototypes and what each calls.
h.assert_equal(#lib.names(), 35, "35 functions")
h.assert_equal(lib.catalog().my_strdup.prototype, "char *my_strdup(char const *src);", "prototype")
h.assert_equal(lib.catalog().my_strdup.deps, { "my_strcpy", "my_strlen" }, "dependencies")
h.assert_equal(lib.catalog().my_strlen.deps, {}, "no dependencies")
h.assert_equal(lib.resolve({ "my_strstr", "nope" }), { "my_strncmp", "my_strstr" }, "resolve")
h.assert_equal(lib.resolve({ "concat_params" }), { "concat_params", "my_strcat", "my_strlen" }, "resolve deeper")

-- Every file comes out of the formatter unchanged, with no hint, and the
-- Makefile passes the Makefile checks.
local all = lib.templates("demo", lib.names())
for path, lines in pairs(all) do
  if path:match("%.[ch]$") then
    local buf = h.buffer("/tmp/epitech_lib/" .. path, lines)
    require("epitech").format_buffer(buf)
    h.assert_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), lines, path .. ": formatter leaves it unchanged")
    h.assert_equal(hints.collect(table.concat(lines, "\n") .. "\n", "/tmp/epitech_lib/" .. path, { root = "/tmp" }),
      {}, path .. ": no hints")
  end
end
h.assert_equal(require("epitech.hints.makefile").run(table.concat(all["lib/my/Makefile"], "\n") .. "\n", "Makefile",
  {}), {}, "lib Makefile checks")
h.assert_equal(vim.list_slice(all["lib/my/my_strlen.c"], 1, 8), {
  "/*", "** EPITECH PROJECT, " .. year, "** demo", "** File description:", "** my_strlen", "*/", "",
  '#include "../../include/my.h"',
}, "an Epitech header on each file")
h.assert_equal(vim.list_slice(all["include/my.h"], 5, 13), {
  "** Prototypes of libmy", "*/", "", "#ifndef MY_H_", "    #define MY_H_", "",
  "char *concat_params(int argc, char **argv);", "int my_advanced_sort_word_array(char **tab,",
  "    int (*cmp)(char const *, char const *));",
}, "my.h, long prototypes wrapped")
h.assert_equal(vim.list_slice(lib.makefile("demo", { "my_putstr", "my_strlen" }), 5, 14), {
  "## Makefile of libmy", "##", "", "CC = gcc", "", "NAME = libmy.a", "", "SRC = my_putstr.c \\",
  "\t\tmy_strlen.c", "",
}, "lib Makefile")

-- With a C compiler: everything compiles with warnings as errors, and
-- behaves (test/fixtures/lib/check.c).
local cc = vim.fn.executable("cc") == 1 and "cc" or vim.fn.executable("gcc") == 1 and "gcc" or nil
if cc then
  local dir = vim.fn.tempname()
  for path, lines in pairs(all) do
    vim.fn.mkdir(vim.fs.dirname(dir .. "/" .. path), "p")
    vim.fn.writefile(lines, dir .. "/" .. path)
  end
  local built = vim.system({ "make", "-C", dir .. "/lib/my", "CC=" .. cc, "CFLAGS=-Wall -Wextra -Werror" },
    { text = true }):wait()
  assert(built.code == 0, built.stderr)
  local linked = vim.system({ cc, "-o", dir .. "/check", plugin .. "/test/fixtures/lib/check.c", "-I" .. dir
    .. "/include", "-L" .. dir .. "/lib/my", "-lmy" }, { text = true }):wait()
  assert(linked.code == 0, linked.stderr)
  local ran = vim.system({ dir .. "/check" }, { text = true }):wait()
  assert(ran.code == 0, ran.stdout)
  h.assert_equal(ran.stdout, "-2147483648 0 xN\na\\09b\\0a\na\nb\n", "printed output")
  vim.fn.delete(dir, "rf")
else
  print("Skipping the libmy compile test: no C compiler")
end

-- :EpitechLib in a project with its own lib/my (my.h in lib/my).
local root, cleanup = h.temp_project({
  ["Makefile"] = { "NAME = demo", "", "SRC = src/main.c", "", "all:", "\t$(MAKE) -C lib/my" },
  ["lib/my/Makefile"] = { "NAME = libmy.a", "", "SRC = my_strlen.c" },
  ["lib/my/my_strlen.c"] = { "int my_strlen(char const *str)", "{", "    return 0;", "}" },
  ["lib/my/my.h"] = { "#ifndef MY_H_", "    #define MY_H_", "", "int my_strlen(char const *str);", "", "#endif" },
  ["src/main.c"] = { "int main(void)", "{", "    return 0;", "}" },
})
h.assert_equal(lib.header_path(root), "lib/my/my.h", "my.h found in lib/my")
h.assert_equal(lib.missing(root, { "my_strdup" }), { "my_strcpy", "my_strdup" }, "my_strlen is already there")
vim.cmd.edit(root .. "/src/main.c")
vim.cmd("EpitechLib my_strdup")
h.assert_equal(notices[#notices], "Added to lib/my: my_strcpy, my_strdup", "added with its dependency")
h.assert_equal(vim.fn.readfile(root .. "/lib/my/Makefile"), {
  "NAME = libmy.a", "", "SRC = my_strlen.c \\", "\t\tmy_strcpy.c \\", "\t\tmy_strdup.c",
}, "lib Makefile updated")
h.assert_equal(vim.fn.readfile(root .. "/lib/my/my.h"), {
  "#ifndef MY_H_", "    #define MY_H_", "", "int my_strlen(char const *str);", "char *my_strcpy(char *dest, char const *src);",
  "char *my_strdup(char const *src);", "", "#endif",
}, "prototypes after the others")
h.assert_equal(vim.fn.readfile(root .. "/lib/my/my_strdup.c")[9], '#include "my.h"', "include from lib/my")
vim.cmd("EpitechLib my_strdup")
h.assert_equal(notices[#notices], "libmy already has my_strdup", "nothing twice")
vim.cmd("EpitechLib my_printf")
h.assert_equal(notices[#notices], "Not in libmy: my_printf (:EpitechLib <Tab> lists them)", "unknown")
h.assert_equal(vim.fn.getcompletion("EpitechLib my_str_is", "cmdline"), { "my_str_isalpha", "my_str_islower",
  "my_str_isnum", "my_str_isprintable", "my_str_isupper" }, "completion")
-- Without a name: a picker of what's missing.
vim.ui.select = function(items, _, on_choice)
  h.assert_equal(#items, 35 - 3, "only missing functions offered")
  h.assert_equal(items[1], "char *concat_params(int argc, char **argv);", "items are prototypes")
  on_choice(items[1])
end
vim.cmd("EpitechLib")
h.assert_equal(notices[#notices], "Added to lib/my: concat_params, my_strcat", "picked")
cleanup()

-- The code action on a call, in a project without lib/my: lib/my and
-- include/my.h are created, main.c includes my.h, and the user is told how
-- to link it.
root, cleanup = h.temp_project({
  ["Makefile"] = { "NAME = demo", "", "SRC = src/main.c" },
  ["src/main.c"] = { "int main(void)", "{", '    my_putstr("hi");', "    return 0;", "}" },
})
vim.cmd.edit(root .. "/src/main.c")
local buf = vim.api.nvim_get_current_buf()
local actions, client = h.code_actions(buf, h.rows(2))
local titles = vim.tbl_map(function(action)
  return action.title
end, actions)
h.assert_equal(titles, { "Add my_putstr to lib/my" }, "action on the call")
h.assert_equal(#h.code_actions(buf, h.rows(3)), 0, "nothing elsewhere")
client:exec_cmd(actions[1].command, { bufnr = buf })
h.assert_equal(vim.fn.readdir(root .. "/lib/my"), { "Makefile", "my_putstr.c", "my_strlen.c" }, "lib/my created")
h.assert_equal(vim.api.nvim_buf_get_lines(buf, 0, 2, false), { '#include "../include/my.h"', "" }, "my.h included")
h.assert_equal(notices[#notices], "Added to lib/my: my_putstr, my_strlen. Build and link it from the Makefile:"
  .. " `$(MAKE) -C lib/my` before linking, then -L./lib/my -lmy", "linking explained")
h.assert_equal(vim.fn.filereadable(root .. "/include/my.h"), 1, "include/my.h created")
h.assert_equal(#h.code_actions(buf, h.rows(4)), 0, "no action once it's there")
-- A function the file defines itself isn't offered.
local own = h.buffer(root .. "/src/own.c", { "int my_strcmp(char const *a, char const *b)", "{", "    return 0;", "}",
  "", "int f(void)", "{", '    return my_strcmp("a", "b");', "}" })
h.assert_equal(#h.code_actions(own, h.rows(7)), 0, "defined in the file")
cleanup()

print("Epitech libmy tests passed")
