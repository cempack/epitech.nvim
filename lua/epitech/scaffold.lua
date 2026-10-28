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

-- A Makefile list: `NAME = first \` then one value per line, two tabs in.
local function list(variable, values)
  local lines = {}
  for i, value in ipairs(values) do
    local text = i == 1 and (variable .. " = " .. value) or ("\t\t" .. value)
    lines[#lines + 1] = i < #values and text .. " \\" or text
  end
  return lines
end

-- The Makefile of a new project. A name ending in .a (libmy.a) builds a
-- library with ar and links the tests against it; any other name builds a
-- program, whose tests take every source but main.c.
function M.makefile(name, sources, tests)
  local options = config.options.scaffold
  local library = name:match("^lib(.+)%.a$")
  local lines = {
    "##",
    "## EPITECH PROJECT, " .. os.date("%Y"),
    "## " .. name,
    "## File description:",
    "## Makefile",
    "##",
    "",
    "CC = " .. options.cc,
    "",
    "CPPFLAGS = -I./include",
    "",
  }
  if options.cflags ~= "" then
    vim.list_extend(lines, { "CFLAGS = " .. options.cflags, "" })
  end
  vim.list_extend(lines, { "NAME = " .. name, "" })
  vim.list_extend(lines, list("SRC", sources))
  vim.list_extend(lines, { "", "OBJ = $(SRC:.c=.o)", "" })
  vim.list_extend(lines, list("TEST_SRC", tests))
  vim.list_extend(lines, { "", "all: $(NAME)", "", "$(NAME): $(OBJ)" })
  if library then
    vim.list_extend(lines, {
      "\tar rc $(NAME) $(OBJ)",
      "",
      "unit_tests: CFLAGS += --coverage",
      "unit_tests: fclean $(NAME)",
      "\t$(CC) -o unit_tests $(TEST_SRC) $(CPPFLAGS) -L. -l" .. library .. " -lcriterion \\",
      "\t--coverage",
    })
  else
    vim.list_extend(lines, {
      "\t$(CC) -o $(NAME) $(OBJ)",
      "",
      "unit_tests: fclean",
      "\t$(CC) -o unit_tests $(filter-out src/main.c, $(SRC)) $(TEST_SRC) \\",
      "\t$(CPPFLAGS) $(CFLAGS) -lcriterion --coverage",
    })
  end
  vim.list_extend(lines, {
    "",
    "tests_run: unit_tests",
    "\t./unit_tests; status=$$?; \\",
    "\t$(MAKE) --no-print-directory fclean; \\",
    "\texit $$status",
    "",
    "clean:",
    "\trm -f $(OBJ)",
    "\trm -f $(OBJ:.o=.gcno) $(OBJ:.o=.gcda)",
    "\trm -f *.gcno *.gcda",
    "",
    "fclean: clean",
    "\trm -f $(NAME)",
    "\trm -f unit_tests",
    "",
    "re: fclean $(NAME)",
    "",
    ".PHONY: all clean fclean re unit_tests tests_run",
  })
  return lines
end

-- The base of a project's file names: libmy.a gives my, my_ls gives my_ls.
function M.base(name)
  return name:match("^lib(.+)%.a$") or name
end

-- The files of a new project: { [relative path] = lines }.
function M.templates(name)
  local base = M.base(name)
  local guard = header.guard_name(base .. ".h")
  local sync = require("epitech.header_sync")
  local files = {}
  local library = base ~= name
  local first_source = library and ("src/" .. base .. ".c") or "src/main.c"

  files["Makefile"] = M.makefile(name, { first_source }, { "tests/test_" .. base .. ".c" })

  files["include/" .. base .. ".h"] = vim.list_extend(c_header(name, "Declarations for " .. name), {
    "",
    "#ifndef " .. guard,
    "    #define " .. guard,
    "",
    sync.BEGIN,
    sync.END,
    "",
    "#endif",
  })

  if library then
    files[first_source] = vim.list_extend(c_header(name, base), { "", '#include "' .. base .. '.h"' })
  else
    files["src/main.c"] = vim.list_extend(c_header(name, "Entry point"), {
      "",
      '#include "' .. base .. '.h"',
      "",
      "int main(int ac, char **av)",
      "{",
      "    return 0;",
      "}",
    })
  end

  files["tests/test_" .. base .. ".c"] = vim.list_extend(c_header(name, "Unit tests"), {
    "",
    "#include <criterion/criterion.h>",
    '#include "' .. base .. '.h"',
    "",
    "Test(" .. base:gsub("[^%w_]", "_") .. ", placeholder)",
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
  state.header = "include/" .. M.base(name) .. ".h"
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
      if vim.startswith(relative, "tests/") then
        local text = "\n" .. table.concat(util.read_lines(root .. "/Makefile"), "\n")
        variable = text:match("\n(TESTS?_SRC)%s*[+:]?=") or variable
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
