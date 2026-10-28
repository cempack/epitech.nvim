-- :EpitechSyncHeader keeps the project header's prototypes in step with the
-- non-static functions of the .c files that feed it (C-H1, C-A4), without
-- any marker in the header. A prototype is updated where it is, a new one
-- goes after the header's last synced prototype, and only prototypes the
-- sync wrote or adopted before (remembered in the project state, outside
-- the repository) are removed when their function is gone: a prototype the
-- user wrote for a function that isn't there yet stays.
local header = require("epitech.header")
local project = require("epitech.project")
local ts = require("epitech.ts")
local util = require("epitech.util")

local M = {}

-- The markers earlier versions wrote around the prototypes: the next sync
-- removes them, with the /* file.c */ lines between them.
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

-- Removes the markers of earlier versions from buf; returns the names of
-- the prototypes they held, which the sync owns.
local function drop_markers(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local first, last = marker_rows(lines)
  local owned = {}
  if not first then
    return owned
  end
  local src = table.concat(lines, "\n")
  local tree = ts.parse_string(src)
  for _, proto in ipairs(tree and ts.collect_prototypes(tree, src) or {}) do
    if proto.row + 1 > first and proto.row + 1 < last then
      owned[proto.name] = true
    end
  end
  for i = last, first, -1 do
    local line = vim.trim(lines[i])
    if i == first or i == last or line:match("^/%*%s*[%w_./-]+%.c%s*%*/$") then
      table.remove(lines, i)
    end
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return owned
end

local function alone(lines, node)
  local start_row, start_col, end_row, end_col = node:range()
  return not lines[start_row + 1]:sub(1, start_col):match("%S") and not lines[end_row + 1]:sub(end_col + 1):match("%S")
end

-- Updates the header in buf from groups. owned is the set of names the
-- sync wrote or adopted on earlier runs. Returns the counts and the new
-- owned set, or nil and a reason when the header has no include guard.
function M.update(buf, groups, owned)
  owned = vim.deepcopy(owned or {})
  if not select(3, header.guard_rows(vim.api.nvim_buf_get_lines(buf, 0, -1, false))) then
    return nil, "it has no include guard (:EpitechGuard adds one)"
  end
  local migrated = false
  for name in pairs(drop_markers(buf)) do
    owned[name] = true
    migrated = true
  end

  local wanted, order = {}, {}
  for _, group in ipairs(groups) do
    for _, prototype in ipairs(group.prototypes) do
      wanted[prototype.name] = prototype.text
      order[#order + 1] = prototype.name
    end
  end

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local src = table.concat(lines, "\n")
  local tree = ts.parse_string(src)
  local counts = { added = 0, changed = 0, removed = 0 }
  local edits, seen, new_owned = {}, {}, {}
  for _, proto in ipairs(tree and ts.collect_prototypes(tree, src) or {}) do
    local name = proto.name
    local text = ts.text(proto.node, src)
    if wanted[name] then
      new_owned[name] = true
      if seen[name] then
        -- the same prototype twice: the later one goes
        if alone(lines, proto.node) then
          edits[#edits + 1] = { node = proto.node, delete = true }
        end
      else
        seen[name] = true
        if squeeze(text) ~= squeeze(wanted[name]) then
          counts.changed = counts.changed + 1
          edits[#edits + 1] = { node = proto.node, text = wanted[name] }
        end
      end
    elseif owned[name] and alone(lines, proto.node) then
      counts.removed = counts.removed + 1
      edits[#edits + 1] = { node = proto.node, delete = true }
    end
  end
  local added = vim.tbl_filter(function(name)
    return not seen[name]
  end, order)
  counts.added = #added

  table.sort(edits, function(a, b)
    return a.node:start() > b.node:start()
  end)
  for _, edit in ipairs(edits) do
    local start_row, start_col, end_row, end_col = edit.node:range()
    if edit.delete then
      vim.api.nvim_buf_set_lines(buf, start_row, end_row + 1, false, {})
      -- No double blank line where it was.
      local around = vim.api.nvim_buf_get_lines(buf, math.max(start_row - 1, 0), start_row + 1, false)
      if start_row > 0 and #around == 2 and around[1]:match("^%s*$") and around[2]:match("^%s*$") then
        vim.api.nvim_buf_set_lines(buf, start_row, start_row + 1, false, {})
      end
    else
      vim.api.nvim_buf_set_text(buf, start_row, start_col, end_row, end_col, { edit.text })
    end
  end

  if #added > 0 then
    -- After the last prototype the sync keeps, else at the end of the guard.
    lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    src = table.concat(lines, "\n")
    tree = ts.parse_string(src)
    local after
    for _, proto in ipairs(tree and ts.collect_prototypes(tree, src) or {}) do
      if new_owned[proto.name] then
        after = select(3, proto.node:range()) + 1
      end
    end
    local texts = vim.tbl_map(function(name)
      return wanted[name]
    end, added)
    if after then
      vim.api.nvim_buf_set_lines(buf, after, after, false, texts)
    else
      local _, _, endif = header.guard_rows(lines)
      local at = endif - 1
      while at > 0 and lines[at]:match("^%s*$") do
        at = at - 1
      end
      vim.api.nvim_buf_set_lines(buf, at, endif - 1, false, vim.list_extend(vim.list_extend({ "" }, texts), { "" }))
    end
    for _, name in ipairs(added) do
      new_owned[name] = true
    end
  end

  if (#edits > 0 or #added > 0 or migrated) and vim.fn.executable("clang-format") == 1 then
    require("epitech.format").format_buffer(buf)
  end
  return counts, new_owned
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
        local owned = {}
        for _, name in ipairs(project.state(root).header_synced or {}) do
          owned[name] = true
        end
        local result, detail = M.update(buf, groups, owned)
        counts, reason = result, not result and detail or nil
        if result then
          local state = project.state(root)
          state.header_synced = vim.tbl_keys(detail)
          table.sort(state.header_synced)
          project.save_state(root, state)
        end
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
