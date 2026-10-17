-- Edits to the project's Makefile: adding and removing source files.
-- Generated lines never use backslash continuations (C-G6 may cover
-- Makefiles too).
local util = require("epitech.util")

local M = {}

local function assignment(line, variable)
  return line:match("^" .. variable .. "%s*[+:]?=%s*(.-)%s*$")
end

-- The rows (1-based) of every assignment to variable, each with the rows of
-- its backslash continuations: { first, last, values (the words) }.
local function assignments(lines, variable)
  local result = {}
  local i = 1
  while i <= #lines do
    local value = assignment(lines[i], variable)
    if value then
      local first, values = i, { value }
      while values[#values]:match("\\%s*$") and lines[i + 1] do
        values[#values] = values[#values]:gsub("\\%s*$", "")
        i = i + 1
        values[#values + 1] = lines[i]
      end
      local words = {}
      for _, text in ipairs(values) do
        for word in text:gmatch("%S+") do
          words[#words + 1] = word
        end
      end
      result[#result + 1] = { first = first, last = i, words = words, raw = table.concat(values, " ") }
    end
    i = i + 1
  end
  return result
end

-- Adds `variable += path` after the last assignment to variable (SRC by
-- default) in root's Makefile. Changes nothing when the Makefile has no
-- such variable or builds it with $(wildcard …), and tells the user what to
-- add instead. Returns whether the path is in the variable afterwards.
function M.add_source(root, path, variable)
  variable = variable or "SRC"
  local makefile = root .. "/Makefile"
  local found = assignments(util.read_lines(makefile), variable)
  local line = variable .. " += " .. path
  if #found == 0 then
    util.notify(("No %s in the Makefile: add `%s` yourself"):format(variable, line), vim.log.levels.WARN)
    return false
  end
  for _, entry in ipairs(found) do
    if entry.raw:find("$(wildcard", 1, true) then
      util.notify(("%s uses $(wildcard …) in the Makefile: add `%s` yourself if it doesn't pick the file up"):format(
        variable, line), vim.log.levels.WARN)
      return false
    end
    if vim.list_contains(entry.words, path) then
      return true
    end
  end
  util.edit_file(makefile, function(buf)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local last = assignments(lines, variable)
    last = last[#last].last
    vim.api.nvim_buf_set_lines(buf, last, last, false, { line })
  end)
  return true
end

-- Removes path from variable (SRC by default): its own `SRC += path` line,
-- or its word in a `SRC = …` list, continuation lines included. Returns
-- whether something was removed.
function M.remove_source(root, path, variable)
  variable = variable or "SRC"
  local removed = false
  util.edit_file(root .. "/Makefile", function(buf)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local found = assignments(lines, variable)
    for index = #found, 1, -1 do
      local entry = found[index]
      if vim.list_contains(entry.words, path) then
        removed = true
        local rows = {}
        for row = entry.first, entry.last do
          local line = lines[row]:gsub("\\%s*$", "")
          local prefix, rest
          if row == entry.first then
            prefix, rest = line:match("^(" .. variable .. "%s*[+:]?=%s*)(.*)$")
          else
            prefix, rest = line:match("^(%s*)(.*)$")
          end
          local words = {}
          for word in rest:gmatch("%S+") do
            if word ~= path then
              words[#words + 1] = word
            end
          end
          if row == entry.first or #words > 0 then
            rows[#rows + 1] = (prefix .. table.concat(words, " ")):gsub("%s+$", "")
          end
        end
        -- `SRC += path` alone goes away entirely.
        local new = {}
        if #entry.words > 1 then
          for i, text in ipairs(rows) do
            new[#new + 1] = i < #rows and text .. " \\" or text
          end
        end
        vim.api.nvim_buf_set_lines(buf, entry.first - 1, entry.last, false, new)
      end
    end
  end)
  return removed
end

return M
