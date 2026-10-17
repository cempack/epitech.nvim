-- :'<,'>EpitechMoveTo src/print_long.c moves the selected functions to
-- another file (C-O3: at most 10 functions per file), with the static
-- helpers only they use. A static helper both files need has to become
-- non-static, which counts against the 5 non-static functions per file, so
-- the user is asked first. Then the Makefile and the project header follow.
local header = require("epitech.header")
local makefile = require("epitech.makefile")
local project = require("epitech.project")
local ts = require("epitech.ts")
local util = require("epitech.util")

local M = {}

-- The names of this file's functions that fn mentions (calls or pointers).
local function mentions(fn, source, known)
  local result = {}
  local function walk(node)
    for child in node:iter_children() do
      if child:type() == "identifier" then
        local name = ts.text(child, source)
        if known[name] and name ~= fn.name then
          result[name] = true
        end
      elseif child:named_child_count() > 0 then
        walk(child)
      end
    end
  end
  walk(fn.body)
  return result
end

-- What moving the functions on rows first..last means:
-- { moved = { fn… } in file order, shared = { fn… } that must become
-- non-static, prototypes = { node… } static prototypes of moved functions }.
function M.plan(buf, first, last)
  local functions = ts.functions(buf)
  local by_name, uses = {}, {}
  for _, fn in ipairs(functions) do
    by_name[fn.name] = fn
  end
  for _, fn in ipairs(functions) do
    uses[fn.name] = mentions(fn, buf, by_name)
  end

  local moved = {}
  for _, fn in ipairs(functions) do
    if fn.start_row <= last and fn.end_row >= first then
      moved[fn.name] = true
    end
  end
  if next(moved) == nil then
    return nil
  end
  local function users(name)
    local result = {}
    for user, used in pairs(uses) do
      if used[name] then
        result[#result + 1] = user
      end
    end
    return result
  end
  -- Static helpers only the moved functions use follow them.
  local changed = true
  while changed do
    changed = false
    for _, fn in ipairs(functions) do
      local who = users(fn.name)
      if fn.is_static and not moved[fn.name] and #who > 0 and vim.iter(who):all(function(user)
        return moved[user]
      end) then
        moved[fn.name] = true
        changed = true
      end
    end
  end

  local plan = { moved = {}, shared = {}, prototypes = {} }
  for _, fn in ipairs(functions) do
    local who = users(fn.name)
    local across = vim.iter(who):any(function(user)
      return moved[user] ~= moved[fn.name]
    end)
    if moved[fn.name] then
      plan.moved[#plan.moved + 1] = fn
    end
    if fn.is_static and across then
      plan.shared[#plan.shared + 1] = fn
    end
  end
  for _, proto in ipairs(ts.prototypes(buf)) do
    if moved[proto.name] and ts.has_storage_class(proto.node, buf, "static") then
      plan.prototypes[#plan.prototypes + 1] = proto.node
    end
  end
  return plan
end

-- The first row of a function, its comment block included.
local function top_row(node)
  local first = node
  local previous = node:prev_sibling()
  while previous and previous:type() == "comment" and select(3, previous:range()) + 1 >= first:range() do
    first = previous
    previous = previous:prev_sibling()
  end
  return (first:range())
end

local function without_static(lines)
  local result = vim.deepcopy(lines)
  for i, line in ipairs(result) do
    local stripped, count = line:gsub("^static%s+", "", 1)
    if count > 0 then
      result[i] = stripped
      break
    end
  end
  return result
end

-- Carries out a plan: returns the moved text (functions separated by one
-- blank line) and edits buf.
local function extract(buf, plan)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local shared = {}
  for _, fn in ipairs(plan.shared) do
    shared[fn.name] = true
  end
  local chunks, removals = {}, {}
  for _, fn in ipairs(plan.moved) do
    local start_row = top_row(fn.node)
    local chunk = vim.list_slice(lines, start_row + 1, fn.end_row + 1)
    chunks[#chunks + 1] = shared[fn.name] and without_static(chunk) or chunk
    removals[#removals + 1] = { start_row, fn.end_row }
  end
  for _, node in ipairs(plan.prototypes) do
    local start_row, _, end_row = node:range()
    removals[#removals + 1] = { start_row, end_row }
  end
  -- Shared helpers that stay lose their static.
  local edits = {}
  for _, fn in ipairs(plan.shared) do
    if not vim.list_contains(plan.moved, fn) then
      edits[#edits + 1] = fn.start_row
    end
  end
  table.sort(removals, function(a, b)
    return a[1] > b[1]
  end)
  for _, row in ipairs(edits) do
    local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
    vim.api.nvim_buf_set_lines(buf, row, row + 1, false, { (line:gsub("^static%s+", "", 1)) })
  end
  for _, removal in ipairs(removals) do
    local start_row, end_row = removal[1], removal[2]
    local current = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    -- Keep exactly one blank line between what's left (C-G2).
    if (current[end_row + 2] or ""):match("^%s*$") and (start_row == 0 or current[start_row]:match("^%s*$")) then
      end_row = end_row + 1
    end
    vim.api.nvim_buf_set_lines(buf, start_row, end_row + 1, false, {})
  end
  local current = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  while #current > 1 and current[#current] == "" do
    vim.api.nvim_buf_set_lines(buf, #current - 1, #current, false, {})
    current = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  end
  local text = {}
  for i, chunk in ipairs(chunks) do
    if i > 1 then
      text[#text + 1] = ""
    end
    vim.list_extend(text, chunk)
  end
  return text, vim.tbl_filter(function(line)
    return line:match("^%s*#%s*include") ~= nil
  end, lines)
end

-- Writes the moved functions to target: a new file gets the Epitech header
-- and the source's #include lines; an existing one gets them appended, and
-- the includes it lacks.
local function write_target(target, root, text, includes, description)
  util.edit_file(target, function(buf)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    if #lines <= 1 and (lines[1] or "") == "" then
      local name = project.name(root)
      lines = header.header_lines(header.comment_styles.c, name, description, os.date("%Y"))
      lines[#lines + 1] = ""
      vim.list_extend(lines, includes)
      if #includes > 0 then
        lines[#lines + 1] = ""
      end
      vim.list_extend(lines, text)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      return
    end
    while #lines > 0 and lines[#lines] == "" do
      table.remove(lines)
    end
    lines[#lines + 1] = ""
    vim.list_extend(lines, text)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    for _, include in ipairs(includes) do
      local name = include:match('#%s*include%s*"(.-)"')
      if name then
        util.ensure_include(buf, name)
      elseif not vim.list_contains(lines, include) then
        local last = 0
        for i, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
          if line:match("^%s*#%s*include") then
            last = i
          end
        end
        vim.api.nvim_buf_set_lines(buf, last, last, false, { include })
      end
    end
  end)
end

-- :'<,'>EpitechMoveTo <path>. on_done (optional) runs once everything,
-- header sync included, is done, with the target path.
function M.move_to(path, first, last, buf, on_done)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  local root = project.root(buf)
  local target = path:sub(1, 1) == "/" and path or root .. "/" .. path
  local relative = util.relative(target, root) or path
  if not target:match("%.c$") then
    return util.notify("Move functions to a .c file", vim.log.levels.WARN)
  end
  if util.normalize(target) == util.normalize(vim.api.nvim_buf_get_name(buf)) then
    return util.notify("That's this file", vim.log.levels.WARN)
  end
  local plan = M.plan(buf, first, last)
  if not plan then
    return util.notify("Select the functions to move", vim.log.levels.WARN)
  end

  local function apply(description)
    local text, includes = extract(buf, plan)
    write_target(target, root, text, includes, description)
    makefile.add_source(root, relative)
    local names = vim.tbl_map(function(fn)
      return fn.name
    end, plan.moved)
    util.notify(("Moved %s to %s"):format(table.concat(names, ", "), relative))
    require("epitech.header_sync").run(root, function()
      if on_done then
        on_done(target)
      end
    end)
  end
  local function ask_description()
    if vim.fn.filereadable(target) == 1 or util.loaded_buffer(target) then
      return apply(nil)
    end
    vim.ui.input({ prompt = "Description of " .. relative .. ": " }, function(description)
      if description and description ~= "" then
        apply(description)
      end
    end)
  end

  if #plan.shared == 0 then
    return ask_description()
  end
  local names = table.concat(vim.tbl_map(function(fn)
    return fn.name
  end, plan.shared), ", ")
  local yes = "Make " .. names .. " non-static"
  vim.ui.select({ yes, "Cancel" }, {
    prompt = names .. " would be used by both files, so it can't stay static (C-O3 allows 5 non-static functions"
      .. " per file)",
  }, function(choice)
    if choice == yes then
      ask_description()
    end
  end)
end

return M
