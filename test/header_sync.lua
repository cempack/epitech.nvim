local plugin = assert(vim.env.EPITECH_NVIM_DIR, "EPITECH_NVIM_DIR is required")
vim.opt.runtimepath:prepend(plugin)
package.path = plugin .. "/lua/?.lua;" .. plugin .. "/lua/?/init.lua;" .. package.path

local h = dofile(plugin .. "/test/helpers.lua")
local config = require("epitech.config")
local project = require("epitech.project")
local sync = require("epitech.header_sync")
config.setup()

local notices = {}
vim.notify = function(message)
  notices[#notices + 1] = message
end

local root, cleanup = h.temp_project({
  ["Makefile"] = { "NAME = demo" },
  ["include/demo.h"] = {
    "#ifndef DEMO_H_", "    #define DEMO_H_", "", "typedef struct x_s {", "    int a;", "} x_t;", "",
    "int old_name(void);", "int parse_args(int ac, char **av);", "", "#endif",
  },
  ["src/parse_args.c"] = {
    "static int is_flag(char const *arg)", "{", "    return arg[0] == '-';", "}", "",
    "int parse_args(int ac, char **av)", "{", "    return ac + is_flag(av[0]);", "}",
  },
  ["src/main.c"] = { "int main(void)", "{", "    return 0;", "}" },
  ["src/io/run.c"] = { "int run(char const *path,", "    int flags)", "{", "    return flags + (path != 0);", "}" },
  ["lib/my/my_putstr.c"] = { "int my_putstr(char const *str)", "{", "    return str != 0;", "}" },
})

-- The first run asks which directories feed the header and remembers it.
local asked = 0
vim.ui.input = function(opts, on_confirm)
  asked = asked + 1
  on_confirm(opts.default)
end
local summary
local function run()
  summary = nil
  sync.run(root, function(result)
    summary = result
  end)
  return summary
end

h.assert_equal(run(), "1 added · 0 changed · 0 removed", "first run: parse_args adopted, run added")
h.assert_equal(vim.fn.readfile(root .. "/include/demo.h"), {
  "#ifndef DEMO_H_", "    #define DEMO_H_", "", "typedef struct x_s {", "    int a;", "} x_t;", "",
  "int old_name(void);", "",
  "/* epitech.nvim: prototypes (:EpitechSyncHeader) */",
  "/* src/io/run.c */", "int run(char const *path, int flags);",
  "/* src/parse_args.c */", "int parse_args(int ac, char **av);",
  "/* epitech.nvim: end of prototypes */", "", "#endif",
}, "block inside the guard; adopted prototype moved; static, main and lib/ left out; other declarations kept")
h.assert_equal(project.state(root).header_dirs, { "src" }, "directories remembered")
h.assert_equal(notices[#notices], "include/demo.h: 1 added · 0 changed · 0 removed", "the user is told")

-- A second run with no changes changes nothing.
local before = vim.fn.readfile(root .. "/include/demo.h")
h.assert_equal(run(), "0 added · 0 changed · 0 removed", "second run")
h.assert_equal(vim.fn.readfile(root .. "/include/demo.h"), before, "header unchanged")
h.assert_equal(asked, 1, "asked only once")

-- A rename: one removed, one added. A new signature: one changed.
vim.fn.writefile({ "int run_file(char const *path,", "    int flags)", "{", "    return flags + (path != 0);", "}" },
  root .. "/src/io/run.c")
h.assert_equal(run(), "1 added · 0 changed · 1 removed", "rename")
local buf = h.buffer(root .. "/src/parse_args.c", {
  "int parse_args(int ac, char const **av)", "{", "    return ac + (av != 0);", "}",
})
h.assert_equal(run(), "0 added · 1 changed · 0 removed", "changed signature (from the unsaved buffer)")
vim.api.nvim_buf_delete(buf, { force = true })

-- A header open in a buffer is edited there, so undo works.
local header_buf = vim.fn.bufadd(root .. "/include/demo.h")
vim.fn.bufload(header_buf)
vim.fn.writefile({ "int parse_args(int ac, char **av)", "{", "    return ac + (av != 0);", "}", "",
  "int count_args(int ac)", "{", "    return ac;", "}" }, root .. "/src/parse_args.c")
h.assert_equal(run(), "1 added · 1 changed · 0 removed", "new function")
h.assert_equal(vim.api.nvim_buf_get_lines(header_buf, 12, 16, false), {
  "/* src/parse_args.c */", "int parse_args(int ac, char **av);", "int count_args(int ac);",
  "/* epitech.nvim: end of prototypes */",
}, "functions keep their order in the file")
h.assert_equal(vim.bo[header_buf].modified, true, "the loaded buffer was edited")

-- Long prototypes are wrapped by the formatter.
vim.fn.writefile({
  "int a_function_with_a_long_name(char const *first_argument, char const *second_argument)", "{",
  "    return first_argument == second_argument;", "}",
}, root .. "/src/long.c")
vim.system({ "git", "add", "-A" }, { cwd = root }):wait()
run()
for _, line in ipairs(vim.api.nvim_buf_get_lines(header_buf, 0, -1, false)) do
  assert(#line < 80, "line wrapped: " .. line)
end
h.assert_equal(run(), "0 added · 0 changed · 0 removed", "a wrapped prototype counts as unchanged")

-- Without group_by_file there are no group comments.
config.setup({ header_sync = { group_by_file = false } })
h.assert_equal(sync.block({ { file = "src/a.c", prototypes = { { name = "f", text = "int f(void);" } } } }, false),
  { sync.BEGIN, "int f(void);", sync.END }, "no group comments")

-- A header without a guard is refused.
local bare, cleanup_bare = h.temp_project({ ["include/bare.h"] = { "int f(void);" }, ["src/f.c"] = { "int f(void)",
  "{", "    return 0;", "}" } })
project.save_state(bare, { header = "include/bare.h", header_dirs = { "src" } })
sync.run(bare)
h.assert_equal(notices[#notices], "Can't sync include/bare.h: it has no include guard (:EpitechGuard adds one)",
  "no guard")
h.assert_equal(vim.fn.readfile(bare .. "/include/bare.h"), { "int f(void);" }, "unguarded header untouched")

require("epitech").setup()
assert(vim.api.nvim_get_commands({ builtin = false }).EpitechSyncHeader, ":EpitechSyncHeader")
cleanup()
cleanup_bare()
print("Epitech header sync tests passed")
