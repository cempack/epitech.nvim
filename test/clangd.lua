local plugin = assert(vim.env.EPITECH_NVIM_DIR, "EPITECH_NVIM_DIR is required")
vim.opt.runtimepath:prepend(plugin)
package.path = plugin .. "/lua/?.lua;" .. plugin .. "/lua/?/init.lua;" .. package.path

local h = dofile(plugin .. "/test/helpers.lua")
local clangd = require("epitech.clangd")
require("epitech").setup()

-- The header to include instead of the one clangd picked.
h.assert_equal({
  clangd.header("malloc.h", "malloc"),
  clangd.header("__stddef_size_t.h", "size_t"),
  clangd.header("bits/types/struct_FILE.h", "FILE"),
  clangd.header("x86_64-linux-gnu/bits/stat.h", "stat"),
  clangd.header("bits/whatever.h", "unknown_thing"),
  clangd.header("unistd.h", "write"),
  clangd.header("SFML/Graphics/RenderWindow.h", "sfRenderWindow_create"),
  clangd.header("SFML/Audio/Music.h", "sfMusic_play"),
  clangd.header("criterion/internal/assert.h", "cr_assert_eq"),
  clangd.header("criterion/redirect.h", "cr_redirect_stdout"),
  clangd.header("ncurses.h", "initscr"),
  clangd.header("mylib/thing.h", "thing"),
}, {
  "stdlib.h", "stddef.h", "stdio.h", "sys/stat.h", nil, "unistd.h", "SFML/Graphics.h", "SFML/Audio.h",
  "criterion/criterion.h", "criterion/redirect.h", "ncurses.h", "mylib/thing.h",
}, "headers")

-- A fake clangd: an in-process server under that name, answering like the
-- real one does with --header-insertion=iwyu.
local function include(path)
  return { { range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 0 } },
    newText = "#include " .. path .. "\n" } }
end
local completion = {
  isIncomplete = false,
  items = {
    { label = "•malloc(size_t size)", filterText = "malloc", additionalTextEdits = include("<malloc.h>") },
    { label = "•size_t", filterText = "size_t", additionalTextEdits = include("<__stddef_size_t.h>") },
    { label = "•write(int fd, const void *buf, size_t n)", filterText = "write",
      additionalTextEdits = include("<unistd.h>") },
    { label = "•my_strlen(const char *str)", filterText = "my_strlen", additionalTextEdits = include('"my.h"') },
    { label = "•sfRenderWindow_create(…)", filterText = "sfRenderWindow_create",
      additionalTextEdits = include("<SFML/Graphics/RenderWindow.h>") },
    { label = "•cr_assert_eq(…)", filterText = "cr_assert_eq",
      additionalTextEdits = include("<criterion/internal/assert.h>") },
    { label = "•__fpending(FILE *fp)", filterText = "__fpending", additionalTextEdits = include("<bits/x.h>") },
    { label = "•printf(const char *fmt, ...)", filterText = "printf",
      additionalTextEdits = include("<bits/stdio2.h>") },
    { label = " ac", filterText = "ac" },
  },
}
local code_actions = {
  { title = "Include <malloc.h> for symbol malloc", kind = "quickfix",
    edit = { changes = { ["file:///x.c"] = include("<malloc.h>") } } },
  { title = "Include <bits/x.h> for symbol __fpending", kind = "quickfix",
    edit = { changes = { ["file:///x.c"] = include("<bits/x.h>") } } },
  { title = "Include <ctype.h> for symbol isalpha", kind = "quickfix",
    edit = { documentChanges = { { textDocument = { uri = "file:///x.c" }, edits = include("<ctype.h>") } } } },
  { title = "Add missing ';'", kind = "quickfix" },
}
local function server(dispatchers)
  local srv, closing = {}, false
  function srv.request(method, _, callback)
    local result
    if method == "initialize" then
      result = { capabilities = { completionProvider = {}, codeActionProvider = true } }
    elseif method == "textDocument/completion" then
      result = vim.deepcopy(completion)
    elseif method == "textDocument/codeAction" then
      result = vim.deepcopy(code_actions)
    end
    vim.schedule(function()
      callback(nil, result)
    end)
    return true, 1
  end
  function srv.notify(method)
    if method == "exit" then
      dispatchers.on_exit(0, 15)
    end
    return true
  end
  function srv.is_closing()
    return closing
  end
  function srv.terminate()
    closing = true
  end
  return srv
