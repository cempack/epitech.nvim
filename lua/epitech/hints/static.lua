-- C-A4 (grader), C-O3: non-static functions that no other file uses could
-- be static. Whether another .c file mentions a name comes from `git grep`,
-- run asynchronously on save; until then there's no hint.
local ts = require("epitech.ts")
local util = require("epitech.util")

local M = { id = "static" }

function M.enabled(options)
  return options.static
end

-- The non-static functions of a .c source other than main.
function M.candidates(tree, source)
  return vim.tbl_filter(function(fn)
    return not fn.is_static and fn.name ~= "main"
  end, ts.collect_functions(tree, source))
end

local function grep_command(names)
  local cmd = { "git", "grep", "-o", "-w", "-F", "--untracked" }
  for _, name in ipairs(names) do
    vim.list_extend(cmd, { "-e", name })
  end
  vim.list_extend(cmd, { "--", "*.c" })
  return cmd
end

-- The set of names mentioned in .c files other than `own` (relative to root).
local function parse_grep(stdout, own)
  local used = {}
  for line in vim.gsplit(stdout or "", "\n", { plain = true, trimempty = true }) do
    local file, name = line:match("^(.*):([%w_]+)$")
    if file and file ~= own then
      used[name] = true
    end
  end
  return used
end

-- Which of names other .c files of the project mention: calls on_done(set),
-- or runs synchronously and returns the set when on_done is nil.
function M.used_elsewhere(root, path, names, on_done)
  local own = util.relative(path, root) or path
  if #names == 0 then
    if on_done then
      return on_done({})
    end
    return {}
  end
  if not on_done then
    return parse_grep(vim.system(grep_command(names), { cwd = root, text = true }):wait().stdout, own)
  end
  vim.system(grep_command(names), { cwd = root, text = true }, function(result)
    vim.schedule(function()
      on_done(parse_grep(result.stdout, own))
    end)
  end)
end

-- Last search per file: { tick, used }. The set stays usable while the
-- buffer changes; a new search runs on save.
M.cache = {}

-- The names other files use, for buf, from the last search (nil before
-- the first one).
function M.cached_used(buf)
  local entry = M.cache[vim.api.nvim_buf_get_name(buf)]
  return entry and entry.used
end

-- Searches again for buf unless its last search was at the same changedtick.
-- on_done runs when the result is in the cache.
function M.search(buf, root, on_done)
  local path = vim.api.nvim_buf_get_name(buf)
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  local entry = M.cache[path]
  if entry and entry.tick == tick then
    if on_done then
      on_done()
    end
    return
  end
  local tree = ts.root(buf)
  if not tree then
    return
  end
  local names = vim.tbl_map(function(fn)
    return fn.name
  end, M.candidates(tree, buf))
  M.used_elsewhere(root, path, names, function(used)
    M.cache[path] = { tick = tick, used = used }
    if on_done then
      on_done()
    end
  end)
end

function M.run(src, path, ctx)
  local used = ctx.static_used
  if not used or not path:match("%.c$") then
    return {}
  end
  local result = {}
  for _, fn in ipairs(M.candidates(ctx.tree, src)) do
    if not used[fn.name] then
      local name = fn.declarator:field("declarator")[1]
      local row, col, _, end_col = name:range()
      result[#result + 1] = {
        lnum = row,
        col = col,
        end_lnum = row,
        end_col = end_col,
        message = "C-A4 only used in this file",
        code = "C-A4",
      }
    end
  end
  return result
end

return M
