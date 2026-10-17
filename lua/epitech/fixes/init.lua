-- The fix registry behind the epitech language server, and the helpers fix
-- modules share to build LSP code actions. A fix module returns
-- { id, rules, filetypes?, commands?, actions = function(buf, range, context) }.
-- Every action it offers keeps the program's meaning (a fix is safe or it
-- isn't offered), is idempotent, and leaves text the formatter keeps as is.
local M = {}

-- Fix modules under lua/epitech/fixes/, by id.
M.modules = {}

local registered

-- Adds a fix module, and its client-side commands to vim.lsp.commands.
function M.register(fix)
  registered = registered or {}
  for _, existing in ipairs(registered) do
    if existing.id == fix.id then
      return
    end
  end
  registered[#registered + 1] = fix
  for name, fn in pairs(fix.commands or {}) do
    vim.lsp.commands[name] = fn
  end
end

function M.list()
  if not registered then
    registered = {}
    for _, id in ipairs(M.modules) do
      M.register(require("epitech.fixes." .. id))
    end
  end
  return registered
end

-- Every action the registered fixes offer for range in buf.
function M.actions(buf, range, context)
  if not require("epitech.config").options.fixes.enabled then
    return {}
  end
  local result = {}
  local filetype = vim.bo[buf].filetype
  for _, fix in ipairs(M.list()) do
    if vim.list_contains(fix.filetypes or { "c" }, filetype) then
      vim.list_extend(result, fix.actions(buf, range, context or {}) or {})
    end
  end
  return result
end

function M.uri(buf)
  return vim.uri_from_bufnr(buf)
end

-- An LSP range from a Treesitter node: 0-based rows and byte columns, which
-- is what the server's utf-8 position encoding means.
function M.range(node)
  local start_row, start_col, end_row, end_col = node:range()
  return {
    start = { line = start_row, character = start_col },
    ["end"] = { line = end_row, character = end_col },
  }
end

function M.position_range(start_row, start_col, end_row, end_col)
  return {
    start = { line = start_row, character = start_col },
    ["end"] = { line = end_row or start_row, character = end_col or start_col },
  }
end

-- Whether a node's rows overlap the rows of an LSP range. Code actions are
-- usually requested for the cursor's line, so columns don't matter.
function M.touches(node, range)
  local start_row, _, end_row = node:range()
  return start_row <= range["end"].line and end_row >= range.start.line
end

-- A code action that applies text edits to buf (edits: { range, newText }).
-- `rule` goes in data so tests and :EpitechFixAll can tell actions apart.
function M.action(title, rule, buf, edits, kind)
  return {
    title = title,
    kind = kind or "quickfix",
    edit = { changes = { [M.uri(buf)] = edits } },
    data = { rule = rule },
  }
end

-- A code action that runs a client-side command (a fix that needs input or
-- touches files on disk).
function M.command_action(title, rule, command, arguments, kind)
  return {
    title = title,
    kind = kind or "quickfix",
    command = { title = title, command = command, arguments = arguments },
    data = { rule = rule },
  }
end

-- Applies text edits to buf right away, outside the LSP round trip.
function M.apply(buf, edits)
  vim.lsp.util.apply_text_edits(edits, buf, "utf-8")
end

-- The indentation of a row.
function M.indent(buf, row)
  local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
  return line:match("^%s*")
end

return M
