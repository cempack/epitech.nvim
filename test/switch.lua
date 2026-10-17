local plugin = assert(vim.env.EPITECH_NVIM_DIR, "EPITECH_NVIM_DIR is required")
vim.opt.runtimepath:prepend(plugin)
package.path = plugin .. "/lua/?.lua;" .. plugin .. "/lua/?/init.lua;" .. package.path

local h = dofile(plugin .. "/test/helpers.lua")
local hints = require("epitech.hints")
require("epitech.config").setup()

local TITLE = "Convert to switch (C-C1)"

-- §9.14 conversions.
h.check_fix("switch", "flags", 2, TITLE, "C-C1")
h.check_fix("switch", "numbers", 2, TITLE, "C-C1")
h.check_fix("switch", "or", 4, TITLE, "C-C1")

-- Refusals.
local function chain(conditions, body)
  local lines = { "int f(int x, int y)", "{", "    while (y > 0) {" }
  for i, condition in ipairs(conditions) do
    lines[#lines + 1] = (i == 1 and "        if (" or "        } else if (") .. condition .. ") {"
    lines[#lines + 1] = "            " .. (body or "y--;")
  end
  vim.list_extend(lines, { "        }", "    }", "    return y;", "}" })
  local buf = h.buffer("/tmp/epitech_switch_refused.c", lines)
  local titles = vim.tbl_map(function(action)
    return action.title
  end, h.actions_for((h.code_actions(buf)), "C-C1"))
  local found = vim.tbl_map(function(d)
    return d.message
  end, vim.tbl_filter(function(d)
    return d.code == "C-C1"
  end, hints.collect(table.concat(lines, "\n"), "x.c", { root = "/tmp" })))
  return titles, found
end
local titles, found = chain({ "x == 1", "x == 2", "x == 3" })
h.assert_equal(titles, { TITLE }, "nested chain reaching depth 3 is offered")
titles, found = chain({ "x == 1", "x < 2", "x == 3" })
h.assert_equal({ titles, found }, { {}, {} }, "refused on <")
titles, found = chain({ "x == 1", "get_next() == 2", "x == 3" })
h.assert_equal({ titles, found }, { {}, {} }, "refused on a side effect in a condition")
titles, found = chain({ "x == 1", "x == 1", "x == 3" })
h.assert_equal({ titles, found }, { {}, {} }, "refused on duplicate constants")
titles, found = chain({ "x == 1", "x == 2", "x == 3" }, "break;")
h.assert_equal({ titles, found }, { {}, { "C-C1 no automatic switch: a break in a branch would act on the switch" } },
  "refused on an inner break, with a hint")
titles, found = chain({ "x == 1", "x == 2", "x == 3" }, "int z = y;")
h.assert_equal({ titles, found }, { {}, { "C-C1 no automatic switch: a branch declares a variable, which can't follow"
  .. " a case label" } }, "refused on a declaration")

-- A short chain that breaks no rule isn't touched.
local short = h.buffer("/tmp/epitech_switch_short.c", { "int f(int x)", "{", "    if (x == 1) {", "        return 1;",
  "    } else if (x == 2) {", "        return 2;", "    }", "    return 0;", "}" })
h.assert_equal(h.actions_for((h.code_actions(short)), "C-C1"), {}, "no action on a fine chain")

print("Epitech switch conversion tests passed")
