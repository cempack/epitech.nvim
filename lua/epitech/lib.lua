-- libmy, the Pool's lib/my: one function per file in lib/my/, built into
-- lib/my/libmy.a by its own Makefile, prototypes in include/my.h. A project
-- only gets the functions it uses (and the ones those call), from the
-- templates in the plugin's templates/my/.
local config = require("epitech.config")
local format = require("epitech.format")
local header = require("epitech.header")
local makefile = require("epitech.makefile")
local project = require("epitech.project")
local ts = require("epitech.ts")
local util = require("epitech.util")

local M = {}

function M.dir()
  return vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(format.path))) .. "/templates/my"
end

local catalog

-- { [name] = { lines, prototype, deps } } for every template: lines are the
-- file without its Epitech header, deps the other lib functions it calls.
function M.catalog()
  if catalog then
    return catalog
  end
  catalog = {}
  local sources = {}
  for name, kind in vim.fs.dir(M.dir()) do
    local fn_name = kind == "file" and name:match("^(.+)%.c$")
    if fn_name then
      sources[fn_name] = vim.fn.readfile(M.dir() .. "/" .. name)
    end
  end
  for name, lines in pairs(sources) do
    local source = table.concat(lines, "\n")
    local tree = ts.parse_string(source)
    local entry = { lines = lines, deps = {} }
    for _, fn in ipairs(ts.collect_functions(tree, source)) do
      if fn.name == name then
        entry.prototype = require("epitech.header_sync").prototype(fn, source)
      end
    end
    for other in pairs(sources) do
      if other ~= name and source:find("%f[%w_]" .. other .. "%(") then
        entry.deps[#entry.deps + 1] = other
      end
    end
    table.sort(entry.deps)
    catalog[name] = entry
  end
  return catalog
end

function M.names()
  local names = vim.tbl_keys(M.catalog())
  table.sort(names)
  return names
end

-- names with every lib function they need, sorted; unknown names dropped.
function M.resolve(names)
  local all, seen = {}, {}
  local function visit(name)
    local entry = M.catalog()[name]
    if entry and not seen[name] then
      seen[name] = true
      all[#all + 1] = name
      for _, dep in ipairs(entry.deps) do
        visit(dep)
      end
    end
  end
  for _, name in ipairs(names) do
    visit(name)
  end
  table.sort(all)
  return all
end

local function c_header(project_name, description)
  return header.header_lines(header.comment_styles.c, project_name, description, os.date("%Y"))
end

-- The project's my.h, relative to root: include/my.h, or lib/my/my.h when
-- only that one exists (both layouts come out of the Pool).
function M.header_path(root)
  if vim.fn.filereadable(root .. "/include/my.h") == 0 and vim.fn.filereadable(root .. "/lib/my/my.h") == 1 then
    return "lib/my/my.h"
  end
  return "include/my.h"
end

-- path (relative to the root) as seen from dir (relative to the root too).
function M.relative_from(dir, path)
  local from = vim.split(dir, "/", { trimempty = true })
  local to = vim.split(path, "/", { trimempty = true })
  local i = 1
  while from[i] and to[i + 1] and from[i] == to[i] do
    i = i + 1
  end
  return ("../"):rep(#from - i + 1) .. table.concat(to, "/", i)
end

local TEMPLATE_INCLUDE = '#include "../../include/my.h"'

-- lib/my/<name>.c with its Epitech header; include is the path of my.h
-- from lib/my (../../include/my.h by default).
function M.file_lines(name, project_name, include)
  local lines = vim.list_extend(c_header(project_name, name), vim.list_extend({ "" }, M.catalog()[name].lines))
  if include then
    for i, line in ipairs(lines) do
      if line == TEMPLATE_INCLUDE then
        lines[i] = '#include "' .. include .. '"'
      end
    end
  end
  return lines
end

-- include/my.h holding the prototypes of names.
function M.header_lines(project_name, names)
  local lines = c_header(project_name, "Prototypes of libmy")
  vim.list_extend(lines, { "", "#ifndef MY_H_", "    #define MY_H_", "" })
  for _, name in ipairs(names) do
    lines[#lines + 1] = M.catalog()[name].prototype
  end
  vim.list_extend(lines, { "", "#endif" })
  -- C-F3: a long prototype is wrapped like the formatter does.
  return util.format_lines(lines)
end

-- lib/my/Makefile, building libmy.a from names.
function M.makefile(project_name, names)
  local lines = {
    "##",
    "## EPITECH PROJECT, " .. os.date("%Y"),
    "## " .. project_name,
    "## File description:",
    "## Makefile of libmy",
    "##",
    "",
    "CC = " .. config.options.scaffold.cc,
    "",
    "NAME = libmy.a",
    "",
  }
  for i, name in ipairs(names) do
    local text = (i == 1 and "SRC = " or "\t\t") .. name .. ".c"
    lines[#lines + 1] = i < #names and text .. " \\" or text
  end
  vim.list_extend(lines, {
    "",
    "OBJ = $(SRC:.c=.o)",
    "",
    "all: $(NAME)",
    "",
    "$(NAME): $(OBJ)",
    "\tar rc $(NAME) $(OBJ)",
    "",
    "clean:",
    "\trm -f $(OBJ)",
    "",
    "fclean: clean",
    "\trm -f $(NAME)",
    "",
    "re: fclean all",
    "",
    ".PHONY: all clean fclean re",
  })
  return lines
end

-- The files of a new lib/my holding names and what they call:
-- { [relative path] = lines }.
function M.templates(project_name, names)
  names = M.resolve(names)
  local files = {
    ["lib/my/Makefile"] = M.makefile(project_name, names),
    ["include/my.h"] = M.header_lines(project_name, names),
  }
  for _, name in ipairs(names) do
    files["lib/my/" .. name .. ".c"] = M.file_lines(name, project_name)
  end
  return files
end

-- The functions of names (with what they call) the project at root lacks:
-- no lib/my/<name>.c and no definition in a tracked .c file.
function M.missing(root, names)
  local defined = ts.project_functions(root)
  return vim.tbl_filter(function(name)
    return not defined[name] and vim.fn.filereadable(root .. "/lib/my/" .. name .. ".c") == 0
  end, M.resolve(names))
end

-- Adds prototypes to my.h before its guard's #endif, skipping the functions
-- it already declares.
local function add_prototypes(path, names)
  util.edit_file(path, function(buf)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local text = table.concat(lines, "\n")
    local new = {}
    for _, name in ipairs(names) do
      if not text:find("%f[%w_]" .. name .. "%(") then
        vim.list_extend(new, util.format_lines({ M.catalog()[name].prototype }))
      end
    end
    local _, _, endif = header.guard_rows(lines)
    if #new == 0 or not endif then
      return
    end
    local last = endif - 1
    while last > 0 and lines[last] == "" do
      last = last - 1
    end
    -- Right after other prototypes, else after a blank line.
    if not lines[last]:match("%);%s*$") then
      table.insert(new, 1, "")
    end
    new[#new + 1] = ""
    vim.api.nvim_buf_set_lines(buf, last, endif - 1, false, new)
  end)
end

-- :EpitechLib name…: writes the missing functions of names into lib/my,
-- adds them to lib/my/Makefile and their prototypes to my.h
-- (creating both when needed). Returns the functions added.
function M.add(root, names)
  local added = M.missing(root, names)
  if #added == 0 then
    util.notify("libmy already has " .. table.concat(names, ", "))
    return added
  end
  local project_name = project.name(root)
  local header_path = M.header_path(root)
  local include = M.relative_from("lib/my", header_path)
  for _, name in ipairs(added) do
    vim.fn.mkdir(root .. "/lib/my", "p")
    vim.fn.writefile(M.file_lines(name, project_name, include), root .. "/lib/my/" .. name .. ".c")
  end
  if vim.fn.filereadable(root .. "/lib/my/Makefile") == 0 then
    vim.fn.writefile(M.makefile(project_name, added), root .. "/lib/my/Makefile")
  else
    for _, name in ipairs(added) do
      makefile.add_source(root .. "/lib/my", name .. ".c")
    end
  end
  local my_h = root .. "/" .. header_path
  if vim.fn.filereadable(my_h) == 0 and not util.loaded_buffer(my_h) then
    vim.fn.mkdir(vim.fs.dirname(my_h), "p")
    vim.fn.writefile(M.header_lines(project_name, added), my_h)
  else
    add_prototypes(my_h, added)
  end
  local message = "Added to lib/my: " .. table.concat(added, ", ")
  local root_makefile = table.concat(util.read_lines(root .. "/Makefile"), "\n")
  if not root_makefile:find("lib/my", 1, true) then
    message = message .. ". Build and link it from the Makefile: `$(MAKE) -C lib/my` before linking,"
      .. " then -L./lib/my -lmy"
  end
  util.notify(message)
  return added
end

-- :EpitechLib [name…]: adds the named functions, or asks which one.
function M.command(names, root)
  root = root or project.root(0)
  if #names > 0 then
    local unknown = vim.tbl_filter(function(name)
      return not M.catalog()[name]
    end, names)
    if #unknown > 0 then
      return util.notify("Not in libmy: " .. table.concat(unknown, ", ") .. " (:EpitechLib <Tab> lists them)",
        vim.log.levels.WARN)
    end
    return M.add(root, names)
  end
  local choices = vim.tbl_map(function(name)
    return M.catalog()[name].prototype
  end, M.missing(root, M.names()))
  if #choices == 0 then
    return util.notify("libmy already has every function the plugin knows")
  end
  vim.ui.select(choices, { prompt = "Add to lib/my" }, function(choice)
    if choice then
      M.add(root, { choice:match("([%w_]+)%(") })
    end
  end)
end

return M
