-- Shared test helpers. Load them after the usual runtimepath lines with
-- local h = dofile(plugin .. "/test/helpers.lua")
local M = {}

function M.assert_equal(actual, expected, label)
  if not vim.deep_equal(actual, expected) then
    error(("%s\nexpected: %s\nactual:   %s"):format(label, vim.inspect(expected), vim.inspect(actual)), 2)
  end
end

local function run(cmd, cwd)
  local result = vim.system(cmd, { cwd = cwd, text = true }):wait()
  if result.code ~= 0 then
    error(table.concat(cmd, " ") .. " failed: " .. (result.stderr or ""), 3)
  end
  return result
end

-- Creates a project from { ["src/main.c"] = { lines... }, ... } in a new temp
-- directory, then runs git init and git add -A, since several features list
-- files with `git ls-files`. Returns the root (symlinks resolved, so it
-- compares equal to what vim.fs.root finds) and a cleanup function.
function M.temp_project(files)
  local root = vim.fn.tempname()
  vim.fn.mkdir(root, "p")
  root = assert(vim.uv.fs_realpath(root))
  for path, lines in pairs(files or {}) do
    local full = root .. "/" .. path
    vim.fn.mkdir(vim.fs.dirname(full), "p")
    vim.fn.writefile(lines, full)
  end
  run({ "git", "init", "-q" }, root)
  run({ "git", "add", "-A" }, root)
  return root, function()
    vim.fn.delete(root, "rf")
  end
end

-- Runs fn with an `epiclang` first on PATH that prints stderr_lines to stderr
-- and exits 0, like the real one does when it finds violations. fn receives a
-- calls() function returning the argument lists the fake was run with.
function M.with_fake_epiclang(stderr_lines, fn)
  local bin = vim.fn.tempname()
  vim.fn.mkdir(bin, "p")
  vim.fn.writefile(stderr_lines, bin .. "/stderr")
  vim.fn.writefile({
    "#!/bin/sh",
    "printf '%s\\t' \"$@\" >> '" .. bin .. "/calls'",
    "printf '\\n' >> '" .. bin .. "/calls'",
    "cat '" .. bin .. "/stderr' >&2",
    "exit 0",
  }, bin .. "/epiclang")
  vim.uv.fs_chmod(bin .. "/epiclang", 493)

  local function calls()
    local result = {}
    if vim.fn.filereadable(bin .. "/calls") == 1 then
      for _, line in ipairs(vim.fn.readfile(bin .. "/calls")) do
        result[#result + 1] = vim.split(line:gsub("\t$", ""), "\t", { plain = true })
      end
    end
    return result
  end

  local path = vim.env.PATH
  vim.env.PATH = bin .. ":" .. path
  local ok, err = pcall(fn, calls)
  vim.env.PATH = path
  vim.fn.delete(bin, "rf")
  if not ok then
    error(err, 0)
  end
end

-- Creates a buffer named `name` (replacing any buffer with that name) with
-- filetype c, fills it with `lines` and makes it current.
function M.buffer(name, lines)
  local full = vim.fn.fnamemodify(name, ":p")
  for _, existing in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_name(existing) == full then
      vim.api.nvim_buf_delete(existing, { force = true })
    end
  end
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(buf, full)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines or {})
  vim.api.nvim_set_current_buf(buf)
  vim.bo[buf].filetype = "c"
  return buf
end

-- An LSP range covering whole rows, first_row to last_row (0-based).
function M.rows(first_row, last_row)
  return { start = { line = first_row, character = 0 }, ["end"] = { line = last_row or first_row, character = 0 } }
end

-- Asks the epitech language server for the code actions on range in buf,
-- through the real LSP path. Returns the actions and the client.
function M.code_actions(buf, range)
  local client_id = assert(require("epitech.lsp").start(buf), "epitech language server didn't start")
  local client = assert(vim.lsp.get_client_by_id(client_id))
  local response = client:request_sync("textDocument/codeAction", {
    textDocument = { uri = vim.uri_from_bufnr(buf) },
    range = range or M.rows(0, vim.api.nvim_buf_line_count(buf) - 1),
    context = { diagnostics = {} },
  }, 1000, buf)
  assert(response and not response.err, "codeAction failed: " .. vim.inspect(response))
  return response.result or {}, client
end

-- Applies an action's edit the way vim.lsp.buf.code_action() does.
function M.apply_action(action, client)
  assert(action.edit, "action has no edit: " .. action.title)
  vim.lsp.util.apply_workspace_edit(action.edit, client.offset_encoding)
end

-- The actions in a list whose data.rule is rule.
function M.actions_for(actions, rule)
  return vim.tbl_filter(function(action)
    return action.data and action.data.rule == rule
  end, actions)
end

-- Checks a fix on test/fixtures/fixes/<fix>/<case>.before.c: the action
-- titled `title` offered on `row` turns it into <case>.after.c, no action for
-- `rule` is offered on the result (idempotence), and format_buffer() leaves
-- the result unchanged.
function M.check_fix(fix, case, row, title, rule)
  local dir = vim.env.EPITECH_NVIM_DIR .. "/test/fixtures/fixes/" .. fix .. "/"
  local label = fix .. "/" .. case
  local buf = M.buffer("/tmp/epitech_fix_" .. fix .. "_" .. case .. ".c", vim.fn.readfile(dir .. case .. ".before.c"))
  local actions, client = M.code_actions(buf, M.rows(row))
  local chosen
  for _, action in ipairs(actions) do
    if action.title == title then
      chosen = action
    end
  end
  assert(chosen, label .. ": no action titled " .. title .. " in " .. vim.inspect(vim.tbl_map(function(action)
    return action.title
  end, actions)))
  M.apply_action(chosen, client)
  local expected = vim.fn.readfile(dir .. case .. ".after.c")
  M.assert_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), expected, label .. ": result")
  M.assert_equal(M.actions_for((M.code_actions(buf)), rule), {}, label .. ": idempotent")
  require("epitech").format_buffer(buf)
  M.assert_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), expected, label .. ": formatter leaves it unchanged")
  return buf
end

return M
