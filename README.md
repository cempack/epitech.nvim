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

Formatting only changes layout. Rules about structure or meaning, such as
function length, parameter count, naming, or `int f()` instead of
`int f(void)`, are left to `epiclang`.

## Tests

```sh
test/run
```

The formatter tests check their output with `epiclang`, so they are skipped
when it or `~/.vim/epitech.vim` is missing.
