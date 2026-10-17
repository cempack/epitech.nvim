-- Budget meters: lines and parameters per function (C-F4, C-F5), functions
-- per file (C-O3) and nesting depth (C-C1).
local config = require("epitech.config")
local project = require("epitech.project")
local ts = require("epitech.ts")

local M = {}

M.ns = vim.api.nvim_create_namespace("epitech.budget")
M.depth_ns = vim.api.nvim_create_namespace("epitech.depth")

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

local CONTROL = {
  if_statement = true,
  while_statement = true,
  for_statement = true,
  do_statement = true,
  -- calibrate: whether Banana counts a switch as a level; counted until
  -- measured.
  switch_statement = true,
}

-- The branches of the if chain starting at if_node: 1, plus one per else
-- if, plus one for a final else.
function M.branches(if_node)
  local count, node = 1, if_node
  while true do
    local alternative = node:field("alternative")[1]
    if not alternative then
      return count
    end
    count = count + 1
    local inner = alternative:named_child(0)
    if not inner or inner:type() ~= "if_statement" then
      return count
    end
    node = inner
  end
end

-- The control statements of a function body with their depth (C-C1, as the
-- PDF unfolds its examples): one level below the nearest enclosing control
-- statement, the body's top level being 0. An else if is inside its if's
-- else_clause, so it lands one level below that if. Each entry is
-- { node, depth, else_if, branches } (branches on the first if of a chain).
function M.depths(body)
  local result = {}
  local function walk(node, depth)
    for child in node:iter_children() do
      local type = child:type()
      if CONTROL[type] then
        local entry = {
          node = child,
          depth = depth + 1,
          else_if = type == "if_statement" and child:parent():type() == "else_clause",
        }
        if type == "if_statement" and not entry.else_if then
          entry.branches = M.branches(child)
        end
        result[#result + 1] = entry
        walk(child, depth + 1)
      elseif child:named_child_count() > 0 then
        walk(child, depth)
      end
    end
  end
  walk(body, 0)
  return result
end

-- The virtual text at the end of a control statement's line.
function M.depth_chunks(entry, options)
  local chunks = {}
  if entry.depth >= options.show_depth_from then
    local text = "depth " .. entry.depth .. (entry.else_if and " (else + if)" or "")
    if entry.depth >= options.max_depth then
      chunks[#chunks + 1] = { text .. " ✗ C-C1", "EpitechBudgetOver" }
    else
      chunks[#chunks + 1] = { text, entry.depth == options.max_depth - 1 and "EpitechBudgetNear" or "EpitechBudgetOk" }
    end
  end
  if entry.branches and entry.branches > options.max_branches then
    if #chunks > 0 then
      chunks[#chunks + 1] = { " · ", "EpitechBudgetOk" }
    end
    chunks[#chunks + 1] = { entry.branches .. " branches ✗ C-C1", "EpitechBudgetOver" }
  end
  return chunks
end

local function update_depth(buf, options)
  vim.api.nvim_buf_clear_namespace(buf, M.depth_ns, 0, -1)
  if not options.depth then
    return
  end
  local rows, order = {}, {}
  for _, fn in ipairs(ts.functions(buf)) do
    for _, entry in ipairs(M.depths(fn.body)) do
      local chunks = M.depth_chunks(entry, options)
      if #chunks > 0 then
        local row = entry.node:range()
        if rows[row] then
          table.insert(rows[row], { " · ", "EpitechBudgetOk" })
          vim.list_extend(rows[row], chunks)
        else
          rows[row] = chunks
          order[#order + 1] = row
        end
      end
    end
  end
  for _, row in ipairs(order) do
    vim.api.nvim_buf_set_extmark(buf, M.depth_ns, row, 0, {
      virt_text = rows[row],
      virt_text_pos = "eol",
      hl_mode = "combine",
    })
  end
end

local function is_header(buf)
  return vim.api.nvim_buf_get_name(buf):match("%.h$") ~= nil
end

-- The number of functions defined in buf, and how many aren't static.
function M.file_counts(buf)
  local functions = ts.functions(buf)
  local non_static = 0
  for _, fn in ipairs(functions) do
    if not fn.is_static then
      non_static = non_static + 1
    end
  end
  return #functions, non_static
end

-- Whether buf gets a file budget: C sources always, headers only when they
-- define functions (static inline ones).
local function has_file_budget(buf)
  if vim.bo[buf].filetype ~= "c" or vim.bo[buf].buftype ~= "" then
    return false
  end
  return not is_header(buf) or #ts.functions(buf) > 0
end

local function count_hl(count, limit, base)
  if count > limit then
    return "EpitechBudgetOver"
  elseif count == limit then
    return "EpitechBudgetNear"
  end
  return base
end

-- The file budget as plain text, "functions 8/10 · non-static 5/5", for a
-- lualine component; "" when the buffer has none.
function M.file_text(buf)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  if not has_file_budget(buf) then
    return ""
  end
  local options = config.options.budget
  local functions, non_static = M.file_counts(buf)
  return ("functions %d/%d · non-static %d/%d"):format(functions, options.max_functions, non_static,
    options.max_non_static)
end

-- The winbar of the window being drawn: "src/parser.c   functions 8/10 ·
-- non-static 5/5", each count colored at and past its limit.
function M.winbar()
  local win = vim.g.statusline_winid or vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_win_get_buf(win)
  if not has_file_budget(buf) then
    return ""
  end
  return ts.cached(buf, "winbar", function()
    local options = config.options.budget
    local name = vim.api.nvim_buf_get_name(buf)
    local root = project.root(buf)
    local path = vim.startswith(name, root .. "/") and name:sub(#root + 2) or vim.fn.fnamemodify(name, ":~:.")
    local functions, non_static = M.file_counts(buf)
    return ("%%#EpitechWinbar#%s   functions %%#%s#%d/%d%%#EpitechWinbar# · non-static %%#%s#%d/%d%%*"):format(
      (path:gsub("%%", "%%%%")),
      count_hl(functions, options.max_functions, "EpitechWinbar"), functions, options.max_functions,
      count_hl(non_static, options.max_non_static, "EpitechWinbar"), non_static, options.max_non_static)
  end)
end

M.WINBAR = "%{%v:lua.require'epitech.budget'.winbar()%}"

-- Shows the file budget in win's winbar, but only when the winbar is empty
-- or the plugin set it: a winbar of the user's or another plugin's is never
-- touched. Clears the plugin's winbar when the window shows another buffer.
function M.update_winbar(win)
  win = (win == nil or win == 0) and vim.api.nvim_get_current_win() or win
  if not vim.api.nvim_win_is_valid(win) or vim.api.nvim_win_get_config(win).relative ~= "" then
    return
  end
  local ours = vim.w[win].epitech_winbar == true and vim.wo[win].winbar == M.WINBAR
  if config.options.budget.file == "winbar" and has_file_budget(vim.api.nvim_win_get_buf(win)) then
    if ours or vim.wo[win].winbar == "" then
      vim.api.nvim_set_option_value("winbar", M.WINBAR, { win = win, scope = "local" })
      vim.w[win].epitech_winbar = true
    end
  elseif ours then
    vim.api.nvim_set_option_value("winbar", "", { win = win, scope = "local" })
    vim.w[win].epitech_winbar = false
  end
end

-- Redraws the meters of buf now.
function M.update(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  update_functions(buf, config.options.budget)
  update_depth(buf, config.options.budget)
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
  if options.budget.functions or options.budget.depth then
    vim.api.nvim_create_autocmd({ "BufEnter", "TextChanged", "TextChangedI", "InsertLeave" }, {
      group = group,
      callback = function(args)
        if vim.bo[args.buf].filetype == "c" then
          M.schedule(args.buf)
        end
      end,
    })
  end
  if options.budget.file == "winbar" then
    vim.api.nvim_create_autocmd({ "BufWinEnter", "WinEnter", "FileType" }, {
      group = group,
      callback = function()
        M.update_winbar(0)
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
