-- Epitech file headers (C-G1) and include guards (C-H2).
local format = require("epitech.format")

local M = {}

-- The original Epitech Vim config supplies the first set of comment styles.
-- The remaining common Neovim filetypes use their normal comment syntax.
local comment_styles = {
  c = { "/*", "**", "*/" },
  cpp = { "//", "//", "//" },
  make = { "##", "##", "##" },
  java = { "//", "//", "//" },
  tex = { "%%", "%%", "%%" },
  html = { "<!--", "  --", "-->" },
  lisp = { ";;", ";;", ";;" },
  css = { "/*", "**", "*/" },
  pov = { "//", "//", "//" },
  pascal = { "{ ", "   ", "}" },
  haskell = { "{-", "-- ", "-}" },
  vim = { '""', '""', '""' },
  sh = { "##", "##", "##", "#!/usr/bin/env sh" },
  bash = { "##", "##", "##", "#!/usr/bin/env bash" },
  zsh = { "##", "##", "##", "#!/usr/bin/env zsh" },
  php = { "/*", "**", "*/", "#!/usr/bin/env php" },
  perl = { "##", "##", "##", "#!/usr/bin/env perl" },
  python = { "##", "##", "##", "#!/usr/bin/env python3" },
  ruby = { "##", "##", "##", "#!/usr/bin/env ruby" },
  node = { "/*", "**", "*/", "#!/usr/bin/env node" },
  lua = { "--", "--", "--" },
  javascript = { "//", "//", "//" },
  javascriptreact = { "//", "//", "//" },
  typescript = { "//", "//", "//" },
  typescriptreact = { "//", "//", "//" },
  go = { "//", "//", "//" },
  rust = { "//", "//", "//" },
  kotlin = { "//", "//", "//" },
  scala = { "//", "//", "//" },
  yaml = { "##", "##", "##" },
  toml = { "##", "##", "##" },
  conf = { "##", "##", "##" },
  dockerfile = { "##", "##", "##" },
  cmake = { "##", "##", "##" },
  markdown = { "<!--", "  --", "-->" },
  xml = { "<!--", "  --", "-->" },
  sql = { "--", "--", "--" },
}

local function header_lines(style, project, description, year)
  return {
    style[1],
    style[2] .. " EPITECH PROJECT, " .. year,
    style[2] .. " " .. project,
    style[2] .. " File description:",
    style[2] .. " " .. description,
    style[3],
  }
end

