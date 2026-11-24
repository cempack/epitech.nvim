# Epitech Coding Style for VS Code

The Epitech C Coding Style in VS Code, from the same repository as
[epitech.nvim](https://github.com/cempack/epitech.nvim): both editors
format, check, fix and scaffold a project the same way, and the tests
compare them line for line. Unofficial.

```c
static int parse_args(int ac, char **av)          13/20 lines · 2/4 args
{
    ...
        if (flag == 'l') {                         depth 2
```

## Write

- **Saving formats the file** so Banana accepts its layout: clang-format with
  Epitech's style, then what clang-format can't do: preprocessor nesting
  (C-G3), spaces in `#define`s (C-L3), the blank line after declarations
  (C-L6), `**` comment prefixes, wrapped lines at the depth Banana counts
  (C-L2).
- **Banana's reports** (epiclang) when you open or save a file, in the
  Problems panel with their rule. Hover one, or click its code, to read the
  rule with an example of what's wrong and what's right.
- **Hints for what only graders check** (faint dots by default): a number
  that deserves a name (C-G9), a function only its file uses (C-A4), a
  pointer whose data is never modified (C-A1), an `int` holding a length
  (C-A2), a function name without a verb (C-F2), a vague file name (C-O4),
  typedef and macro names (C-V1). One Banana already reports doesn't show
  twice.
- **Meters**: `13/20 lines · 2/4 args` after each function (C-F4, C-F5),
  `depth 2` and `depth 3 ✗ C-C1` on nested blocks, `4 branches ✗ C-C1` on
  long `if` chains, `functions 8/10 · non-static 5/5` in the status bar
  (C-O3). Yellow at the limit, red past it.
- **Makefiles** are checked too: header, 80 columns, trailing spaces, empty
  lines, final newline.
- **Snippets**: `main`, `fn`, `sfn`, `tdef`, `tenum`, `sw`, `fori`, `ife`, `mal`.

## Fix

`Ctrl+.` on a report:

| Rule | Fix |
|---|---|
| C-F6 | `int f()` → `int f(void)` |
| C-L5 | declarations moved to the top of the function, one per line |
| C-L1 | `a = b = 0;`, `s[i++] = c;`, `if ((fd = open(…)) == -1)` and `a && f();` split into one statement per line |
| C-C1 | a long `if`/`else if` chain on one variable → `switch` |
| C-A1 | `char *str` → `char const *str`, in the header's prototype too |
| C-A4 | `static`, and the prototype removed from the header |
| C-G9 | a number → a macro in the project header (suggests a name, reuses one that exists) |
| Makefile | one `SRC +=` per file when a line is too long, trailing spaces, the header |

A fix is offered only when it keeps the program's meaning; otherwise a hint
says why (`C-L5 no automatic fix: a const variable can't be assigned
later`). Every report also has **Explain** in the same menu.

## Build and test

- **Testing view**: every `Test(suite, name)` of `tests/`. Run one test, a
  file or all of them: `make unit_tests`, Criterion, each failure at its
  line. **Run with Coverage** shows gcovr's line coverage in the editor.
  Afterwards `make fclean` cleans up, as `tests_run` does.
- **Tasks** (Terminal › Run Task, `Ctrl+Shift+B`): `make`, `make re`,
  `make debug`, `make clean`, `make fclean`, `make tests_run`, with compiler
  errors in the Problems panel.

## Start and deliver

- **Epitech: New Project**: Makefile (`all`, `clean`, `fclean`, `re`,
  `unit_tests`, `tests_run`, `debug`), `include/<name>.h`, `src/main.c`,
  `src/print_error.c` with the part of libmy it uses, a Criterion test, a
  `.gitignore`, and a git repository. Pick the libraries to link (CSFML,
  ncurses, math). `libsomething.a` makes a library.
- **Epitech: New Source File** (also on a folder in the Explorer): the file
  with its header, added to the Makefile's `SRC` of the project it's in, even
  in a repository holding several projects.
- **The Epitech sidebar** (`Ctrl+Alt+B` or its beaker): the whole project
  checked, Banana on every tracked file, the Makefiles, the hints and the
  repository rules (C-O1 compiled files tracked, C-O2 extensions, C-O4
  names), grouped by rule. **Untrack Compiled and Temporary Files** fixes
  C-O1.
- **Ignore the Rules in This File / Project** silences a file you didn't
  write (formatting and fixes still work).
- **Get Started** walks through all of it.

## Requirements

| | |
|---|---|
| clang-format 21 or later | the formatter (`epitech.format.clangFormat` to point at it) |
| epiclang | Banana's reports and the project check |
| git | the project check and the static hint |
| make, Criterion, gcovr | the tests and their coverage |

[epitech-dump-arch](https://github.com/cempack/epitech-dump-arch) installs
all of it on Arch and Ubuntu, this extension included, and keeps it current.
Elsewhere: `pipx install clang-format`, and epiclang from Epitech's dump.

## Install

- With epitech-dump-arch: nothing to do.
- By hand: download `epitech.vsix` from the
  [latest release](https://github.com/cempack/epitech.nvim/releases/latest),
  then `code --install-extension epitech.vsix`.

**Updates.** Once a day the extension looks for a newer release; **Update
now** installs it in place (then reload the window). **Epitech: Check for
Updates** does it on demand, and `epitech.updates.check` turns the daily
check off. With epitech-dump-arch, `epitech-upgrade` also updates it every
week; without it, the update message offers the installer, which brings
epiclang, clang-format and the rest (Arch and Ubuntu).

## Settings

| Setting | Default | |
|---|---|---|
| `epitech.format.enabled` | `true` | format C files (on save, through `editor.formatOnSave`) |
| `epitech.format.clangFormat` | `clang-format` | clang-format 21+ |
| `epitech.diagnostics.enabled` | `true` | Banana on open and save |
| `epitech.diagnostics.command` | `epiclang` | the checker |
| `epitech.diagnostics.args` | `["-x", "c", "-fsyntax-only"]` | its arguments before the include flags |
| `epitech.hints.enabled` | `true` | the hints |
| `epitech.hints.severity` | `hint` | `hint` (dots), `information` or `warning` (Problems panel) |
| `epitech.hints.magicNumbers` | `true` | C-G9 |
| `epitech.hints.magicNumbersAllow` | `[0, 1, -1, 84]` | numbers never flagged |
| `epitech.hints.static` | `true` | C-A4 |
| `epitech.hints.types` | `true` | C-A1, C-A2 |
| `epitech.hints.naming` | `true` | C-F2, C-O4, C-V1 |
| `epitech.makefile.enabled` | `true` | Makefile checks |
| `epitech.budget.functions` | `true` | lines and parameters per function |
| `epitech.budget.depth` | `true` | nesting depth and branches |
| `epitech.budget.file` | `true` | function counts in the status bar |
| `epitech.scaffold.cc` | `epiclang` | `CC` of new projects |
| `epitech.scaffold.cflags` | `""` | their `CFLAGS` |
| `epitech.scaffold.debugCflags` | `-g3` | what `make debug` adds; empty for no rule |
| `epitech.scaffold.errorFile` | `true` | `src/print_error.c` and libmy in new programs |
| `epitech.updates.check` | `true` | look for a new version once a day |

For C files it also sets 4 spaces, a ruler at 80 columns, format on save,
no trailing spaces and a final newline, and opens `.h` files as C.

## Development

Plain JavaScript, no build step. Everything Epitech-specific lives in
modules without a VS Code dependency (`src/format.js`, `banana.js`,
`budget.js`, `hints/`, `fixes/`, `check.js`, `scaffold.js`, `tests.js`…),
ported from the Neovim plugin's Lua; `src/extension.js` wires them to VS
Code. The rules, word lists, header styles, clang-format style, snippets and
templates are the plugin's own files, at the repository root.

```sh
cd vscode
npm ci
npm test          # node --test: every port against the Lua code on every
                  # fixture of the repository, plus the VS Code wiring
npm run package   # epitech.vsix
```

`npm run vendor` copies the parser and the shared files into `vendor/` and
`data/` (both generated) before running the extension with F5.
