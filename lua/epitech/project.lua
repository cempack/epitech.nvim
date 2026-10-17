-- Project-level facts: root, name, compile flags, header choice, and the
-- per-project state, which lives in Neovim's data directory because C-O1
-- forbids unnecessary files in the student's repository.
local header = require("epitech.header")

local M = {}

local function absolute(path)
  return (vim.fs.normalize(vim.fn.fnamemodify(path, ":p")):gsub("(.)/$", "%1"))
end

-- The project root of a buffer (0 for the current one) or a file path: the
-- nearest directory with .git, else with a Makefile, else the file's own
-- directory (the current directory for an unnamed buffer).
function M.root(source)
  source = source or 0
  local root = vim.fs.root(source, { ".git", "Makefile" })
  if root then
    return absolute(root)
  end
  local name = type(source) == "number" and vim.api.nvim_buf_get_name(source) or source
  if name == "" then
    return absolute(vim.fn.getcwd())
  end
  return vim.fs.dirname(absolute(name))
end

-- Tracked files under root matching the git pathspecs (e.g. "*.c"), relative
-- to root, or nil when root isn't inside a git repository.
function M.files(root, pathspecs)
  local cmd = { "git", "ls-files", "--" }
  vim.list_extend(cmd, pathspecs or {})
  local result = vim.system(cmd, { cwd = root, text = true }):wait()
  if result.code ~= 0 then
    return nil
  end
  return vim.split(result.stdout, "\n", { trimempty = true })
end

local function read_head(path, count)
  local ok, lines = pcall(vim.fn.readfile, path, "", count)
  return ok and lines or {}
end

