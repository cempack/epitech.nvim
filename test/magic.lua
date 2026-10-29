local plugin = assert(vim.env.EPITECH_NVIM_DIR, "EPITECH_NVIM_DIR is required")
vim.opt.runtimepath:prepend(plugin)
package.path = plugin .. "/lua/?.lua;" .. plugin .. "/lua/?/init.lua;" .. package.path

local h = dofile(plugin .. "/test/helpers.lua")
local config = require("epitech.config")
local hints = require("epitech.hints")
local magic = require("epitech.hints.magic")
config.setup()

local notices = {}
vim.notify = function(message)
  notices[#notices + 1] = message
end

h.assert_equal({ magic.value("4096"), magic.value("0x1F"), magic.value("010"), magic.value("0b11"),
  magic.value("1.5f"), magic.value("42UL") }, { 4096, 31, 8, 3, 1.5, 42 }, "literal values")

-- §9.6 hints: 4096 and 42 are flagged, 0, 1, -1 and 84 aren't, nor anything
-- in #define, enums or global constants.
local fixture = vim.fn.readfile(plugin .. "/test/fixtures/hints/magic.c")
local src = table.concat(fixture, "\n")
local function only_g9(diagnostics)
  return vim.tbl_filter(function(d)
    return d.code == "C-G9"
  end, diagnostics)
end
local found = vim.tbl_map(function(d)
  return { d.lnum, d.col, d.code, d.message, d.severity, d.source }
end, only_g9(hints.collect(src, "magic.c", { root = "/tmp" })))
local HINT = vim.diagnostic.severity.HINT
h.assert_equal(found, {
  { 17, 16, "C-G9", "C-G9 name this number?", HINT, "epitech.nvim" },
  { 20, 20, "C-G9", "C-G9 name this number?", HINT, "epitech.nvim" },
  { 21, 17, "C-G9", "C-G9 name this number?", HINT, "epitech.nvim" },
  { 21, 32, "C-G9", "C-G9 name this number?", HINT, "epitech.nvim" },
  { 24, 19, "C-G9", "C-G9 name this number?", HINT, "epitech.nvim" },
}, "magic number hints (4096, 42, -5, 0x10, 2.5)")

-- Obvious numbers: argument counts and positions, 2 and 10 as a factor,
-- divisor or modulus, a const variable's value, a standard file descriptor
-- given to write(). Not: 10 as a dividend, 3 as a divisor, 2 compared with
-- something else, a length, a descriptor given to another function.
local obvious_src = table.concat({
  "int main(int ac, char **av)",
  "{",
  "    const int limit = 4;",
  "    int nb = 0;",
  "",
  "    if (ac != 2 || argc < 3 || av[2] == 0)",
  "        return 84;",
  "    nb = nb * 10 + nb % 10 + nb / 2 + 2 * nb;",
  "    nb *= 10;",
  "    nb = 10 / nb + nb / 3;",
  "    write(2, \"ab\", 2);",
  "    my_write(2, \"ab\");",
  "    return nb == 2 ? limit : 5;",
  "}",
}, "\n")
h.assert_equal(vim.tbl_map(function(literal)
  return { literal.row, literal.text }
end, magic.literals(require("epitech.ts").parse_string(obvious_src), obvious_src, { 0, 1, -1, 84 })),
  { { 9, "10" }, { 9, "3" }, { 10, "2" }, { 11, "2" }, { 12, "2" }, { 12, "5" } }, "obvious numbers aren't flagged")

-- The allow list and the switches.
h.assert_equal(#only_g9(hints.collect(src, "magic.c", { root = "/tmp", options = config.merge({
  hints = { magic_numbers = { allow = { 0, 1, -1, 84, 4096, 42, -5, 16, 2.5 } } },
}).hints })), 0, "allowed numbers")
h.assert_equal(#only_g9(hints.collect(src, "magic.c", { root = "/tmp", options = config.merge({
  hints = { magic_numbers = false },
}).hints })), 0, "magic_numbers = false")

