local plugin = assert(vim.env.EPITECH_NVIM_DIR, "EPITECH_NVIM_DIR is required")
vim.opt.runtimepath:prepend(plugin)
package.path = plugin .. "/lua/?.lua;" .. plugin .. "/lua/?/init.lua;" .. package.path

local h = dofile(plugin .. "/test/helpers.lua")
local format = require("epitech.format")

-- Formats lines twice: the result, which must not change the second time.
local function formatted(name, lines)
  local buf = h.buffer("/tmp/epitech_wrap_" .. name .. ".c", lines)
  format.format_buffer(buf)
  local once = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  format.format_buffer(buf)
  h.assert_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), once, name .. ": idempotent")
  for _, line in ipairs(once) do
    assert(#line <= 79, name .. ": over 79 columns: " .. line)
  end
  return once
end

-- C-L2: every wrapped line one level below its statement's first line, never
-- deeper ("level 4 indentation (should be 3)"); arguments wrap after a comma,
-- not right after the call's '('; a comparison doesn't sit alone on a line.
h.assert_equal(formatted("condition", {
  "int parse(int argc, char **argv)",
  "{",
  "    if (argc > 1) {",
  "        if (parse_options(argc, &parsed_arguments, argv, options) == -1 || parse_file_arguments(argc,"
    .. " &parsed_arguments, argv, file_arguments) == -1) {",
  "            return -1;",
  "        }",
  "    }",
  "    return 0;",
  "}",
}), {
  "int parse(int argc, char **argv)",
  "{",
  "    if (argc > 1) {",
  "        if (parse_options(argc, &parsed_arguments, argv, options) == -1",
  "            || parse_file_arguments(argc, &parsed_arguments, argv,",
  "            file_arguments) == -1) {",
  "            return -1;",
  "        }",
  "    }",
  "    return 0;",
  "}",
}, "nested call in a condition")

h.assert_equal(formatted("statements", {
  "int show(char const *name, int entries, int directories, int files_count)",
  "{",
  '    my_printf("%s: %d entries, %d directories and %d files\\n", name, entries, directories, files_count);',
  "    while (current != NULL && current->next != NULL && my_strcmp(current->name, current->next->name) > 0) {",
  "        current = current->next;",
  "    }",
  "    return my_put_error_message_and_exit_with_code(program_name, error_message, EXIT_FAILURE);",
  "}",
}), {
  "int show(char const *name, int entries, int directories, int files_count)",
  "{",
  '    my_printf("%s: %d entries, %d directories and %d files\\n", name, entries,',
  "        directories, files_count);",
  "    while (current != NULL && current->next != NULL",
  "        && my_strcmp(current->name, current->next->name) > 0) {",
  "        current = current->next;",
  "    }",
  "    return my_put_error_message_and_exit_with_code(program_name, error_message,",
  "        EXIT_FAILURE);",
  "}",
}, "calls, loop conditions and returns")

-- Deeply nested calls still end up one level down.
local deep = formatted("deep", {
  "void draw(game_t *game)",
  "{",
  "    if (game->running) {",
  "        while (game->window) {",
  "            sfRenderWindow_drawSprite(game->window, get_sprite_from_name(game->sprites, compute_sprite_name(game->player->state, game->player->direction)), NULL);",
  "        }",
  "    }",
  "}",
})
for i = 6, #deep - 3 do
  h.assert_equal(deep[i]:match("^ *"), string.rep(" ", 16), "deep: line " .. i .. " one level below its statement")
end

-- A for header, a do while condition and a signature.
h.assert_equal(formatted("headers", {
  "int count_matching_entries(char const *first_directory_path, char const *second_directory_path)",
  "{",
  "    int count = 0;",
  "",
  "    for (int index = 0; index < maximum_number_of_entries && entries[index] != NULL; index++) {",
  "        count++;",
  "    }",
  "    do {",
  "        count--;",
  "    } while (count > 0 && my_strcmp(first_directory_path, second_directory_path) != 0);",
  "    return count;",
  "}",
}), {
  "int count_matching_entries(char const *first_directory_path,",
  "    char const *second_directory_path)",
  "{",
  "    int count = 0;",
  "",
  "    for (int index = 0;",
  "        index < maximum_number_of_entries && entries[index] != NULL; index++) {",
  "        count++;",
  "    }",
  "    do {",
  "        count--;",
  "    } while (count > 0",
  "        && my_strcmp(first_directory_path, second_directory_path) != 0);",
  "    return count;",
  "}",
}, "for, do while and signature")

-- A parameter is never split between its type and its name (a too high
-- penalty on breaking after '(' did that), and typedefs are flattened too.
h.assert_equal(formatted("typedef", {
  "typedef int (*very_long_function_pointer_type_name_t)(char const *first_argument, int second_argument, void *third);",
}), {
  "typedef int (*very_long_function_pointer_type_name_t)(",
  "    char const *first_argument, int second_argument, void *third);",
}, "function pointer typedef")

-- Initializer lists keep clang-format's layout; a comment inside a wrapped
-- statement leaves it alone (joining a line after it would comment it out).
local untouched = {
  "static const flag_t FLAGS[] = {",
  "    {'l', &print_long_format_for_every_single_entry},",
  "    {'R', &print_recursively_every_directory_found},",
  "};",
}
h.assert_equal(formatted("initializer", untouched), untouched, "initializer list")

print("Epitech formatter wrap tests passed")
