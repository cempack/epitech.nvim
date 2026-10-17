local format = require("epitech.format")
local header = require("epitech.header")

local M = {}

M.format_buffer = format.format_buffer
M.format_stdout = format.format_stdout
M.insert_header = header.insert_header
M.insert_guard = header.insert_guard

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
      ("lua dofile(%q).format_stdout()"):format(format.path),
      "-c",
      "qa!",
      "-",
    },
    stdin = true,
    condition = function()
      return vim.fn.filereadable(vim_config) == 1
        and vim.fn.filereadable(format.style_file) == 1
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
