local plugin = assert(vim.env.EPITECH_NVIM_DIR, "EPITECH_NVIM_DIR is required")
vim.opt.runtimepath:prepend(plugin)
package.path = plugin .. "/lua/?.lua;" .. plugin .. "/lua/?/init.lua;" .. package.path

local h = dofile(plugin .. "/test/helpers.lua")
local project = require("epitech.project")

local function header(project_name)
  return { "/*", "** EPITECH PROJECT, 2026", "** " .. project_name, "** File description:", "** Test", "*/" }
end

local function with_select(answers, fn)
  local original = vim.ui.select
  local asked = {}
  vim.ui.select = function(items, opts, on_choice)
    asked[#asked + 1] = { items = items, prompt = opts.prompt }
    on_choice(table.remove(answers, 1))
  end
  local ok, err = pcall(fn, asked)
  vim.ui.select = original
  assert(ok, err)
end

local function header_of(root)
  local result = "not called"
  project.project_header(root, function(path)
    result = path
  end)
  return result
end

-- root(): .git first, then a Makefile, then the file's own directory.
local root, cleanup = h.temp_project({
  ["Makefile"] = { "NAME = my_ls # the binary" },
  ["src/main.c"] = header("Unused name"),
  ["lib/my/Makefile"] = { "NAME = libmy.a" },
  ["lib/my/my_putstr.c"] = {},
})
h.assert_equal(project.root(root .. "/src/main.c"), root, "root of a file in src/")
h.assert_equal(project.root(root .. "/lib/my/my_putstr.c"), root, ".git wins over a nearer Makefile")
local buf = h.buffer(root .. "/src/main.c", {})
h.assert_equal(project.root(buf), root, "root of a buffer")
h.assert_equal(project.root(0), root, "root of the current buffer")
vim.api.nvim_buf_delete(buf, { force = true })

local function temp_dir()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  return vim.uv.fs_realpath(dir)
end

local plain = temp_dir()
vim.fn.mkdir(plain .. "/sub", "p")
vim.fn.writefile({ "NAME = plain" }, plain .. "/Makefile")
h.assert_equal(project.root(plain .. "/sub/x.c"), plain, "a Makefile without .git")
local lonely = temp_dir()
h.assert_equal(project.root(lonely .. "/alone.c"), lonely, "a file outside any project uses its directory")

-- files(): tracked files, or nil outside git.
h.assert_equal(project.files(root, { "*.c" }), { "lib/my/my_putstr.c", "src/main.c" }, "tracked C files")
h.assert_equal(project.files(lonely, { "*.c" }), nil, "files() outside git")

-- name(): NAME, else a header's project line, else the directory name.
h.assert_equal(project.name(root), "my_ls", "NAME from the Makefile, comment dropped")
h.assert_equal(project.name(plain), "plain", "NAME without git")
vim.fn.writefile({ "NAME := $(BIN)", "BIN = x" }, plain .. "/Makefile")
vim.fn.writefile(header("Plain project"), plain .. "/sub/x.c")
h.assert_equal(project.name(plain), "Plain project", "header of a C file when NAME is a variable")
vim.fn.writefile(vim.list_extend({ "##", "## EPITECH PROJECT, 2026", "## Makefile project", "## File description:",
  "## Makefile", "##" }, { "", "all:" }), plain .. "/Makefile")
h.assert_equal(project.name(plain), "Makefile project", "the Makefile's header")
h.assert_equal(project.name(lonely), vim.fs.basename(lonely), "directory name")
cleanup()
vim.fn.delete(plain, "rf")
vim.fn.delete(lonely, "rf")

-- include_flags(): compile_commands.json, else include/ and the root.
root, cleanup = h.temp_project({ ["src/main.c"] = {}, ["include/my.h"] = {} })
h.assert_equal(project.include_flags(root, root .. "/src/main.c"), { "-I" .. root .. "/include", "-I" .. root },
  "fallback flags with include/")
vim.fn.delete(root .. "/include", "rf")
h.assert_equal(project.include_flags(root, root .. "/src/main.c"), { "-I" .. root }, "fallback flags without include/")

vim.fn.writefile({ vim.json.encode({
  {
    directory = root,
    file = "src/main.c",
    arguments = { "gcc", "-Wall", "-I", "include", "-Ilib/my", "-isystem", "/opt/inc", "-DDEBUG", "-D", "X=1",
      "-std=gnu17", "-c", "-o", "src/main.o", "src/main.c" },
  },
  {
    directory = root .. "/build",
    file = root .. "/src/other.c",
    command = [[cc -I../include -DNAME=\"my_ls\" -c -o other.o ../src/other.c]],
  },
}) }, root .. "/compile_commands.json")
h.assert_equal(project.include_flags(root, root .. "/src/main.c"), {
  "-I" .. root .. "/include", "-I" .. root .. "/lib/my", "-isystem", "/opt/inc", "-DDEBUG", "-DX=1", "-std=gnu17",
}, "flags from arguments")
h.assert_equal(project.include_flags(root, root .. "/src/other.c"), { "-I" .. root .. "/include", '-DNAME="my_ls"' },
  "flags from a command string, relative to its directory")
h.assert_equal(project.include_flags(root, root .. "/include/my.h"), project.include_flags(root, root .. "/src/main.c"),
  "a header uses the first entry")
cleanup()

-- state() and save_state(): JSON in stdpath("data"), never in the project.
root, cleanup = h.temp_project({ ["src/main.c"] = {} })
local other, cleanup_other = h.temp_project({})
h.assert_equal(project.state_file(), vim.fn.stdpath("data") .. "/epitech.nvim/projects.json", "state file path")
assert(vim.startswith(project.state_file(), vim.env.XDG_DATA_HOME), "test/run isolates the data directory")
h.assert_equal(project.state(root), {}, "empty state")
local function status()
  return vim.system({ "git", "status", "--porcelain", "--ignored", "--untracked-files=all" }, { cwd = root, text = true })
    :wait().stdout
end
local before = status()
project.save_state(root, { header = "include/my.h", dirs = { "src" } })
project.save_state(other, { header = "other.h" })
h.assert_equal(project.state(root), { header = "include/my.h", dirs = { "src" } }, "saved state")
h.assert_equal(project.state(root .. "/"), project.state(root), "state keyed by the normalized root")
h.assert_equal(project.state(other), { header = "other.h" }, "states are per project")
h.assert_equal(status(), before, "no file written in the project")
cleanup()
cleanup_other()

-- project_header(): include/<name>.h, else the only header in include/.
root, cleanup = h.temp_project({
  ["Makefile"] = { "NAME = my_ls" },
  ["include/my_ls.h"] = {},
  ["include/my.h"] = {},
})
with_select({}, function(asked)
  h.assert_equal(header_of(root), root .. "/include/my_ls.h", "include/<name>.h")
  vim.fn.delete(root .. "/include/my_ls.h")
  vim.fn.delete(root .. "/include/my.h")
  vim.fn.writefile({}, root .. "/include/only.h")
  h.assert_equal(header_of(root), root .. "/include/only.h", "the only header in include/")
  h.assert_equal(#asked, 0, "no question when the header is obvious")
end)
cleanup()

-- Otherwise the user picks one, and the choice is remembered.
root, cleanup = h.temp_project({
  ["Makefile"] = { "NAME = my_ls" },
  ["include/a.h"] = {},
  ["include/b.h"] = {},
  ["lib/my/my.h"] = {},
})
with_select({ "include/b.h" }, function(asked)
  h.assert_equal(header_of(root), root .. "/include/b.h", "picked header")
  h.assert_equal(asked[1].items, { "include/a.h", "include/b.h", "lib/my/my.h", "include/my_ls.h" },
    "every tracked header, plus include/<name>.h")
  h.assert_equal(header_of(root), root .. "/include/b.h", "remembered header")
  h.assert_equal(#asked, 1, "asked only once")
  h.assert_equal(project.state(root).header, "include/b.h", "choice saved in the state")
end)
project.save_state(root, {})
with_select({ nil }, function(asked)
  h.assert_equal(header_of(root), nil, "cancelled pick")
  h.assert_equal(project.state(root).header, nil, "nothing saved on cancel")
  h.assert_equal(#asked, 1, "asked once")
end)
cleanup()

print("Epitech project tests passed")
