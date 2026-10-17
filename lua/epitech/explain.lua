-- Explains a coding style rule in a float: the rule under the cursor
-- (<leader>cE, :EpitechExplain) or one picked from the list (:EpitechRules).
local rules = require("epitech.rules")

local M = {}

local checker_icons = { banana = "🍌", grader = "👤", both = "🍌👤" }
local WIDTH = 56

local function capitalize(text)
  return text:sub(1, 1):upper() .. text:sub(2)
end

-- Words of text, keeping `inline code` spans whole so wrapping never breaks
-- them across lines.
local function words(text)
  local result, open = {}, false
  for word in text:gmatch("%S+") do
    if open then
      result[#result] = result[#result] .. " " .. word
    else
      result[#result + 1] = word
    end
    if select(2, word:gsub("`", "")) % 2 == 1 then
      open = not open
    end
  end
  return result
end

local function wrap(text, width)
  local lines, line = {}, ""
  for _, word in ipairs(words(text)) do
    if line ~= "" and vim.fn.strdisplaywidth(line .. " " .. word) > width then
      lines[#lines + 1] = line
      line = word
    else
      line = line == "" and word or line .. " " .. word
    end
  end
  if line ~= "" then
    lines[#lines + 1] = line
  end
  return lines
end

-- The float's markdown lines for a rule, and for the diagnostic that led
-- there when there is one.
function M.lines(rule, diagnostic)
  local head = rule.code .. " · " .. rule.title
  local tail = capitalize(rule.severity) .. " · " .. checker_icons[rule.checker]
  local gap = math.max(WIDTH - vim.fn.strdisplaywidth(head) - vim.fn.strdisplaywidth(tail), 2)
  local lines = { head .. string.rep(" ", gap) .. tail }
  if diagnostic then
    vim.list_extend(lines, wrap("› " .. (diagnostic.source and diagnostic.source .. ": " or "")
      .. diagnostic.message, WIDTH))
  end
  vim.list_extend(lines, wrap(rule.summary, WIDTH))
  if rule.notes then
    vim.list_extend(lines, wrap("Measured: " .. rule.notes, WIDTH))
  end

  local lang = rule.lang or "c"
  for _, example in ipairs({ { "✗", rule.bad }, { "✓", rule.good } }) do
    lines[#lines + 1] = example[1]
    lines[#lines + 1] = "```" .. lang
    vim.list_extend(lines, example[2])
    lines[#lines + 1] = "```"
  end
  return lines
end

-- Opens the float; returns its buffer and window.
function M.show(rule, diagnostic)
  return vim.lsp.util.open_floating_preview(M.lines(rule, diagnostic), "markdown", {
    border = "rounded",
    focus_id = "epitech_explain",
  })
end

local function item_text(rule)
  return ("%-5s  %s  (%s)"):format(rule.code, rule.title, capitalize(rule.severity))
end

-- :EpitechRules: every rule in vim.ui.select; the choice opens the float.
function M.pick()
  vim.ui.select(rules.rules, { prompt = "Epitech rules", format_item = item_text }, function(rule)
    if rule then
      M.show(rule)
    end
  end)
end

-- Diagnostics on a row whose code is a coding style rule, from any source
-- (Banana, the plugin's hints, other tools using the same codes).
local function rule_diagnostics(buf, row)
  return vim.tbl_filter(function(diagnostic)
    return type(diagnostic.code) == "string" and rules.by_code[diagnostic.code] ~= nil
  end, vim.diagnostic.get(buf, { lnum = row }))
end

local function distinct_codes(diagnostics)
  local result, seen = {}, {}
  for _, diagnostic in ipairs(diagnostics) do
    if not seen[diagnostic.code] then
      seen[diagnostic.code] = true
      result[#result + 1] = diagnostic
    end
  end
  return result
end

-- Explains `code`, or the rule of a diagnostic on the cursor's line: the one
-- under the cursor when several codes are there, else a choice. Without any,
-- opens the rule picker.
function M.explain(code)
  if code and code ~= "" then
    local rule = rules.by_code[code:upper()]
    if not rule then
      vim.notify("Unknown rule: " .. code, vim.log.levels.WARN, { title = "Epitech" })
      return
    end
    return M.show(rule)
  end

  local buf = vim.api.nvim_get_current_buf()
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local on_line = distinct_codes(rule_diagnostics(buf, row - 1))
  if #on_line == 0 then
    return M.pick()
  end
  if #on_line > 1 then
    local under = distinct_codes(vim.tbl_filter(function(diagnostic)
      local last = diagnostic.end_lnum == diagnostic.lnum and diagnostic.end_col or math.huge
      return diagnostic.col <= col and col <= math.max(last or diagnostic.col, diagnostic.col)
    end, on_line))
    if #under == 1 then
      on_line = under
    end
  end
  if #on_line == 1 then
    return M.show(rules.by_code[on_line[1].code], on_line[1])
  end
  vim.ui.select(on_line, {
    prompt = "Explain which rule?",
    format_item = function(diagnostic)
      return item_text(rules.by_code[diagnostic.code]) .. " · " .. diagnostic.message
    end,
  }, function(diagnostic)
    if diagnostic then
      M.show(rules.by_code[diagnostic.code], diagnostic)
    end
  end)
end

function M.complete(lead)
  return vim.tbl_filter(function(code)
    return vim.startswith(code:lower(), lead:lower())
  end, vim.tbl_map(function(rule)
    return rule.code
  end, rules.rules))
end

return M
