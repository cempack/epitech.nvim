-- Live Banana diagnostics: runs epiclang on a C file when it's opened or
-- saved, and shows what Banana reports as ordinary diagnostics.
local config = require("epitech.config")
local project = require("epitech.project")

local M = {}

M.ns = vim.api.nvim_create_namespace("epitech.banana")

-- Banana's lines on stderr (§6.1 of CLAUDE.md); some have no position.
local WITH_POS = "^(.-):(%d+):(%d+): %a+: %[Banana%] %[(%a+)%] (.-) %((C%-%u%d+)%)%s*$"
local NO_POS = "^(.-): %a+: %[Banana%] %[(%a+)%] (.-) %((C%-%u%d+)%)%s*$"

local severities = {
  Fatal = vim.diagnostic.severity.ERROR,
  Major = vim.diagnostic.severity.ERROR,
  Minor = vim.diagnostic.severity.WARN,
  Info = vim.diagnostic.severity.INFO,
}

local function resolve(path, root)
  if path:sub(1, 1) ~= "/" then
    path = root .. "/" .. path
  end
  path = vim.fs.normalize(path)
  return vim.uv.fs_realpath(path) or path
end

-- Parses epiclang's stderr into diagnostics (0-based positions). Only
-- entries about `file` are kept (every entry when file is nil); paths are
-- resolved against root, where epiclang ran. Other compiler output is
-- ignored: clangd already shows real errors. user_data holds the entry's
-- absolute path and its level ("fatal", "major", "minor" or "info").
function M.parse(stderr, file, root)
  local target = file and resolve(file, root)
  local result, seen = {}, {}
  for line in vim.gsplit(stderr or "", "\n", { plain = true, trimempty = true }) do
    local path, lnum, col, level, message, code = line:match(WITH_POS)
    if not path then
      path, level, message, code = line:match(NO_POS)
    end
    if path and severities[level] then
      path = resolve(path, root)
      lnum = lnum and tonumber(lnum) - 1 or 0
      col = col and math.max(tonumber(col) - 1, 0) or 0
      -- A header's entries come back once for every file including it.
      local key = table.concat({ path, lnum, col, code, message }, "\0")
      if (not target or path == target) and not seen[key] then
        seen[key] = true
        result[#result + 1] = {
          lnum = lnum,
          col = col,
          severity = severities[level],
          -- A fatal means the project isn't graded at all.
          message = (level == "Fatal" and "FATAL: " or "") .. message,
          code = code,
          source = "Banana",
          user_data = { path = path, level = level:lower() },
        }
      end
    end
  end
  return result
end

-- The checker and its arguments, without the include flags and the file.
function M.command()
  local options = config.options.diagnostics
  local cmd = { options.cmd }
  vim.list_extend(cmd, options.args)
  return cmd
end

local jobs = {}
local warned = false

-- Whether the checker can run; says so once per session when it can't.
function M.available()
  local cmd = config.options.diagnostics.cmd
  if vim.fn.executable(cmd) == 1 then
    return true
  end
  if not warned then
    warned = true
    vim.notify(cmd .. " not found: live Banana diagnostics are off", vim.log.levels.WARN, { title = "Epitech" })
  end
  return false
end

-- Checks buf's file on disk and replaces its Banana diagnostics. A run still
-- going for the same buffer is killed. on_done, if given, receives the
-- diagnostics.
function M.run(buf, on_done)
  buf = buf == 0 and vim.api.nvim_get_current_buf() or buf
  local name = vim.api.nvim_buf_get_name(buf)
  if name == "" or vim.bo[buf].buftype ~= "" then
    return
  end
  local file = vim.fn.fnamemodify(name, ":p")
  if vim.fn.filereadable(file) == 0 or not M.available() then
    return
  end

  if jobs[buf] then
    pcall(jobs[buf].kill, jobs[buf], 15)
  end
  local root = project.root(buf)
  local cmd = M.command()
  vim.list_extend(cmd, project.include_flags(root, file))
  cmd[#cmd + 1] = file

  local job
  local ok, started = pcall(vim.system, cmd, { cwd = root, text = true }, function(result)
    vim.schedule(function()
      if jobs[buf] ~= job then
        return
      end
      jobs[buf] = nil
      if not vim.api.nvim_buf_is_valid(buf) then
        return
      end
      local diagnostics = M.parse(result.stderr, file, root)
      vim.diagnostic.set(M.ns, buf, diagnostics)
      local hints = package.loaded["epitech.hints"]
      if hints then
        hints.refresh(buf)
      end
      if on_done then
        on_done(diagnostics)
      end
    end)
  end)
  if ok then
    job = started
    jobs[buf] = job
  end
end

local function is_c(buf)
  return vim.bo[buf].filetype == "c" or vim.api.nvim_buf_get_name(buf):match("%.[ch]$") ~= nil
end

function M.setup(options)
  local group = vim.api.nvim_create_augroup("epitech.banana", { clear = true })
  if not options.diagnostics.enabled then
    return
  end
  vim.api.nvim_create_autocmd(options.diagnostics.events, {
    group = group,
    callback = function(args)
      if is_c(args.buf) then
        M.run(args.buf)
      end
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    callback = function(args)
      if jobs[args.buf] then
        pcall(jobs[args.buf].kill, jobs[args.buf], 15)
        jobs[args.buf] = nil
      end
    end,
  })
end

return M
