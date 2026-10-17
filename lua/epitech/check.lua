-- The whole-project check: Banana on every tracked .c and .h file, the
-- plugin's hints and Makefile checks, and the repository rules (C-O1, C-O2,
-- C-O4), in one list sorted by severity. :EpitechCheck shows it in Trouble
-- or the quickfix list; scripts/check.lua prints it for CI and the git hook.
local banana = require("epitech.banana")
local config = require("epitech.config")
local project = require("epitech.project")
local rules = require("epitech.rules")
local util = require("epitech.util")

local M = {}

local LEVELS = { "fatal", "major", "minor", "info", "hint" }
local RANK = { fatal = 1, major = 2, minor = 3, info = 4, hint = 5 }
local QF_TYPE = { fatal = "E", major = "E", minor = "W", info = "I", hint = "N" }

-- C-O1: compiled, temporary and debugging files.
M.unwanted = { "*.o", "*.a", "*.so", "*~", "#*#", "vgcore.*", "*.gcda", "*.gcno" }
-- C-O2: C sources with another extension.
M.foreign = { "cpp", "cc", "cxx", "hpp", "hh", "inl", "inc" }
-- C-O4 doesn't apply to these.
M.name_exceptions = { "Makefile", "README.md", "LICENSE" }

local function capitalize(text)
  return text:sub(1, 1):upper() .. text:sub(2)
end

local function entry(path, lnum, col, level, code, message)
  return { path = path, lnum = lnum, col = col, level = level, code = code, message = (message:gsub("^C%-%u%d+ ", "")) }
end

-- The C-O1 pattern a tracked file matches, if any.
function M.unwanted_pattern(file)
  local name = vim.fs.basename(file)
  for _, pattern in ipairs(M.unwanted) do
    if vim.glob.to_lpeg(pattern):match(name) then
      return pattern
    end
  end
end

