-- Makefile fixes: add the Epitech header (C-G1), split a long or
-- backslash-continued SRC assignment into one file per line (C-F3, C-G6),
-- remove trailing spaces (C-G7).
local config = require("epitech.config")
local fixes = require("epitech.fixes")
local header = require("epitech.header")
local makefile = require("epitech.hints.makefile")

local M = { id = "makefile", rules = { "C-G1", "C-F3", "C-G7" }, filetypes = { "make" } }

-- The assignment to a *SRC variable that covers row, following backslash
-- continuations: { first, last (0-based rows), name, operator, words, long },
-- or nil when it isn't one or a value isn't a plain file name ($(wildcard …)
-- can't be split safely).
function M.source_assignment(lines, row)
  local first = row
  while first > 0 and lines[first]:match("\\%s*$") do
    first = first - 1
  end
  local name, operator, rest = lines[first + 1]:match("^([%w_]*SRC)%s*([:+?]?=)%s*(.-)%s*$")
  if not name then
    return nil
  end
  local last, values = first, { rest }
  while values[#values]:match("\\%s*$") and lines[last + 2] do
    values[#values] = values[#values]:gsub("\\%s*$", "")
    last = last + 1
    values[#values + 1] = lines[last + 1]
  end
  if last < row then
    return nil
  end
  local words, long = {}, last > first
  for _, value in ipairs(values) do
    for word in value:gsub("\\%s*$", ""):gmatch("%S+") do
      if word:find("[$()]") then
        return nil
      end
      words[#words + 1] = word
    end
  end
  for i = first, last do
    long = long or makefile.width(lines[i + 1], config.options.makefile.tab_width) + 1 > 80
  end
  return { first = first, last = last, name = name, operator = operator, words = words, long = long }
end

-- One file per line. The first line keeps the original operator, so a
-- `SRC = …` that resets an earlier value still does.
function M.split_lines(assignment)
  local result = {}
  for i, word in ipairs(assignment.words) do
    result[#result + 1] = ("%s %s %s"):format(assignment.name, i == 1 and assignment.operator or "+=", word)
  end
  return result
end

function M.actions(buf, range)
  if not config.options.makefile.enabled then
    return {}
  end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local actions = {}
  if range.start.line == 0 and not header.existing_header(vim.list_slice(lines, 1, 8)) then
    actions[#actions + 1] = fixes.command_action("Add the Epitech header (C-G1)", "C-G1", "epitech.makefile_header",
      { fixes.uri(buf) })
  end
  local split_done = {}
  for row = range.start.line, math.min(range["end"].line, #lines - 1) do
    local assignment = M.source_assignment(lines, row)
    if assignment and assignment.long and #assignment.words > 1 and not split_done[assignment.first] then
      split_done[assignment.first] = true
      actions[#actions + 1] = fixes.action(("Split into %s += lines (C-F3)"):format(assignment.name), "C-F3", buf, {
        {
          range = fixes.position_range(assignment.first, 0, assignment.last, #lines[assignment.last + 1]),
          newText = table.concat(M.split_lines(assignment), "\n"),
        },
      })
    end
    local trailing = lines[row + 1]:find("%s+$")
    if trailing then
      actions[#actions + 1] = fixes.action("Remove trailing spaces (C-G7)", "C-G7", buf, {
        { range = fixes.position_range(row, trailing - 1, row, #lines[row + 1]), newText = "" },
      })
    end
  end
  return actions
end

M.commands = {
  ["epitech.makefile_header"] = function(command)
    local buf = vim.uri_to_bufnr(command.arguments[1])
    vim.api.nvim_buf_call(buf, header.insert_header)
  end,
}

return M
