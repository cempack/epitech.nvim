local plugin = assert(vim.env.EPITECH_NVIM_DIR, "EPITECH_NVIM_DIR is required")
vim.opt.runtimepath:prepend(plugin)
package.path = plugin .. "/lua/?.lua;" .. plugin .. "/lua/?/init.lua;" .. package.path

local h = dofile(plugin .. "/test/helpers.lua")
local header = require("epitech.header")
local makefile = require("epitech.makefile")
local makefile_checks = require("epitech.hints.makefile")
local project = require("epitech.project")
require("epitech.config").setup()
local notices = {}
vim.notify = function(message)
  notices[#notices + 1] = message
end

local year = os.date("%Y")
local dir = vim.fn.tempname()
vim.fn.mkdir(dir, "p")
dir = vim.uv.fs_realpath(dir)
vim.fn.chdir(dir)
require("epitech").setup()
vim.cmd("EpitechNew demo")

local function read(path)
  return vim.fn.readfile(dir .. "/" .. path)
end
local c_header = function(description)
  return { "/*", "** EPITECH PROJECT, " .. year, "** demo", "** File description:", "** " .. description, "*/" }
end

h.assert_equal(read("Makefile"), {
  "##", "## EPITECH PROJECT, " .. year, "## demo", "## File description:", "## Makefile", "##", "",
  "NAME = demo", "", "SRC += src/main.c", "", "TESTS_SRC += tests/test_demo.c", "", "OBJ = $(SRC:.c=.o)", "",
  "UT_SRC = $(filter-out src/main.c, $(SRC)) $(TESTS_SRC)", "", "UT_FLAGS = --coverage -lcriterion", "",
  "CFLAGS += -Wall -Wextra -I include", "", "all: $(NAME)", "", "$(NAME): $(OBJ)", "\t$(CC) -o $(NAME) $(OBJ)", "",
  "clean:", "\t$(RM) $(OBJ) *.gcda *.gcno", "", "fclean: clean", "\t$(RM) $(NAME) unit_tests", "",
  "re: fclean all", "", "tests_run:", "\t$(CC) -o unit_tests $(UT_SRC) $(CFLAGS) $(UT_FLAGS)", "\t./unit_tests", "",
  ".PHONY: all clean fclean re tests_run",
}, "Makefile")
h.assert_equal(read("include/demo.h"), vim.list_extend(c_header("Declarations for demo"), {
  "", "#ifndef DEMO_H_", "    #define DEMO_H_", "", "/* epitech.nvim: prototypes (:EpitechSyncHeader) */",
  "/* epitech.nvim: end of prototypes */", "", "#endif",
}), "project header")
h.assert_equal(read("src/main.c"), vim.list_extend(c_header("Entry point"), {
  "", '#include "demo.h"', "", "int main(int ac, char **av)", "{", "    return 0;", "}",
}), "main.c")
h.assert_equal(read("tests/test_demo.c"), vim.list_extend(c_header("Unit tests"), {
  "", "#include <criterion/criterion.h>", '#include "demo.h"', "", "Test(demo, placeholder)", "{",
  "    cr_assert_eq(1, 1);", "}",
}), "Criterion skeleton")
h.assert_equal(read(".gitignore"), { "*.o", "*.a", "*.so", "*.gcda", "*.gcno", "vgcore.*", "*~", "\\#*#", "demo",
  "unit_tests" }, ".gitignore")

-- The Makefile passes the Makefile checks; every C file has its header and
-- comes out of the formatter unchanged.
h.assert_equal(makefile_checks.run(table.concat(read("Makefile"), "\n") .. "\n", "Makefile", {}), {},
  "Makefile passes §9.10")
for _, path in ipairs({ "include/demo.h", "src/main.c", "tests/test_demo.c" }) do
  local lines = read(path)
  assert(header.existing_header(lines) == 1, path .. " header")
  local buf = h.buffer(dir .. "/" .. path, lines)
  require("epitech").format_buffer(buf)
  h.assert_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), lines, path .. " formatter keeps it")
end
h.assert_equal(project.state(dir).header, "include/demo.h", "project header remembered")

-- A second :EpitechNew refuses; :EpitechNew! overwrites.
vim.fn.writefile({ "NAME = changed" }, dir .. "/Makefile")
vim.cmd("EpitechNew demo")
h.assert_equal(read("Makefile"), { "NAME = changed" }, "refused when a Makefile exists")
vim.cmd("EpitechNew! demo")
h.assert_equal(read("Makefile")[8], "NAME = demo", ":EpitechNew! overwrites")

