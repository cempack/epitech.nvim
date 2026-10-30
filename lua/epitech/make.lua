-- :EpitechMake [target]: runs make at the project root and puts what the
-- compiler, the linker, Banana and make itself complain about in the
-- quickfix list (or Trouble), with paths resolved against the directory make
-- was in (make -C lib/my).
local project = require("epitech.project")
local util = require("epitech.util")

local M = {}

local QF_TYPE = { error = "E", ["fatal error"] = "E", warning = "W", note = "N" }

local function absolute(dir, file)
  if file:sub(1, 1) == "/" then
    return vim.fs.normalize(file)
  end
  return vim.fs.normalize(dir .. "/" .. file)
end

-- Quickfix items from make's output (stdout and stderr together, in order):
-- { items, errors, warnings }. Duplicates (epiclang prints its warnings
-- twice) are dropped.
function M.parse(lines, root)
  local dirs, items, seen = { root }, {}, {}
  local errors, warnings = 0, 0
  local make_errors = {}
  local function add(item)
    local key = table.concat({ item.filename or "", item.lnum or 0, item.col or 0, item.text }, "\0")
    if seen[key] then
      return
    end
    seen[key] = true
    items[#items + 1] = item
    if item.type == "E" then
      errors = errors + 1
    elseif item.type == "W" then
      warnings = warnings + 1
    end
  end
  for _, raw in ipairs(lines) do
    local line = raw:gsub("\27%[[%d;]*m", "")
    local dir = dirs[#dirs]
    local entering = line:match("^make%[%d+%]: Entering directory ['`](.-)'$")
    if entering then
      dirs[#dirs + 1] = entering
    elseif line:match("^make%[%d+%]: Leaving directory") then
      if #dirs > 1 then
        table.remove(dirs)
      end
    else
      local file, lnum, col, kind, text = line:match("^([^:%s][^:]*):(%d+):(%d+): (%a[%a ]-): (.*)$")
      if not file then
        file, lnum, kind, text = line:match("^([^:%s][^:]*):(%d+): (%a[%a ]-): (.*)$")
      end
      if file and QF_TYPE[kind] then
        add({
          filename = absolute(dir, file),
          lnum = tonumber(lnum),
          col = tonumber(col) or 0,
          type = QF_TYPE[kind],
          text = text,
        })
      else
        -- The linker names the source but no line: main.c:(.text+0x1e).
        local source, message = line:match("^([^:%s][^:]*%.c):%(%.text[^)]*%): (.*)$")
        local missing = line:match("^make[^:]*: %*%*%* (No rule to make target .*)$")
        local failed = line:match("^make[^:]*: %*%*%* %[(.-)%] Error %d+$")
        if source then
          add({ filename = absolute(dir, source), lnum = 0, col = 0, type = "E", text = "ld: " .. message })
        elseif line:match("^/usr/bin/ld: .*undefined reference") or line:match("^ld: .*undefined") then
          add({ type = "E", text = line })
        elseif missing then
          add({ type = "E", text = "make: " .. missing })
        elseif failed then
          make_errors[#make_errors + 1] = failed
        end
      end
    end
  end
  -- "[Makefile:6: demo] Error 1" only says something when nothing else did.
  if errors == 0 then
    for _, failed in ipairs(make_errors) do
      local file, lnum, target = failed:match("^(.-):(%d+): (.*)$")
      add({
        filename = file and absolute(root, file) or nil,
        lnum = tonumber(lnum) or 0,
        type = "E",
        text = "make: " .. (target and ("building " .. target .. " failed") or failed),
      })
    end
  end
  return { items = items, errors = errors, warnings = warnings }
end

-- Shows the items in the quickfix list, opened in Trouble when it's there,
-- unless there's nothing to see.
function M.show(title, items)
  vim.fn.setqflist({}, " ", { title = title, items = items })
  if #items == 0 then
    return
  end
  if vim.fn.exists(":Trouble") == 2 then
    vim.cmd("Trouble qflist open")
  else
    vim.cmd("botright copen")
  end
end

-- Runs make with args in root; on_done(code, lines) gets the output with
-- stdout and stderr interleaved as make wrote them.
function M.run(args, root, on_done)
  local command = vim.list_extend({ "sh", "-c", 'exec make "$@" 2>&1', "make" }, args)
  return util.system(command, { cwd = root, text = true }, function(result)
    local lines = vim.split(result.stdout or "", "\n", { trimempty = true })
    vim.schedule(function()
      on_done(result.code, lines)
    end)
  end)
end

local function summary(result)
  local parts = {}
  if result.errors > 0 then
    parts[#parts + 1] = result.errors .. (result.errors == 1 and " error" or " errors")
  end
  if result.warnings > 0 then
    parts[#parts + 1] = result.warnings .. (result.warnings == 1 and " warning" or " warnings")
  end
  return table.concat(parts, " · ")
end

-- :EpitechMake [target…]: on_done (optional) receives the parsed result
-- plus the exit code.
function M.make(args, root, on_done)
  root = root or project.root(0)
  if vim.fn.filereadable(root .. "/Makefile") == 0 then
    return util.notify("No Makefile in " .. root, vim.log.levels.WARN)
  end
  local label = "make" .. (#args > 0 and " " .. table.concat(args, " ") or "")
  local started = vim.uv.hrtime()
  util.notify(label .. "…")
  M.run(args, root, function(code, lines)
    local result = M.parse(lines, root)
    result.code = code
    local seconds = ("%.1fs"):format((vim.uv.hrtime() - started) / 1e9)
    local details = summary(result)
    M.show(label .. (details ~= "" and ": " .. details or ""), result.items)
    if code == 0 then
      util.notify(("%s done in %s%s"):format(label, seconds, details ~= "" and " (" .. details .. ")" or ""))
    else
      util.notify(("%s failed%s"):format(label, details ~= "" and ": " .. details or ""), vim.log.levels.ERROR)
    end
    if on_done then
      on_done(result)
    end
  end)
end

-- The rules of root's Makefile, for completion.
function M.targets(root)
  local targets = {}
  for _, line in ipairs(util.read_lines((root or project.root(0)) .. "/Makefile")) do
    local target = line:match("^([%w_.%-]+)%s*:")
    if target and not line:match("^[%w_.%-]+%s*:=") and not target:match("^%.")
      and not vim.list_contains(targets, target) then
      targets[#targets + 1] = target
    end
  end
  return targets
end

return M