local function existing_header(lines)
  for start = 1, math.min(2, #lines - 5) do
    for _, style in pairs(comment_styles) do
      local first = lines[start]
      local second = lines[start + 1]
      local third = lines[start + 2]
      local fourth = lines[start + 3]
      local fifth = lines[start + 4]
      local last = lines[start + 5]
      if style[1] == "/*" then
        second = second and second:gsub("^ ", "")
        third = third and third:gsub("^ ", "")
        fourth = fourth and fourth:gsub("^ ", "")
        fifth = fifth and fifth:gsub("^ ", "")
        last = last and last:gsub("^ ", "")
      end
      local year = second and second:match("EPITECH PROJECT, (%d%d%d%d)$")
      if first == style[1]
        and year
        and second:sub(1, #style[2] + 1) == style[2] .. " "
        and third:sub(1, #style[2] + 1) == style[2] .. " "
        and fourth == style[2] .. " File description:"
        and fifth:sub(1, #style[2] + 1) == style[2] .. " "
        and last == style[3]
      then
        return start, style, third:sub(#style[2] + 2), fifth:sub(#style[2] + 2)
      end
    end
  end
end

local function has_header(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, 6, false)
  return lines[6] ~= nil
    and lines[1] == "/*"
    and lines[2]:match("^ ?%*%* EPITECH PROJECT, %d%d%d%d$") ~= nil
    and lines[3]:match("^ ?%*%* .*$") ~= nil
    and lines[4]:match("^ ?%*%* File description:$") ~= nil
    and lines[5]:match("^ ?%*%* .*$") ~= nil
    and lines[6]:match("^ ?%*/$") ~= nil
end

function M.insert_header()
  local buf = vim.api.nvim_get_current_buf()
  if not vim.bo[buf].modifiable then
    vim.notify("This buffer is not modifiable", vim.log.levels.ERROR, { title = "Epitech" })
    return
  end

  local ft = vim.bo[buf].filetype
  local style = comment_styles[ft]
  if not style then
    vim.notify("Unsupported Epitech header filetype: " .. (ft ~= "" and ft or "(none)"), vim.log.levels.WARN, { title = "Epitech" })
    return
  end

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local start, previous_style, previous_project, previous_description = existing_header(lines)
  if start then
    if previous_style[1] == style[1] and previous_style[2] == style[2] and previous_style[3] == style[3] then
      vim.notify("This file already has an Epitech header", vim.log.levels.INFO, { title = "Epitech" })
      return
    end
    vim.ui.select({ "Replace", "Keep" }, { prompt = "Replace the header with " .. ft .. " comment syntax?" }, function(choice)
      if choice ~= "Replace" or not vim.api.nvim_buf_is_valid(buf) or not vim.bo[buf].modifiable then
        return
      end
      vim.api.nvim_buf_set_lines(buf, start - 1, start + 5, false,
        header_lines(style, previous_project, previous_description, os.date("%Y")))
    end)
    return
  end

  vim.ui.input({ prompt = "Project name: " }, function(project)
    if project == nil then
      return
    end

    vim.ui.input({ prompt = "File description: " }, function(description)
      if description == nil or not vim.api.nvim_buf_is_valid(buf) or not vim.bo[buf].modifiable then
        return
      end

      local current = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      if existing_header(current) then
        vim.notify("This file already has an Epitech header", vim.log.levels.INFO, { title = "Epitech" })
        return
      end
      local insert_at = 0
      local new_header = header_lines(style, project, description, os.date("%Y"))
      if current[1] and current[1]:match("^#!") then
        insert_at = 1
      elseif style[4] then
        table.insert(new_header, 1, style[4])
      end
      if current[insert_at + 1] ~= "" then
        new_header[#new_header + 1] = ""
      end
      vim.api.nvim_buf_set_lines(buf, insert_at, insert_at, false, new_header)
    end)
  end)
end

-- Only #ifndef/#define/#endif counts as a guard (C-H2). #pragma once is one
-- of the language extensions the coding style lists as unsupported by Banana,
-- so it is not a guard here: insert_guard() replaces it with a real one.
local function has_guard(lines)
  for i = 1, math.min(#lines, 30) do
    local name = lines[i]:match("^%s*#%s*ifndef%s+([%a_][%w_]*)%s*$")
    if name then
      for j = i + 1, math.min(i + 5, #lines) do
        if lines[j]:match("^%s*#%s*define%s+" .. name .. "%s*$") then
          return true
        end
      end
    end
  end
  return false
end

-- Row (1-based) of a #pragma once line near the top of the file, if any.
local function find_pragma_once(lines)
  for i = 1, math.min(#lines, 30) do
    if lines[i]:match("^%s*#%s*pragma%s+once%s*$") then
      return i
    end
  end
end

-- Deletes the #pragma once line, plus the blank line after it when that
-- would otherwise leave two blank lines in a row (or a leading blank line).
local function remove_pragma_once(buf, lines, row)
  local last = row
  if lines[row + 1] == "" and (row == 1 or lines[row - 1] == "") then
    last = row + 1
  end
  vim.api.nvim_buf_set_lines(buf, row - 1, last, false, {})
end

function M.insert_guard()
  local buf = vim.api.nvim_get_current_buf()
  local filename = vim.fs.basename(vim.api.nvim_buf_get_name(buf))
  if not filename:match("%.h$") then
    vim.notify("Name this buffer as a .h file first", vim.log.levels.WARN, { title = "Epitech" })
    return
  end
  if not vim.bo[buf].modifiable then
    vim.notify("This buffer is not modifiable", vim.log.levels.ERROR, { title = "Epitech" })
    return
  end

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local pragma = find_pragma_once(lines)
  if pragma then
    remove_pragma_once(buf, lines, pragma)
    lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  end
  if has_guard(lines) then
    if pragma then
      vim.notify("Removed #pragma once: the file already has an include guard", vim.log.levels.INFO, { title = "Epitech" })
    else
      vim.notify("This file already has an include guard", vim.log.levels.INFO, { title = "Epitech" })
    end
    return
  end

  local guard = filename:gsub("[^%w]", "_"):upper() .. "_"
  if not guard:match("^[A-Z]") then
    guard = "HEADER_" .. guard
  end

  local wrapped = {}
  local body_start = 1
  if has_header(buf) then
    vim.list_extend(wrapped, lines, 1, 6)
    wrapped[#wrapped + 1] = ""
    body_start = 7
  end
  wrapped[#wrapped + 1] = "#ifndef " .. guard
  wrapped[#wrapped + 1] = "#define " .. guard
  wrapped[#wrapped + 1] = ""
  local cursor_line = #wrapped
  if lines[body_start] == "" then
    body_start = body_start + 1
  end
  vim.list_extend(wrapped, lines, body_start)
  if wrapped[#wrapped] ~= "" then
    wrapped[#wrapped + 1] = ""
  end
  wrapped[#wrapped + 1] = "#endif"

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, wrapped)
  format.indent_preprocessor(buf)
  vim.api.nvim_win_set_cursor(0, { cursor_line, 0 })
  if pragma then
    vim.notify("Replaced #pragma once with an include guard", vim.log.levels.INFO, { title = "Epitech" })
  end
end

M.comment_styles = comment_styles
M.header_lines = header_lines
M.existing_header = existing_header
M.has_header = has_header
M.has_guard = has_guard

return M
