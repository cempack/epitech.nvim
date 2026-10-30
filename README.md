# epitech.nvim

Write Epitech C in Neovim with the coding style handled for you: code that's
formatted the way Banana wants, Banana's verdict live as you save, meters
that warn before a function gets too long, one-key fixes for most
violations, and the project chores (Makefiles, headers, libmy, tests, the
pre-delivery check) done in a command.

Built for LazyVim, works with any lazy.nvim setup. Covers the Epitech C
Coding Style v7.1.

```c
int parse_args(int ac, char **av, options_t *options)    16/20 lines · 3/4 args
{
    ...
            if (av[i][j] == 'l') {                       depth 2
                ...
            } else if (av[i][j] == 'R') {                depth 3 ✗ C-C1
```

## Install

With [LazyVim](https://www.lazyvim.org/) (or lazy.nvim with
[conform.nvim](https://github.com/stevearc/conform.nvim)):

```lua
return {
  { import = "lazyvim.plugins.extras.lang.clangd" },
  {
    "cempack/epitech.nvim",
    lazy = false,
    init = function()
      vim.filetype.add({ extension = { h = "c" } })
    end,
    config = function()
      require("epitech").setup()
    end,
  },
  {
    "stevearc/conform.nvim",
    dependencies = { "epitech.nvim" },
    opts = function(_, opts)
      opts.formatters_by_ft = opts.formatters_by_ft or {}
      opts.formatters_by_ft.c = { "epitech_vim" }
      opts.formatters_by_ft.make = { "bake" }
      opts.formatters = opts.formatters or {}
      opts.formatters.epitech_vim = require("epitech").formatter()
    end,
  },
}
```

On Arch, [epitech-dump-arch](https://github.com/cempack/epitech-dump-arch)
installs all of this, the requirements, and keeps the plugin updated.

| Needs | For |
|---|---|
| Neovim 0.11.2+, `clang-format` 21+, `~/.vim/epitech.vim` ([vim-epitech](https://github.com/Epitech/vim-epitech)) | formatting |
| `epiclang` | Banana diagnostics, the project check, the push guard |
| git | the "could be static" hint, header sync, the check, the hook |
| `mbake` | Makefile formatting (the `bake` line) |
| optional: clangd, Trouble, blink.cmp or LuaSnip, gcovr | call sites for one fix, nicer lists, snippets, coverage |

Anything missing just turns its feature off; nothing errors.

## Start a project

**`:EpitechNew my_ls`** sets up a project that passes Banana from the first
commit. It first asks which libraries to link (CSFML graphics, audio,
network, ncurses, math), then writes:

```
Makefile              CC = epiclang, SRC/TEST_SRC lists, all clean fclean re unit_tests tests_run, LDLIBS
include/my_ls.h       guard, PROGRAM_NAME, EXIT_ERROR 84
src/main.c            int main(void)
src/print_error.c     print_error(path) → "my_ls: path: No such file or directory", returns 84
lib/my/               only the libmy functions the project uses (my_strlen here), with its Makefile
tests/test_my_ls.c    a Criterion test
.gitignore            build products, vgcore, *.gcda…
```

`:EpitechNew libmy.a` makes a library instead (`ar rc`, tests linked
against it).

**`<leader>cN`** asks for a path and a description and creates the file
with its Epitech header (a `.h` gets its guard), adds it to the Makefile's
`SRC` (or `TEST_SRC` under `tests/`) and opens it.

**libmy, on demand.** The plugin carries your Pool's libmy: 35 functions
with the Pool's prototypes, one per file, written to pass Banana. Call
`my_strdup(src)`, hit `<leader>ca` → **Add my_strdup to lib/my**: it copies
`my_strdup.c` and what it calls (`my_strcpy`, `my_strlen`) into `lib/my`,
adds them to `lib/my/Makefile` and `my.h`, and includes `my.h`.
`:EpitechLib` picks from the list, `:EpitechLib my_getnbr my_revstr` adds
several.

## Write

**Format on save** (`<leader>cf`): clang-format with the Epitech profile,
then what clang-format can't do: preprocessor nesting (C-G3), the single
blank line after declarations (C-L6), spacing in `#define`s, and wrapped
lines indented the way Banana counts them, one level per parenthesis still
open:

```c
        if (parse_options(argc, &parsed_arguments, argv, options) == -1
            || parse_file_arguments(argc, &parsed_arguments, argv,
                file_arguments) == -1) {
```

**Banana, live.** Open or save a file and `epiclang` runs in the
background: its reports show up as diagnostics (`[Banana] C-L1`), errors for
Major and Fatal (`FATAL:` in front, since a Fatal means no grade). Only the
file's own problems, not its headers'.

**`<leader>cE`** explains the rule under the cursor: severity, who checks it
(🍌 Banana, 👤 a grader), a bad and a good example, and what measuring
`epiclang` showed (blank lines count toward C-F4's 20). `:EpitechRules` lists
all 42.

**Meters** keep you under the limits before Banana complains:

- after each signature, `13/20 lines · 2/4 args`, turning yellow at 17
  lines and red past 20 or past 4 parameters (`...` counts, as for Banana);
- `depth 2`, `depth 3 ✗ C-C1` on nested control statements (`else if`,
  `switch` and `do while` count as Banana counts them), `4 branches ✗ C-C1`
  on long `if` chains;
- the winbar: `src/parser.c   functions 8/10 · non-static 5/5` (C-O3).

**Hints** for the rules a grader checks and Banana can't, shown as faint
hints and dropped when Banana says the same:

| Hint | Example |
|---|---|
| magic number (C-G9) | `char buf[4096]` → `C-G9 name this number?`, action **Extract into a macro** (`#define` lands in your header) |
| could be static (C-A4) | a function no other file uses → **Add static** |
| const pointer (C-A1) | `C-A1 str is never modified → char const *str`, action **Make str const** |
| precise type (C-A2) | `int len = my_strlen(s)` → `size_t?` |
| naming (C-F2, C-O4, C-V1) | `int vowels(char *s)` → `no verb → get_vowels?`; `utils.c`; typedef without `_t` |

Obvious numbers stay quiet (`ac != 2`, `nb % 10`, `write(2, …)`, `return 84`).
`:EpitechHints off` hides them all.

**Makefiles** get checked too: header, 80 columns (tabs counted), trailing
spaces, `\r`, blank lines, with fixes to add the header or split a long
`SRC` line.

**clangd's includes, fixed.** Accepting `malloc` from clangd's completion
used to add `<malloc.h>`, `size_t` `<__stddef_size_t.h>`, `printf` a
`<bits/…>` header. The plugin rewrites those to the public header
(`<stdlib.h>`, `<stddef.h>`, `<stdio.h>`), CSFML's to `<SFML/Graphics.h>`,
Criterion's to `<criterion/criterion.h>`, and drops the ones it can't
place.

**Snippets** in the style: `main`, `fn`, `sfn`, `tdef`, `tenum`, `sw`,
`fori`, `ife`, `mal` ([setup below](#snippets)).

## Fix

`<leader>ca` on a violation shows the fixes next to clangd's. A fix only
appears when it keeps what the program does; when it can't, a hint says
why.

| Fix | Before → after |
|---|---|
| **Add void** (C-F6) | `int print_help()` → `int print_help(void)`; `:EpitechFixAll C-F6` for the whole project |
| **Move declarations to the top** (C-L5) | `int x = f();` mid-function → `int x;` at the top, `x = f();` where it was |
| **One statement per line** (C-L1) | `str[i++] = c;` → `str[i] = c;` `i++;` · `a = b = 0;` → two lines · `if ((fd = open(…)) == -1)` → assignment first · `a && f();` → `if (a) { f(); }` |
| **Convert to switch** (C-C1) | a 4-branch `if (c == 'l') … else if (c == 'a')` chain → `switch (c)` |
| **Pass by pointer** (C-F7) | `int area(rect_t r)` → `int area(rect_t const *r)`, `r.w` → `r->w`, every call gets `&` |
| **Move to include/x.h** (C-H1) | a `typedef`, `#define` or prototype in a `.c` → into the header, inside its guard |
| **Extract into a macro** (C-G9) | `4096` → `BUFFER_SIZE`, defined in your header |
| **Add static** (C-A4) | `void helper(void)` → `static void helper(void)`, header prototype removed |
| **Make const** (C-A1) | `char *str` → `char const *str`, prototypes too |

Fixes that make a line too long come out wrapped like the formatter would.

## Restructure

**Function too long? Extract it.** Select statements, `<leader>ca` →
**Extract to a function…** (or `:'<,'>EpitechExtract count_spaces`): they
move into a `static` function above, with a call in their place. Variables
are handled so nothing changes: moved in when only they use it, passed by
pointer when the extracted code changes them, by value otherwise. clangd's
extract only works on C++.

```c
int count_text(char const *str)          static void count_spaces(char const *str, int *count)
{                                        {
    int count = 0;                           int i = 0;
    int i = 0;                       →
                                             while (str[i] != '\0') {
    while (str[i] != '\0') {                     *count += str[i] == ' ';
        count += str[i] == ' ';                  i++;
        i++;                                 }
    }                                    }
    return count;
}                                        int count_text(char const *str)
                                         {
                                             int count = 0;

                                             count_spaces(str, &count);
                                             return count;
                                         }
```

**File too big? Split it.** Select whole functions,
`:'<,'>EpitechMoveTo src/print_long.c`: they move with the static helpers
only they use, the new file gets its header and includes, `SRC` and the
project header follow.

**Header out of date?** `:EpitechSyncHeader` rewrites the project header's
prototypes from your `.c` files: `1 added · 1 changed · 0 removed`. No
markers in your header; a prototype you wrote by hand is never deleted.

## Build and test

**`<leader>cM`** (`:EpitechMake [target]`) runs make and puts every compiler
error, warning, Banana report and linker error in the quickfix list (Trouble
when installed), at the right file even from `make -C lib/my`.

**`<leader>cT`** (`:EpitechTest`) builds `unit_tests`, runs it, and lists each
failed Criterion assert at its line:

```
Tests: 12 passed · 1 failed · 84% of lines covered
tests/test_parse.c|14| parse::empty_string: The expression parse("") == NULL is false.
```

With gcovr installed, every line of your code gets a sign: green when the
tests ran it, red when they didn't. `:EpitechCoverage off` hides them. The
build is cleaned up afterwards (`make fclean`), as `tests_run` does.

## Deliver

**`<leader>cB`** (`:EpitechCheck`) checks the whole project: Banana on every
tracked file, the hints, the Makefile, and the repository rules (tracked
`.o`, `vgcore.*`, `*.gcda`, `*~`… for C-O1, `.cpp` files, file names that
aren't snake_case). Sorted by severity:
`Epitech check: 0 fatal · 3 major · 5 minor · 2 info · 4 hints`.
`:EpitechCheck untrack` removes the build products from git and adds them to
`.gitignore`. Headless, for CI:
`nvim --clean --headless -l …/epitech.nvim/scripts/check.lua --ci .`

**`:EpitechHooks`** adds a pre-push hook: `git push` stops while a Major is
left (`git push --no-verify` to force it). It chains with an existing hook,
and `:EpitechHooks remove` takes it out.

**`:EpitechLazygit`** adds `B` (Banana check) to lazygit's files panel.

**`:EpitechIgnore [file|project]`** silences the warnings for a file you
didn't write (formatting and fixes still work); `:EpitechUnignore` brings
them back.

Nothing the plugin remembers goes in your repository (C-O1): it lives in
`~/.local/share/nvim/epitech.nvim/`.

## Commands and keys

| Key | Command | |
|---|---|---|
| `<leader>cf` | | format (conform) |
| `<leader>ca` | | fixes, next to clangd's |
| `<leader>cE` | `:EpitechExplain [code]` | explain a rule |
| `<leader>cN` | `:EpitechNewFile [path]` | new source file |
| `<leader>cM` | `:EpitechMake [target]` | make → quickfix |
| `<leader>cT` | `:EpitechTest` | unit tests → quickfix, coverage |
| `<leader>cB` | `:EpitechCheck [untrack]` | check the project |
| `<leader>cH` | `:EpitechHeader` | Epitech header (40 filetypes) |
| `<leader>cG` | `:EpitechGuard` | include guard |
| | `:EpitechNew[!] [name]` | new project |
| | `:EpitechLib [name…]` | add libmy functions |
| | `:'<,'>EpitechExtract [name]` | extract a function |
| | `:'<,'>EpitechMoveTo <path>` | move functions to a file |
| | `:EpitechSyncHeader` | sync the header's prototypes |
| | `:EpitechFixAll C-F6` | `(void)` everywhere |
| | `:EpitechRules` | the 42 rules |
| | `:EpitechHints [on\|off]` | hints |
| | `:EpitechCoverage [on\|off]` | coverage signs |
| | `:EpitechIgnore` / `:EpitechUnignore [file\|project]` | silence warnings |
| | `:EpitechHooks [remove]` | pre-push hook |
| | `:EpitechLazygit [remove]` | lazygit key |

Keys are only mapped when free (LazyVim's `<leader>cm` stays Mason) and can
be changed or disabled in `setup()`.

## Configuration

`setup()` alone is enough. Everything below is the default:

```lua
require("epitech").setup({
  header = { keymap = "<leader>cH" },
  guard = { keymap = "<leader>cG" },
  diagnostics = {
    enabled = true,
    cmd = "epiclang",
    args = { "-x", "c", "-fsyntax-only" }, -- include flags are added per project
    events = { "BufWritePost", "BufReadPost" },
  },
  explain = { keymap = "<leader>cE" },
  budget = {
    functions = true, -- "13/20 lines · 2/4 args"
    file = "winbar", -- "winbar", "lualine" (use require("epitech").file_budget()) or false
    depth = true,
    max_lines = 20, warn_lines = 17,
    max_args = 4,
    max_functions = 10, max_non_static = 5,
    max_depth = 3, show_depth_from = 2,
    max_branches = 3,
  },
  hints = {
    enabled = true,
    severity = vim.diagnostic.severity.HINT,
    magic_numbers = { enabled = true, allow = { 0, 1, -1, 84 } },
    static = true,
    types = true,
    naming = { enabled = true, verbs = nil, vague_files = nil }, -- nil: built-in lists
  },
  makefile = { enabled = true, tab_width = 8 },
  fixes = { enabled = true },
  clangd = { fix_includes = true },
  check = { keymap = "<leader>cB", fail_on = { "fatal", "major" } },
  make = { keymap = "<leader>cM" },
  tests = { keymap = "<leader>cT", coverage = true, fclean = true },
  scaffold = { keymap = "<leader>cN", cc = "epiclang", cflags = "", error_file = true },
})
```

A `keymap` set to `false` maps nothing; `feature = false` turns off anything
with an `enabled` key; lists replace the default. A misspelled option gets a
warning, a wrong type an error naming it.

Highlight groups (override them in your colorscheme): `EpitechBudgetOk`,
`EpitechBudgetNear`, `EpitechBudgetOver`, `EpitechWinbar`,
`EpitechCoverageHit`, `EpitechCoverageMissed`.

### Snippets

With blink.cmp (LazyVim's default), keeping its default search path:

```lua
{
  "saghen/blink.cmp",
  opts = function(_, opts)
    local providers = vim.tbl_get(opts, "sources", "providers") or {}
    local snippets = providers.snippets or {}
    snippets.opts = snippets.opts or {}
    snippets.opts.search_paths = snippets.opts.search_paths or { vim.fn.stdpath("config") .. "/snippets" }
    table.insert(snippets.opts.search_paths, require("epitech").snippets_dir())
    opts.sources = opts.sources or {}
    opts.sources.providers = providers
    providers.snippets = snippets
  end,
}
```

With LuaSnip:
`require("luasnip.loaders.from_vscode").lazy_load({ paths = { require("epitech").snippets_dir() } })`.

### Lua API

`require("epitech")`: `format_buffer(buf)`, `insert_header()`,
`insert_guard()`, `snippets_dir()`, `file_budget()`.
`require("epitech.rules").by_code["C-L1"]` for a rule,
`require("epitech.ts").functions(buf)` for a buffer's functions.

## Development

`test/run` runs the suite. Tests that need the real `epiclang` (the
formatter checked by Banana, and `test/calibrate.lua`, which measures how
Banana counts lines, parameters, depth and indentation) are skipped without
it.