end

local buf = h.buffer("/tmp/epitech_clangd.c", { "#include <stdio.h>", "", "int main(void)", "{", "}" })
local id = vim.lsp.start({ name = "clangd", cmd = server, root_dir = "/tmp" }, { bufnr = buf })
local client = assert(vim.lsp.get_client_by_id(id))
assert(vim.wait(2000, function()
  return client.initialized
end), "fake clangd started")

local params = { textDocument = { uri = vim.uri_from_bufnr(buf) }, position = { line = 3, character = 0 } }
local function summary(items)
  return vim.tbl_map(function(item)
    local edits = vim.tbl_map(function(edit)
      return vim.trim(edit.newText)
    end, item.additionalTextEdits or {})
    return item.label .. " " .. table.concat(edits, " ")
  end, items)
end
local expected = {
  "•malloc(size_t size) #include <stdlib.h>",
  "•size_t #include <stddef.h>",
  "•write(int fd, const void *buf, size_t n) #include <unistd.h>",
  '•my_strlen(const char *str) #include "my.h"',
  "•sfRenderWindow_create(…) #include <SFML/Graphics.h>",
  "•cr_assert_eq(…) #include <criterion/criterion.h>",
  " __fpending(FILE *fp) ",
  " printf(const char *fmt, ...) ",
  " ac ",
}

-- Through request_sync, client:request with a handler (blink.cmp, nvim-cmp)
-- and the older client.request(…) form.
local sync = client:request_sync("textDocument/completion", params, 1000, buf)
h.assert_equal(summary(sync.result.items), expected, "request_sync: includes fixed, internal ones dropped")
local got
client:request("textDocument/completion", params, function(_, result)
  got = result
end, buf)
assert(vim.wait(1000, function()
  return got ~= nil
end))
h.assert_equal(summary(got.items), expected, "client:request")
got = nil
vim.deprecate = function() end
client.request("textDocument/completion", params, function(_, result)
  got = result
end, buf)
assert(vim.wait(1000, function()
  return got ~= nil
end))
h.assert_equal(summary(got.items), expected, "client.request")

-- The "Include … for symbol" quick fixes.
local actions = client:request_sync("textDocument/codeAction", {
  textDocument = { uri = vim.uri_from_bufnr(buf) },
  range = { start = { line = 3, character = 0 }, ["end"] = { line = 3, character = 0 } },
  context = { diagnostics = {} },
}, 1000, buf).result
h.assert_equal(vim.tbl_map(function(action)
  return action.title
end, actions), { "Include <stdlib.h> for symbol malloc", "Include <ctype.h> for symbol isalpha", "Add missing ';'" },
  "quick fixes: fixed, dropped, kept")
h.assert_equal(actions[1].edit.changes["file:///x.c"][1].newText, "#include <stdlib.h>\n", "quick fix edit")

-- Only clangd is touched, and only once.
local before = client.request
clangd.attach(client)
h.assert_equal(client.request == before, true, "wrapped once")
client:stop(true)

-- Turned off: clangd's answers go through untouched.
require("epitech").setup({ clangd = { fix_includes = false } })
local raw = vim.lsp.start({ name = "clangd", cmd = server, root_dir = "/tmp/off" }, { bufnr = buf })
local off = assert(vim.lsp.get_client_by_id(raw))
assert(vim.wait(2000, function()
  return off.initialized
end))
h.assert_equal(off:request_sync("textDocument/completion", params, 1000, buf).result.items[1].additionalTextEdits[1]
  .newText, "#include <malloc.h>\n", "fix_includes = false")
off:stop(true)

print("Epitech clangd include tests passed")
