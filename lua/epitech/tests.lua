-- :EpitechTest: builds and runs the Criterion tests, puts failed asserts
-- and crashes in the quickfix list, and with gcovr marks each covered and
-- uncovered line in the sign column (:EpitechCoverage on|off).
local config = require("epitech.config")
local make = require("epitech.make")
local project = require("epitech.project")
local util = require("epitech.util")

local M = {}

M.ns = vim.api.nvim_create_namespace("epitech.coverage")

-- { [absolute path] = { hit = { rows }, missed = { rows } } }, 1-based rows.
M.coverage = {}
M.visible = true

function M.highlights()
  vim.api.nvim_set_hl(0, "EpitechCoverageHit", { link = "DiagnosticOk", default = true })
  vim.api.nvim_set_hl(0, "EpitechCoverageMissed", { link = "DiagnosticError", default = true })
end

-- Failed asserts and crashes from Criterion's output: { items, synthesis }.
-- A failure looks like
--   [----] tests/test_x.c:12: Assertion Failed
--   [----]   The expression (a == b) is false.
--   [FAIL] suite::name: (0.00s)
-- and a crash like `[----] …:5: Unexpected signal caught below this line!`
-- then `[FAIL] suite::name: CRASH!`.
function M.parse(lines, root)
  local items, pending, synthesis = {}, {}, nil
  for _, raw in ipairs(lines) do
    local line = raw:gsub("\27%[[%d;]*m", "")
    local file, lnum, headline = line:match("^%[%-%-%-%-%] ([^:%s][^:]*):(%d+): (.*)$")
    local detail = not file and line:match("^%[%-%-%-%-%]%s+(.-)%s*$")
    local suite, name, status = line:match("^%[FAIL%] ([^:]+)::(%S+): (.*)$")
    local counts = line:match("^%[====%] Synthesis: (.-)%s*$")
    if file then
      pending[#pending + 1] = { file = file, lnum = tonumber(lnum), headline = headline, details = {} }
    elseif detail and detail ~= "" and #pending > 0 then
      table.insert(pending[#pending].details, detail)
    elseif suite then
      local test = suite .. "::" .. name
      status = vim.trim(status:gsub("%(%d+%.%d+s%)", ""))
      if #pending == 0 then
        items[#items + 1] = { type = "E", text = test .. ": " .. (status ~= "" and status or "failed") }
      end
      for _, entry in ipairs(pending) do
        local text = #entry.details > 0 and table.concat(entry.details, " ") or entry.headline
        if status == "CRASH!" then
          text = "crashed below this line"
        end
        items[#items + 1] = {
          filename = entry.file:sub(1, 1) == "/" and entry.file or root .. "/" .. entry.file,
          lnum = entry.lnum,
          type = "E",
          text = test .. ": " .. text,
        }
      end
      pending = {}
    elseif counts then
      synthesis = {}
      for key, value in counts:gmatch("(%a+): (%d+)") do
        synthesis[key:lower()] = tonumber(value)
      end
    end
  end
  return { items = items, synthesis = synthesis }
end

-- Coverage from gcovr's JSON report, test files left out:
-- { files = { [path] = { hit, missed } }, lines, covered }.
function M.parse_coverage(json, root)
  local ok, report = pcall(vim.json.decode, json)
  if not ok or type(report) ~= "table" then
    return nil
  end
  local files, lines, covered = {}, 0, 0
  for _, entry in ipairs(report.files or {}) do
    local path = entry.file:sub(1, 1) == "/" and entry.file or root .. "/" .. entry.file
    path = vim.fs.normalize(path)
    local relative = util.relative(path, root) or path
    if not relative:match("^tests?/") then
      local file = { hit = {}, missed = {} }
      for _, line in ipairs(entry.lines or {}) do
        if not line["gcovr/noncode"] then
          lines = lines + 1
          if (line.count or 0) > 0 then
            covered = covered + 1
            file.hit[#file.hit + 1] = line.line_number
          else
            file.missed[#file.missed + 1] = line.line_number
          end
        end
      end
      files[path] = file
    end
  end
  return { files = files, lines = lines, covered = covered }
end

-- Draws (or clears) the coverage signs of a buffer.
function M.draw(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
  local name = vim.api.nvim_buf_get_name(buf)
  local file = M.visible and name ~= "" and M.coverage[vim.fs.normalize(name)]
  if not file then
    return
  end
  local count = vim.api.nvim_buf_line_count(buf)
  local function mark(rows, group)
    for _, row in ipairs(rows) do
      if row >= 1 and row <= count then
        vim.api.nvim_buf_set_extmark(buf, M.ns, row - 1, 0, {
          sign_text = "▎",
          sign_hl_group = group,
          priority = 5,
        })
      end
    end
  end
  mark(file.hit, "EpitechCoverageHit")
  mark(file.missed, "EpitechCoverageMissed")
end

local function redraw_all()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      M.draw(buf)
    end
  end
end

-- :EpitechCoverage [on|off]: shows or hides the signs (toggles without an
-- argument).
function M.toggle(state)
  if state == "on" then
    M.visible = true
  elseif state == "off" then
    M.visible = false
  else
    M.visible = not M.visible
  end
  redraw_all()
  util.notify("Coverage signs " .. (M.visible and "on" or "off"))
end

local function has_rule(root, rule)
  return vim.list_contains(make.targets(root), rule)
end

-- Removes what a coverage build leaves (make fclean, then any .gcda or
-- .gcno it didn't remove), as tests_run does.
local function clean(root, on_done)
  make.run({ "fclean" }, root, function()
    for _, file in ipairs(vim.fs.find(function(name)
      return name:match("%.gcda$") or name:match("%.gcno$")
    end, { path = root, type = "file", limit = math.huge })) do
      os.remove(file)
    end
    on_done()
  end)
end

local function finish(root, result, coverage, on_done)
  local passed = result.synthesis and result.synthesis.passing
  local failed = result.synthesis and ((result.synthesis.failing or 0) + (result.synthesis.crashing or 0))
  local parts = {}
  if result.synthesis then
    parts[#parts + 1] = ("%d passed"):format(passed or 0)
    if failed > 0 then
      parts[#parts + 1] = ("%d failed"):format(failed)
    end
  end
  if coverage and coverage.lines > 0 then
    parts[#parts + 1] = ("%d%% of lines covered"):format(math.floor(coverage.covered * 100 / coverage.lines))
  end
  local text = "Tests: " .. (#parts > 0 and table.concat(parts, " · ") or "no Criterion output")
  make.show(text, result.items)
  util.notify(text, #result.items > 0 and vim.log.levels.ERROR or vim.log.levels.INFO)
  if on_done then
    on_done(vim.tbl_extend("force", result, { coverage = coverage }))
  end
end

-- :EpitechTest: `make unit_tests` and ./unit_tests when the Makefile has
-- that rule (coverage comes from the build it leaves), else
-- `make tests_run`. on_done (optional) receives { items, synthesis,
-- coverage }.
function M.run(root, on_done)
  root = root or project.root(0)
  local options = config.options.tests
  if vim.fn.filereadable(root .. "/Makefile") == 0 then
    return util.notify("No Makefile in " .. root, vim.log.levels.WARN)
  end
  if not has_rule(root, "unit_tests") then
    if not has_rule(root, "tests_run") then
      return util.notify("The Makefile has no unit_tests or tests_run rule", vim.log.levels.WARN)
    end
    util.notify("make tests_run…")
    return make.run({ "tests_run" }, root, function(_, lines)
      local result = M.parse(lines, root)
      vim.list_extend(result.items, make.parse(lines, root).items)
      finish(root, result, nil, on_done)
    end)
  end
  util.notify("Building the unit tests…")
  make.run({ "unit_tests" }, root, function(code, lines)
    if code ~= 0 then
      local built = make.parse(lines, root)
      make.show("make unit_tests failed", built.items)
      util.notify("The unit tests don't build", vim.log.levels.ERROR)
      return clean(root, function() end)
    end
    util.system({ "sh", "-c", "exec ./unit_tests 2>&1" }, { cwd = root, text = true }, function(run)
      vim.schedule(function()
        local result = M.parse(vim.split(run.stdout or "", "\n", { trimempty = true }), root)
        local function done(coverage)
          if coverage then
            M.coverage = coverage.files
            redraw_all()
          end
          local after = function()
            finish(root, result, coverage, on_done)
          end
          if options.fclean then
            clean(root, after)
          else
            after()
          end
        end
        if not options.coverage or vim.fn.executable("gcovr") == 0 then
          return done(nil)
        end
        util.system({ "gcovr", "-r", root, "--json", "-" }, { cwd = root, text = true }, function(report)
          vim.schedule(function()
            done(report.code == 0 and M.parse_coverage(report.stdout or "", root) or nil)
          end)
        end)
      end)
    end)
  end)
end

function M.setup()
  M.highlights()
  local group = vim.api.nvim_create_augroup("epitech.coverage", { clear = true })
  vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = M.highlights })
  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = group,
    callback = function(args)
      if next(M.coverage) then
        M.draw(args.buf)
      end
    end,
  })
end

return M
