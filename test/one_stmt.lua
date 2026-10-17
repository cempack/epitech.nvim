local plugin = assert(vim.env.EPITECH_NVIM_DIR, "EPITECH_NVIM_DIR is required")
vim.opt.runtimepath:prepend(plugin)
package.path = plugin .. "/lua/?.lua;" .. plugin .. "/lua/?/init.lua;" .. package.path

local h = dofile(plugin .. "/test/helpers.lua")
local hints = require("epitech.hints")
require("epitech.config").setup()

-- §9.13 before/after for every pattern.
h.check_fix("one_stmt", "chain_constant", 5, "Split the chained assignment (C-L1)", "C-L1")
h.check_fix("one_stmt", "chain_call", 5, "Split the chained assignment (C-L1)", "C-L1")
h.check_fix("one_stmt", "increment", 2, "Move i++; to its own line (C-L1)", "C-L1")
h.check_fix("one_stmt", "prefix", 4, "Move i++; to its own line (C-L1)", "C-L1")
h.check_fix("one_stmt", "if_assign", 4, "Move the assignment out of the condition (C-L1)", "C-L1")
h.check_fix("one_stmt", "and", 2, "Turn the && into an if (C-L1)", "C-L1")
h.check_fix("one_stmt", "or", 2, "Turn the || into an if (C-L1)", "C-L1")
h.check_fix("one_stmt", "or_expression", 2, "Turn the || into an if (C-L1)", "C-L1")

-- Refusals: a hint, and no action.
local function refused(body)
  local lines = vim.list_extend({ "int f(char *s, char const *t, int i, int c)", "{" }, body)
  table.insert(lines, "}")
  local buf = h.buffer("/tmp/epitech_one_stmt_refused.c", lines)
  h.assert_equal(h.actions_for((h.code_actions(buf)), "C-L1"), {}, "no action: " .. body[1])
  return vim.tbl_map(function(d)
    return { d.lnum, d.message }
  end, vim.tbl_filter(function(d)
    return d.code == "C-L1"
  end, hints.collect(table.concat(lines, "\n"), "x.c", { root = "/tmp" })))
end
h.assert_equal(refused({ "    s[i++] = t[i];" }), {
  { 2, "C-L1 no automatic fix: i is used twice on this line, so its behaviour is undefined" },
}, "undefined behaviour")
h.assert_equal(refused({ "    if (i) {", "        return 1;", "    } else if ((c = i) > 2) {", "        return c;", "    }",
  "    return 0;" }), {
  { 4, "C-L1 no automatic fix: in an else if, the assignment would run before the earlier conditions" },
}, "assignment in an else if")
h.assert_equal(refused({ "    if (i > 0 && (c = i) > 2) {", "        return c;", "    }", "    return 0;" }), {
  { 2, "C-L1 no automatic fix: the assignment only runs when the condition before it allows" },
}, "assignment on the right of &&")
h.assert_equal(refused({ "    while ((c = getchar()) != EOF) {", "        i++;", "    }", "    return i;" }), {
  { 2, "C-L1 no automatic fix: the assignment would have to be repeated before the loop and at the end of its body,"
    .. " and a continue would skip it" },
}, "assignment in a while condition")
local cond = h.buffer("/tmp/epitech_one_stmt_cond.c", { "void f(char *s, int i)", "{", "    i > 0 && s[i--];", "}" })
h.assert_equal(vim.tbl_map(function(action)
  return action.title
end, h.actions_for((h.code_actions(cond)), "C-L1")), { "Turn the && into an if (C-L1)" },
  "an update on the right of && isn't moved out, the && becomes an if")
local chain = h.buffer("/tmp/epitech_one_stmt_chain.c", { "void f(char *s, char *t, int i, int c)", "{",
  "    s[i] = t[i] = c++;", "}" })
h.assert_equal(vim.tbl_map(function(action)
  return action.title
end, h.actions_for((h.code_actions(chain)), "C-L1")), {
  "Split the chained assignment (C-L1)", "Move c++; to its own line (C-L1)",
}, "both patterns on one line, each its own action")
local actions, client = h.code_actions(chain)
h.apply_action(h.actions_for(actions, "C-L1")[1], client)
h.assert_equal(vim.api.nvim_buf_get_lines(chain, 2, 4, false), { "    t[i] = c++;", "    s[i] = t[i];" },
  "a value with side effects is evaluated once")

-- A plain i++; is already one statement.
local buf = h.buffer("/tmp/epitech_one_stmt_plain.c", { "void f(int i)", "{", "    i++;", "    (i)--;", "}" })
h.assert_equal(h.actions_for((h.code_actions(buf)), "C-L1"), {}, "nothing to do")

print("Epitech one statement per line tests passed")
