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
    { label = "•strlen(const char *s)", filterText = "strlen",
      additionalTextEdits = include('"/usr/include/bits/string_fortified.h"') },
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
  { title = "#include <bits/string_fortified.h>", kind = "quickfix",
    diagnostics = { { message = 'No header providing "strdup" is directly included (fixes available)' } },
    edit = { changes = { ["file:///x.c"] = include("<bits/string_fortified.h>") } } },
  { title = "#include <bits/stdio2.h>", kind = "quickfix",
    diagnostics = { { message = 'No header providing "printf" is directly included (fixes available)' } },
    edit = { changes = { ["file:///x.c"] = include("<bits/stdio2.h>") } } },
  { title = "Add missing ';'", kind = "quickfix" },
}
local notified = {}
local pushers = {}
local function server(dispatchers)
  pushers[#pushers + 1] = dispatchers
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
  function srv.notify(method, notify_params)
    notified[#notified + 1] = { method = method, params = notify_params }
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
  "•strlen(const char *s) #include <string.h>",
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
end, actions), {
  "Include <stdlib.h> for symbol malloc", "Include <ctype.h> for symbol isalpha", "#include <string.h>",
  "Add missing ';'",
}, "quick fixes: fixed, dropped (stdio.h is included), kept")
h.assert_equal(actions[3].edit.changes["file:///x.c"][1].newText, "#include <string.h>\n", "include-cleaner fix")
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

-- clangd learns the Makefile's -I directories for each file it opens.
require("epitech").setup()
local root, cleanup = h.temp_project({
  ["Makefile"] = { "NAME = demo", "", "CPPFLAGS = -I./include  # headers", "", "SRC = src/main.c" },
  ["include/demo.h"] = { "#ifndef DEMO_H_", "    #define DEMO_H_", "#endif" },
  ["src/main.c"] = { '#include "demo.h"', "", "int main(void)", "{", "    return 0;", "}" },
})
h.assert_equal(require("epitech.project").build_include_dirs(root, root .. "/src/main.c"), { root .. "/include" },
  "build include dirs from the Makefile")
vim.cmd.edit(root .. "/src/main.c")
local main = vim.api.nvim_get_current_buf()
notified = {}
local dirs_client = assert(vim.lsp.get_client_by_id(assert(vim.lsp.start({ name = "clangd", cmd = server,
  root_dir = root }, { bufnr = main }))))
local file = vim.uri_to_fname(vim.uri_from_bufnr(main))
local function sent()
  for _, message in ipairs(notified) do
    if message.method == "workspace/didChangeConfiguration" then
      return message.params.settings.compilationDatabaseChanges
    end
  end
end
assert(vim.wait(2000, function()
  return sent() ~= nil
end), "include dirs sent")
h.assert_equal(sent(), {
  [file] = { workingDirectory = root, compilationCommand = { "clang", "-I" .. root .. "/include", file } },
}, "compilation command for the file")
dirs_client:stop(true)

-- Nothing when the project has a compile_commands.json, or no -I.
vim.fn.writefile({ "[]" }, root .. "/compile_commands.json")
h.assert_equal(clangd.compile_command(root, file), nil, "own database")
vim.fn.delete(root .. "/compile_commands.json")
vim.fn.writefile({ "NAME = demo" }, root .. "/Makefile")
h.assert_equal(clangd.compile_command(root, file), nil, "no -I in the Makefile")
vim.fn.writefile({ "CPPFLAGS = -I$(INC) -I include -Ilib/../include" }, root .. "/Makefile")
h.assert_equal(require("epitech.project").build_include_dirs(root, file), { root .. "/include" },
  "variables skipped, paths normalized, no duplicates")
cleanup()

