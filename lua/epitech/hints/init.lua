-- Hints for the rules Banana can't see, or only partly: guesses at what a
-- grader would flag. They're diagnostics with hints.severity (HINT) in their
-- own namespace, and a hint is dropped when Banana reports the same code on
-- the same line. Hint modules are pure, run(src, path, ctx) -> diagnostics,
-- so the project check can run them on files that aren't open.
local config = require("epitech.config")
local project = require("epitech.project")
local ts = require("epitech.ts")

local M = {}

M.ns = vim.api.nvim_create_namespace("epitech.hints")

-- Hint modules under hints/, by id. Each is { id, enabled(options), run }.
M.modules = { "magic", "static", "types", "naming" }

local active = true

-- Every hint for a C source. ctx holds root (the project root), and
-- optionally options (the hints options), tree (src's syntax tree, or the
-- buffer's when src is its text) and buf.
function M.collect(src, path, ctx)
  ctx = ctx or {}
  ctx.options = ctx.options or config.options.hints
  ctx.tree = ctx.tree or ts.parse_string(src)
  if not ctx.tree then
    return {}
  end
  local result = {}
  for _, id in ipairs(M.modules) do
    local hint = require("epitech.hints." .. id)
    if hint.enabled(ctx.options) then
      vim.list_extend(result, hint.run(src, path, ctx))
    end
  end
  if config.options.fixes.enabled then
    vim.list_extend(result, require("epitech.fixes").hints(src, path, ctx))
  end
  for _, diagnostic in ipairs(result) do
    diagnostic.severity = ctx.options.severity
    diagnostic.source = "epitech.nvim"
  end
  return result
end

-- Drops the hints Banana already reports (same code on the same line).
-- Hints that explain why a fix isn't offered (user_data.keep) stay.
function M.dedup(hints, banana)
  local reported = {}
  for _, diagnostic in ipairs(banana) do
    reported[diagnostic.lnum .. ":" .. tostring(diagnostic.code)] = true
  end
  return vim.tbl_filter(function(diagnostic)
    return (diagnostic.user_data and diagnostic.user_data.keep) or not reported[diagnostic.lnum .. ":" .. diagnostic.code]
  end, hints)
end

-- Recomputes buf's hints now.
function M.refresh(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  if not active or not config.options.hints.enabled or vim.bo[buf].filetype ~= "c"
    or require("epitech.ignore").ignored(buf) then
    vim.diagnostic.reset(M.ns, buf)
    return
  end
  local src = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
  local hints = M.collect(src, vim.api.nvim_buf_get_name(buf), {
    root = project.root(buf),
    tree = ts.root(buf),
    buf = buf,
    static_used = require("epitech.hints.static").cached_used(buf),
  })
  local banana = vim.diagnostic.get(buf, { namespace = require("epitech.banana").ns })
  vim.diagnostic.set(M.ns, buf, M.dedup(hints, banana))
end

local timers = {}

-- Recomputes buf's hints once edits pause for 250 ms.
function M.schedule(buf)
  local timer = timers[buf]
  if not timer then
    timer = assert(vim.uv.new_timer())
    timers[buf] = timer
  end
  timer:stop()
  timer:start(250, 0, vim.schedule_wrap(function()
    M.refresh(buf)
  end))
end

-- :EpitechHints on|off; no argument toggles.
function M.toggle(state)
  if state == "on" then
    active = true
  elseif state == "off" then
    active = false
  else
    active = not active
  end
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      M.refresh(buf)
    end
  end
  vim.notify("Epitech hints " .. (active and "on" or "off"), vim.log.levels.INFO, { title = "Epitech" })
end

function M.is_active()
  return active
end

function M.setup(options)
  local group = vim.api.nvim_create_augroup("epitech.hints", { clear = true })
  if not options.hints.enabled then
    return
  end
  vim.api.nvim_create_autocmd({ "BufEnter", "TextChanged", "TextChangedI", "InsertLeave" }, {
    group = group,
    callback = function(args)
      if vim.bo[args.buf].filetype == "c" then
        M.schedule(args.buf)
      end
    end,
  })
  if options.hints.static then
    -- C-A4 needs a git grep over the project: on save, and on entering a
    -- buffer whose last search is out of date.
    vim.api.nvim_create_autocmd({ "BufWritePost", "BufEnter" }, {
      group = group,
      callback = function(args)
        if vim.bo[args.buf].filetype == "c" and vim.api.nvim_buf_get_name(args.buf):match("%.c$") then
          require("epitech.hints.static").search(args.buf, project.root(args.buf), function()
            M.refresh(args.buf)
          end)
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