-- Repository entries for the tracked files: C-O1, C-O2 and C-O4.
function M.repository(files)
  local result = {}
  for _, file in ipairs(files) do
    local unwanted = M.unwanted_pattern(file)
    local extension = file:match("%.([^./]+)$")
    if unwanted then
      result[#result + 1] = entry(file, 1, 1, "major", "C-O1", "compiled or temporary file in the repository")
    elseif extension and vim.list_contains(M.foreign, extension) then
      result[#result + 1] = entry(file, 1, 1, "major", "C-O2", "C sources use the .c and .h extensions")
    end
    if not vim.list_contains(M.name_exceptions, file) and not unwanted then
      local segments = vim.split(file, "/", { plain = true })
      for i, segment in ipairs(segments) do
        if segment:sub(1, 1) == "." then
          break
        end
        local name = i == #segments and segment:gsub("%.[^.]+$", "") or segment
        if not name:match("^[a-z0-9_]+$") then
          result[#result + 1] = entry(file, 1, 1, "minor", "C-O4",
            ("%s isn't snake_case"):format(i == #segments and vim.fs.basename(file) or segment .. "/"))
          break
        end
      end
    end
  end
  return result
end

-- Runs fn(item, done) for each item, at most `limit` at a time, then
-- on_done().
local function each_limited(items, limit, fn, on_done)
  local next_index, running, finished = 1, 0, 0
  if #items == 0 then
    return on_done()
  end
  local function start()
    while running < limit and next_index <= #items do
      local item = items[next_index]
      next_index = next_index + 1
      running = running + 1
      fn(item, function()
        running = running - 1
        finished = finished + 1
        if finished == #items then
          on_done()
        else
          start()
        end
      end)
    end
  end
  start()
end

-- Banana's entries for the files (relative to root), deduplicated on file,
-- line, column and code: a header's entries come back for every file
-- including it.
local function run_banana(root, files, on_done)
  local results, seen = {}, {}
  each_limited(files, math.max(vim.uv.available_parallelism(), 1), function(file, done)
    local path = root .. "/" .. file
    local cmd = banana.command()
    vim.list_extend(cmd, project.include_flags(root, path))
    cmd[#cmd + 1] = path
    local ok = pcall(vim.system, cmd, { cwd = root, text = true }, function(result)
      vim.schedule(function()
        for _, d in ipairs(banana.parse(result.stderr, nil, root)) do
          local relative = util.relative(d.user_data.path, root)
          local key = table.concat({ relative or "", d.lnum, d.col, d.code }, ":")
          if relative and not seen[key] then
            seen[key] = true
            local message = d.message:gsub("^FATAL: ", "")
            results[#results + 1] = entry(relative, d.lnum + 1, d.col + 1, d.user_data.level, d.code, message)
          end
        end
        done()
      end)
    end)
    if not ok then
      done()
    end
  end, function()
    on_done(results)
  end)
end

-- The plugin's hints for a .c or .h file, minus what Banana reports on the
-- same line.
local function file_hints(root, file, banana_entries)
  local path = root .. "/" .. file
  -- From disk, like Banana, so the lines agree.
  local src = table.concat(vim.fn.readfile(path), "\n")
  local tree = require("epitech.ts").parse_string(src)
  if not tree then
    return {}
  end
  local ctx = { root = root, tree = tree }
  local static = require("epitech.hints.static")
  if config.options.hints.static and file:match("%.c$") then
    local names = vim.tbl_map(function(fn)
      return fn.name
    end, static.candidates(tree, src))
    ctx.static_used = static.used_elsewhere(root, path, names)
  end
  local hints = require("epitech.hints")
  local reported = vim.tbl_map(function(e)
    return { lnum = e.lnum - 1, code = e.code }
  end, vim.tbl_filter(function(e)
    return e.path == file
  end, banana_entries))
  local result = {}
  for _, d in ipairs(hints.dedup(hints.collect(src, path, ctx), reported)) do
    result[#result + 1] = entry(file, d.lnum + 1, d.col + 1, "hint", d.code, d.message)
  end
  return result
end

-- The Makefile checks for a tracked Makefile, at each rule's own level.
local function makefile_entries(root, file)
  local fd = io.open(root .. "/" .. file, "rb")
  if not fd then
    return {}
  end
  local src = fd:read("*a")
  fd:close()
  local result = {}
  for _, d in ipairs(require("epitech.hints.makefile").run(src, file)) do
    local rule = rules.by_code[d.code]
    result[#result + 1] = entry(file, d.lnum + 1, d.col + 1, rule and rule.severity or "minor", d.code, d.message)
  end
  return result
end

-- "Epitech check: 0 fatal · 3 major · 5 minor · 2 info · 4 hints"
function M.title(counts)
  return ("Epitech check: %d fatal · %d major · %d minor · %d info · %d hints"):format(counts.fatal, counts.major,
    counts.minor, counts.info, counts.hint)
end

function M.sort(entries)
  table.sort(entries, function(a, b)
    if RANK[a.level] ~= RANK[b.level] then
      return RANK[a.level] < RANK[b.level]
    elseif a.path ~= b.path then
      return a.path < b.path
    elseif a.lnum ~= b.lnum then
      return a.lnum < b.lnum
    end
    return a.col < b.col
  end)
  return entries
end

-- Checks the project at root. on_done receives { entries, counts, title,
-- banana } (banana is false when epiclang is missing).
function M.run(root, on_done)
  local files = project.files(root, {})
  if not files then
    return on_done({ error = root .. " isn't a git repository" })
  end
  local sources = vim.tbl_filter(function(file)
    return file:match("%.[ch]$") ~= nil
  end, files)

  local function finish(banana_entries, banana_ran)
    local entries = M.repository(files)
    vim.list_extend(entries, banana_entries)
    if config.options.hints.enabled then
      for _, file in ipairs(sources) do
        vim.list_extend(entries, file_hints(root, file, banana_entries))
      end
    end
    if config.options.makefile.enabled then
      for _, file in ipairs(files) do
        if vim.fs.basename(file) == "Makefile" then
          vim.list_extend(entries, makefile_entries(root, file))
        end
      end
    end
    M.sort(entries)
    local counts = { fatal = 0, major = 0, minor = 0, info = 0, hint = 0 }
    for _, e in ipairs(entries) do
      counts[e.level] = counts[e.level] + 1
    end
    on_done({ entries = entries, counts = counts, title = M.title(counts), banana = banana_ran })
  end

  if vim.fn.executable(config.options.diagnostics.cmd) == 1 then
    run_banana(root, sources, function(results)
      finish(results, true)
    end)
  else
    finish({}, false)
  end
end

-- A line for CI: path:line:col: [Level] message (CODE)
function M.format_entry(e)
  return ("%s:%d:%d: [%s] %s (%s)"):format(e.path, e.lnum, e.col, capitalize(e.level), e.message, e.code)
end

-- Whether any entry has a level in check.fail_on (hints never fail).
function M.failures(result)
  local failing = {}
  for _, level in ipairs(config.options.check.fail_on) do
    if result.counts[level] and result.counts[level] > 0 then
      failing[#failing + 1] = ("%d %s"):format(result.counts[level], capitalize(level))
    end
  end
  return failing
end

-- :EpitechCheck: the list in Trouble when it's installed, else the
-- quickfix list.
function M.open(root)
  root = root or project.root(0)
  util.notify("Checking " .. vim.fs.basename(root) .. "…")
  M.run(root, function(result)
    if result.error then
      return util.notify(result.error, vim.log.levels.WARN)
    end
    if not result.banana then
      util.notify(config.options.diagnostics.cmd .. " not found: the check only covers the repository rules and hints",
        vim.log.levels.WARN)
    end
    local items = vim.tbl_map(function(e)
      return {
        filename = root .. "/" .. e.path,
        lnum = e.lnum,
        col = e.col,
        type = QF_TYPE[e.level],
        text = ("[%s] %s (%s)"):format(capitalize(e.level), e.message, e.code),
      }
    end, result.entries)
    vim.fn.setqflist({}, " ", { title = result.title, items = items })
    if vim.fn.exists(":Trouble") == 2 then
      vim.cmd("Trouble qflist open")
    else
      vim.cmd("botright copen")
    end
    util.notify(result.title)
  end)
end

-- :EpitechCheck untrack: git rm --cached on the C-O1 files and their
-- patterns added to .gitignore, after a confirmation.
function M.untrack(root, on_done)
  root = root or project.root(0)
  on_done = on_done or function() end
  local files = vim.tbl_filter(function(file)
    return M.unwanted_pattern(file) ~= nil
  end, project.files(root, {}) or {})
  if #files == 0 then
    util.notify("No compiled or temporary file is tracked")
    return on_done(false)
  end
  local yes = ("Untrack %d %s and ignore them"):format(#files, #files == 1 and "file" or "files")
  vim.ui.select({ yes, "Cancel" }, { prompt = "git rm --cached " .. table.concat(files, " ") }, function(choice)
    if choice ~= yes then
      return on_done(false)
    end
    local cmd = { "git", "rm", "--cached", "--quiet", "--" }
    vim.list_extend(cmd, files)
    local result = vim.system(cmd, { cwd = root, text = true }):wait()
    if result.code ~= 0 then
      util.notify("git rm failed: " .. (result.stderr or ""), vim.log.levels.ERROR)
      return on_done(false)
    end
    local ignore = util.read_lines(root .. "/.gitignore")
    for _, file in ipairs(files) do
      -- A .gitignore line starting with # is a comment.
      local pattern = M.unwanted_pattern(file):gsub("^#", "\\#")
      if not vim.list_contains(ignore, pattern) then
        ignore[#ignore + 1] = pattern
      end
    end
    vim.fn.writefile(ignore, root .. "/.gitignore")
    util.notify(("Untracked %s; .gitignore updated"):format(table.concat(files, ", ")))
    on_done(true)
  end)
end

M.LEVELS = LEVELS

return M
