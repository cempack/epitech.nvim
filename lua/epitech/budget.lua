-- Budget meters: lines and parameters per function (C-F4, C-F5).
local config = require("epitech.config")
local ts = require("epitech.ts")

local M = {}

M.ns = vim.api.nvim_create_namespace("epitech.budget")

-- Defaults link to standard groups, so colorschemes can override them.
function M.highlights()
  for name, link in pairs({
    EpitechBudgetOk = "Comment",
    EpitechBudgetNear = "DiagnosticWarn",
    EpitechBudgetOver = "DiagnosticError",
    EpitechWinbar = "WinBar",
  }) do
    vim.api.nvim_set_hl(0, name, { link = link, default = true })
  end
end

-- The virtual text after a function's signature: "13/20 lines · 2/4 args".
function M.function_chunks(fn, options)
  local lines_hl = "EpitechBudgetOk"
  if fn.body_lines > options.max_lines then
    lines_hl = "EpitechBudgetOver"
  elseif fn.body_lines >= options.warn_lines then
    lines_hl = "EpitechBudgetNear"
  end

  local args = #fn.params
  local args_hl = "EpitechBudgetOk"
  if args > options.max_args then
    args_hl = "EpitechBudgetOver"
  elseif fn.variadic and args + 1 > options.max_args then
    -- calibrate: whether Banana counts `...` as a parameter (C-F5 forbids
    -- variadics that get around the limit); a warning until measured.
    args_hl = "EpitechBudgetNear"
  end

  return {
    { ("%d/%d lines"):format(fn.body_lines, options.max_lines), lines_hl },
    { " · ", "EpitechBudgetOk" },
    { ("%d/%d args"):format(args, options.max_args) .. (fn.variadic and " + …" or ""), args_hl },
  }
end

local function update_functions(buf, options)
  vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
  if not options.functions then
    return
  end
  for _, fn in ipairs(ts.functions(buf)) do
    vim.api.nvim_buf_set_extmark(buf, M.ns, fn.signature_row, 0, {
      virt_text = M.function_chunks(fn, options),
      virt_text_pos = "eol",
      hl_mode = "combine",
    })
  end
end

-- Redraws the meters of buf now.
function M.update(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  update_functions(buf, config.options.budget)
end

local timers = {}

-- Redraws the meters of buf once edits pause for 150 ms.
function M.schedule(buf)
  local timer = timers[buf]
  if not timer then
    timer = assert(vim.uv.new_timer())
    timers[buf] = timer
  end
  timer:stop()
  timer:start(150, 0, vim.schedule_wrap(function()
    M.update(buf)
  end))
end

function M.setup(options)
  M.highlights()
  local group = vim.api.nvim_create_augroup("epitech.budget", { clear = true })
  vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = M.highlights })
  if options.budget.functions then
    vim.api.nvim_create_autocmd({ "BufEnter", "TextChanged", "TextChangedI", "InsertLeave" }, {
      group = group,
      callback = function(args)
        if vim.bo[args.buf].filetype == "c" then
          M.schedule(args.buf)
        end
      end,
    })
  end
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    callback = function(args)
      if timers[args.buf] then
        timers[args.buf]:close()
        timers[args.buf] = nil
      end
    end,
  })
end

return M
