-- :EpitechNew creates a project skeleton that follows the coding style, and
-- :EpitechNewFile adds a source file with its header (and its SRC line).
-- These are the only times the plugin creates files in a project, because
-- the user asked (C-O1).
local config = require("epitech.config")
local header = require("epitech.header")
local lib = require("epitech.lib")
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

-- Libraries Epitech projects often link, offered by :EpitechNew. Audio and
-- network need csfml-system too.
M.libraries = {
  {
    name = "CSFML graphics (graphics, window, system)",
    flags = { "-lcsfml-graphics", "-lcsfml-window", "-lcsfml-system" },
  },
  { name = "CSFML audio", flags = { "-lcsfml-audio", "-lcsfml-system" } },
  { name = "CSFML network", flags = { "-lcsfml-network", "-lcsfml-system" } },
  { name = "ncurses", flags = { "-lncurses" } },
  { name = "math (-lm)", flags = { "-lm" } },
}

-- The flags of the chosen libraries (indexes in M.libraries), in the
-- list's order, each once.
function M.library_flags(chosen)
  local flags, seen = {}, {}
  for i, library in ipairs(M.libraries) do
    if chosen[i] then
      for _, flag in ipairs(library.flags) do
        if not seen[flag] then
          seen[flag] = true
          flags[#flags + 1] = flag
        end
      end
    end
  end
  return flags
end

-- Asks which libraries to link: picking one toggles it, Done (first, so
-- Enter alone means none) finishes. on_done receives the flags, or nil
-- when the picker was closed.
function M.pick_libraries(on_done)
  local chosen = {}
  local function ask()
    local items = { "Done" }
    for i, library in ipairs(M.libraries) do
      items[#items + 1] = (chosen[i] and "[x] " or "[ ] ") .. library.name
    end
    vim.ui.select(items, { prompt = "Libraries to link (pick to toggle, then Done)" }, function(_, index)
      if not index then
        return on_done(nil)
      elseif index == 1 then
        return on_done(M.library_flags(chosen))
      end
      chosen[index - 1] = not chosen[index - 1]
      ask()
    end)
  end
  ask()
end

-- The Makefile of a new project. A name ending in .a (libmy.a) builds a
-- library with ar and links the tests against it; any other name builds a
-- program, whose tests take every source but main.c. With with_lib, the
-- program and its tests build lib/my first and link libmy.
function M.makefile(name, sources, tests, ldlibs, with_lib)
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
  if with_lib then
    vim.list_extend(lines, { "LDFLAGS = -L./lib/my", "" })
    ldlibs = vim.list_extend({ "-lmy" }, ldlibs or {})
  end
  if ldlibs and #ldlibs > 0 then
    local line = "LDLIBS = " .. table.concat(ldlibs, " ")
    -- C-F3: one flag per line when they don't fit on one.
    vim.list_extend(lines, #line < 80 and { line } or list("LDLIBS", ldlibs))
    lines[#lines + 1] = ""
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
      "\t$(LDLIBS) --coverage",
    })
  elseif with_lib then
    vim.list_extend(lines, {
      "\t$(MAKE) -C lib/my",
      "\t$(CC) -o $(NAME) $(OBJ) $(LDFLAGS) $(LDLIBS)",
      "",
      "unit_tests: fclean",
      "\t$(MAKE) -C lib/my",
      "\t$(CC) -o unit_tests $(filter-out src/main.c, $(SRC)) $(TEST_SRC) \\",
      "\t$(CPPFLAGS) $(CFLAGS) $(LDFLAGS) $(LDLIBS) -lcriterion --coverage",
    })
  else
    vim.list_extend(lines, {
      "\t$(CC) -o $(NAME) $(OBJ) $(LDLIBS)",
      "",
      "unit_tests: fclean",
      "\t$(CC) -o unit_tests $(filter-out src/main.c, $(SRC)) $(TEST_SRC) \\",
      "\t$(CPPFLAGS) $(CFLAGS) $(LDLIBS) -lcriterion --coverage",
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
  })
  if with_lib then
    lines[#lines + 1] = "\t$(MAKE) -C lib/my clean"
  end
  vim.list_extend(lines, {
    "\trm -f $(OBJ)",
    "\trm -f $(OBJ:.o=.gcno) $(OBJ:.o=.gcda)",
    "\trm -f *.gcno *.gcda",
    "",
    "fclean: clean",
  })
  if with_lib then
    lines[#lines + 1] = "\t$(MAKE) -C lib/my fclean"
  end
  vim.list_extend(lines, {
    "\trm -f $(NAME)",
    "\trm -f unit_tests",
    "",
    "re: fclean $(NAME)",
    "",
  })
  -- Debug information only on demand: `make debug` rebuilds everything with
  -- it (a target's variables apply to what it builds), plain `make` stays
  -- as the moulinette builds it.
  local phony = "all clean fclean re unit_tests tests_run"
  if options.debug_cflags ~= "" then
    vim.list_extend(lines, { "debug: CFLAGS += " .. options.debug_cflags, "debug: re", "" })
    phony = phony .. " debug"
  end
  lines[#lines + 1] = ".PHONY: " .. phony
  return lines
end

-- The plugin's templates/ directory, shared with the VS Code extension.
function M.templates_dir()
  return vim.fs.dirname(lib.dir())
end

-- The base of a project's file names: libmy.a gives my, my_ls gives my_ls.
function M.base(name)
  return name:match("^lib(.+)%.a$") or name
end

-- src/print_error.c: messages for errno values a project usually meets,
-- printed as `name: subject: message` on the error output (like the shell's
-- tools do) with a write() of its own (libmy only writes to the standard
-- output), returning EXIT_ERROR so main can `return print_error(path);`.
-- A switch keeps the cases flat (C-C1 allows 3 branches to an if chain).
function M.error_file(name)
  local base = M.base(name)
  local lines = c_header(name, "Error messages")
  -- The body is shared with the VS Code extension: templates/project/.
  for _, line in ipairs(vim.fn.readfile(M.templates_dir() .. "/project/print_error.c")) do
    lines[#lines + 1] = (line:gsub("@BASE@", base))
  end
  return lines
end

-- The lib/my functions the error file calls.
M.ERROR_FILE_LIB = { "my_strlen" }

-- The files of a new project: { [relative path] = lines }. A program gets
-- src/print_error.c and the part of libmy it uses when scaffold.error_file
-- is on.
function M.templates(name, ldlibs)
  local base = M.base(name)
  local guard = header.guard_name(base .. ".h")
  local files = {}
  local library = base ~= name
  local errors = not library and config.options.scaffold.error_file
  local first_source = library and ("src/" .. base .. ".c") or "src/main.c"
  local sources = { first_source }
  if errors then
    sources[#sources + 1] = "src/print_error.c"
    files["src/print_error.c"] = M.error_file(name)
    for path, lines in pairs(lib.templates(name, M.ERROR_FILE_LIB)) do
      files[path] = lines
    end
  end

  files["Makefile"] = M.makefile(name, sources, { "tests/test_" .. base .. ".c" }, ldlibs, errors)

  local project_header = c_header(name, "Declarations for " .. name)
  vim.list_extend(project_header, { "", "#ifndef " .. guard, "    #define " .. guard })
  if errors then
    vim.list_extend(project_header, {
      '    #define PROGRAM_NAME "' .. name .. '"',
      "    #define EXIT_ERROR 84",
      "",
      "int print_error(char const *subject);",
      "int print_error_message(char const *message);",
    })
  end
  vim.list_extend(project_header, { "", "#endif" })
  files["include/" .. base .. ".h"] = project_header

  if library then
    files[first_source] = vim.list_extend(c_header(name, base), { "", '#include "' .. base .. '.h"' })
  else
    files["src/main.c"] = vim.list_extend(c_header(name, "Entry point"), {
      "",
      '#include "' .. base .. '.h"',
      "",
      "int main(void)",
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
function M.new(name, dir, force, ldlibs)
  dir = util.normalize(dir or vim.fn.getcwd()):gsub("/$", "")
  name = (name and name ~= "") and name or vim.fs.basename(dir)
  if vim.fn.filereadable(dir .. "/Makefile") == 1 and not force then
    util.notify("There's already a Makefile here: :EpitechNew! overwrites the project files", vim.log.levels.WARN)
    return nil
  end
  local written = {}
  for path, lines in pairs(M.templates(name, ldlibs)) do
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

-- :EpitechNew[!] [name]: asks for the libraries to link, then M.new().
function M.create(name, dir, force)
  dir = dir or vim.fn.getcwd()
  if vim.fn.filereadable(dir .. "/Makefile") == 1 and not force then
    return M.new(name, dir, force)
  end
  M.pick_libraries(function(flags)
    if flags then
      M.new(name, dir, force, flags)
    end
  end)
end

-- :EpitechNewFile [path]: a .c or .h file with its Epitech header, relative
-- to the project root. A .c file is added to SRC (TESTS_SRC under tests/
-- when the Makefile has it); a .h gets an include guard. Then it's opened.
-- on_done (optional) receives the absolute path.
function M.new_file_prompt(root)
  return "New file in " .. vim.fs.basename(root) .. "/: "
end

-- The projects under dir: directories with a Makefile that are their own
-- root (a lib/my belongs to its project), sorted.
function M.projects(dir)
  local found = {}
  for _, makefile in ipairs(vim.fs.find("Makefile", { path = dir, type = "file", limit = 50 })) do
    local folder = vim.fs.dirname(makefile)
    if project.root(folder) == util.normalize(folder):gsub("/$", "") then
      found[#found + 1] = util.normalize(folder):gsub("/$", "")
    end
  end
  table.sort(found)
  return found
end

-- Calls on_done with the folder new paths are typed from: the current
-- file's project, else (a file tree, a terminal, no file) a project under
-- the current directory, asked when there are several.
function M.base_folder(on_done)
  local name = vim.api.nvim_buf_get_name(0)
  if name ~= "" and vim.bo.buftype == "" then
    return on_done(project.root(0))
  end
  local cwd = util.normalize(vim.fn.getcwd()):gsub("/$", "")
  local found = M.projects(cwd)
  if #found <= 1 then
    return on_done(found[1] or project.root(cwd))
  end
  vim.ui.select(found, {
    prompt = "Which project?",
    format_item = function(dir)
      return util.relative(dir, cwd) or dir
    end,
  }, function(dir)
    if dir then
      on_done(dir)
    end
  end)
end

function M.new_file(path, root, on_done)
  if not path then
    -- No path given (<leader>cN): ask for it, relative to the project, which
    -- the prompt names (a repository can hold several projects).
    local function ask(base)
      vim.ui.input({ prompt = M.new_file_prompt(base) }, function(answer)
        if answer and answer ~= "" then
          M.new_file(answer, base, on_done)
        end
      end)
    end
    return root and ask(root) or M.base_folder(ask)
  end
  root = root or project.root(0)
  local full = vim.fs.normalize(path:sub(1, 1) == "/" and path or root .. "/" .. path)
  -- The project is the one the file lands in: bootstrap/src/x.c typed from
  -- the repository's root goes into bootstrap's Makefile.
  root = project.root(full)
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
