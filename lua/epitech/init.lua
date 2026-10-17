local config = require("epitech.config")
local format = require("epitech.format")
local header = require("epitech.header")

local M = {}

M.format_buffer = format.format_buffer
M.format_stdout = format.format_stdout
M.insert_header = header.insert_header
M.insert_guard = header.insert_guard

-- The file budget ("functions 8/10 · non-static 5/5") for a lualine
-- component; "" when the current buffer has none.
function M.file_budget()
  return require("epitech.budget").file_text()
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

  command("EpitechHints", function(args)
    require("epitech.hints").toggle(args.args ~= "" and args.args or nil)
  end, "Turn the Epitech hints on or off", {
    nargs = "?",
    complete = function()
      return { "on", "off" }
    end,
  })

  command("EpitechFixAll", function(args)
    require("epitech.fixes").fix_all(args.args:upper(), require("epitech.project").root(0))
  end, "Apply an Epitech fix to the whole project", {
    nargs = 1,
    complete = function()
      return require("epitech.fixes").fix_all_codes()
    end,
  })

  command("EpitechSyncHeader", function()
    require("epitech.header_sync").run(require("epitech.project").root(0))
  end, "Update the project header's prototypes")

  command("EpitechNew", function(args)
    require("epitech.scaffold").new(args.args, nil, args.bang)
  end, "Create an Epitech project in the current directory", { nargs = "?", bang = true })
  command("EpitechNewFile", function(args)
    require("epitech.scaffold").new_file(args.args)
  end, "Create a source file with its Epitech header", { nargs = 1, complete = "file" })

  require("epitech.lsp").setup(options)
  require("epitech.banana").setup(options)
  require("epitech.budget").setup(options)
  require("epitech.hints").setup(options)
  require("epitech.hints.makefile").setup(options)
end

return M
