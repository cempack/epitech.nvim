local plugin = assert(vim.env.EPITECH_NVIM_DIR, "EPITECH_NVIM_DIR is required")
vim.opt.runtimepath:prepend(plugin)
package.path = plugin .. "/lua/?.lua;" .. plugin .. "/lua/?/init.lua;" .. package.path

local h = dofile(plugin .. "/test/helpers.lua")
local make = require("epitech.make")
require("epitech").setup()
local notices = {}
vim.notify = function(message)
  notices[#notices + 1] = message
end

local function short(items)
  return vim.tbl_map(function(item)
    return ("%s %s:%d:%d %s"):format(item.type, item.filename and vim.fs.basename(item.filename) or "-",
      item.lnum or 0, item.col or 0, item.text)
  end, items)
end

-- Compiler errors and warnings (epiclang prints its warnings twice), notes,
-- a sub-make's own directory, the linker and make itself.
local parsed = make.parse({
  "epiclang -I./include -c -o src/main.o src/main.c",
  "src/main.c:7:5: error: use of undeclared identifier 'x'",
  "    7 |     x = 2;",
  "      |     ^",
  "src/main.c:3:1: warning: [Banana] [Major] multiple statements on the same line (C-L1)",
  "src/main.c:3:1: warning: [Banana] [Major] multiple statements on the same line (C-L1)",
  "\27[1msrc/main.c:9:10: \27[0;1;35mwarning: \27[0munused variable 'y' [-Wunused-variable]",
  "src/main.c:2:6: note: previous declaration is here",
  "make[1]: Entering directory '/project/lib/my'",
  "my_strlen.c:4:12: error: expected ';' after return statement",
  "make[1]: Leaving directory '/project/lib/my'",
  "/usr/bin/ld: src/main.o: in function `main':",
  "main.c:(.text+0x1e): undefined reference to `print_help'",
  "collect2: error: ld returned 1 exit status",
  "make: *** No rule to make target 'src/gone.c', needed by 'demo'.  Stop.",
  "make: *** [Makefile:12: demo] Error 1",
}, "/project")
h.assert_equal(short(parsed.items), {
  "E main.c:7:5 use of undeclared identifier 'x'",
  "W main.c:3:1 [Banana] [Major] multiple statements on the same line (C-L1)",
  "W main.c:9:10 unused variable 'y' [-Wunused-variable]",
  "N main.c:2:6 previous declaration is here",
  "E my_strlen.c:4:12 expected ';' after return statement",
  "E main.c:0:0 ld: undefined reference to `print_help'",
  "E -:0:0 make: No rule to make target 'src/gone.c', needed by 'demo'.  Stop.",
}, "items")
h.assert_equal(parsed.items[5].filename, "/project/lib/my/my_strlen.c", "a sub-make's file is in its directory")
h.assert_equal(parsed.items[1].filename, "/project/src/main.c", "paths are made absolute")
h.assert_equal({ parsed.errors, parsed.warnings }, { 4, 2 }, "counts")
-- With nothing else to show, make's own failure line points at the Makefile.
h.assert_equal(short(make.parse({ "make: *** [Makefile:12: demo] Error 1" }, "/project").items),
  { "E Makefile:12:0 make: building demo failed" }, "make's failure alone")

-- A real build: an error in lib/my, built through make -C, and a warning.
local root, cleanup = h.temp_project({
  ["Makefile"] = { "NAME = demo", "", "all: $(NAME)", "", "$(NAME):", "\t$(MAKE) -C lib/my",
    "\tcc -Wall -c src/main.c -o src/main.o", "", "clean:", "\trm -f src/main.o", "", ".PHONY: all clean" },
  ["lib/my/Makefile"] = { "all:", "\tcc -c my_strlen.c -o my_strlen.o" },
  ["lib/my/my_strlen.c"] = { "int my_strlen(char const *str)", "{", "    return 0", "}" },
  ["src/main.c"] = { "int main(void)", "{", "    int unused;", "", "    return 0;", "}" },
})
h.assert_equal(make.targets(root), { "all", "clean" }, "targets")
local result
make.make({}, root, function(r)
  result = r
end)
assert(vim.wait(20000, function()
  return result ~= nil
end), "make finished")
h.assert_equal(result.code ~= 0, true, "make failed")
local errors = vim.tbl_filter(function(item)
  return item.type == "E" and item.filename == root .. "/lib/my/my_strlen.c"
end, result.items)
h.assert_equal(#errors > 0 and errors[1].lnum, 3, "the error in lib/my, at its line")
local qf = vim.fn.getqflist({ title = 1, items = 1 })
assert(qf.title:match("^make: %d+ errors?"), qf.title)
h.assert_equal(#qf.items, #result.items, "in the quickfix list")
assert(notices[#notices]:match("^make failed"), notices[#notices])

-- Fixed: success, empty list.
vim.fn.writefile({ "int my_strlen(char const *str)", "{", "    return 0;", "}" }, root .. "/lib/my/my_strlen.c")
vim.fn.writefile({ "int main(void)", "{", "    return 0;", "}" }, root .. "/src/main.c")
result = nil
vim.cmd("cclose")
make.make({ "all" }, root, function(r)
  result = r
end)
assert(vim.wait(20000, function()
  return result ~= nil
end), "make finished")
h.assert_equal({ result.code, #result.items }, { 0, 0 }, "a clean build")
assert(notices[#notices]:match("^make all done in"), notices[#notices])
h.assert_equal(vim.fn.getqflist({ title = 1 }).title, "make all", "the list is replaced")
cleanup()

h.assert_equal(vim.fn.maparg("<leader>cM", "n", false, true).desc, "Epitech Make", "<leader>cM")
print("Epitech make tests passed")