-- "Included header … is not used directly": dropped in a header, and on a
-- project header in a .c; kept on an unused <stdio.h>. Its "remove" fix
-- goes with it.
local dir = vim.fn.tempname()
vim.fn.mkdir(dir, "p")
local header_buf = h.buffer(dir .. "/game.h", { "#include <CSFML/Graphics.h>", '#include "assets.h"' })
local source_buf = h.buffer(dir .. "/main.c", { '#include "game.h"', "#include <stdio.h>", "", "int x;" })
local function unused(row, name)
  return {
    range = { start = { line = row, character = 0 }, ["end"] = { line = row, character = 10 } },
    severity = 2, source = "clangd", code = "unused-includes",
    message = "Included header " .. name .. " is not used directly (fixes available)",
  }
end
local other = {
  range = { start = { line = 3, character = 4 }, ["end"] = { line = 3, character = 5 } },
  severity = 1, source = "clangd", code = "undeclared_var_use", message = "Use of undeclared identifier",
}
pushers = {}
local quiet = assert(vim.lsp.get_client_by_id(assert(vim.lsp.start({ name = "clangd", cmd = server,
  root_dir = dir }, { bufnr = header_buf }))))
assert(vim.wait(2000, function()
  return quiet.initialized
end))
vim.lsp.buf_attach_client(source_buf, quiet.id)
local push = pushers[#pushers]
local function messages(target)
  return vim.tbl_map(function(diagnostic)
    return diagnostic.message
  end, vim.diagnostic.get(target))
end
push.notification("textDocument/publishDiagnostics", { uri = vim.uri_from_bufnr(header_buf),
  diagnostics = { unused(0, "Graphics.h"), unused(1, "assets.h") } })
push.notification("textDocument/publishDiagnostics", { uri = vim.uri_from_bufnr(source_buf),
  diagnostics = { unused(0, "game.h"), unused(1, "stdio.h"), other } })
assert(vim.wait(1000, function()
  return #vim.diagnostic.get(source_buf) > 0
end), "diagnostics published")
h.assert_equal(messages(header_buf), {}, "nothing unused in a header")
h.assert_equal(messages(source_buf), {
  "Included header stdio.h is not used directly (fixes available)", "Use of undeclared identifier",
}, "a project header in a .c is quiet, <stdio.h> isn't")
local fixes = {
  { title = "remove #include directive", kind = "quickfix", diagnostics = { unused(0, "game.h") } },
  { title = "remove #include directive", kind = "quickfix", diagnostics = { unused(1, "stdio.h") } },
}
local filtered = assert(require("epitech.clangd").fix_code_actions(vim.deepcopy(fixes), source_buf))
h.assert_equal(#filtered, 2, "fix_code_actions leaves them to the unused-include filter")
code_actions = fixes
local offered = quiet:request_sync("textDocument/codeAction", {
  textDocument = { uri = vim.uri_from_bufnr(source_buf) },
  range = { start = { line = 0, character = 0 }, ["end"] = { line = 1, character = 0 } },
  context = { diagnostics = {} },
}, 1000, source_buf).result
h.assert_equal(#offered, 1, "the remove fix of a quiet warning is dropped")
h.assert_equal(offered[1].diagnostics[1].message:match("stdio"), "stdio", "the <stdio.h> one stays")
h.assert_equal(require("epitech.clangd").fix_pulled_diagnostics({ items = { unused(1, "assets.h") } }, header_buf)
  .items, {}, "pulled diagnostics too")
quiet:stop(true)

-- Turned off, they all show.
require("epitech").setup({ clangd = { quiet_unused_includes = false } })
pushers = {}
local loud = assert(vim.lsp.get_client_by_id(assert(vim.lsp.start({ name = "clangd", cmd = server,
  root_dir = dir .. "/loud" }, { bufnr = header_buf }))))
assert(vim.wait(2000, function()
  return loud.initialized
end))
pushers[#pushers].notification("textDocument/publishDiagnostics", { uri = vim.uri_from_bufnr(header_buf),
  diagnostics = { unused(1, "assets.h") } })
assert(vim.wait(1000, function()
  return #vim.diagnostic.get(header_buf) > 0
end), "quiet_unused_includes = false")
loud:stop(true)
vim.fn.delete(dir, "rf")

print("Epitech clangd include tests passed")
