-- Options for setup(opts): the defaults, a deep merge and validation.
local M = {}

M.defaults = {
  header = { keymap = "<leader>cH" },
  guard = { keymap = "<leader>cG" },
  diagnostics = {
    enabled = true,
    cmd = "epiclang",
    args = { "-x", "c", "-fsyntax-only" }, -- include flags are added per project
    events = { "BufWritePost", "BufReadPost" },
  },
  explain = { keymap = "<leader>cE" },
  budget = {
    functions = true,
    file = "winbar",
    depth = true,
    max_lines = 20,
    warn_lines = 17,
    max_args = 4,
    max_functions = 10,
    max_non_static = 5,
    max_depth = 3,
    show_depth_from = 2,
    max_branches = 3,
  },
  hints = {
    enabled = true,
    severity = vim.diagnostic.severity.HINT,
    -- 84 is Epitech's conventional error exit code.
    magic_numbers = { enabled = true, allow = { 0, 1, -1, 84 } },
    static = true,
    types = true,
    naming = { enabled = true }, -- verbs and vague_files: nil uses the built-in lists
  },
  makefile = { enabled = true, tab_width = 8 },
  fixes = { enabled = true },
  check = { keymap = "<leader>cB", fail_on = { "fatal", "major" } },
  scaffold = { keymap = "<leader>cN", cc = "epiclang", cflags = "" },
}

-- Lists replace the default instead of being merged into it; the value says
-- what their items must be.
local lists = {
  ["diagnostics.args"] = "string",
  ["diagnostics.events"] = "string",
  ["hints.magic_numbers.allow"] = "number",
  ["hints.naming.verbs"] = "string",
  ["hints.naming.vague_files"] = "string",
  ["check.fail_on"] = "string",
}

-- Options whose default is nil, so the defaults table can't describe them.
local optional = {
  ["hints.naming.verbs"] = true,
  ["hints.naming.vague_files"] = true,
}

-- Options that take one of a few values instead of any value of their type.
local choices = {
  ["budget.file"] = { "winbar", "lualine", false },
}

local item_choices = {
  ["check.fail_on"] = { "fatal", "major", "minor", "info" },
}

local function fail(path, expected, value)
  error(("epitech.nvim: option %s must be %s, got %s"):format(path, expected, vim.inspect(value)), 0)
end

local function check_list(path, value)
  if type(value) ~= "table" or not vim.islist(value) then
    fail(path, "a list of " .. lists[path] .. "s", value)
  end
  for _, item in ipairs(value) do
    if type(item) ~= lists[path] then
      fail(path, "a list of " .. lists[path] .. "s", value)
    end
    if item_choices[path] and not vim.list_contains(item_choices[path], item) then
      fail(path, "a list of " .. table.concat(item_choices[path], ", "), value)
    end
  end
  return vim.deepcopy(value)
end

-- Merges `value` over `default` at `path`, collecting unknown keys.
local function merge(path, default, value, unknown)
  if lists[path] then
    return check_list(path, value)
  end
  if choices[path] then
    if not vim.list_contains(choices[path], value) then
      fail(path, "one of " .. vim.inspect(choices[path]), value)
    end
    return value
  end
  if path:match("keymap$") then
    if value ~= false and type(value) ~= "string" then
      fail(path, "a key sequence or false", value)
    end
    return value
  end

  if type(default) == "table" then
    -- `naming = false` is short for `naming = { enabled = false }`.
    if type(value) == "boolean" and default.enabled ~= nil then
      value = { enabled = value }
    end
    if type(value) ~= "table" then
      fail(path, "a table", value)
    end
    local result = vim.deepcopy(default)
    for key, item in pairs(value) do
      local item_path = path == "" and tostring(key) or path .. "." .. tostring(key)
      if default[key] ~= nil or optional[item_path] then
        result[key] = merge(item_path, default[key], item, unknown)
      else
        unknown[#unknown + 1] = item_path
      end
    end
    return result
  end

  if type(value) ~= type(default) then
    fail(path, "a " .. type(default), value)
  end
  return value
end

-- Returns the defaults merged with opts. Raises an error naming the option on
-- a wrong type; unknown options are dropped with a single warning.
function M.merge(opts)
  if opts ~= nil and type(opts) ~= "table" then
    error("epitech.nvim: setup(opts) expects a table, got " .. vim.inspect(opts), 0)
  end
  local unknown = {}
  local result = merge("", M.defaults, opts or {}, unknown)
  if #unknown > 0 then
    table.sort(unknown)
    vim.notify("epitech.nvim: unknown option" .. (#unknown > 1 and "s" or "") .. " ignored: "
      .. table.concat(unknown, ", "), vim.log.levels.WARN, { title = "Epitech" })
  end
  return result
end

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.options = M.merge(opts)
  return M.options
end

return M
