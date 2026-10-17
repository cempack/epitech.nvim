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

return M
