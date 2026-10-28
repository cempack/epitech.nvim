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
-- The library picker: CSFML graphics, then math, then Done.
local picks = { 2, 6, 1 }
local shown = {}
vim.ui.select = function(items, _, on_choice)
  shown[#shown + 1] = items
  local index = table.remove(picks, 1) or 1
  on_choice(items[index], index)
end
vim.cmd("EpitechNew demo")
h.assert_equal(shown[3], { "Done", "[x] CSFML graphics (graphics, window, system)", "[ ] CSFML audio",
  "[ ] CSFML network", "[ ] ncurses", "[x] math (-lm)" }, "picked libraries are checked")

local function read(path)
  return vim.fn.readfile(dir .. "/" .. path)
end
local c_header = function(description)
  return { "/*", "** EPITECH PROJECT, " .. year, "** demo", "** File description:", "** " .. description, "*/" }
end

local function makefile_tail(unit_tests)
  return vim.list_extend(vim.deepcopy(unit_tests), {
    "", "tests_run: unit_tests", "\t./unit_tests; status=$$?; \\", "\t$(MAKE) --no-print-directory fclean; \\",
    "\texit $$status", "", "clean:", "\trm -f $(OBJ)", "\trm -f $(OBJ:.o=.gcno) $(OBJ:.o=.gcda)",
    "\trm -f *.gcno *.gcda", "", "fclean: clean", "\trm -f $(NAME)", "\trm -f unit_tests", "",
    "re: fclean $(NAME)", "", ".PHONY: all clean fclean re unit_tests tests_run",
  })
end
h.assert_equal(read("Makefile"), vim.list_extend({
  "##", "## EPITECH PROJECT, " .. year, "## demo", "## File description:", "## Makefile", "##", "",
  "CC = epiclang", "", "CPPFLAGS = -I./include", "",
  "LDLIBS = -lcsfml-graphics -lcsfml-window -lcsfml-system -lm", "", "NAME = demo", "", "SRC = src/main.c", "",
  "OBJ = $(SRC:.c=.o)", "", "TEST_SRC = tests/test_demo.c", "", "all: $(NAME)", "", "$(NAME): $(OBJ)",
  "\t$(CC) -o $(NAME) $(OBJ) $(LDLIBS)", "",
}, makefile_tail({
  "unit_tests: fclean", "\t$(CC) -o unit_tests $(filter-out src/main.c, $(SRC)) $(TEST_SRC) \\",
  "\t$(CPPFLAGS) $(CFLAGS) $(LDLIBS) -lcriterion --coverage",
})), "Makefile with the picked libraries")
h.assert_equal(require("epitech.scaffold").library_flags({ [2] = true, [3] = true }),
  { "-lcsfml-audio", "-lcsfml-system", "-lcsfml-network" }, "csfml-system once")
local every = require("epitech.scaffold").makefile("demo", { "src/main.c" }, { "tests/test_demo.c" },
  require("epitech.scaffold").library_flags({ true, true, true, true, true }))
h.assert_equal(vim.list_slice(every, 12, 19), { "LDLIBS = -lcsfml-graphics \\", "\t\t-lcsfml-window \\",
  "\t\t-lcsfml-system \\", "\t\t-lcsfml-audio \\", "\t\t-lcsfml-network \\", "\t\t-lncurses \\", "\t\t-lm", "" },
  "every library: one per line")
h.assert_equal(makefile_checks.run(table.concat(every, "\n") .. "\n", "Makefile", {}), {}, "still under 80 columns")
-- A library (libmy.a) is built with ar and its tests link against it; cc
-- and cflags come from the options.
require("epitech.config").setup({ scaffold = { cc = "gcc", cflags = "-Wall -Wextra" } })
local library = require("epitech.scaffold").makefile("libmy.a", { "src/my.c", "src/my_putstr.c" }, { "tests/test_my.c" })
h.assert_equal(vim.list_slice(library, 8, #library), vim.list_extend({
  "CC = gcc", "", "CPPFLAGS = -I./include", "", "CFLAGS = -Wall -Wextra", "", "NAME = libmy.a", "",
  "SRC = src/my.c \\", "\t\tsrc/my_putstr.c", "", "OBJ = $(SRC:.c=.o)", "", "TEST_SRC = tests/test_my.c", "",
  "all: $(NAME)", "", "$(NAME): $(OBJ)", "\tar rc $(NAME) $(OBJ)", "",
}, makefile_tail({
  "unit_tests: CFLAGS += --coverage", "unit_tests: fclean $(NAME)",
  "\t$(CC) -o unit_tests $(TEST_SRC) $(CPPFLAGS) -L. -lmy -lcriterion \\", "\t$(LDLIBS) --coverage",
})), "library Makefile")
h.assert_equal(vim.tbl_keys(require("epitech.scaffold").templates("libmy.a")), vim.tbl_keys({
  Makefile = 1, ["include/my.h"] = 1, ["src/my.c"] = 1, ["tests/test_my.c"] = 1, [".gitignore"] = 1,
}), "library files")
require("epitech.config").setup()
h.assert_equal(read("include/demo.h"), vim.list_extend(c_header("Declarations for demo"), {
  "", "#ifndef DEMO_H_", "    #define DEMO_H_", "", "#endif",
}), "project header")
h.assert_equal(read("src/main.c"), vim.list_extend(c_header("Entry point"), {
  "", '#include "../include/demo.h"', "", "int main(void)", "{", "    return 0;", "}",
}), "main.c")
h.assert_equal(read("tests/test_demo.c"), vim.list_extend(c_header("Unit tests"), {
  "", "#include <criterion/criterion.h>", '#include "../include/demo.h"', "", "Test(demo, placeholder)", "{",
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
h.assert_equal(read("Makefile")[12], "NAME = demo", ":EpitechNew! overwrites")

-- :EpitechNewFile: header, SRC line, opened. A header gets a guard.
vim.system({ "git", "init", "-q" }, { cwd = dir }):wait()
vim.ui.input = function(_, on_confirm)
  on_confirm("Argument parsing")
end
vim.cmd("EpitechNewFile src/parse_args.c")
h.assert_equal(vim.api.nvim_buf_get_name(0), dir .. "/src/parse_args.c", "new file opened")
h.assert_equal(read("src/parse_args.c"), c_header("Argument parsing"), "new file header")
h.assert_equal(vim.list_slice(read("Makefile"), 14, 15), { "SRC = src/main.c \\", "\t\tsrc/parse_args.c" },
  "added to the SRC list")
vim.cmd("EpitechNewFile include/parse_args.h")
h.assert_equal(read("include/parse_args.h"), vim.list_extend(c_header("Argument parsing"), {
  "", "#ifndef PARSE_ARGS_H_", "    #define PARSE_ARGS_H_", "", "#endif",
}), "new header with a guard")
vim.cmd("EpitechNewFile tests/test_parse_args.c")
h.assert_equal(vim.list_slice(read("Makefile"), 19, 20), { "TEST_SRC = tests/test_demo.c \\",
  "\t\ttests/test_parse_args.c" }, "tests go to TEST_SRC")
h.assert_equal(#vim.tbl_filter(function(line)
  return line:find("parse_args.h", 1, true) ~= nil
end, read("Makefile")), 0, "a header isn't added to the Makefile")

-- <leader>cN asks for the path in a small window.
h.assert_equal(vim.fn.maparg("<leader>cN", "n", false, true).desc, "Epitech New File", "<leader>cN")
local prompts = {}
vim.ui.input = function(opts, on_confirm)
  prompts[#prompts + 1] = { opts.prompt, opts.default }
  on_confirm(opts.prompt == "New file: " and "src/display.c" or "Display")
end
vim.fn.maparg("<leader>cN", "n", false, true).callback()
h.assert_equal(prompts, { { "New file: " }, { "File description: " } }, "asks for the path, then the description")
h.assert_equal(read("src/display.c"), c_header("Display"), "file created from the typed path")
vim.ui.input = function(_, on_confirm)
  on_confirm("")
end
local before = vim.fn.readfile(dir .. "/Makefile")
vim.cmd("EpitechNewFile")
h.assert_equal(vim.fn.readfile(dir .. "/Makefile"), before, "an empty answer creates nothing")
vim.fn.chdir("/")
vim.fn.delete(dir, "rf")

-- add_source and remove_source on several Makefile layouts.
local function layout(lines)
  local root, cleanup = h.temp_project({ ["Makefile"] = lines })
  return root, cleanup
end
local root, cleanup = layout({ "SRC = src/a.c \\", "\tsrc/b.c \\", "\tsrc/c.c", "", "OBJ = $(SRC:.c=.o)" })
h.assert_equal(makefile.add_source(root, "src/d.c"), true, "add to a continued list")
h.assert_equal(vim.fn.readfile(root .. "/Makefile"), { "SRC = src/a.c \\", "\tsrc/b.c \\", "\tsrc/c.c \\",
  "\tsrc/d.c", "", "OBJ = $(SRC:.c=.o)" }, "one more line of the list, same indentation")
h.assert_equal(makefile.add_source(root, "src/b.c"), true, "already listed")
h.assert_equal(#vim.fn.readfile(root .. "/Makefile"), 6, "not added twice")
h.assert_equal(makefile.remove_source(root, "src/b.c"), true, "remove from a continued list")
h.assert_equal(vim.fn.readfile(root .. "/Makefile"), { "SRC = src/a.c \\", "\tsrc/c.c \\", "\tsrc/d.c", "",
  "OBJ = $(SRC:.c=.o)" }, "word removed")
makefile.remove_source(root, "src/d.c")
makefile.remove_source(root, "src/c.c")
h.assert_equal(vim.fn.readfile(root .. "/Makefile"), { "SRC = src/a.c", "", "OBJ = $(SRC:.c=.o)" },
  "last continuation lines removed")
makefile.add_source(root, "src/e.c")
h.assert_equal(vim.fn.readfile(root .. "/Makefile"), { "SRC = src/a.c \\", "\t\tsrc/e.c", "",
  "OBJ = $(SRC:.c=.o)" }, "a one-file list grows into a continued one")
cleanup()

root, cleanup = layout({ "SRC += src/a.c", "NAME = x" })
makefile.add_source(root, "src/b.c")
h.assert_equal(vim.fn.readfile(root .. "/Makefile"), { "SRC += src/a.c", "SRC += src/b.c", "NAME = x" },
  "SRC += lines get one more")
makefile.remove_source(root, "src/b.c")
h.assert_equal(vim.fn.readfile(root .. "/Makefile"), { "SRC += src/a.c", "NAME = x" }, "SRC += line removed")
h.assert_equal(makefile.remove_source(root, "src/zz.c"), false, "nothing to remove")
cleanup()

root, cleanup = layout({ "SRC := src/a.c src/b.c", "NAME = x" })
makefile.add_source(root, "src/c.c")
makefile.remove_source(root, "src/a.c")
h.assert_equal(vim.fn.readfile(root .. "/Makefile"), { "SRC := src/b.c \\", "\t\tsrc/c.c", "NAME = x" },
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
