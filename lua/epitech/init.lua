local config = require("epitech.config")
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

local function command(name, fn, desc, opts)
  if vim.api.nvim_get_commands({ builtin = false })[name] == nil then
    vim.api.nvim_create_user_command(name, fn, vim.tbl_extend("force", { desc = desc }, opts or {}))
  end
end

-- A mapping is only set when it's enabled and its keys are still free.
local function keymap(lhs, fn, desc)
  if lhs and vim.fn.maparg(lhs, "n") == "" then
    vim.keymap.set("n", lhs, fn, { desc = desc })
  end
end

function M.setup(opts)
  local options = config.setup(opts)

  command("EpitechHeader", M.insert_header, "Insert an Epitech header")
  keymap(options.header.keymap, M.insert_header, "Epitech Header")
  command("EpitechGuard", M.insert_guard, "Add an include guard based on the header filename")
  keymap(options.guard.keymap, M.insert_guard, "Epitech Include Guard")

  command("EpitechExplain", function(args)
    require("epitech.explain").explain(args.args)
  end, "Explain an Epitech coding style rule", {
    nargs = "?",
    complete = function(lead)
      return require("epitech.explain").complete(lead)
    end,
  })
  command("EpitechRules", function()
    require("epitech.explain").pick()
  end, "List the Epitech coding style rules")
  keymap(options.explain.keymap, function()
    require("epitech.explain").explain()
  end, "Epitech Explain Rule")

  require("epitech.lsp").setup(options)
  require("epitech.banana").setup(options)
end

return M
