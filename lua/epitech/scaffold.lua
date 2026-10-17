-- :EpitechNew creates a project skeleton that follows the coding style, and
-- :EpitechNewFile adds a source file with its header (and its SRC line).
-- These are the only times the plugin creates files in a project, because
-- the user asked (C-O1).
local config = require("epitech.config")
local header = require("epitech.header")
local makefile = require("epitech.makefile")
local project = require("epitech.project")
local util = require("epitech.util")

local M = {}

local function c_header(name, description)
  return header.header_lines(header.comment_styles.c, name, description, os.date("%Y"))
end

-- The files of a new project: { [relative path] = lines }.
function M.templates(name)
  local year = os.date("%Y")
  local guard = header.guard_name(name .. ".h")
  local sync = require("epitech.header_sync")
  local files = {}

  files["Makefile"] = {
    "##",
    "## EPITECH PROJECT, " .. year,
    "## " .. name,
    "## File description:",
    "## Makefile",
    "##",
    "",
    "NAME = " .. name,
    "",
    "SRC += src/main.c",
    "",
    "TESTS_SRC += tests/test_" .. name .. ".c",
    "",
    "OBJ = $(SRC:.c=.o)",
    "",
    "UT_SRC = $(filter-out src/main.c, $(SRC)) $(TESTS_SRC)",
    "",
    "UT_FLAGS = --coverage -lcriterion",
    "",
    "CFLAGS += " .. config.options.scaffold.cflags .. " -I include",
    "",
    "all: $(NAME)",
    "",
    "$(NAME): $(OBJ)",
    "\t$(CC) -o $(NAME) $(OBJ)",
    "",
    "clean:",
    "\t$(RM) $(OBJ) *.gcda *.gcno",
    "",
    "fclean: clean",
    "\t$(RM) $(NAME) unit_tests",
    "",
    "re: fclean all",
    "",
    "tests_run:",
    "\t$(CC) -o unit_tests $(UT_SRC) $(CFLAGS) $(UT_FLAGS)",
    "\t./unit_tests",
    "",
    ".PHONY: all clean fclean re tests_run",
  }

  files["include/" .. name .. ".h"] = vim.list_extend(c_header(name, "Declarations for " .. name), {
    "",
    "#ifndef " .. guard,
    "    #define " .. guard,
    "",
    sync.BEGIN,
    sync.END,
    "",
    "#endif",
  })

  files["src/main.c"] = vim.list_extend(c_header(name, "Entry point"), {
    "",
    '#include "' .. name .. '.h"',
    "",
    "int main(int ac, char **av)",
    "{",
    "    return 0;",
    "}",
  })

  files["tests/test_" .. name .. ".c"] = vim.list_extend(c_header(name, "Unit tests"), {
    "",
    "#include <criterion/criterion.h>",
    '#include "' .. name .. '.h"',
    "",
    "Test(" .. name:gsub("[^%w_]", "_") .. ", placeholder)",
    "{",
    "    cr_assert_eq(1, 1);",
    "}",
  })

  -- A .gitignore line starting with # is a comment: \#*# is the pattern.
  files[".gitignore"] = { "*.o", "*.a", "*.so", "*.gcda", "*.gcno", "vgcore.*", "*~", "\\#*#", name, "unit_tests" }
  return files
end

-- :EpitechNew[!] [name]: the skeleton in dir (the current directory). It
-- refuses when a Makefile exists, unless force is set. Returns the files
-- written (relative paths), or nil.
function M.new(name, dir, force)
  dir = util.normalize(dir or vim.fn.getcwd()):gsub("/$", "")
  name = (name and name ~= "") and name or vim.fs.basename(dir)
  if vim.fn.filereadable(dir .. "/Makefile") == 1 and not force then
    util.notify("There's already a Makefile here: :EpitechNew! overwrites the project files", vim.log.levels.WARN)
    return nil
  end
  local written = {}
  for path, lines in pairs(M.templates(name)) do
    vim.fn.mkdir(vim.fs.dirname(dir .. "/" .. path), "p")
    vim.fn.writefile(lines, dir .. "/" .. path)
    written[#written + 1] = path
  end
  table.sort(written)
  local state = project.state(dir)
  state.header = "include/" .. name .. ".h"
  state.header_dirs = state.header_dirs or { "src" }
  project.save_state(dir, state)
  util.notify(("Created %s: %s"):format(name, table.concat(written, ", ")))
  return written
end

-- :EpitechNewFile <path>: a .c or .h file with its Epitech header, relative
-- to the project root. A .c file is added to SRC (TESTS_SRC under tests/
-- when the Makefile has it); a .h gets an include guard. Then it's opened.
-- on_done (optional) receives the absolute path.
function M.new_file(path, root, on_done)
  root = root or project.root(0)
  local full = path:sub(1, 1) == "/" and path or root .. "/" .. path
  local relative = util.relative(full, root) or path
  if vim.fn.filereadable(full) == 1 then
    util.notify(relative .. " already exists", vim.log.levels.WARN)
    vim.cmd.edit(vim.fn.fnameescape(full))
    return on_done and on_done(full)
  end
  local extension = full:match("%.([ch])$")
  if not extension then
    return util.notify("Give the new file a .c or .h name", vim.log.levels.WARN)
  end
  vim.ui.input({ prompt = "File description: " }, function(description)
    if not description or description == "" then
      return
    end
    local lines = c_header(project.name(root), description)
    if extension == "h" then
      local guard = header.guard_name(full)
      vim.list_extend(lines, { "", "#ifndef " .. guard, "    #define " .. guard, "", "#endif" })
    end
    vim.fn.mkdir(vim.fs.dirname(full), "p")
    vim.fn.writefile(lines, full)
    if extension == "c" then
      local variable = "SRC"
      if vim.startswith(relative, "tests/")
        and table.concat(util.read_lines(root .. "/Makefile"), "\n"):match("\nTESTS_SRC%s*[+:]?=") then
        variable = "TESTS_SRC"
      end
      makefile.add_source(root, relative, variable)
    end
    vim.cmd.edit(vim.fn.fnameescape(full))
    if on_done then
      on_done(full)
    end
  end)
end

return M
