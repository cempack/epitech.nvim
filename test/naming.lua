local plugin = assert(vim.env.EPITECH_NVIM_DIR, "EPITECH_NVIM_DIR is required")
vim.opt.runtimepath:prepend(plugin)
package.path = plugin .. "/lua/?.lua;" .. plugin .. "/lua/?/init.lua;" .. package.path

local h = dofile(plugin .. "/test/helpers.lua")
local config = require("epitech.config")
local hints = require("epitech.hints")
local naming = require("epitech.hints.naming")
config.setup()

local function naming_hints(src, path, options)
  local found = {}
  for _, d in ipairs(hints.collect(src, path, { root = "/tmp", options = options })) do
    if d.code == "C-F2" or d.code == "C-O4" or d.code == "C-V1" then
      found[#found + 1] = { d.lnum + 1, d.message }
    end
  end
  table.sort(found, function(a, b)
    return a[1] < b[1]
  end)
  return found
end

local src = table.concat(vim.fn.readfile(plugin .. "/test/fixtures/hints/naming.c"), "\n")
h.assert_equal(naming_hints(src, "src/naming.c"), {
  { 1, "C-V1 macros in UPPER_SNAKE_CASE → BUFFER_SIZE?" },
  { 5, "C-V1 typedef names end in _t → player_t?" },
  { 9, "C-V1 enum values in UPPER_SNAKE_CASE → RED?" },
  { 13, "C-V1 global constants in UPPER_SNAKE_CASE → MAX_PLAYERS?" },
  { 17, "C-F2 no verb → get_vowels_number?" },
  { 22, "C-F2 no verb in player_hp" },
}, "naming hints (not MAX, _GNU_SOURCE, pixel_t, GREEN, a pointer to const, LIMIT, my_strlen, get_x,"
  .. " putstr_error, my_display or main)")

h.assert_equal(naming_hints("int main(void)\n{\n    return 0;\n}", "src/utils.c"), {
  { 1, "C-O4 vague name: utils.c" },
}, "vague file name")
h.assert_equal(naming_hints("", "src/string_toolbox.c"), {}, "precise file name")

-- Custom lists replace the built-in ones.
local custom = config.merge({ hints = { naming = { verbs = { "vowels" }, vague_files = { "toolbox" } } } }).hints
h.assert_equal(vim.tbl_map(function(d)
  return d[2]
end, naming_hints("int vowels_number(void)\n{\n    return 0;\n}", "src/toolbox.c", custom)), {
  "C-O4 vague name: toolbox.c",
}, "custom verbs and vague names")
h.assert_equal(naming_hints(src, "src/naming.c", config.merge({ hints = { naming = false } }).hints), {},
  "naming = false")

h.assert_equal({ naming.has_verb("my_putstr_error", naming.verbs), naming.has_verb("vowels", naming.verbs) },
  { true, false }, "has_verb")
h.assert_equal(vim.tbl_map(function(name)
  return naming.has_verb(name, naming.verbs)
end, { "dispatch", "skip_spaces", "shell_loop", "str_to_int", "to_upper", "int_to", "player_pos", "window_size",
  "map_width", "player_hitbox", "user_name" }),
  { true, true, true, true, false, false, false, false, false, false, false },
  "more verbs, x_to_y conversions, and nouns that start like verbs")
h.assert_equal(naming.upper_snake("bufferSize2Max"), "BUFFER_SIZE2_MAX", "upper_snake")

print("Epitech naming hint tests passed")
