local M = {}

local module_path = debug.getinfo(1, "S").source:sub(2)
local plugin_dir = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(module_path)))
local style_file = plugin_dir .. "/epitech.clang-format"

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

-- Vim's C indent treats preprocessor lines as column-zero. Banana C-G3 instead
-- counts conditional preprocessor nesting independently of C block nesting.
local function indent_preprocessor(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local depth = 0
  local changed = false

  for i, line in ipairs(lines) do
    local directive = line:match("^%s*#%s*([%a_][%w_]*)")
    if directive then
      local branch = directive == "else" or directive == "elif" or directive == "elifdef" or directive == "elifndef"
      local closing = directive == "endif"
      if branch or closing then
        depth = math.max(depth - 1, 0)
      end

      local normalized = string.rep("    ", depth) .. line:gsub("^%s*", "")
      if normalized ~= line then
        lines[i] = normalized
        changed = true
      end

      if directive == "if" or directive == "ifdef" or directive == "ifndef" or branch then
        depth = depth + 1
      end
    end
  end

  if changed then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  end
end

function M.format_buffer()
  local buf = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local header = {}
  local body_start = 1

  if has_header(buf) then
    vim.list_extend(header, lines, 1, 6)
    for i = 2, 6 do
      header[i] = header[i]:gsub("^ ", "")
    end
    body_start = 7
  end

  local body = {}
  vim.list_extend(body, lines, body_start)
  local result = vim.system({
    "clang-format",
    "--style=file:" .. style_file,
    "--assume-filename=epitech.c",
  }, { stdin = table.concat(body, "\n") .. "\n", text = true }):wait()
  if result.code ~= 0 then
    error("clang-format failed: " .. (result.stderr or ""))
  end

  body = vim.split(result.stdout:gsub("\n$", ""), "\n", { plain = true })
  while body[1] == "" do
    table.remove(body, 1)
  end
  while body[#body] == "" do
    table.remove(body)
  end

  local formatted = header
  if #header > 0 and #body > 0 then
    formatted[#formatted + 1] = ""
  end
  vim.list_extend(formatted, body)
  if #formatted == 0 then
    formatted[1] = ""
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, formatted)
  indent_preprocessor(buf)
end

function M.format_stdout()
  local ok, err = pcall(M.format_buffer)
  if not ok then
    io.stderr:write("Epitech formatter: " .. tostring(err) .. "\n")
    vim.cmd("cquit 1")
    return
  end
  io.stdout:write(table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n") .. "\n")
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

local function has_guard(lines)
  for i = 1, math.min(#lines, 30) do
    if lines[i]:match("^%s*#pragma%s+once%s*$") then
      return true
    end
    local name = lines[i]:match("^%s*#ifndef%s+([%a_][%w_]*)%s*$")
    if name then
      for j = i + 1, math.min(i + 5, #lines) do
        if lines[j]:match("^%s*#define%s+" .. name .. "%s*$") then
          return true
        end
      end
    end
  end
  return false
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
  if has_guard(lines) then
    vim.notify("This file already has an include guard", vim.log.levels.INFO, { title = "Epitech" })
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
  indent_preprocessor(buf)
  vim.api.nvim_win_set_cursor(0, { cursor_line, 0 })
end

function M.formatter(opts)
  opts = opts or {}
  local vim_config = opts.vim_config or vim.fn.expand("~/.vim/epitech.vim")

  return {
    command = vim.v.progpath ~= "" and vim.v.progpath or "nvim",
    args = {
      "--clean",
      "--headless",
      "-u",
      vim_config,
      "-c",
      "set filetype=c",
      "-c",
      ("lua dofile(%q).format_stdout()"):format(module_path),
      "-c",
      "qa!",
      "-",
    },
    stdin = true,
    condition = function()
      return vim.fn.filereadable(vim_config) == 1
        and vim.fn.filereadable(style_file) == 1
        and vim.fn.executable("clang-format") == 1
    end,
  }
end

function M.setup()
  if vim.api.nvim_get_commands({ builtin = false }).EpitechHeader == nil then
    vim.api.nvim_create_user_command("EpitechHeader", M.insert_header, {
      desc = "Insert an Epitech header",
    })
  end
  if vim.fn.maparg("<leader>cH", "n") == "" then
    vim.keymap.set("n", "<leader>cH", M.insert_header, {
      desc = "Epitech Header",
    })
  end
  if vim.api.nvim_get_commands({ builtin = false }).EpitechGuard == nil then
    vim.api.nvim_create_user_command("EpitechGuard", M.insert_guard, {
      desc = "Add an include guard based on the header filename",
    })
  end
  if vim.fn.maparg("<leader>cG", "n") == "" then
    vim.keymap.set("n", "<leader>cG", M.insert_guard, {
      desc = "Epitech Include Guard",
    })
  end
end

return M
