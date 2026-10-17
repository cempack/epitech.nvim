-- :EpitechSyncHeader keeps the project header's prototypes in step with the
-- non-static functions of the .c files that feed it (C-H1, C-A4). They live
-- in a marked block inside the include guard; the rest of the header is the
-- user's.
local config = require("epitech.config")
local header = require("epitech.header")
local project = require("epitech.project")
local ts = require("epitech.ts")
local util = require("epitech.util")

local M = {}

M.BEGIN = "/* epitech.nvim: prototypes (:EpitechSyncHeader) */"
M.END = "/* epitech.nvim: end of prototypes */"

local function collapse(text)
  return vim.trim((text:gsub("%s+", " "):gsub("%( ", "("):gsub(" %)", ")")))
end

local function squeeze(text)
  return (text:gsub("%s+", ""))
end

-- The prototype of a definition: its text up to the end of its declarator,
-- whitespace collapsed, plus `;`.
function M.prototype(fn, source)
  local start_row, start_col = fn.node:range()
  local _, _, end_row, end_col = fn.node:field("declarator")[1]:range()
  local lines = vim.split(source, "\n", { plain = true })
  local parts = {}
  for row = start_row, end_row do
    local line = lines[row + 1]
    local first = row == start_row and start_col + 1 or 1
    local last = row == end_row and end_col or #line
    parts[#parts + 1] = line:sub(first, last)
  end
  return collapse(table.concat(parts, " ")) .. ";"
end

-- { file, prototypes = { { name, text } } } for each .c file under dirs
-- (tracked, or new and not ignored), sorted by path; static functions and
-- main left out.
function M.collect(root, dirs)
  local pathspecs = vim.tbl_map(function(dir)
    return dir:gsub("/$", "") .. "/*.c"
  end, dirs)
  -- New files (from :EpitechNewFile or :EpitechMoveTo) count before git add.
  local files = project.files(root, pathspecs, { untracked = true }) or {}
  table.sort(files)
  local result, seen = {}, {}
  for _, file in ipairs(files) do
    local src = table.concat(util.read_lines(root .. "/" .. file), "\n")
    local tree = ts.parse_string(src)
    local prototypes = {}
    for _, fn in ipairs(tree and ts.collect_functions(tree, src) or {}) do
      if not fn.is_static and fn.name ~= "main" and not seen[fn.name] then
        seen[fn.name] = true
        prototypes[#prototypes + 1] = { name = fn.name, text = M.prototype(fn, src) }
      end
    end
    if #prototypes > 0 then
      result[#result + 1] = { file = file, prototypes = prototypes }
    end
  end
  return result
end

-- The lines of the block.
function M.block(groups, group_by_file)
  local lines = { M.BEGIN }
  for _, group in ipairs(groups) do
    if group_by_file then
      lines[#lines + 1] = "/* " .. group.file .. " */"
    end
    for _, prototype in ipairs(group.prototypes) do
      lines[#lines + 1] = prototype.text
    end
  end
  lines[#lines + 1] = M.END
  return lines
end

local function marker_rows(lines)
  local first, last
  for i, line in ipairs(lines) do
    if vim.trim(line) == M.BEGIN then
      first = i
    elseif first and vim.trim(line) == M.END then
      last = i
      break
    end
  end
  return first, last
end

-- Updates the header in buf from groups. Returns the counts, or nil and a
-- reason when the header has no include guard.
function M.update(buf, groups, group_by_file)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local src = table.concat(lines, "\n")
  local first, last = marker_rows(lines)
  local _, _, endif = header.guard_rows(lines)
  if not endif then
    return nil, "it has no include guard (:EpitechGuard adds one)"
  end

  local wanted = {}
  for _, group in ipairs(groups) do
    for _, prototype in ipairs(group.prototypes) do
      wanted[prototype.name] = prototype.text
    end
  end

  -- What the header declares now: in the block, and elsewhere (adopted on
  -- the first run, duplicates later).
  local old, in_block, stray = {}, {}, {}
  local tree = ts.parse_string(src)
  for _, proto in ipairs(tree and ts.collect_prototypes(tree, src) or {}) do
    local start_row, start_col, end_row, end_col = proto.node:range()
    local inside = first and start_row + 1 > first and end_row + 1 < last
    if inside then
      in_block[proto.name] = true
      old[proto.name] = ts.text(proto.node, src)
    elseif wanted[proto.name] then
      old[proto.name] = old[proto.name] or ts.text(proto.node, src)
      local alone = not lines[start_row + 1]:sub(1, start_col):match("%S")
        and not lines[end_row + 1]:sub(end_col + 1):match("%S")
      if alone then
        stray[#stray + 1] = { start_row, end_row }
      end
    end
  end

  local counts = { added = 0, changed = 0, removed = 0 }
  for name, text in pairs(wanted) do
    if not old[name] then
      counts.added = counts.added + 1
    elseif squeeze(old[name]) ~= squeeze(text) then
      counts.changed = counts.changed + 1
    end
  end
  for name in pairs(in_block) do
    if not wanted[name] then
      counts.removed = counts.removed + 1
    end
  end
  if counts.added + counts.changed + counts.removed == 0 and #stray == 0 and first then
    return counts
  end

  local block = M.block(groups, group_by_file)
  if first then
    vim.api.nvim_buf_set_lines(buf, first - 1, last, false, block)
  else
    local at = endif - 1
    while at > 0 and lines[at]:match("^%s*$") do
      at = at - 1
    end
    vim.api.nvim_buf_set_lines(buf, at, endif - 1, false, vim.list_extend(vim.list_extend({ "" }, block), { "" }))
  end
  table.sort(stray, function(a, b)
    return a[1] > b[1]
  end)
  for _, rows in ipairs(stray) do
    vim.api.nvim_buf_set_lines(buf, rows[1], rows[2] + 1, false, {})
  end
  if vim.fn.executable("clang-format") == 1 then
    require("epitech.format").format_buffer(buf)
  end
  return counts
end

function M.summary(counts)
  return ("%d added · %d changed · %d removed"):format(counts.added, counts.changed, counts.removed)
end

-- Syncs the project at root, asking for the header and its source
-- directories the first time. on_done (optional) receives the summary, or
-- nil when nothing happened.
function M.run(root, on_done)
  on_done = on_done or function() end
  project.project_header(root, function(header_path)
    if not header_path then
      return on_done(nil)
    end
    local function sync(dirs)
      local groups = M.collect(root, dirs)
      local counts, reason
      local ok, err = pcall(util.edit_file, header_path, function(buf)
        if vim.api.nvim_buf_line_count(buf) <= 1 and vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == "" then
          local name = project.name(root)
          vim.api.nvim_buf_set_lines(buf, 0, -1, false, header.new_header(header_path, name, "Declarations for " .. name))
        end
        counts, reason = M.update(buf, groups, config.options.header_sync.group_by_file)
      end)
      if not ok then
        util.notify("Header sync failed: " .. tostring(err), vim.log.levels.ERROR)
        return on_done(nil)
      end
      local relative = util.relative(header_path, root) or header_path
      if not counts then
        util.notify(("Can't sync %s: %s"):format(relative, reason), vim.log.levels.WARN)
        return on_done(nil)
      end
      local summary = M.summary(counts)
      util.notify(relative .. ": " .. summary)
      on_done(summary)
    end

    local state = project.state(root)
    if state.header_dirs then
      return sync(state.header_dirs)
    end
    vim.ui.input({ prompt = "Directories whose functions go in the header: ", default = "src" }, function(input)
      if not input or vim.trim(input) == "" then
        return on_done(nil)
      end
      local dirs = vim.split(vim.trim(input), "[%s,]+")
      state = project.state(root)
      state.header_dirs = dirs
      project.save_state(root, state)
      sync(dirs)
    end)
  end)
end

return M