-- NAME from the Makefile, else the project line of an Epitech header (the
-- Makefile's, then the first C file's that has one), else the directory name.
function M.name(root)
  local makefile = root .. "/Makefile"
  if vim.fn.filereadable(makefile) == 1 then
    local lines = vim.fn.readfile(makefile)
    for _, line in ipairs(lines) do
      local name = line:gsub("%s*#.*$", ""):match("^%s*NAME%s*[:?]?=%s*(%S+)%s*$")
      if name and not name:find("$", 1, true) then
        return name
      end
    end
    local _, _, project = header.existing_header(vim.list_slice(lines, 1, 8))
    if project and project ~= "" then
      return project
    end
  end

  local sources = M.files(root, { "*.c", "*.h" })
  if not sources then
    sources = vim.fs.find(function(name)
      return name:match("%.[ch]$") ~= nil
    end, { path = root, type = "file", limit = 20 })
  end
  for i = 1, math.min(#sources, 20) do
    local path = sources[i]:sub(1, 1) == "/" and sources[i] or root .. "/" .. sources[i]
    local _, _, project = header.existing_header(read_head(path, 8))
    if project and project ~= "" then
      return project
    end
  end
  return vim.fs.basename(root)
end

-- Splits a shell command line into words, handling quotes and backslashes.
local function shell_words(command)
  local words, word, quote, i = {}, nil, nil, 1
  while i <= #command do
    local c = command:sub(i, i)
    if quote then
      if c == quote then
        quote = nil
      elseif c == "\\" and quote == '"' and i < #command then
        i = i + 1
        word = word .. command:sub(i, i)
      else
        word = word .. c
      end
    elseif c == "'" or c == '"' then
      quote = c
      word = word or ""
    elseif c == "\\" and i < #command then
      i = i + 1
      word = (word or "") .. command:sub(i, i)
    elseif c:match("%s") then
      if word then
        words[#words + 1] = word
        word = nil
      end
    else
      word = (word or "") .. c
    end
    i = i + 1
  end
  if word then
    words[#words + 1] = word
  end
  return words
end

local database_cache = {}

local function read_database(root)
  for _, path in ipairs({ root .. "/compile_commands.json", root .. "/build/compile_commands.json" }) do
    local stat = vim.uv.fs_stat(path)
    if stat then
      local cached = database_cache[path]
      if cached and cached.mtime == stat.mtime.sec and cached.size == stat.size then
        return cached.entries
      end
      local ok, entries = pcall(vim.json.decode, table.concat(vim.fn.readfile(path), "\n"))
      if ok and type(entries) == "table" and vim.islist(entries) then
        database_cache[path] = { mtime = stat.mtime.sec, size = stat.size, entries = entries }
        return entries
      end
    end
  end
end

-- Flags from one compile_commands.json entry that matter to epiclang: include
-- paths (made absolute), -D and -std=. -c, -o <x>, the file and every other
-- flag are dropped.
local function entry_flags(entry)
  local args = entry.arguments or shell_words(entry.command or "")
  local directory = entry.directory or "."
  local function path(value)
    return value:sub(1, 1) == "/" and value or vim.fs.normalize(directory .. "/" .. value)
  end

  local flags = {}
  local i = 2
  while i <= #args do
    local arg = args[i]
    if (arg == "-I" or arg == "-isystem" or arg == "-D") and args[i + 1] then
      if arg == "-I" then
        flags[#flags + 1] = "-I" .. path(args[i + 1])
      elseif arg == "-isystem" then
        vim.list_extend(flags, { "-isystem", path(args[i + 1]) })
      else
        flags[#flags + 1] = "-D" .. args[i + 1]
      end
      i = i + 1
    elseif arg == "-o" then
      i = i + 1
    elseif vim.startswith(arg, "-isystem") then
      vim.list_extend(flags, { "-isystem", path(arg:sub(9)) })
    elseif vim.startswith(arg, "-I") then
      flags[#flags + 1] = "-I" .. path(arg:sub(3))
    elseif vim.startswith(arg, "-D") or vim.startswith(arg, "-std=") then
      flags[#flags + 1] = arg
    end
    i = i + 1
  end
  return flags
end

-- Compiler flags epiclang needs to resolve the project's includes for file:
-- from compile_commands.json when there is one (the file's own entry, else
-- the first one, since headers have none), else -I<root>/include when that
-- directory exists, plus -I<root>.
function M.include_flags(root, file)
  local entries = read_database(root)
  if entries and #entries > 0 then
    local target = file and absolute(file)
    local chosen = entries[1]
    for _, entry in ipairs(entries) do
      local entry_file = entry.file
      if entry_file and entry_file:sub(1, 1) ~= "/" then
        entry_file = (entry.directory or root) .. "/" .. entry_file
      end
      if target and entry_file and absolute(entry_file) == target then
        chosen = entry
        break
      end
    end
    return entry_flags(chosen)
  end

  local flags = {}
  if vim.fn.isdirectory(root .. "/include") == 1 then
    flags[#flags + 1] = "-I" .. root .. "/include"
  end
  flags[#flags + 1] = "-I" .. root
  return flags
end

function M.state_file()
  return vim.fn.stdpath("data") .. "/epitech.nvim/projects.json"
end

local function read_states()
  local path = M.state_file()
  if vim.fn.filereadable(path) == 0 then
    return {}
  end
  local ok, states = pcall(vim.json.decode, table.concat(vim.fn.readfile(path), "\n"),
    { luanil = { object = true, array = true } })
  return ok and type(states) == "table" and states or {}
end

-- What the plugin remembers about the project at root (a table, empty at
-- first).
function M.state(root)
  return read_states()[absolute(root)] or {}
end

-- Replaces what the plugin remembers about the project at root.
function M.save_state(root, tbl)
  local states = read_states()
  states[absolute(root)] = tbl
  local path = M.state_file()
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  vim.fn.writefile({ vim.json.encode(states) }, path)
end

-- Calls callback with the absolute path of the project's main header: the
-- remembered choice, else include/<name>.h, else the only .h in include/,
-- else the user's pick (remembered), or nil when the user cancels. The
-- callback may run before this function returns.
function M.project_header(root, callback)
  root = absolute(root)
  local state = M.state(root)
  if state.header and vim.fn.filereadable(root .. "/" .. state.header) == 1 then
    return callback(root .. "/" .. state.header)
  end

  local name = M.name(root)
  if vim.fn.filereadable(root .. "/include/" .. name .. ".h") == 1 then
    return callback(root .. "/include/" .. name .. ".h")
  end
  local in_include = vim.fn.glob(root .. "/include/*.h", false, true)
  if #in_include == 1 then
    return callback(absolute(in_include[1]))
  end

  local choices = M.files(root, { "*.h" })
  if not choices then
    choices = vim.tbl_map(function(path)
      return path:sub(#root + 2)
    end, vim.fs.find(function(file)
      return file:match("%.h$") ~= nil
    end, { path = root, type = "file", limit = math.huge }))
  end
  table.sort(choices)
  if not vim.list_contains(choices, "include/" .. name .. ".h") then
    choices[#choices + 1] = "include/" .. name .. ".h"
  end
  vim.ui.select(choices, { prompt = "Project header" }, function(choice)
    if not choice then
      return callback(nil)
    end
    state.header = choice
    M.save_state(root, state)
    callback(root .. "/" .. choice)
  end)
end

return M
