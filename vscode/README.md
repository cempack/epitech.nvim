# Epitech Coding Style for VS Code

The Epitech C Coding Style in VS Code, from the same repository as
[epitech.nvim](https://github.com/cempack/epitech.nvim): both editors format,
measure and scaffold a project the same way, and the tests check it.

```c
static int parse_args(int ac, char **av)          13/20 lines · 2/4 args
{
    ...
        if (flag == 'l') {                         depth 2
```

## What it does

- **Formats C files and headers so Banana accepts their layout.** Format
  Document (`Shift+Alt+F`, or format on save) runs clang-format with
  Epitech's style, then the passes clang-format can't do: preprocessor
  indentation (C-G3), spacing in `#define`s (C-L3), the one blank line after
  declarations (C-L6), `**` comment prefixes, wrapped lines indented the way
  Banana counts them (C-L2). It's the Neovim plugin's formatter, ported line
  for line.
- **Banana's reports as you save**: epiclang runs on every C file you open
  or save, and its reports land in the Problems panel with their rule code.
  Hover one to read the rule, with an example of what's wrong and what's
  right. **Epitech: Check the Whole Project with Banana** checks every
  tracked file.
- **Meters**: `13/20 lines · 2/4 args` after each function's signature
  (C-F4, C-F5), the nesting depth from 2 on and long `if` chains (C-C1),
  and `functions 8/10 · non-static 5/5` in the status bar (C-O3). They turn
  yellow at the limit and red past it.
- **Fixes**: `()` becomes `(void)` (C-F6) from the light bulb, or in the
  whole file with **Epitech: Add (void) to Every Empty Parameter List**.
- **Headers**: **Epitech: Insert Epitech Header** (`Ctrl+Alt+H`) for C,
  Makefiles and about 35 other languages; **Epitech: Add an Include Guard**
  (which also replaces `#pragma once`).
- **New projects**: **Epitech: New Project** asks for a name and the
  libraries to link (CSFML, ncurses, math) and writes the Makefile
  (`all`, `clean`, `fclean`, `re`, `unit_tests`, `tests_run`, `debug`),
  `include/<name>.h`, `src/main.c`, `src/print_error.c` with the part of
  libmy it needs, a Criterion test and a `.gitignore`. A name like
  `libmy.a` makes a library. **Epitech: New Source File** adds a file with
  its header and its line in the Makefile's `SRC`.
- **Rules**: **Epitech: Explain a Coding Style Rule** (`Ctrl+Alt+E`) shows
  the rule under the cursor, or lets you pick one of the 42.
- **Snippets**: `main`, `fn`, `sfn`, `tdef`, `tenum`, `sw`, `fori`, `ife`,
  `mal`, all in the style.

It also sets C files to 4 spaces, a ruler at 80 columns, no trailing spaces
and a final newline, and opens `.h` files as C.

## Requirements

| | |
|---|---|
| clang-format 21 or later | the formatter (`epitech.format.clangFormat` to point at it) |
| epiclang | Banana's reports and the project check (`epitech.diagnostics.command`) |
| git | the project check (it covers tracked files) |

On Arch, [epitech-dump-arch](https://github.com/cempack/epitech-dump-arch)
installs all of it, this extension included, and keeps it up to date.

## Install

- With epitech-dump-arch: nothing to do, it installs the extension in each of
  `code`, `codium` and `code-oss` it finds, and updates it every week.
- By hand: download `epitech.vsix` from the
  [latest release](https://github.com/cempack/epitech.nvim/releases/latest),
  then `code --install-extension epitech.vsix`.

## Settings

| Setting | Default | |
|---|---|---|
| `epitech.format.enabled` | `true` | format C files |
| `epitech.format.clangFormat` | `clang-format` | clang-format 21+ |
| `epitech.diagnostics.enabled` | `true` | run Banana on open and save |
| `epitech.diagnostics.command` | `epiclang` | the checker |
| `epitech.diagnostics.args` | `["-x", "c", "-fsyntax-only"]` | its arguments before the include flags |
| `epitech.budget.functions` | `true` | lines and parameters per function |
| `epitech.budget.depth` | `true` | nesting depth and branches |
| `epitech.budget.file` | `true` | function counts in the status bar |
| `epitech.scaffold.cc` | `epiclang` | `CC` of new projects |
| `epitech.scaffold.cflags` | `""` | their `CFLAGS` |
| `epitech.scaffold.debugCflags` | `-g3` | what `make debug` adds; empty for no rule |
| `epitech.scaffold.errorFile` | `true` | `src/print_error.c` and libmy in new programs |

## Development

The extension is plain JavaScript, no build step. Everything Epitech-specific
is in modules without a VS Code dependency (`src/format.js`, `banana.js`,
`budget.js`, `scaffold.js`…); `src/extension.js` wires them to VS Code. The
rules, header styles, clang-format style, snippets and templates are the
Neovim plugin's own files, at the repository root.

```sh
cd vscode
npm ci
npm test          # node --test: the modules, the wiring, and the
                  # formatter/scaffold/meters against the Neovim plugin
npm run package   # epitech.vsix
```

`npm run vendor` copies the parser and the shared files into `vendor/` and
`data/` (both generated) before running the extension with F5.
