-- The in-process language server "epitech". It only answers code action
-- requests, with the fixes registered in fixes/init.lua, so they show up in
-- vim.lsp.buf.code_action() (LazyVim's <leader>ca) next to clangd's. Fixes
-- read buffers directly, so the server needs no text sync.
local M = {}

local function code_actions(params)
  local buf = vim.uri_to_bufnr(params.textDocument.uri)
  return require("epitech.fixes").actions(buf, params.range, params.context or {})
end

local function create_server(dispatchers)
  local closing, next_id = false, 0
  local server = {}

  function server.request(method, params, callback)
    next_id = next_id + 1
    local err, result
    if method == "initialize" then
      result = {
        capabilities = {
          codeActionProvider = { codeActionKinds = { "quickfix", "refactor.rewrite", "refactor.extract" } },
          positionEncoding = "utf-8",
        },
        serverInfo = { name = "epitech.nvim" },
      }
    elseif method == "textDocument/codeAction" then
      local ok, actions = pcall(code_actions, params)
      if ok then
        result = actions
      else
        err = { code = -32603, message = "epitech.nvim: " .. tostring(actions) }
      end
    end
    vim.schedule(function()
      callback(err, result)
    end)
    return true, next_id
  end

  -- There's no process to wait for: exiting is reporting the exit.
  local function exit()
    if not closing then
      closing = true
      dispatchers.on_exit(0, 15)
    end
  end

  function server.notify(method)
    if method == "exit" then
      exit()
    end
    return true
  end

  function server.is_closing()
    return closing
  end

  server.terminate = exit

  return server
end

-- Attaches the server to buf (one client per project root) and returns the
-- client id. Unnamed and special buffers are skipped.
function M.start(buf)
  buf = buf == 0 and vim.api.nvim_get_current_buf() or buf
  if vim.api.nvim_buf_get_name(buf) == "" or vim.bo[buf].buftype ~= "" then
    return nil
  end
  return vim.lsp.start({
    name = "epitech",
    cmd = create_server,
    root_dir = require("epitech.project").root(buf),
  }, { bufnr = buf })
end

function M.setup(options)
  local group = vim.api.nvim_create_augroup("epitech.lsp", { clear = true })
  if not options.fixes.enabled then
    return
  end
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = { "c", "make" },
    callback = function(args)
      M.start(args.buf)
    end,
  })
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.list_contains({ "c", "make" }, vim.bo[buf].filetype) then
      M.start(buf)
    end
  end
end

return M
