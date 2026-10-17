local plugin = assert(vim.env.EPITECH_NVIM_DIR, "EPITECH_NVIM_DIR is required")
vim.opt.runtimepath:prepend(plugin)
package.path = plugin .. "/lua/?.lua;" .. plugin .. "/lua/?/init.lua;" .. package.path

local h = dofile(plugin .. "/test/helpers.lua")
local expand = dofile(plugin .. "/test/snippet_expand.lua")
require("epitech.config").setup()

-- The files parse and blink.cmp's manifest points at c.json.
local dir = require("epitech").snippets_dir()
h.assert_equal(dir, plugin .. "/snippets", "snippets_dir()")
local manifest = vim.json.decode(table.concat(vim.fn.readfile(dir .. "/package.json"), "\n"))
h.assert_equal(manifest.contributes.snippets, { { language = "c", path = "./c.json" } }, "package.json")

local prefixes = {}
for _, snippet in pairs(expand.snippets) do
  prefixes[#prefixes + 1] = snippet.prefix
  assert(snippet.description and snippet.description ~= "", snippet.prefix .. " description")
  for _, line in ipairs(snippet.body) do
    assert(not line:find("${%d+/"), snippet.prefix .. ": no regex transforms (Neovim can't expand them)")
  end
end
table.sort(prefixes)
h.assert_equal(prefixes, { "fn", "fori", "ife", "main", "mal", "sfn", "sw", "tdef", "tenum" }, "every snippet")

h.assert_equal(expand.expand(expand.snippets["Epitech for loop"].body), {
  "for (int i = 0; i < n; i++) {", "    break;", "}",
}, "mirrors and defaults")

-- Neovim's own snippet engine (what blink.cmp expands with) gives the same
-- text with the defaults.
for name, snippet in pairs(expand.snippets) do
  local buf = h.buffer("/tmp/epitech_snippet_engine.c", {})
  vim.snippet.expand(table.concat(snippet.body, "\n"))
  vim.snippet.stop()
  h.assert_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), expand.expand(snippet.body), name .. " in vim.snippet")
end

-- Each expanded snippet comes out of the formatter unchanged.
for prefix, context in pairs(expand.contexts()) do
  local buf = h.buffer("/tmp/epitech_snippet_" .. prefix .. ".c", context[1])
  require("epitech").format_buffer(buf)
  h.assert_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), context[1], prefix .. " passes the formatter")
end

print("Epitech snippet tests passed")
