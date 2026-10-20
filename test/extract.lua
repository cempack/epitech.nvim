local plugin = assert(vim.env.EPITECH_NVIM_DIR, "EPITECH_NVIM_DIR is required")
vim.opt.runtimepath:prepend(plugin)
package.path = plugin .. "/lua/?.lua;" .. plugin .. "/lua/?/init.lua;" .. package.path

local h = dofile(plugin .. "/test/helpers.lua")
local extract = require("epitech.fixes.extract")
require("epitech").setup()

local notices = {}
vim.notify = function(message)
  notices[#notices + 1] = message
end

local dir = plugin .. "/test/fixtures/fixes/extract/"

-- Each case: rows (1-based, as selected), the name typed, and the expected
-- file, which the formatter keeps as it is.
local function check(case, first, last, name)
  local buf = h.buffer("/tmp/epitech_extract_" .. case .. ".c", vim.fn.readfile(dir .. case .. ".before.c"))
  extract.extract(buf, first - 1, last - 1, name)
  local expected = vim.fn.readfile(dir .. case .. ".after.c")
  h.assert_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), expected, case .. ": result")
  require("epitech").format_buffer(buf)
  h.assert_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), expected, case .. ": formatter leaves it unchanged")
  return buf
end

-- Declarations only the selection uses move with it; a struct goes by
-- pointer (C-F7), with -> for its fields; what's only read goes by value.
check("moved", 17, 27, "count_words")
-- Up to the end of the function, its returns come along.
check("tail_return", 8, 13, "search_word")
-- What's read after the selection goes by pointer; an array as a pointer.
check("pointers", 6, 9, "add_lines")
-- Inside a loop, what the selection changes goes by pointer even when
-- nothing after it reads it: the next turn does. `.` on an unknown type
-- means a struct.
check("in_loop", 6, 10, "step_on")
-- C-F3: a long signature and call are wrapped like the formatter does.
check("long_call", 6, 9, "process_configuration_entries_until_limit")

-- Refusals, with their reasons.
local refusals = h.buffer("/tmp/epitech_extract_refusals.c", {
  "int bad(int a, int b, int c, int d, int e)", -- 1
  "{",
  "    int x = 0;",
  "    int y = 1;",
  "",
  "    if (a)", -- 6
  "        return 1;",
  "    for (int i = 0; i < a; i++) {",
  "        if (i == b)",
  "            break;", -- 10
  "        x += i;",
  "    }",
  "    x = a + b + c + d + e;",
  "    int late = x;",
  "    my_put_nbr(late);", -- 15
  "    goto end;",
  "    return x + y;",
  "}",
  "",
  "void sized(void)", -- 20
  "{",
  "    char buf[64];",
  "",
  "    my_memset(buf, 0, sizeof(buf));",
  "    my_putstr(buf);", -- 25
  "}",
})
local function reason(first, last)
  local plan = extract.plan(refusals, first - 1, last - 1)
  return plan and plan.refused
end
h.assert_equal(reason(6, 7), "a return would leave the new function instead of this one; select up to the end of the"
  .. " function to keep it", "return")
h.assert_equal(reason(9, 10), "a break would leave the selection", "break")
h.assert_equal(reason(13, 13), "the new function would take 6 parameters (C-F5 allows 4)", "C-F5")
h.assert_equal(reason(14, 14), "the selection only declares variables", "only declarations")
h.assert_equal(reason(13, 14), "late is declared in the selection and used after it", "used after")
h.assert_equal(reason(16, 16), "goto and labels can't move to another function", "goto")
h.assert_equal(reason(3, 3), "select all the declarations at the top of the function, or none", "C-L5")
h.assert_equal(reason(24, 24), "sizeof buf would measure a pointer in the new function", "sizeof")
h.assert_equal(extract.plan(refusals, 0, 2), nil, "the signature isn't a statement")

-- The code action: only on a selection, titled with the reason when refused.
local buf = h.buffer("/tmp/epitech_extract_action.c", vim.fn.readfile(dir .. "moved.before.c"))
local function titles(range)
  return vim.tbl_map(function(action)
    return action.title
  end, h.actions_for((h.code_actions(buf, range)), "C-F4"))
end
local selection = { start = { line = 16, character = 0 }, ["end"] = { line = 26, character = 9 } }
h.assert_equal(titles(selection), { "Extract to a function… (C-F4)" }, "action on a selection")
h.assert_equal(titles({ start = { line = 16, character = 4 }, ["end"] = { line = 16, character = 4 } }), {},
  "no action at the cursor alone")
h.assert_equal(titles({ start = { line = 12, character = 0 }, ["end"] = { line = 13, character = 0 } }),
  { "Can't extract to a function: select all the declarations at the top of the function, or none" },
  "a refusal says why; a range ending at a line's start doesn't take that line")
vim.ui.input = function(opts, on_confirm)
  h.assert_equal(opts.prompt, "Name of the new function: ", "prompt")
  on_confirm("count_words")
end
local actions, client = h.code_actions(buf, selection)
client:exec_cmd(h.actions_for(actions, "C-F4")[1].command, { bufnr = buf })
h.assert_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), vim.fn.readfile(dir .. "moved.after.c"),
  "the action asks for the name and extracts")
h.assert_equal(titles({ start = { line = 0, character = 0 }, ["end"] = { line = 40, character = 0 } }), {},
  "nothing offered on the whole file")

-- Names: snake_case, not a keyword, a variable or an existing function.
local plan = extract.plan(h.buffer("/tmp/epitech_extract_names.c", vim.fn.readfile(dir .. "moved.before.c")), 16, 26)
local names = vim.api.nvim_get_current_buf()
h.assert_equal({
  extract.check_name(plan, names, "countWords"),
  extract.check_name(plan, names, "while"),
  extract.check_name(plan, names, "stats"),
  extract.check_name(plan, names, "count_text"),
  extract.check_name(plan, names, "count_words"),
}, {
  "use snake_case (C-F2, C-V1)",
  "while is a C keyword",
  "stats is a variable here",
  "count_text already exists",
}, "name checks")
notices = {}
extract.extract(names, 16, 26, "count_text")
h.assert_equal(notices, { "Can't name it count_text: count_text already exists" }, "a bad name is reported")
notices = {}
extract.extract(refusals, 5, 6, "early")
h.assert_equal(notices, { "Can't extract to a function: a return would leave the new function instead of this one;"
  .. " select up to the end of the function to keep it" }, "a refusal is reported")

-- :EpitechExtract on a range, with the name as argument.
local command_buf = h.buffer("/tmp/epitech_extract_command.c", vim.fn.readfile(dir .. "tail_return.before.c"))
vim.cmd("8,13EpitechExtract search_word")
h.assert_equal(vim.api.nvim_buf_get_lines(command_buf, 0, -1, false), vim.fn.readfile(dir .. "tail_return.after.c"),
  ":EpitechExtract")

print("Epitech extract function tests passed")
