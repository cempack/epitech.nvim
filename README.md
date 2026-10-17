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