-- :EpitechNewFile: header, SRC line, opened. A header gets a guard.
vim.system({ "git", "init", "-q" }, { cwd = dir }):wait()
vim.ui.input = function(_, on_confirm)
  on_confirm("Argument parsing")
end
vim.cmd("EpitechNewFile src/parse_args.c")
h.assert_equal(vim.api.nvim_buf_get_name(0), dir .. "/src/parse_args.c", "new file opened")
h.assert_equal(read("src/parse_args.c"), c_header("Argument parsing"), "new file header")
h.assert_equal(vim.list_slice(read("Makefile"), 10, 11), { "SRC += src/main.c", "SRC += src/parse_args.c" },
  "added to SRC")
vim.cmd("EpitechNewFile include/parse_args.h")
h.assert_equal(read("include/parse_args.h"), vim.list_extend(c_header("Argument parsing"), {
  "", "#ifndef PARSE_ARGS_H_", "    #define PARSE_ARGS_H_", "", "#endif",
}), "new header with a guard")
vim.cmd("EpitechNewFile tests/test_parse_args.c")
h.assert_equal(vim.list_slice(read("Makefile"), 13, 14), { "TESTS_SRC += tests/test_demo.c",
  "TESTS_SRC += tests/test_parse_args.c" }, "tests go to TESTS_SRC")
h.assert_equal(#vim.tbl_filter(function(line)
  return line:find("parse_args.h", 1, true) ~= nil
end, read("Makefile")), 0, "a header isn't added to the Makefile")
vim.fn.chdir("/")
vim.fn.delete(dir, "rf")

-- add_source and remove_source on several Makefile layouts.
local function layout(lines)
  local root, cleanup = h.temp_project({ ["Makefile"] = lines })
  return root, cleanup
end
local root, cleanup = layout({ "SRC = src/a.c \\", "\tsrc/b.c \\", "\tsrc/c.c", "", "OBJ = $(SRC:.c=.o)" })
h.assert_equal(makefile.add_source(root, "src/d.c"), true, "add after a continued list")
h.assert_equal(vim.fn.readfile(root .. "/Makefile"), { "SRC = src/a.c \\", "\tsrc/b.c \\", "\tsrc/c.c",
  "SRC += src/d.c", "", "OBJ = $(SRC:.c=.o)" }, "added after the last continuation line")
h.assert_equal(makefile.add_source(root, "src/b.c"), true, "already listed")
h.assert_equal(#vim.fn.readfile(root .. "/Makefile"), 6, "not added twice")
h.assert_equal(makefile.remove_source(root, "src/b.c"), true, "remove from a continued list")
h.assert_equal(vim.fn.readfile(root .. "/Makefile"), { "SRC = src/a.c \\", "\tsrc/c.c", "SRC += src/d.c", "",
  "OBJ = $(SRC:.c=.o)" }, "word removed")
makefile.remove_source(root, "src/c.c")
h.assert_equal(vim.fn.readfile(root .. "/Makefile"), { "SRC = src/a.c", "SRC += src/d.c", "", "OBJ = $(SRC:.c=.o)" },
  "last continuation line removed")
makefile.remove_source(root, "src/d.c")
h.assert_equal(vim.fn.readfile(root .. "/Makefile"), { "SRC = src/a.c", "", "OBJ = $(SRC:.c=.o)" },
  "SRC += line removed")
h.assert_equal(makefile.remove_source(root, "src/zz.c"), false, "nothing to remove")
cleanup()

root, cleanup = layout({ "SRC := src/a.c src/b.c", "NAME = x" })
makefile.add_source(root, "src/c.c")
makefile.remove_source(root, "src/a.c")
h.assert_equal(vim.fn.readfile(root .. "/Makefile"), { "SRC := src/b.c", "SRC += src/c.c", "NAME = x" },
  ":= list on one line")
cleanup()

root, cleanup = layout({ "SRC = $(wildcard src/*.c)" })
notices = {}
h.assert_equal(makefile.add_source(root, "src/c.c"), false, "wildcard")
h.assert_equal(notices, { "SRC uses $(wildcard …) in the Makefile: add `SRC += src/c.c` yourself if it doesn't pick"
  .. " the file up" }, "the user is told")
h.assert_equal(vim.fn.readfile(root .. "/Makefile"), { "SRC = $(wildcard src/*.c)" }, "wildcard Makefile unchanged")
cleanup()

root, cleanup = layout({ "NAME = x" })
notices = {}
h.assert_equal(makefile.add_source(root, "src/c.c"), false, "no SRC")
h.assert_equal(notices, { "No SRC in the Makefile: add `SRC += src/c.c` yourself" }, "the user is told what to add")
cleanup()

print("Epitech scaffolding tests passed")
