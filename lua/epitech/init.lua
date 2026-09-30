local M = {}

local module_path = debug.getinfo(1, "S").source:sub(2)

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

function M.format_buffer()
  local buf = vim.api.nvim_get_current_buf()

  if not has_header(buf) then
    vim.cmd("silent normal! gg=G")
    return
  end

  local header = vim.api.nvim_buf_get_lines(buf, 0, 6, false)
  for line = 2, 6 do
    header[line] = header[line]:gsub("^ ", "")
  end
  vim.api.nvim_buf_set_lines(buf, 0, 6, false, header)

  if vim.api.nvim_buf_line_count(buf) > 6 then
    vim.cmd("silent normal! 7G=G")
  end
end

function M.insert_header()
  local buf = vim.api.nvim_get_current_buf()

  if has_header(buf) then
    vim.notify("This file already has an Epitech header", vim.log.levels.INFO, { title = "Epitech" })
    return
  end
  if not vim.bo[buf].modifiable then
    vim.notify("This buffer is not modifiable", vim.log.levels.ERROR, { title = "Epitech" })
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

      vim.api.nvim_buf_set_lines(buf, 0, 0, false, {
        "/*",
        "** EPITECH PROJECT, " .. os.date("%Y"),
        "** " .. project,
        "** File description:",
        "** " .. description,
        "*/",
      })
    end)
  end)
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
      ("lua dofile(%q).format_buffer()"):format(module_path),
      "-c",
      [[lua io.stdout:write(table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n") .. "\n")]],
      "-c",
      "qa!",
      "-",
    },
    stdin = true,
    condition = function()
      return vim.fn.filereadable(vim_config) == 1
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
end

return M