-- The runner: buffer hints, Banana dedup and :EpitechHints.
local buf = h.buffer("/tmp/epitech_magic.c", fixture)
hints.refresh(buf)
h.assert_equal(#only_g9(vim.diagnostic.get(buf, { namespace = hints.ns })), 5, "hints on the buffer")
vim.diagnostic.set(require("epitech.banana").ns, buf, {
  { lnum = 20, col = 0, message = "named by Banana", code = "C-G9", source = "Banana" },
})
hints.refresh(buf)
h.assert_equal(vim.tbl_map(function(d)
  return d.lnum
end, only_g9(vim.diagnostic.get(buf, { namespace = hints.ns }))), { 17, 21, 21, 24 },
  "hint dropped where Banana says the same")
h.assert_equal(#hints.dedup({ { lnum = 20, code = "C-G9", user_data = { keep = true } } },
  { { lnum = 20, code = "C-G9" } }), 1, "explanations are kept")
vim.diagnostic.reset(require("epitech.banana").ns, buf)

require("epitech").setup()
vim.cmd("EpitechHints off")
h.assert_equal(#vim.diagnostic.get(buf, { namespace = hints.ns }), 0, ":EpitechHints off clears them")
vim.cmd("EpitechHints on")
h.assert_equal(#only_g9(vim.diagnostic.get(buf, { namespace = hints.ns })), 5, ":EpitechHints on brings them back")
vim.cmd("EpitechHints")
h.assert_equal(hints.is_active(), false, ":EpitechHints toggles")
vim.cmd("EpitechHints on")

-- Edits refresh the hints after the debounce.
vim.api.nvim_buf_set_lines(buf, 20, 21, false, { "    total = total + 7;" })
vim.api.nvim_exec_autocmds("TextChanged", { buffer = buf })
assert(vim.wait(2000, function()
  local d = vim.diagnostic.get(buf, { namespace = hints.ns, lnum = 20 })[1]
  return d and d.col == 20 and #only_g9(vim.diagnostic.get(buf, { namespace = hints.ns })) == 5
end), "hints refreshed after an edit")

-- §9.6 fix: extract into a macro in the project header.
local root, cleanup = h.temp_project({
  ["Makefile"] = { "NAME = demo" },
  ["include/demo.h"] = { "#ifndef DEMO_H_", "    #define DEMO_H_", "", "int read_all(int fd);", "", "#endif" },
  ["include/other.h"] = { "#ifndef OTHER_H_", "    #define OTHER_H_", "    #define PAGE (4096)", "#endif" },
  ["src/main.c"] = {
    "/*", "** EPITECH PROJECT, 2026", "** demo", "** File description:", "** Main", "*/", "",
    "#include <unistd.h>", "",
    "int read_all(int fd)", "{", "    char buffer[4096];", "", "    return read(fd, buffer, 4096);", "}",
  },
})
local main = h.buffer(root .. "/src/main.c", vim.fn.readfile(root .. "/src/main.c"))
local actions, client = h.code_actions(main, h.rows(11))
h.assert_equal(vim.tbl_map(function(action)
  return action.title
end, actions), { "Extract 4096 into a macro…" }, "extract action")

local prompts = {}
vim.ui.select = function(items, opts, on_choice)
  local texts = vim.tbl_map(opts.format_item or tostring, items)
  prompts[#prompts + 1] = texts
  -- Pick "New macro…" first, then "All 2 occurrences".
  on_choice(items[#items])
end
local default
vim.ui.input = function(opts, on_confirm)
  default = opts.default
  on_confirm("BUFFER_SIZE")
end
client:exec_cmd(actions[1].command, { bufnr = main })
h.assert_equal(prompts, { { "PAGE (include/other.h)", "New macro…" }, { "This one", "All 2 occurrences" } },
  "an existing macro with the same value comes first")
h.assert_equal(default, "BUFFER_SIZE", "array size suggests NAME_SIZE")
local fixed = {
  "/*", "** EPITECH PROJECT, 2026", "** demo", "** File description:", "** Main", "*/", "",
  "#include <unistd.h>", '#include "demo.h"', "",
  "int read_all(int fd)", "{", "    char buffer[BUFFER_SIZE];", "", "    return read(fd, buffer, BUFFER_SIZE);", "}",
}
h.assert_equal(vim.api.nvim_buf_get_lines(main, 0, -1, false), fixed, "literals replaced and header included")
h.assert_equal(vim.fn.readfile(root .. "/include/demo.h"), {
  "#ifndef DEMO_H_", "    #define DEMO_H_", "    #define BUFFER_SIZE 4096", "", "int read_all(int fd);", "", "#endif",
}, "define inserted inside the guard")
h.assert_equal(h.actions_for((h.code_actions(main)), "C-G9"), {}, "idempotent")
require("epitech").format_buffer(main)
h.assert_equal(vim.api.nvim_buf_get_lines(main, 0, -1, false), fixed, "the formatter keeps the result")

-- Using an existing macro: no new #define, its header gets included.
vim.api.nvim_buf_set_lines(main, 13, 14, false, { "    return read(fd, buffer, 4096);" })
actions = h.code_actions(main, h.rows(13))
local offered_macros
vim.ui.select = function(items, opts, on_choice)
  offered_macros = vim.tbl_map(opts.format_item, items)
  on_choice(items[2])
end
client:exec_cmd(actions[1].command, { bufnr = main })
h.assert_equal(offered_macros, { "BUFFER_SIZE (include/demo.h)", "PAGE (include/other.h)", "New macro…" },
  "every macro with that value")
h.assert_equal(vim.api.nvim_buf_get_lines(main, 7, 10, false), { "#include <unistd.h>", '#include "demo.h"',
  '#include "other.h"' }, "existing macro's header included")
h.assert_equal(vim.api.nvim_buf_get_lines(main, 14, 15, false), { "    return read(fd, buffer, PAGE);" },
  "existing macro used")

-- Names are checked against UPPER_SNAKE_CASE and existing definitions.
vim.api.nvim_buf_set_lines(main, 14, 15, false, { "    return read(fd, buffer, 512);" })
local before = vim.api.nvim_buf_get_lines(main, 0, -1, false)
for _, name in ipairs({ "buffer_size", "BUFFER_SIZE" }) do
  vim.ui.input = function(_, on_confirm)
    on_confirm(name)
  end
  notices = {}
  client:exec_cmd(h.code_actions(main, h.rows(14))[1].command, { bufnr = main })
  h.assert_equal(vim.api.nvim_buf_get_lines(main, 0, -1, false), before, name .. " refused")
end
h.assert_equal(notices, { "BUFFER_SIZE is already defined as 4096" }, "redefinition refused")

-- A new project header is created with an Epitech header and a guard.
local fresh, cleanup_fresh = h.temp_project({
  ["Makefile"] = { "NAME = fresh" },
  ["src/main.c"] = { "int get_width(void)", "{", "    int width = 1920;", "", "    return width;", "}" },
})
local fresh_main = h.buffer(fresh .. "/src/main.c", vim.fn.readfile(fresh .. "/src/main.c"))
vim.ui.select = function(items, _, on_choice)
  on_choice(items[1])
end
vim.ui.input = function(opts, on_confirm)
  default = opts.default
  on_confirm(opts.default)
end
actions, client = h.code_actions(fresh_main, h.rows(2))
client:exec_cmd(actions[1].command, { bufnr = fresh_main })
h.assert_equal(default, "WIDTH", "an initialized variable suggests its name")
h.assert_equal(vim.fn.readfile(fresh .. "/include/fresh.h"), {
  "/*", "** EPITECH PROJECT, " .. os.date("%Y"), "** fresh", "** File description:", "** Declarations for fresh", "*/",
  "", "#ifndef FRESH_H_", "    #define FRESH_H_", "    #define WIDTH 1920", "", "#endif",
}, "new header")
h.assert_equal(vim.api.nvim_buf_get_lines(fresh_main, 0, 3, false), { '#include "fresh.h"', "", "int get_width(void)" },
  "include added at the top of a file without a header")

require("epitech.fixes.macro").insert_define(fresh, fresh .. "/include/fresh.h", "OFFSET", "-5")
h.assert_equal(vim.fn.readfile(fresh .. "/include/fresh.h")[11], "    #define OFFSET (-5)", "negative values in parentheses")

cleanup()
cleanup_fresh()
print("Epitech magic number tests passed")
