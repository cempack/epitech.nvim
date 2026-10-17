# epitech.nvim

Neovim support for the Epitech C Coding Style: a formatter whose output passes
Banana (`epiclang`), Epitech file headers, and include guards.

## Install

With [LazyVim](https://www.lazyvim.org/) (or any lazy.nvim setup that has
[conform.nvim](https://github.com/stevearc/conform.nvim)), add a spec such as:

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

[epitech-dump-arch](https://github.com/cempack/epitech-dump-arch) installs this
spec and the requirements below, and its weekly `epitech-upgrade` timer keeps
the plugin up to date through lazy.nvim.

Requirements:

- Neovim 0.11.2 or newer
- `clang-format` 21 or newer (older versions cannot load `epitech.clang-format`)
- the Epitech Vim config at `~/.vim/epitech.vim`, from
  [Epitech/vim-epitech](https://github.com/Epitech/vim-epitech); the formatter
  stays inactive without it
- [`mbake`](https://pypi.org/project/mbake/) for Makefiles, if you use the
  `bake` line above
- `epiclang` (Epitech's Banana checker) for live diagnostics; everything else
  works without it

## What it does

- `<leader>cf` (and LazyVim's format on save) formats C files and headers:
  four-space indentation including `case` labels, braces, spacing (also inside
  `#define` bodies), 80-column line and comment wrapping, function separation,
  the single blank line after a function's declarations, trailing spaces, and
  preprocessor nesting (C-G3). The Epitech header is kept as is.
- `<leader>cH` / `:EpitechHeader` inserts an Epitech header using the current
  filetype's comment syntax (C, Makefile, shell, Python, Lua, HTML and more).
- `<leader>cG` / `:EpitechGuard` wraps a `.h` file in an include guard named
  after the file (`my_macro_abs.h` becomes `MY_MACRO_ABS_H_`).
- C buffers use four-space indentation with spaces, as the Epitech Vim config
  does.

### Live Banana diagnostics

When you open or save a C file or header, the plugin runs `epiclang` on it in
the background and shows what Banana reports as ordinary diagnostics: signs,
virtual text, `]d`, Trouble. Each one has `source = "Banana"` and the rule as
its code (`C-L1`). Fatal and Major problems are errors, Minor ones warnings,
Info ones information; a Fatal message starts with `FATAL:` because a fatal
means the project isn't graded. Only the file's own problems are shown, not
those of the headers it includes. Include flags come from
`compile_commands.json` when there is one, else `-I include` and `-I .`.

This needs `epiclang`; without it you get one notice per session and nothing
else.

```lua
diagnostics = {
  enabled = true,
  cmd = "epiclang",
  args = { "-x", "c", "-fsyntax-only" }, -- include flags are added per project
  events = { "BufWritePost", "BufReadPost" },
},
```

### Hints

Some rules are checked by a grader, not by Banana. For those, the plugin
shows hints (HINT diagnostics with `source = "epitech.nvim"`): guesses, so
read them as questions. A hint disappears when Banana reports the same rule
on the same line. `:EpitechHints off` hides them, `:EpitechHints on` brings
them back, and `:EpitechHints` toggles.

- **Magic numbers** (C-G9): a number inside a function body that isn't 0, 1,
  -1 or 84 (Epitech's error exit code) gets `C-G9 name this number?`. The
  code action **Extract 4096 into a macro…** asks for a name (suggesting
  `BUFFER_SIZE` for `char buffer[4096]`), offers the project's existing
  macros with the same value first, and can replace every identical number
  in the file. The `#define` goes in the project header, inside its include
  guard (C-H1), and the file gets the `#include` it needs.

- **Could be static** (C-A4, C-O3): a non-static function, other than
  `main`, that no other `.c` file of the project mentions gets
  `C-A4 only used in this file`. The project is searched with `git grep`
  when you save. **Add static** makes it static (and its prototypes in the
  file too). When a header declares it, the action is **Add static and
  remove the prototype from include/x.h**, offered only when nothing in the
  file uses the function before its definition; otherwise the program
  wouldn't compile, so there's no action. Needs git.

- **Const and precise types** (C-A1, C-A2): a pointer parameter whose data
  the function never modifies gets `C-A1 str is never modified →
  char const *str`, with the action **Make str const**, which rewrites the
  definition and the prototypes. The check is cautious: a write through the
  pointer, passing it to a function that doesn't take `const` there,
  returning it, or any use it can't classify means no hint. An `int` set from
  `strlen`, `my_strlen` or `sizeof` gets `C-A2 holds a length → size_t?`
  (no automatic fix: changing a type ripples into comparisons and format
  strings).

- **Naming** (C-F2, C-O4, C-V1): a function name without a verb
  (`C-F2 no verb → get_vowels_number?`, with a suggestion when the function
  returns something), a vague file name such as `utils.c`, a typedef name
  that doesn't end in `_t`, and macros, enum values or global constants that
  aren't UPPER_SNAKE_CASE. A name counts as having a verb when one of its
  words (a leading `my` aside) is a verb or starts with one, like `putstr`;
  the lib/my classics (`my_strlen`, `my_getnbr`…) and `main` are left alone.
  `verbs` and `vague_files` replace the built-in lists.

```lua
hints = {
  enabled = true,
  severity = vim.diagnostic.severity.HINT,
  magic_numbers = { enabled = true, allow = { 0, 1, -1, 84 } },
  static = true,
  types = true,
  naming = { enabled = true, verbs = nil, vague_files = nil }, -- nil: built-in lists
},
```

### Makefile checks

The coding style covers Makefiles too. In a `Makefile` buffer, the plugin
reports a missing Epitech header (C-G1), lines past 80 columns with tabs
counted at `makefile.tab_width` columns (C-F3, `C-F3 86/80 columns`, the
newline included), `\r` line endings (C-G6), trailing whitespace (C-G7),
empty lines at the start or more than one at the end (C-G8), and a missing
final newline (C-A3). These aren't guesses, so they use the rule's own
severity. Header detection accepts both `##` and the PDF's `###` inner
lines. Code actions: **Add the Epitech header**, **Split into SRC += lines**
for a long or backslash-continued `SRC` assignment (the first line keeps its
`=`), and **Remove trailing spaces**.

```lua
makefile = { enabled = true, tab_width = 8 },
```

### Header sync

`:EpitechSyncHeader` updates the project header's prototypes (C-H1) from the
non-static functions of the `.c` files that feed it, and reports
`1 added · 1 changed · 0 removed`. The first time, it asks which header (when
it isn't obvious) and which directories feed it (`src` by default; `lib/`
usually has its own header), and remembers both. The prototypes live in a
block inside the include guard, grouped by file:

```c
/* epitech.nvim: prototypes (:EpitechSyncHeader) */
/* src/parse_args.c */
int parse_args(int ac, char **av);
/* epitech.nvim: end of prototypes */
```

On the first run, prototypes already in the header for those functions move
into the block; the rest of the header is left alone. `static` functions and
`main` stay out. An open header is edited in its buffer (so undo works),
then formatted so long prototypes wrap at 80 columns.

```lua
header_sync = { group_by_file = true }, -- false: no /* file */ lines
```

### Rule explainer

`<leader>cE` (or `:EpitechExplain`) on a line with a Banana diagnostic or one
of the plugin's hints opens a float that explains the rule: its code and
title, its severity, who checks it (🍌 Banana, 👤 a grader), a short summary
and a bad and a good example. With several rules on the line, the one under
the cursor wins, else you choose; with none, you pick from the list.
`:EpitechExplain C-F6` explains a given rule, and `:EpitechRules` lists all
42 rules. Change or disable the key with `explain = { keymap = … }`.

### Budget meters

After each function's signature, a meter shows how much of its budget it
uses: `13/20 lines · 2/4 args` (C-F4, C-F5). It's dim below 17 lines, in the
warning color from 17 to 20 and in the error color past 20; the parameter
count turns red past 4, and a variadic shows as `2/4 args + …`. The colors
are the `EpitechBudgetOk`, `EpitechBudgetNear` and `EpitechBudgetOver`
highlight groups (linked to `Comment`, `DiagnosticWarn` and `DiagnosticError`
unless your colorscheme sets them).

Each C file's winbar shows its file budget (C-O3):
`src/parser.c   functions 8/10 · non-static 5/5`, each count in the warning
color at its limit and the error color past it. Headers only get one when
they define functions (`static inline`). The plugin only uses a winbar that's
empty or its own, so another plugin's winbar is left alone. To show the
budget in lualine instead, set `budget.file = "lualine"` and add a component:

```lua
{
  "nvim-lualine/lualine.nvim",
  opts = function(_, opts)
    table.insert(opts.sections.lualine_c, {
      function()
        return require("epitech").file_budget()
      end,
    })
  end,
}
```

Control statements nested two levels deep or more get a depth label at the
end of their line (C-C1): `depth 2`, `depth 2 (else + if)` on an `else if`
(which counts as an `if` inside the `else`), and `depth 3 ✗ C-C1` in the
error color. The first `if` of a chain with more than three branches gets
`4 branches ✗ C-C1`. A `switch` counts as a level.

```lua
budget = {
  functions = true, -- the meter after each signature
  file = "winbar", -- "winbar", "lualine" (component only) or false
  depth = true, -- the depth labels
  max_lines = 20, warn_lines = 17,
  max_args = 4,
  max_functions = 10, max_non_static = 5,
  max_depth = 3, show_depth_from = 2,
  max_branches = 3,
},
```

### Fix menu

The plugin runs a small language server inside Neovim, called `epitech`, for
C files, headers and Makefiles. It offers fixes for coding style problems as
code actions, so they appear in `<leader>ca` (`vim.lsp.buf.code_action()`)
next to clangd's. It's why `:checkhealth vim.lsp` and `:LspInfo` list a
client named `epitech`. A fix is only offered when its rewrite keeps the
program's meaning. Turn the menu off with `fixes = { enabled = false }`.

- **Add void** (C-F6): `int print_help()` becomes `int print_help(void)`, for
  definitions, prototypes, `main()` and pointer-returning functions (function
  pointers are left alone). `:EpitechFixAll C-F6` does it in every tracked
  `.c` and `.h` file of the project and reports
  `3 functions fixed in 2 files`; open buffers are edited and left for you
  to save, and a buffer with unsaved changes is skipped.
- **Move declarations to the top** (C-L5, C-L6): on a declaration after the
  first statement, or one declaring several variables, rewrites the whole
  function: one variable per declaration, all at the top in their original
  order, then the blank line. A moved declaration's initializer stays where
  it was as an assignment (`int x = f();` leaves `x = f();`). `for` loop
  initializers stay. When moving would change the program (an array or
  struct initializer, a `const` or `static` variable with an initializer, a
  variable-length array, the same name declared twice), a hint says why and
  there's no action.
- **One statement per line** (C-L1), each pattern its own action:
  **Split the chained assignment** (`a = b = 0;` gives `a = 0;` and
  `b = 0;`; with a value that has side effects, it's computed once:
  `b = f();` then `a = b;`), **Move i++ to its own line**
  (`str[i++] = 'A';` gives `str[i] = 'A';` then `i++;`), **Move the
  assignment out of the condition** (`if ((fd = open(…)) == -1)` gives
  `fd = open(…);` then `if (fd == -1)`), and **Turn the && into an if**
  (`a && f();` gives `if (a) { f(); }`, and `a || f();` gives
  `if (!a) { … }`). A hint explains the cases without a fix: a variable
  updated and read on the same line (undefined behaviour), an assignment in
  an `else if` or on the right of `&&`/`||`, and an assignment in a loop
  condition.
- **Convert to switch** (C-C1): on the first `if` of a chain with more than
  three branches, or whose `else if`s reach depth 3, when every condition
  compares the same variable (or field) with distinct constants: numbers,
  characters or UPPER_SNAKE macros, `x == K`, `K == x` or several of them
  joined with `||` (several `case` labels). A final `else` becomes
  `default:`, and each branch gets a `break;` unless it already ends in
  `return`, `break`, `continue` or `exit(…)`. A `break` or `continue` in a
  branch, or a declaration, means no conversion, with a hint saying why.
- **Move to include/x.h** (C-H1): type definitions, struct, enum and union
  declarations, macros and non-static prototypes in a `.c` file get the hint
  `C-H1 belongs in a header`. The action moves them into
  `include/<file>.h` when it exists, else the project header: inside the
  include guard, before the prototypes block of `:EpitechSyncHeader`, with
  macros indented for C-G3, and adds the `#include` to the `.c`. A `static`
  function's prototype can't go in a header: the action moves the definition
  (with its comment) above its first use and deletes the prototype.
- **Pass x by pointer** (C-F7): on a function taking a struct by value, the
  parameter becomes `point_t const *point`, `point.x` becomes `point->x`,
  other uses become `*point`, the prototypes follow, and every call gets
  `&` (`sum_point(&origin)`). Call sites come from clangd when it's attached,
  else from `git grep`. A call whose argument isn't a variable (a struct
  returned by a function) goes to the quickfix list for you to fix. A
  function that modifies its copy, takes its address, calls itself or hides
  the name gets a hint instead: with a pointer it would change the caller's
  struct, or the change can't be checked.

Formatting only changes layout. Rules about structure or meaning, such as
function length, parameter count, naming, or `int f()` instead of
`int f(void)`, are left to `epiclang`.

## Configuration

`require("epitech").setup(opts)` takes an optional table. Every option has a
default, so `setup()` alone is enough. The options that exist today:

```lua
require("epitech").setup({
  header = { keymap = "<leader>cH" }, -- :EpitechHeader; false for no mapping
  guard = { keymap = "<leader>cG" }, -- :EpitechGuard; false for no mapping
  fixes = { enabled = true }, -- the epitech language server's code actions
  diagnostics = { enabled = true }, -- live Banana diagnostics, see below
  explain = { keymap = "<leader>cE" }, -- explain the rule under the cursor
})
```

Mappings are only set when their keys are still free, and commands only when
you haven't defined one with the same name. A feature with an `enabled` key
can be turned off with `feature = false`. Lists replace the default list
instead of extending it. Unknown options are ignored with a warning, and an
option of the wrong type stops `setup()` with an error naming it.

## Project detection

Features that work on the whole project find its root from the current file:
the nearest directory with `.git`, else with a `Makefile`, else the file's
own directory. The project name is `NAME` from the Makefile, else the project
line of an Epitech header, else the directory name. Include flags for
`epiclang` come from `compile_commands.json` (at the root or in `build/`)
when there is one, else `-I include` and `-I .`. When the project's main
header isn't obvious (`include/<name>.h`, or the only header in `include/`),
you're asked once.

What the plugin remembers about a project is stored in
`~/.local/share/nvim/epitech.nvim/projects.json` (Neovim's data directory),
never in your repository: C-O1 forbids unnecessary files there.

## Lua API

- `require("epitech").format_buffer(buf)` formats a buffer in place, the
  current one when `buf` is omitted, exactly as `<leader>cf` does.
- `require("epitech").insert_header()` and `insert_guard()` are what
  `:EpitechHeader` and `:EpitechGuard` run, for your own mappings.
- `require("epitech").file_budget()` returns the current file's budget as
  text, for a statusline.
- `require("epitech.rules").rules` lists the 42 rules of the coding style
  (code, title, severity, who checks it, a summary and examples);
  `require("epitech.rules").by_code["C-L1"]` finds one.
- `require("epitech.ts").functions(buf)` lists a C buffer's functions (name,
  static or not, parameters, body length) with Neovim's bundled C parser;
  nvim-treesitter isn't needed.

## Tests

```sh
test/run
```

Tests that need the real `epiclang` (the formatter tests, which also need
`~/.vim/epitech.vim`, and a Banana diagnostics test) are skipped when it is
missing; the rest of the suite uses a stand-in.

The suite runs with a temporary `XDG_DATA_HOME`, so it never touches the
plugin's state in your own data directory. Test scripts share the helpers in
`test/helpers.lua`: `assert_equal`, `temp_project` (a temp git repository
built from a table of files), `with_fake_epiclang` (a stand-in `epiclang` that
prints canned Banana output, so nothing but calibration needs the real tool)
and `buffer`.
