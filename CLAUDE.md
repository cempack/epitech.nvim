# CLAUDE.md

Guidance for Claude Code in the epitech.nvim repository. Read it fully before the first change. Section 2 (ground rules) is not optional, and section 6 lists facts that were checked by running code, so trust them over memory.

**Quick start:** read §2, run `test/run` (§4), then work through the milestones in §8 and §9 in order. Each milestone ends with green tests, an updated README and one commit per feature.

---

## 1. What this repo is

epitech.nvim is a Neovim plugin for the **Epitech C Coding Style v7.1**, built for LazyVim but usable with any lazy.nvim setup. Today it:

- formats C files and headers so their layout passes Banana (`epiclang`): `format_buffer()` runs clang-format with `epitech.clang-format`, then Lua passes handle what clang-format can't (C-G3 preprocessor nesting, C-L3 spacing inside `#define`, C-L6 blank lines, `**` comment prefixes, continuation indentation);
- inserts Epitech headers for about 40 filetypes (`:EpitechHeader`, `<leader>cH`);
- wraps headers in include guards (`:EpitechGuard`, `<leader>cG`);
- sets 4-space indentation for C buffers (`after/ftplugin/c.lua`).

It deliberately leaves rules about structure and meaning to epiclang. The roadmap in this file fills that gap: live Banana diagnostics, budget meters, hints for the rules Banana never checks, code actions that fix violations, and project-level tools.

Owner: Elliot (GitHub `cempack`), an Epitech student. He uses LazyVim, lazygit and Hardtime. His machine has epiclang and `~/.vim/epitech.vim` (installed by his `epitech-dump-arch` setup, which also installs this plugin and updates it weekly through lazy.nvim).

---

## 2. Ground rules

1. **The formatter runs `dofile` on a Lua file inside `nvim --clean`.** `formatter()` builds a command like `nvim --clean --headless -u ~/.vim/epitech.vim -c "lua dofile('<path>').format_stdout()" -`. In that process the plugin is on neither `runtimepath` nor `package.path`, so the file it runs must not `require("epitech.…")` anything. Today that file is `lua/epitech/init.lua`. Milestone 0 (§8.0) moves the formatter to `lua/epitech/format.lua`, which must stay free of requires; after that move, `init.lua` may require modules. Until then, a top-level `require` in `init.lua` breaks format-on-save. `test/nvim.lua` runs the formatter subprocess, so the suite does catch it.
2. **Never write plugin files into the student's repository.** C-O1 forbids unnecessary files in the repo, and graders see everything that's tracked. Per-project state goes in `vim.fn.stdpath("data") .. "/epitech.nvim/"`. The plugin only creates files in a project when the user explicitly asks for them (scaffolding, new source files, header edits), plus the untracked `.git/hooks/pre-push` from `:EpitechHooks`.
3. **Respect the user's setup.** `setup()` already defines a command or keymap only when the user hasn't defined one with the same name or left-hand side. Do the same for every new command and mapping. Every feature can be turned off through `setup(opts)`.
4. **No new hard dependencies.** The baseline is Neovim ≥ 0.11.2 and its bundled C Treesitter parser. Trouble, Snacks, lualine, blink.cmp, LuaSnip and clangd are optional: use `pcall(require, …)` or `vim.fn.exists(":Trouble") == 2`, with a plain-Neovim fallback (quickfix list, `vim.ui.select`, a statusline function).
5. **Banana is the source of truth.** When Banana's behaviour is unknown (how it counts function lines, whether `switch` adds depth…), measure it with a calibration test against the real epiclang (§10) and record the answer in the rules table's `notes`. A temporary guess gets a `-- calibrate:` comment, never silence. If Elliot has a local clone of Epitech's `banana-coding-style-checker` repo (accessible to Epitech students), read it instead of guessing.
6. **Hints are hints.** Anything that guesses at a rule a grader checks uses severity HINT in its own namespace and can be switched off. When Banana already reports the same code on the same line, drop the hint.
7. **A fix is safe or it isn't offered.** A code action appears only when its rewrite keeps the program's meaning. When the plugin can't be sure, it shows a hint explaining why there is no fix. Every fix is idempotent (no action is offered on its own output), and its output passes the formatter unchanged.
8. **Generated C follows the style and Elliot's taste**: braces on every block, even one-line bodies; 4-space indentation; `(void)` for empty parameter lists; one statement per line; plain, classic C with no clever shortcuts. Tests run generated code through `format_buffer()` and expect no change.
9. **Tests for everything** (§4). `test/run` must pass on a machine without epiclang; tests that need epiclang are gated exactly like the formatter tests are today.
10. **Commits**: conventional commits as in the history (`feat:`, `fix:`, `test:`, `docs:`, `refactor:`), one feature per commit, README updated in the same commit. Lua style follows the existing code: 2-space indentation, `local function`, comments that explain *why* and cite the rule code (`-- C-L6: …`).

---

## 3. Repository map

Today:

```
after/ftplugin/c.lua        C buffer options (4 spaces, expandtab, comment leaders)
epitech.clang-format        clang-format 21 style for the layout rules
lua/epitech/init.lua        everything: formatter, headers, guards, setup()
test/run                    runs every test (luac -p, then headless nvim scripts)
test/nvim.lua               setup, headers, guards, formatter subprocess
test/header-filetypes.lua   headers for non-C filetypes
test/format-guard.lua       guards + formatter, checked by epiclang (gated)
test/format-style.lua       formatter output, checked by epiclang (gated)
```

Target. Create these as you go; keep the names unless there's a reason not to:

```
lua/epitech/
  init.lua            setup(opts), commands, keymaps, public API (re-exports)
  format.lua          the formatter, moved from init.lua; must never require anything
  config.lua          defaults, validation, merge
  header.lua          comment styles, header detection and insertion, include guards
  project.lua         root, project name, header choice, compile flags, per-project state
  rules.lua           the rules table (data only)
  ts.lua              Treesitter helpers and the function finder
  lsp.lua             the in-process language server (the "fix menu")
  banana.lua          epiclang runner and output parser
  explain.lua         rule float and :EpitechRules
  budget.lua          function budget, file budget, depth meter
  hints/init.lua      hint runner: debounce, namespace, dedup against Banana
  hints/magic.lua  hints/static.lua  hints/types.lua  hints/naming.lua  hints/makefile.lua
  fixes/init.lua      fix registry used by lsp.lua
  fixes/void.lua  fixes/decl.lua  fixes/one_stmt.lua  fixes/switch.lua  fixes/struct_ptr.lua
  fixes/macro.lua  fixes/static.lua  fixes/move_header.lua  fixes/makefile.lua
  header_sync.lua     :EpitechSyncHeader
  makefile.lua        Makefile edits (SRC += …)
  scaffold.lua        :EpitechNew, :EpitechNewFile
  split.lua           :EpitechMoveTo
  check.lua           :EpitechCheck and its CI mode
  hooks.lua           :EpitechHooks, :EpitechLazygit
scripts/check.lua     headless entry point for the git hook and lazygit
snippets/package.json
snippets/c.json
test/helpers.lua      shared assertions, temp projects, fake epiclang
test/fixtures/…       C files, Makefiles and expected outputs
```

---

## 4. Tests

- Run everything with `test/run`. It syntax-checks every Lua file with `luac -p`, then runs each script with `nvim --clean --headless -u NONE -l test/<name>.lua` and `EPITECH_NVIM_DIR` set.
- Requirements: Neovim ≥ 0.11.2, clang-format ≥ 21 (older versions can't load `epitech.clang-format`) and `luac`. epiclang and `~/.vim/epitech.vim` are optional: tests that need them are skipped when either is missing, like `format-guard.lua` and `format-style.lua` today. epiclang isn't publicly available, so expect those tests to skip on any machine other than Elliot's.

**Fresh machine** (a cloud container, CI). These steps set up the suite on Ubuntu:

```sh
# Neovim 0.11 from the official release (it ships the C Treesitter parser)
curl -L -o /tmp/nvim.tar.gz https://github.com/neovim/neovim/releases/download/v0.11.4/nvim-linux-x86_64.tar.gz
tar -xzf /tmp/nvim.tar.gz -C /opt
ln -sf /opt/nvim-linux-x86_64/bin/nvim /usr/local/bin/nvim

# clang-format 21 (add --break-system-packages where pip asks for it)
pip install "clang-format>=21,<22"
```

When no Lua is installed, this stand-in for `luac -p` checks syntax with Neovim's LuaJIT. Save it as `luac` on `PATH` and make it executable:

```sh
#!/bin/sh
# Stand-in for `luac -p`: syntax-checks each file with Neovim's LuaJIT.
[ "$1" = "-p" ] && shift
for file in "$@"; do
    LUAC_FILE="$file" nvim --clean --headless \
        +'lua local ok, err = loadfile(os.getenv("LUAC_FILE")) if not ok then io.stderr:write(err .. "\n") os.exit(1) end os.exit(0)' \
        || exit 1
done
```

The coding style PDF is not in this repository and must never be committed: it's Epitech's document. §5 is the reference; if Elliot provides a copy, keep it outside the repo.
- A new test file starts with the first three lines of `test/nvim.lua` (runtimepath and `package.path`), uses plain `assert` plus `assert_equal`, prints one line on success, and gets added to `test/run` (inside the gated block if it needs epiclang).

Add `test/helpers.lua` in Milestone 0:

- `assert_equal(actual, expected, label)`, moved from `test/nvim.lua`.
- `temp_project(files)` creates a temp directory from `{ ["src/main.c"] = { …lines }, … }`, runs `git init` and `git add -A` (several features rely on `git ls-files`), and returns the root plus a `cleanup()`.
- `with_fake_epiclang(stderr_lines, fn)` writes an `epiclang` script to a temp bin directory that prints the given lines to stderr and exits 0, prepends that directory to `vim.env.PATH`, runs `fn`, then restores `PATH`. The runner, the parser, the project check and the hook can then be tested anywhere; the real tool is only needed for calibration.
- `buffer(name, lines)` creates a named buffer with filetype `c` and makes it current.

Code actions are tested through the real LSP path: start the server on a buffer, `client:request_sync("textDocument/codeAction", params, 1000, buf)`, apply with `vim.lsp.util.apply_workspace_edit(action.edit, client.offset_encoding)` (verified in §6.3). Fixtures live in `test/fixtures/fixes/<fix>/<case>.before.c` and `.after.c`. Each fix test checks three things: the output matches `.after.c`, no action for the same rule is offered on the output (idempotence), and `format_buffer()` leaves the output unchanged.

Calibration tests (§10) go in `test/calibrate.lua`, run only when epiclang exists, and print what they measured.

---

## 5. The coding style in one table

**Severity.** Fatal: the project is rejected and not graded at all. Major: structural, fix first. Minor: presentation, repeated violations hurt. Info: good practice. Rules that aren't written in the PDF ("implicit rules") count as Info.

**Checked by.** Banana (🍌, automatic), Grader (👤, a person reads the code), or Both. Banana fully checks 27 rules, partly checks 8, and never checks 7.

| Code | Name | Severity | Checked by | In short |
|---|---|---|---|---|
| C-O1 | Contents of the repository | Major | Banana | No compiled (`.o`, `.a`, `.so`…), temporary (`*~`, `#*#`) or unnecessary files in the repo. |
| C-O2 | File extension | Major | Grader | C sources only use `.c` and `.h`. |
| C-O3 | File coherence | Major | Both | One logical entity per file; at most 10 functions per file, at most 5 of them non-static. |
| C-O4 | Naming files and folders | Minor | Both | English snake_case names that say what the file holds (`string_toolbox.c`, not `string.c`); abbreviations only if still clear. |
| C-G1 | File header | Minor | Banana | Every `.c`, `.h` and Makefile starts with the Epitech header, with a meaningful description. |
| C-G2 | Separation of functions | Minor | Banana | Exactly one empty line between function implementations. |
| C-G3 | Indentation of preprocessor directives | Minor | Banana | Directives are indented by nesting level (4 spaces), independently of the code. |
| C-G4 | Global variables | Major | Banana | No global variables, only `const` globals. |
| C-G5 | include | Major | Banana | `#include` only header files. |
| C-G6 | Line endings | Minor | Banana | Unix line endings, no `\r` anywhere, no line ending with a backslash. |
| C-G7 | Trailing spaces | Minor | Banana | No trailing whitespace. |
| C-G8 | Leading/trailing lines | Minor | Banana | No empty lines at the start of a file, at most one at the end. |
| C-G9 | Constant values | Minor | Grader | Non-trivial constants go in a macro or a global constant. |
| C-G10 | Inline assembly | Fatal | Banana | Never use inline assembly. |
| C-F1 | Coherence of functions | Minor | Grader | A function does one thing, at one level of abstraction. |
| C-F2 | Naming functions | Minor | Both | English snake_case names that contain a verb and say what the function does. |
| C-F3 | Number of columns | Major | Banana | At most 80 columns per line, the newline included, tabs counting as several columns; Makefiles too. |
| C-F4 | Number of lines | Major | Banana | A function body has at most 20 lines. |
| C-F5 | Number of parameters | Major | Banana | At most 4 parameters; variadics may not be used to get around that. |
| C-F6 | Functions without parameters | Major | Banana | Write `(void)`, never `()`. |
| C-F7 | Structures as parameters | Major | Banana | Pass structs by pointer, never by copy. |
| C-F8 | Comments inside a function | Minor | Banana | No comments inside function bodies; put one above the function instead. |
| C-F9 | Nested functions | Major | Banana | No nested functions (a GNU extension). |
| C-L1 | Code line content | Major | Both | One statement per line (a `for` loop's three parts excepted); no assignment inside a condition, no `cond && f();` tricks. |
| C-L2 | Indentation | Minor | Both | 4 spaces per level, no tabs, one level per scope. |
| C-L3 | Spaces | Minor | Banana | Single spaces as separators, around binary and ternary operators, after commas and keywords; none before a call's `(`, a `;` or a `,`. |
| C-L4 | Curly brackets | Minor | Banana | Opening brace at the end of the line, except function definitions (own line); closing brace alone, except `else`, `do while`, struct and enum. |
| C-L5 | Variable declarations | Major | Banana | Declare at the start of the function, one variable per statement (`for` initializers excepted). |
| C-L6 | Blank lines | Minor | Banana | One blank line after the declarations and no other blank line inside a function. |
| C-V1 | Naming identifiers | Minor | Both | English snake_case; typedef names end in `_t`; macros, global constants and enum values in UPPER_SNAKE_CASE. |
| C-V2 | Structures | Major | Grader | A struct groups data that forms a coherent entity and stays small. |
| C-V3 | Pointers | Minor | Banana | The `*` sticks to the name (`int *a`), with matching rules for casts (`(int *) ptr`). |
| C-C1 | Conditional branching | Major | Banana | At most 3 branches per `if` chain; no nesting depth of 3 or more, where `else if` counts as an `if` inside an `else`. |
| C-C2 | Ternary operators | Major | Both | Simple ternaries only, never nested or chained, and their value must be used. |
| C-C3 | goto | Major | Banana | No `goto`. |
| C-H1 | Content | Major | Both | Prototypes, types, structs, enums, global declarations, macros and `static inline` functions only appear in headers; no conditional preprocessing in `.c` files. |
| C-H2 | Include guard | Major | Banana | Headers use `#ifndef` / `#define` / `#endif` guards. |
| C-H3 | Macros | Major | Banana | A macro is one statement on one line, and not a shortcut for a long expression. |
| C-A1 | Constant pointers | Info | Grader | Mark pointed-to data `const` when the function doesn't modify it. |
| C-A2 | Typing | Info | Grader | Use the most precise type (`size_t`, `uint8_t`, `ptrdiff_t`…). |
| C-A3 | Line break at the end of file | Info | Banana | Files end with a newline. |
| C-A4 | static | Info | Grader | Functions and globals used only in their own file are `static`. |

**Language extensions.** The PDF lists `__attribute__((noreturn))` (use `[[noreturn]]`), `#pragma once` (use `#ifndef`/`#define`/`#endif`) and `\e` (use `\x1B`) as unsupported: Banana's behaviour on them is undefined.

**Makefile header.** The PDF's Makefile example shows `###` on the inner header lines, while Epitech's official Vim config (Epitech/vim-epitech, `epitech.vim`) writes `##`. The plugin writes `##`, as the official config and the existing tests do. Detection must accept both.

---

## 6. Verified facts

These were checked by running code (Neovim 0.11.4, clang-format 21.1.8, October 2026). Re-check them if versions change.

### 6.1 epiclang

- The existing tests run `epiclang -x c -fsyntax-only <file>`, which works for `.h` files too.
- A clean file gives exit code 0 and empty stderr. Violations are clang warnings on **stderr**, and the exit code stays 0.
- Line format (from cs2's parser and the epiclang-macos README):
  `src/main.c:3:50: warning: [Banana] [Major] multiple statements on the same line (C-L1)`.
  Some entries may have no line or column (cs2's regex allows `file: warning: …`). Levels are `Fatal`, `Major`, `Minor`, `Info`. Codes can have two digits (`C-G10`).
- Errors in a header are printed again for every file that includes it.
- Other compiler output (real errors, `1 warning generated.`) is mixed in. Ignore every line without `[Banana]`; clangd already shows compile errors.
- Measured on Elliot's machine (§10): epiclang prints every warning **twice** in one run, each followed by clang's source excerpt (`   8 | int computeSum(…)` and a `^` line), and a header's warnings come after `In file included from …:8:` with the header's absolute path (when included through an absolute `-I`). It never reports C-O4. It counts a tab as 4 columns for C-F3 (`100-character line` for a tab and 96 characters). Run on a Makefile, it reads it as C (C-G4 on `all:`, C-L2 on recipe tabs, C-G1 even with a correct `##` header), so it can't check Makefiles.
- `#include "my.h"` only resolves with `-I include`, or with the flags from `compile_commands.json`.
- Lua patterns, tested on the lines above:

```lua
local WITH_POS = "^(.-):(%d+):(%d+): %a+: %[Banana%] %[(%a+)%] (.-) %((C%-%u%d+)%)%s*$"
local NO_POS = "^(.-): %a+: %[Banana%] %[(%a+)%] (.-) %((C%-%u%d+)%)%s*$"
-- path, line, col, level, message, code = line:match(WITH_POS)
-- path, level, message, code = line:match(NO_POS)
```

### 6.2 Treesitter C (the parser bundled with Neovim 0.11.4)

Neovim ships the C parser (`lib/nvim/parser/c.so`), so nvim-treesitter is not needed. Shapes observed by dumping trees:

| Code | Tree |
|---|---|
| `#pragma once` | `preproc_call` (`preproc_directive` `#pragma`, `preproc_arg` `once`) |
| `#define BUFFER_SIZE 4096` | `preproc_def` (`identifier`, `preproc_arg`) |
| `typedef struct player_s {…} player_t;` | `type_definition` > `struct_specifier`, then `type_identifier` `player_t` |
| `__attribute__((noreturn)) void die(void);` | `declaration` > `attribute_specifier` |
| `int print_help();` | `declaration` > `function_declarator` > `parameter_list` with **no children** |
| `int f(void)` | `parameter_list` with one `parameter_declaration` whose type is `primitive_type` `void`; not a parameter |
| `static char *dup_str(char const *s, int a, ...)` | `function_definition` with `storage_class_specifier` `static`; `pointer_declarator` wraps the `function_declarator`; `...` is `variadic_parameter` |
| `int i, j = 0;` | one `declaration` with an `identifier` (`i`) and an `init_declarator` (`j`, value) |
| `char buffer[4096];` | `declaration` > `array_declarator` > `number_literal` |
| `a = j = i = 0;` | right-nested `assignment_expression`s |
| `str[i++] = 'A';` | `assignment_expression` > `subscript_expression` > `update_expression` |
| `if ((fd = open(p, O_RDONLY)) == -1)` | `if_statement` > `parenthesized_expression` > `binary_expression` > `parenthesized_expression` > `assignment_expression`; `-1` is one `number_literal` |
| `else if (…)` | `if_statement` > `else_clause` > `if_statement` |
| `else {…}` | `else_clause` > `compound_statement` |
| `switch` | `switch_statement` > `compound_statement` > `case_statement`s (`default:` is a `case_statement` without a value) |
| `player.name` | `field_expression` (`identifier`, `field_identifier`); the `.` or `->` is an anonymous child |
| `(a != c) && my_putstr("…");` | `expression_statement` > `binary_expression` with a `call_expression` operand |
| `"\e[31m"` | `string_literal` > `escape_sequence` `\e` |
| `NULL`, `// text` | `null`, `comment` |

Always search down the declarator chain for the `function_declarator`, because pointer-returning functions wrap it. To confirm a shape, use the dump script in the appendix.

### 6.3 An in-process language server works

`vim.lsp.start({ cmd = fn })` accepts a Lua function that receives `dispatchers` and returns `{ request, notify, is_closing, terminate }` (`vim.lsp.rpc.PublicClient`). Returning `positionEncoding = "utf-8"` from `initialize` makes ranges byte-based, which matches Treesitter. `vim.lsp.buf.code_action()` (LazyVim's `<leader>ca`) merges this client's actions with clangd's. Client-side commands go in `vim.lsp.commands[name] = function(command, ctx) … end`; use them for fixes that need input. The skeleton in §8.3 was run: it offered the C-F6 action, `offset_encoding` came back as `utf-8`, and applying the edit produced `int print_help(void);`.

### 6.4 Snippets in blink.cmp (LazyVim's default completion)

blink's snippet source loads every path in `sources.providers.snippets.opts.search_paths`. A path containing a VS Code–style `package.json` (`contributes.snippets[]` with `language` and `path`) is loaded through that manifest. The default list is `{ vim.fn.stdpath("config") .. "/snippets" }`, and setting the option replaces it, so keep the default when adding the plugin's folder. LuaSnip users load the same folder with `require("luasnip.loaders.from_vscode").lazy_load({ paths = { dir } })`. Don't use VS Code regex transforms in snippet bodies: Neovim's snippet expansion doesn't support them.

### 6.5 Neovim APIs to lean on

`vim.fs.root(buf, { ".git", "Makefile" })`, `vim.system` (async, `:kill()`), `vim.diagnostic.set`, `nvim_buf_set_extmark` (`virt_text`, `virt_text_pos = "eol"`, `virt_lines`), the window-local `winbar` option, `vim.ui.select` and `vim.ui.input` (LazyVim routes them to Snacks), `vim.lsp.util.open_floating_preview`, `vim.fn.setqflist({}, " ", { title = …, items = … })`, `vim.json.decode`, `vim.uv`. Neovim 0.11 also has `vim.diagnostic.config({ virtual_lines = true })`; that's the user's choice, so never change their diagnostic config.

### 6.6 Neovim 0.12 (checked with 0.12.5 on Elliot's machine)

- `vim.glob.to_lpeg("#*#")` no longer matches `#notes.c#` (`*.o`, `*~` and `vgcore.*` still match). The project check matches its C-O1 patterns with a plain Lua pattern instead.
- `vim.system` raises an error when `cwd` doesn't exist (0.11 didn't get there in practice). `project.files` returns nil for a missing root, which happens when a check finishes after its project was deleted.

---

## 7. Configuration

`require("epitech").setup(opts)`. Calling `setup()` with no argument must keep working: the README spec and the dump call it that way.

```lua
{
  diagnostics = {
    enabled = true,
    cmd = "epiclang",
    args = { "-x", "c", "-fsyntax-only" }, -- include flags are added per project
    events = { "BufWritePost", "BufReadPost" },
  },
  explain = { keymap = "<leader>cE" },
  budget = {
    functions = true,          -- "13/20 lines · 2/4 args" after each signature
    file = "winbar",           -- "winbar" | "lualine" (component only) | false
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
    naming = { enabled = true, verbs = nil, vague_files = nil }, -- nil = built-in lists
  },
  makefile = { enabled = true, tab_width = 8 },
  fixes = { enabled = true },
  check = { keymap = "<leader>cB", fail_on = { "fatal", "major" } },
  scaffold = { keymap = "<leader>cN", cc = "epiclang", cflags = "" },
}
```

`84` is in the default allow list because it's Epitech's conventional error exit code; without it, every `return 84;` would light up. `makefile.tab_width = 8` is a conservative guess for how wide a recipe tab is; see §10.

Validation: an unknown key gives one warning through `vim.notify`; a wrong type raises an error naming the key path.

**Keymaps** (only set when free, each configurable or disabled with `false`): `<leader>cE` explains the rule under the cursor, `<leader>cB` runs the project check and `<leader>cN` creates a source file (asked for by Elliot); the existing `<leader>cH` and `<leader>cG` stay. Everything else is a command. LazyVim already uses `<leader>ca` (code actions, where the fixes appear), `<leader>cd`, `<leader>cf`, `<leader>cr`, `<leader>cR`, `<leader>cs`, `<leader>cS`, and its clangd extra uses `<leader>ch`; don't take those.

**Highlight groups** (defined with `default = true` so colorschemes can override): `EpitechBudgetOk` → `Comment`, `EpitechBudgetNear` → `DiagnosticWarn`, `EpitechBudgetOver` → `DiagnosticError`, `EpitechWinbar` → `WinBar`.

**Namespaces**: `epitech.banana`, `epitech.hints`, `epitech.makefile`, `epitech.budget`, `epitech.depth`.

---

## 8. Groundwork and shared pieces

### 8.0 Milestone 0: groundwork

1. **Move the formatter** (`format_buffer`, `format_stdout` and their helpers, `style_file`) to `lua/epitech/format.lua`. It computes the plugin directory from its own path, keeps its own small C header check, and requires nothing. `formatter()` now runs `dofile` on `format.lua`. `init.lua` re-exports `format_buffer` and `format_stdout`. `format_buffer()` only works on the current buffer today; give it an optional `buf` argument, because header sync, fixes and tests need to format other buffers. Existing tests pass unchanged.
2. **Move headers and guards** (`comment_styles`, `header_lines`, `existing_header`, `has_header`, the guard helpers including the `#pragma once` fix from §13) to `lua/epitech/header.lua`. Keep `insert_header` and `insert_guard` exported from `init.lua`.
3. **`config.lua`**: the defaults in §7, a deep merge, and validation.
4. **`project.lua`**:
   - `root(buf)`: `vim.fs.root(buf, { ".git", "Makefile" })`, falling back to the file's directory.
   - `name(root)`: `NAME = …` from the Makefile, else the project line (line 3) of an existing Epitech header, else the directory name.
   - `include_flags(root, file)`: from `compile_commands.json` when present (keep `-I`, `-isystem`, `-D`, `-std=`; drop `-c`, `-o <x>` and the file itself), else `-I<root>/include` when that directory exists, plus `-I<root>`.
   - `state(root)` and `save_state(root, tbl)`: JSON in `stdpath("data")/epitech.nvim/projects.json`, keyed by the absolute root.
   - `project_header(root)`: the remembered choice, else `include/<name>.h`, else the only `.h` in `include/`, else ask with `vim.ui.select` and remember the answer.
5. **`test/helpers.lua`** (§4).

### 8.1 Rules table: `lua/epitech/rules.lua`

Data only, one entry per rule in PDF order:

```lua
{
  code = "C-L1",
  title = "Code line content",
  severity = "major",          -- "fatal" | "major" | "minor" | "info"
  checker = "both",            -- "banana" | "grader" | "both"
  summary = "One statement per line; a for loop's three parts are the only exception.",
  bad = { "a++; b++;" },
  good = { "a++;", "b++;" },
  notes = nil,                 -- calibration results, e.g. "blank lines count toward C-F4"
}
```

Also export `by_code`, `extensions` (the three unsupported constructs with their replacements) and `severity_rank = { fatal = 1, major = 2, minor = 3, info = 4 }`. Write summaries and examples in your own short words, from §5 (and the PDF when Elliot provides one; never paste its text).

**Tests:** 42 entries with unique codes; severity and checker match §5 exactly (hard-code the expected map in the test); every entry has a non-empty `summary`, `bad` and `good`.

### 8.2 Function finder: `lua/epitech/ts.lua`

```lua
---@class epitech.Function
---@field name string
---@field node TSNode            function_definition
---@field is_static boolean
---@field params TSNode[]        parameter_declaration nodes, (void) excluded
---@field variadic boolean
---@field param_list TSNode
---@field signature_row integer  0-based row holding the function name
---@field body TSNode            compound_statement
---@field body_lines integer     lines strictly between { and } (calibrate, §10)
---@field start_row integer
---@field end_row integer

M.parser(buf)                -- pcall around vim.treesitter.get_parser; nil without a C parser
M.functions(buf)             -- epitech.Function[]
M.prototypes(buf)            -- { name, node, row, empty_params }[] for declarations with a function_declarator
M.function_declarator(node)  -- walks pointer_declarator / parenthesized_declarator chains
M.text(node, source)
M.project_functions(root)    -- { [name] = { file, is_static, row } } over tracked .c files
```

Cache per buffer by `vim.b[buf].changedtick`, so budgets, hints and fixes share one walk per edit. `project_functions` parses file contents with `vim.treesitter.get_string_parser` and caches per file by modification time.

**Tests:** a fixture with a static function, a pointer-returning one, `(void)`, `()`, a variadic, a signature spread over two lines, and Epitech's `{` on its own line.

### 8.3 Fix menu: `lua/epitech/lsp.lua` and `lua/epitech/fixes/init.lua`

An in-process language server named `epitech`, started for `c` and `make` buffers (FileType autocmd) when `fixes.enabled` is on. It implements only:

- `initialize` → `{ capabilities = { codeActionProvider = { codeActionKinds = { "quickfix", "refactor.rewrite" } }, positionEncoding = "utf-8" }, serverInfo = { name = "epitech.nvim" } }`
- `textDocument/codeAction` → asks every registered fix for actions in `params.range`
- `shutdown` → `nil`; the `exit` notification calls `dispatchers.on_exit(0, 15)`
- any other request → a `nil` result

No text sync is needed: fixes read the buffer directly through `vim.uri_to_bufnr`.

Fix modules return:

```lua
{
  id = "void",
  rules = { "C-F6" },
  actions = function(buf, range) return {} end, -- lsp.CodeAction[]
}
```

An action is either edit-based (`edit = { changes = { [uri] = { { range = …, newText = … } } } }`, ranges straight from Treesitter: 0-based rows, byte columns) or command-based (`command = { title = …, command = "epitech.<id>", arguments = { … } }`), with the command handled client-side in `vim.lsp.commands["epitech.<id>"]`. Use commands when the fix needs input (a macro name, a header) or touches files on disk.

This skeleton was run on Neovim 0.11.4 and applied an edit successfully:

```lua
local function create_server(dispatchers)
  local closing, next_id = false, 0
  local srv = {}

  function srv.request(method, params, callback)
    next_id = next_id + 1
    local result
    if method == "initialize" then
      result = {
        capabilities = { codeActionProvider = true, positionEncoding = "utf-8" },
        serverInfo = { name = "epitech.nvim" },
      }
    elseif method == "textDocument/codeAction" then
      local buf = vim.uri_to_bufnr(params.textDocument.uri)
      result = require("epitech.fixes").actions(buf, params.range)
    end
    vim.schedule(function()
      callback(nil, result)
    end)
    return true, next_id
  end

  function srv.notify(method)
    if method == "exit" then
      dispatchers.on_exit(0, 15)
    end
    return true
  end

  function srv.is_closing()
    return closing
  end

  function srv.terminate()
    closing = true
  end

  return srv
end

vim.lsp.start({ name = "epitech", cmd = create_server, root_dir = root }, { bufnr = buf })
```

`:checkhealth vim.lsp` and `:LspInfo` will list a client called `epitech`; that's expected, so mention it in the README.

---

## 9. Features

Build them in this order. Each section gives the rules involved, what the user sees, how to build it, edge cases, tests, and when it's done.

### Milestone 1: live feedback

#### 9.1 Live Banana diagnostics (`banana.lua`)

**Rules:** every rule Banana checks.

**User sees:** when a C file or header is opened or saved, Banana's complaints appear as normal diagnostics (signs, virtual text, `]d`, Trouble), with `source = "Banana"` and `code = "C-L1"`.

**Build:**
- Autocmds on `diagnostics.events` for C buffers (`.h` files are filetype `c` through the README's `vim.filetype.add`).
- Resolve the root and include flags (`project.lua`), then run `vim.system({ cmd, args…, flags…, file }, { cwd = root, text = true }, on_exit)`. Keep one job per buffer and kill the previous one when a new save comes in.
- Parse stderr with the §6.1 patterns. Keep entries whose path, resolved against the root, is this buffer's file; drop the rest (header repeats). Entries without a position go on line 0, column 0.
- Severity: Fatal and Major → ERROR, Minor → WARN, Info → INFO. Prefix Fatal messages with `FATAL: `, since a fatal means the project isn't graded.
- `vim.diagnostic.set(ns_banana, buf, diags)` inside `vim.schedule`.
- epiclang missing: one `vim.notify` per session ("epiclang not found: live Banana diagnostics are off"), then nothing.
- Expose `M.run(buf)` and a pure `M.parse(stderr, file, root)` for tests and for §9.21.

**Edge cases:** an unnamed buffer is skipped; a file outside any project uses its own directory as root.

**Tests:** `parse()` on canned output containing header repeats, an entry without position, a real clang error and `N warnings generated.`; an end-to-end run with the fake epiclang; a gated real run on `test/fixtures/banana/bad.c` that expects at least C-L1 and C-F2.

**Done when:** saving that fixture with the real epiclang shows exactly the codes epiclang prints for it, at the right positions, and nothing for other files.

#### 9.2 Rule explainer (`explain.lua`)

**Rules:** all 42.

**User sees:** `<leader>cE` (or `:EpitechExplain [code]`) on a line with a Banana diagnostic or an epitech hint opens a float:

```
C-L1 · Code line content                 Major · 🍌👤
One statement per line; a for loop's three parts are
the only exception.
✗  a++; b++;
✓  a++;
   b++;
```

With several codes on the line, use the one under the cursor column, else ask with `vim.ui.select`. With no diagnostic on the line, open the picker. `:EpitechRules` lists all rules in `vim.ui.select` (`C-L1  Code line content  (Major)`); choosing one opens the float.

**Build:** `vim.lsp.util.open_floating_preview(lines, "markdown", { border = "rounded", focus_id = "epitech_explain" })`, with the examples in a fenced `c` block so they get highlighted. A pure `M.lines(rule, diagnostic)` builds the content.

**Tests:** the rules table test (§8.1); `M.lines()` output for one rule with and without a diagnostic; the picker gets 42 items.

### Milestone 2: budgets

#### 9.3 Function budget (`budget.lua`)

**Rules:** C-F4, C-F5.

**User sees:** at the end of each function's signature line, `13/20 lines · 2/4 args`. Dim below `warn_lines`, warning color from `warn_lines`, error color past `max_lines`; the args part turns red past `max_args`. A variadic shows as `2/4 args + …`.

**Build:** extmarks in `epitech.budget` on `signature_row`, the line with the function name (in Epitech style the `{` is on the next line). Update with a 150 ms debounce on `BufEnter`, `TextChanged`, `TextChangedI` and `InsertLeave`.

**Calibrate (§10):** whether blank lines, comment lines, the C-L6 blank line and the continuation lines of a multi-line statement count toward the 20.

**Tests:** a fixture with 13-, 17-, 20- and 21-line bodies and 0, 1, 4 and 5 parameters → expected extmark texts and highlight groups; the gated calibration test.

**Done when:** the meter agrees with epiclang's C-F4 and C-F5 verdicts on every calibration fixture.

#### 9.4 File budget (`budget.lua`)

**Rules:** C-O3.

**User sees:** a winbar `src/parser.c   functions 8/10 · non-static 5/5`; each count turns to the warning color at its limit and the error color past it. With `budget.file = "lualine"` there's no winbar and `require("epitech").file_budget()` returns the text for a lualine component.

**Build:** set a window-local winbar only when the window's winbar is empty or was set by the plugin (`vim.w[win].epitech_winbar = true`), on `BufWinEnter` and `WinEnter`, and clear it when the window switches to a non-C buffer. Use `%{%v:lua.require'epitech.budget'.winbar()%}`, cached per `changedtick`. For headers, show the bar only when they define functions (`static inline`).

**Tests:** the winbar string on fixtures; a user-defined winbar is never overwritten.

#### 9.5 Nesting depth meter (`budget.lua`)

**Rules:** C-C1.

**User sees:** at the end of control statements from depth `show_depth_from` (2) on: `depth 2`, `depth 2 (else + if)` on an `else if`, and `depth 3 ✗ C-C1` in the error color from `max_depth`. On the first `if` of a chain with more than 3 branches: `4 branches ✗ C-C1`.

**Depth rule**, from the PDF's own unfolded examples: inside a function body, an `if`, `while`, `for` or `do` sits one level below the nearest enclosing control statement (the function's top level is 0). An `if` that is the direct child of an `else_clause` is nested in the `else` of the previous `if`, so it sits one level below that `if`. Expected results:

| Code | Depths |
|---|---|
| `while { for { if } }` | 1, 2, 3 → violation |
| `if / else if / else if` | 1, 2, 3 → violation |
| `if {} else if { while {} }` | 1, 2, 3 → violation |
| `if / else if / else` | 1, 2 → fine |
| `while { if }` | 1, 2 → fine |

**Branches:** 1 + the number of `else if` + 1 if there's a final `else`. More than 3 is a violation (`if / else if / else if / else` = 4).

**`switch`:** unknown whether Banana counts it. Count it as a level until §10 says otherwise.

**Tests:** a fixture with every row of the table → expected labels per row; the gated calibration test.

### Milestone 3: hints for what Banana can't see

`hints/init.lua` runs the hint modules on `BufEnter`, `TextChanged`, `TextChangedI` and `InsertLeave` with a 250 ms debounce (the subprocess-based static check runs on `BufWritePost` instead), writes to `epitech.hints` with `hints.severity`, `source = "epitech.nvim"` and `code = "C-…"`, and drops a hint when `epitech.banana` has the same code on the same line. `:EpitechHints on|off` toggles them. Hint modules are pure: `run(src, path, ctx) -> diagnostics`, so §9.21 can call them on files that aren't open.

#### 9.6 Magic numbers (`hints/magic.lua`, `fixes/macro.lua`)

**Rules:** C-G9 (grader), with C-H1 deciding where macros go.

**User sees:** a hint on number literals inside function bodies that aren't in `allow`: `C-G9 name this number?`. Code action **Extract 4096 into a macro…** asks for a name with `vim.ui.input` (prefilled when there's an obvious one, such as `BUFFER_SIZE` for an array size), checks it against `^[A-Z][A-Z0-9_]*$`, and offers an existing project macro with the same value first.

**Build:** query `(number_literal)` under `function_definition` bodies; `#define`s, enums and global `const`s are outside bodies, so they're never flagged. The fix, a client-side command, inserts `#define NAME value` into the project header inside the guard (after the last `#define`, else right after the guard's own `#define`, indented by the C-G3 logic), then replaces this literal, or every identical literal in the file when the user picks "all N occurrences". It adds `#include "<header>.h"` to the `.c` if it's missing.

**Tests:** hints on a fixture (flags 4096; not 0, 1, -1, 84; nothing in `#define`s or global consts); the fix result; idempotence; name validation.

#### 9.7 Could be static (`hints/static.lua`, `fixes/static.lua`)

**Rules:** C-A4 (grader), C-O3.

**User sees:** a hint on non-static functions that no other file uses: `C-A4 only used in this file`. Code actions: **Add static**, plus **Add static and remove the prototype from include/x.h** when a header declares it.

**Build:** for each non-static function other than `main`, run `git grep -l -w -F -- <name>` in the root (async, on save, cached per file and `changedtick`). A mention in another `.c` file means it's used elsewhere; a prototype in a header alone doesn't. The fix inserts `static ` at the start of the definition (keeping `static inline` order if relevant). Offer prototype removal only when the definition comes before every use in its own file; otherwise removing it would break compilation.

**Tests:** a temp project where `a.c` has a helper used only internally and `b.c` uses another file's function → expected hints and edits.

#### 9.8 Const and precise types (`hints/types.lua`)

**Rules:** C-A1, C-A2 (both grader, Info).

**User sees:** `C-A1 str is never modified → char const *str` on the parameter and `C-A2 holds a length → size_t?` on `int len = my_strlen(str);`. Code action for C-A1: **Make str const**, which rewrites the parameter as `char const *str` (the PDF's examples put `const` after the type) in the definition and in the header prototype.

**C-A1 detection** (pointer parameter `p`, one pointer level in v1). The hint appears only when none of these happen:
- a write through it: `*p = …`, `*p += …`, `p[i] = …`, `(*p)++`, `p[i]++`, `p->f = …`, `p->f++`;
- `p` passed to a function, unless that function's prototype (project headers, via the finder) takes `const` at that position;
- `p` returned, or assigned to another non-const pointer.

When any use is unclear, there's no hint.

**C-A2:** `int` variables initialized or assigned from `strlen(`, `my_strlen(` or `sizeof` get a hint. No fix in v1: changing a type ripples into comparisons and format strings.

**Tests:** positive and negative fixtures for each condition above.

#### 9.9 Naming coach (`hints/naming.lua`)

**Rules:** C-F2, C-O4, C-V1 (all checked partly by Banana, partly by a grader).

**User sees:** hints on function names with no verb (`C-F2 no verb → get_vowels_number?`, with a suggestion only when one is obvious), on vague file names at line 1 (`C-O4 vague name: utils.c`), on typedef names without `_t`, and on macros, enum values or global constants that aren't UPPER_SNAKE_CASE (C-V1). The Banana dedup rule applies, so whatever Banana already reports for C-V1 doesn't show twice.

**Verb check:** split on `_`, ignore a leading `my`, and accept the name when one word is a verb from the list or starts with one (`putstr`). Skip the lib/my classics (`my_strlen`, `my_putstr`, `my_getnbr`, `my_revstr`, `my_strcpy`, `my_strdup`…) and `main`. Starting verb list (configurable): get, set, is, has, can, create, init, new, free, destroy, delete, remove, add, insert, append, push, pop, put, print, display, show, write, read, open, close, load, save, parse, handle, process, compute, calculate, count, find, search, check, validate, update, apply, build, make, convert, copy, dup, move, swap, sort, fill, clear, reset, run, exec, start, stop, alloc, draw, render, split, join, trim, format, concat, compare, match, send, receive, connect, wait, toggle, enable, disable, list, dump, eval, solve, generate, pick, select, filter, merge, sum, reverse, rotate.

**Vague file names** (configurable): utils, util, tools, tool, misc, helpers, helper, functions, funcs, algo, algorithm, string, strings, stuff, common, temp, tmp, new, old.

**Tests:** fixtures for each case, with negatives (`my_strlen`, `get_x`, `pixel_t`).

#### 9.10 Makefile checks (`hints/makefile.lua`, `fixes/makefile.lua`)

**Rules:** C-G1, C-F3, C-G6, C-G7, C-G8, C-A3.

**User sees:** diagnostics in `Makefile` buffers on open, save and edit. These aren't guesses, so they use the rule's real severity (Major → ERROR, Minor → WARN, Info → INFO) in `epitech.makefile`: missing header on line 1; lines wider than 79 visible columns with tabs expanded to `makefile.tab_width` (message `C-F3 86/80 columns`, counting the newline as the PDF says); trailing whitespace; `\r`; leading empty lines; more than one trailing empty line; a missing final newline (only possible when `fixendofline` is off).

**Fixes:** **Add the Epitech header** (reuses header insertion with the make style, asking for project and description), **Split into SRC += lines** for an over-long `SRC = …` line (also converts a backslash-continued assignment), **Remove trailing spaces**.

**Build note:** header detection accepts `##` and `###` inner prefixes (§5).

**Tests:** a fixture Makefile with each problem; each fix's output; the tab-width computation.

### Milestone 4: fixes

#### 9.11 `()` to `(void)` (`fixes/void.lua`)

**Rules:** C-F6 (Major, Banana).

**User sees:** on a line with an empty parameter list, the code action **Add void (C-F6)**. `:EpitechFixAll C-F6` applies it to every tracked `.c` and `.h` in the project and reports `3 functions fixed in 2 files`.

**Build:** query `(function_declarator parameters: (parameter_list) @p)` where `@p` has no named children (this covers definitions, prototypes, `main()` and pointer-returning functions). The edit inserts `void` between the parentheses. The project-wide command edits loaded buffers through the same edits and other files on disk; it skips a file whose buffer has unsaved changes and says so.

**Tests:** before/after fixtures for a definition, a header prototype, a pointer-returning function and `main()`; idempotence; the `:EpitechFixAll` message.

#### 9.12 Declarations to the top (`fixes/decl.lua`)

**Rules:** C-L5 (Major, Banana), C-L6.

**User sees:** on a declaration that isn't at the start of its function, or that declares several variables, the action **Move declarations to the top (C-L5)**, applied to the whole function.

**Algorithm per function:**
1. Collect the `declaration` nodes in the body at any depth, except `for` initializers.
2. Split multi-declarators: `int i, j = 0;` → `int i;` and `int j = 0;`, each keeping its own pointer or array part (`char *a, b[4];` → `char *a;` and `char b[4];`).
3. Declarations before the first statement stay where they are. The others move: `type name;` goes to the end of the leading block, and an initializer stays in place as `name = value;`.
4. Refuse, with a hint saying why, when: an array has an initializer list (`int t[3] = {1, 2, 3};` can't become an assignment); a `const` variable has an initializer; two moved declarations share a name (shadowing).
5. Keep the original order and emit the C-L6 blank line after the declarations.

**Tests:** a mid-function declaration with an initializer, a multi-declarator, a declaration in a nested block, a `for` initializer left alone, and the three refusals.

#### 9.13 One statement per line (`fixes/one_stmt.lua`)

**Rules:** C-L1 (Major, Banana and grader).

Each pattern is its own action, offered on the line:

- **Chained assignment** `a = b = c = v;` (right-nested, plain `=` only): when `v` has no side effects (a literal, identifier or constant) → `a = v;`, `b = v;`, `c = v;` in source order; otherwise → `c = v;`, `b = c;`, `a = b;`. Compound operators (`+=`) are left alone.
- **Increment inside a statement:** `str[i++] = x;` → `str[i] = x;` then `i++;`. In general: postfix updates of plain identifiers used nowhere else in the statement move after it; prefix updates move before it. When the same identifier appears twice (`s[i++] = t[i]`), refuse with a hint saying the line's behaviour is undefined.
- **Assignment inside an `if` condition:** `if ((x = f()) != NULL)` → `x = f();` before the `if`, and the condition becomes `x != NULL`. Only for a plain `if`, not an `else if` (the assignment would run before the earlier conditions), and only when the assignment always runs (not on the right side of `&&` or `||`).
- **`while ((c = getchar()) != EOF)`:** a hint, no fix. A safe rewrite needs the assignment before the loop and at the end of the body, and a `continue` breaks that.
- **`&&` / `||` used as an `if`** (the PDF's sneaky example): `a && f();` → `if (a) {` `f();` `}`; `a || f();` → `if (!(a)) {` `f();` `}`, dropping the parentheses when `a` is a simple operand. Braces always.

**Tests:** before/after for every pattern; each refusal produces a hint and no action.

#### 9.14 Long if-chain to switch (`fixes/switch.lua`)

**Rules:** C-C1 (Major, Banana).

**User sees:** on the first `if` of a chain with more than 3 branches, or one whose `else if`s reach depth 3, the action **Convert to switch (C-C1)** when the chain is eligible.

**Eligible when:** every condition is `x == K` or `K == x` on the same `x` (an identifier or a field expression without side effects), optionally `x == K1 || x == K2` (several case labels), where every `K` is a `number_literal`, a `char_literal` or an UPPER_SNAKE identifier, and all `K`s differ. A final `else` becomes `default:`.

**Generation:** each branch → `case K:`, its statements, then `break;` unless it already ends in `return`, `break`, `continue` or `exit(…)`. Refuse when a branch contains a `break` or `continue` that isn't inside its own loop or switch, because it would now act on the new `switch`. Follow the formatter's case indentation (`IndentCaseLabels` and `IndentCaseBlocks` are on).

**Tests:** a my_ls-style flag chain on `char`, a numeric chain, `||` combinations, refusal on `<`, refusal on a side effect in a condition, refusal on an inner `break`.

#### 9.15 Pass structs by pointer (`fixes/struct_ptr.lua`)

**Rules:** C-F7 (Major, Banana), C-A1.

**User sees:** on a function definition with a struct parameter passed by value (`struct s x`, or a typedef that resolves to a struct), the action **Pass x by pointer (C-F7)**.

**Build:**
1. A parameter is a struct when its type has a `struct_specifier`, or a `type_identifier` that the project's typedef index (a Treesitter scan of the headers for `type_definition` with a `struct_specifier`) marks as a struct.
2. The parameter becomes `T const *x` when the body never writes to it (no assignment to `x.f`, no `x.f++`, no `&x` passed to a non-const parameter, no assignment to `x`), else `T *x`.
3. In the body, `x.f` becomes `x->f` (a `field_expression` with a `.` on the identifier `x`), and bare uses of `x` as a value become `*x`.
4. The matching prototype in the headers gets the same parameter rewrite.
5. Call sites come from clangd (`textDocument/references` on the function name, through `vim.lsp.get_clients({ bufnr = buf, name = "clangd" })`), falling back to `git grep -w`. The argument at that position gets `&` when it's an lvalue (identifier, field expression, subscript); other calls go to the quickfix list for a manual fix, and the user is told.
6. Apply everything as one `WorkspaceEdit` across files.

**Tests:** a temp project with a header, the definition and two call sites (one lvalue, one rvalue) → expected edits and one quickfix entry.

### Milestone 5: headers and project

#### 9.16 Header sync (`header_sync.lua`)

**Rules:** C-H1 (Major, Banana and grader), C-A4.

**User sees:** `:EpitechSyncHeader` updates the project header's prototype block and reports `1 added · 1 changed · 0 removed`.

**Build:**
- The header and its source directories come from the project state. The first run asks for the header (`project_header`) and which directories feed it (default `{ "src" }`; `lib/` usually has its own header).
- Collect the non-static, non-`main` function definitions from tracked `.c` files in those directories. A prototype is the definition's text from its start to the end of its declarator, whitespace collapsed, plus `;`.
- The block lives inside the include guard, between two markers:

  ```c
  /* epitech.nvim: prototypes (:EpitechSyncHeader) */
  /* src/parse_args.c */
  int parse_args(int ac, char **av);
  /* epitech.nvim: end of prototypes */
  ```

  With `group_by_file`, a `/* path */` line opens each file's group; files are sorted and functions keep their order in the file.
- First run without markers: insert the block before the guard's `#endif`, and delete the prototypes elsewhere in the header that the block now contains. Other declarations are left alone.
- Counts compare by function name. Write through the header's buffer when it's loaded (so undo works), else to the file, then run `format_buffer` on it so long prototypes wrap at 80 columns.

**Tests:** first run on a temp project (adoption of existing prototypes), a second run with no changes, a rename (one removed, one added), static functions and `main` excluded, group comments.

#### 9.17 Move to header (`fixes/move_header.lua`)

**Rules:** C-H1 (Major, Banana and grader).

**User sees:** a hint `C-H1 belongs in a header` on top-level type definitions, struct and enum declarations, macros and non-static prototypes in `.c` files, with the action **Move to include/x.h**.

**Build:** the target is `include/<basename>.h` when it exists, else the project header. Insert before the prototypes marker when present (types must come before the prototypes that use them), else before `#endif`, indented by the C-G3 logic. Add `#include "x.h"` to the `.c` when missing.

**Edge cases:** a prototype of a **static** function must not go to a header; offer **Move the definition above its first use** instead, and delete the prototype. Non-const global variables are C-G4, which Banana reports; don't touch them.

**Tests:** a struct typedef moved inside the guard; a macro moved; a prototype moved into the marker block; the static-prototype case.

#### 9.18 Project scaffolding (`scaffold.lua`, `makefile.lua`)

**Rules:** C-O1, C-G1, and everything in the templates.

**User sees:** `:EpitechNew [name]` in an empty directory (or the current one) creates:

```
Makefile             header; NAME, SRC as SRC += lines, OBJ, CFLAGS, all, $(NAME), clean, fclean, re, tests_run, .PHONY
include/<name>.h     header, include guard, empty prototypes block
src/main.c           header, int main(int ac, char **av) returning 0
tests/test_<name>.c  Criterion skeleton
.gitignore           *.o *.a *.so *.gcda *.gcno vgcore.* *~ #*# <name> unit_tests
```

It refuses when a Makefile already exists, unless called as `:EpitechNew!`. `:EpitechNewFile src/x.c` creates the file with a header (project name from `project.name`), adds `SRC += src/x.c` to the Makefile and opens it. For a `.h` it adds a header and a guard and leaves the Makefile alone.

**Makefile template** (recipe lines start with a real tab):

```make
##
## EPITECH PROJECT, <year>
## <name>
## File description:
## Makefile
##

NAME = <name>

SRC += src/main.c

TESTS_SRC += tests/test_<name>.c

OBJ = $(SRC:.c=.o)

UT_SRC = $(filter-out src/main.c, $(SRC)) $(TESTS_SRC)

UT_FLAGS = --coverage -lcriterion

CFLAGS += -Wall -Wextra -I include

all: $(NAME)

$(NAME): $(OBJ)
	$(CC) -o $(NAME) $(OBJ)

clean:
	$(RM) $(OBJ) *.gcda *.gcno

fclean: clean
	$(RM) $(NAME) unit_tests

re: fclean all

tests_run:
	$(CC) -o unit_tests $(UT_SRC) $(CFLAGS) $(UT_FLAGS)
	./unit_tests

.PHONY: all clean fclean re tests_run
```

(Superseded by Elliot's template, see §13: generated Makefiles use backslash-continued lists.) Every line stays under 80 columns with tabs counted at `makefile.tab_width`.

**`makefile.lua`:** `add_source(root, path)` finds the last `SRC` assignment (`^SRC%s*[+:]?=`), follows its backslash continuations and inserts `SRC += path` after it. When `SRC` uses `$(wildcard` or doesn't exist, it changes nothing and tells the user what to add. `remove_source(root, path)` removes a `SRC += path` line or the path from a `SRC =` list.

**Tests:** run `:EpitechNew` in a temp directory and compare every file with expected templates (with the year filled in); the Makefile passes §9.10 and every C file passes header detection; `add_source` and `remove_source` on several Makefile layouts.

#### 9.19 Split a file (`split.lua`)

**Rules:** C-O3.

**User sees:** select whole functions in a `.c` in visual mode, then `:'<,'>EpitechMoveTo src/print_long.c`. The functions move to the new (or existing) file along with any static helpers only they use; a new file gets its header and the source file's `#include`s; `SRC` and the header are updated.

**Build:**
1. Take every function that intersects the selection (function finder).
2. For each static function the moved ones call: used only by moved functions → it moves too; used by both files → it has to become non-static, which counts against the 5 non-static limit (C-O3), so ask first.
3. A new file gets the Epitech header (ask for the description with `vim.ui.input`), the source file's `#include` lines and the functions separated by one blank line (C-G2).
4. Then `makefile.add_source` and `header_sync.run`.

**Tests:** in a temp project, move two functions plus a private helper; the shared-helper case asks; check the resulting texts.

#### 9.20 Epitech snippets (`snippets/`)

**Rules:** C-F6, C-V1, C-L1, C-L4, C-L5.

**User sees:** completion items in C buffers:

| Prefix | Expands to |
|---|---|
| `main` | `int main(int ac, char **av)` with `return 0;` |
| `fn` | a `/* ** description */` block above a function with `(void)` as placeholder |
| `sfn` | the same, `static` |
| `tdef` | `typedef struct name_s {` … `} name_t;` |
| `tenum` | `typedef enum name_e {` … `} name_t;` with an UPPER_SNAKE value |
| `sw` | a `switch` with two cases, `default:` and `break;`s |
| `fori` | `for (int i = 0; i < n; i++) {` … `}` |
| `ife` | `if` / `else` with braces |
| `mal` | `ptr = malloc(sizeof(type) * (size));` followed by a braced `NULL` check returning `NULL` |

**Files:** `snippets/package.json`:

```json
{
  "name": "epitech-snippets",
  "contributes": {
    "snippets": [{ "language": "c", "path": "./c.json" }]
  }
}
```

and `snippets/c.json` in VS Code's format. Expose `require("epitech").snippets_dir()`. README spec for blink.cmp, keeping the default search path (§6.4):

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

LuaSnip alternative: `require("luasnip.loaders.from_vscode").lazy_load({ paths = { require("epitech").snippets_dir() } })`.

**Tests:** the JSON parses; each snippet, expanded with its placeholder defaults (`${1:x}` → `x`, `$0` → empty) in a function or file context, comes out of `format_buffer` unchanged; a gated epiclang run on the expanded file reports nothing for the snippet lines.

### Milestone 6: project check and push guard

#### 9.21 Whole-project check (`check.lua`, `scripts/check.lua`)

**Rules:** all, plus the repository rules C-O1, C-O2 and C-O4.

**User sees:** `:EpitechCheck` (`<leader>cB`) checks every tracked `.c` and `.h` (`git ls-files`) and opens Trouble (`Trouble qflist open`) or the quickfix list, titled `Epitech check: 0 fatal · 3 major · 5 minor · 2 info · 4 hints`, sorted by severity, then file, then line. Repository entries:
- C-O1: tracked `*.o`, `*.a`, `*.so`, `*~`, `#*#`, `vgcore.*`, `*.gcda`, `*.gcno`;
- C-O2: sources with other extensions (`*.cpp`, `*.cc`, `*.cxx`, `*.hpp`, `*.hh`, `*.inl`, `*.inc`);
- C-O4: path segments that aren't snake_case before the extension (skip `Makefile`, `README.md`, `LICENSE` and dotfiles).

`:EpitechCheck untrack` runs `git rm --cached` on the C-O1 files and appends their patterns to `.gitignore`, after a confirmation through `vim.ui.select`.

**Build:**
- Run epiclang per file with a concurrency limit of `vim.uv.available_parallelism()`, reuse `banana.parse`, and deduplicate on (file, line, column, code).
- Run the hint modules on each file's contents (they're pure, see Milestone 3).
- `--ci` mode prints `path:line:col: [Level] message (CODE)` lines and a summary, and exits 1 when any level in `check.fail_on` occurs. Hints never fail the check.
- `scripts/check.lua` runs as `nvim --clean --headless -l scripts/check.lua [--ci] [root]`. It sets `package.path` from its own location (the trick the tests use), requires `epitech.check`, waits for the jobs with `vim.wait`, and exits with `os.exit(code)`.

**Tests:** a temp project and the fake epiclang printing canned output for two files plus a header repeated twice → expected entries (deduplicated), order and title counts; the repository checks (tracked `main.o`, `Utils.c`, `x.cpp`); `--ci` exit codes through `vim.system({ "nvim", "--clean", "--headless", "-l", … })`.

#### 9.22 Push guard (`hooks.lua`)

**User sees:** `:EpitechHooks` installs a pre-push hook in the current repo. A `git push` from the terminal or lazygit then stops while a Fatal or Major is left: `epitech.nvim: 2 Major left, push stopped. Run :EpitechCheck to see them, or git push --no-verify to skip.` `:EpitechHooks remove` deletes it. `:EpitechLazygit` shows the YAML for a lazygit key that runs the check.

**Build:**
- Hooks directory: `git rev-parse --git-path hooks` (handles worktrees).
- When a `pre-push` exists without the plugin's marker comment, ask: **Chain** (run the existing one, then the check), **Replace**, or **Cancel**.
- Hook content, with absolute paths resolved at install time (`vim.v.progpath` for nvim, so git clients without the user's PATH still work), made executable with `vim.uv.fs_chmod(path, 493)`:

  ```sh
  #!/bin/sh
  # Installed by epitech.nvim (:EpitechHooks). Delete this file to remove it.
  root="$(git rev-parse --show-toplevel)" || exit 0
  exec "/usr/bin/nvim" --clean --headless -l "/home/<user>/.local/share/nvim/lazy/epitech.nvim/scripts/check.lua" --ci "$root"
  ```

- When `setup()` finds that the current repo's hook is the plugin's but points to a path that no longer exists (plugin reinstalled), warn once and suggest `:EpitechHooks`.
- lazygit: `:EpitechLazygit` adds this entry to the user's lazygit config (Elliot's choice; it used to only show it), marked with a comment so it can be updated or removed with `:EpitechLazygit remove`:

  ```yaml
  customCommands:
    - key: "B"
      context: "files"
      description: "Banana check"
      command: "nvim --clean --headless -l /path/to/epitech.nvim/scripts/check.lua --ci ."
      output: terminal
  ```

  `output: terminal` is the current lazygit key; older versions used `subprocess: true`. Check `lazygit --version` against lazygit's Custom_Command_Keybindings documentation before relying on it.

**Tests:** in a temp git repo: install → the file exists, is executable and contains the marker and the paths; an existing foreign hook goes through chain, replace and cancel (with `vim.ui.select` stubbed); running the hook against a temp project whose fake epiclang prints a Major exits 1, and a clean one exits 0.

---

## 10. Calibration against the real epiclang

`test/calibrate.lua`, gated on epiclang. Elliot's machine has it. Measure each item, record the answer in `rules.lua` `notes`, adjust the code, and add a test that pins the measured behaviour.

**Done** (first run on Elliot's machine, epiclang as installed there, Neovim 0.12.5): 1. C-F4 counts every line between the braces (blank, the C-L6 blank, comment and continuation lines); 2. `...` counts as a parameter, so four parameters plus `...` is a C-F5 violation (the meter now counts it); 3. `switch` and `do while` add a level and `else { if }` counts like `else if`; 4. four branches are flagged, three aren't; 5. a header's entries repeat with the header's path and stay off the `.c`; 6. C-O4 isn't reported by epiclang at all; 7. nothing for C-G9, C-A1, C-A2, C-A4; 8. a Makefile is read as C, so Banana-through-epiclang doesn't check Makefiles and `makefile.tab_width` stays 8. Also measured: a tab is 4 columns for C-F3. All of it is pinned in `test/calibrate.lua`. The items:

1. **C-F4 line counting.** Generate bodies of 20 and 21 lines made of (a) only statements, (b) declarations plus the C-L6 blank line, (c) a statement spread over two lines, (d) a comment line (also a C-F8 violation; check whether it counts). Find the threshold in each case.
2. **C-F5 variadics.** Does `(int a, int b, int c, int d, ...)` count as 5?
3. **C-C1 depth.** Do `switch` and `case` add a level (`while { switch { case: if {} } }`)? Does `do while` count? Does a plain `else { if }` behave like `else if`?
4. **C-C1 branches.** `if / else if / else if / else` (4) is flagged and `if / else if / else` (3) isn't?
5. **Header repeats.** A `.c` including a bad header: confirm the repeated lines and their paths.
6. **File-level messages.** Trigger C-O4 with a bad file name: are there line and column numbers?
7. **Grader-only rules.** Confirm Banana prints nothing for C-G9, C-A1, C-A2 and C-A4 violations.
8. **Makefiles.** Does anything in Banana check Makefiles (header, columns, tab width, backslash continuations)? If nothing does, `makefile.tab_width` stays a conservative 8 and generated Makefiles keep avoiding backslashes anyway.

---

## 11. README updates

Per feature: what it does, its commands and keys, its config keys, and its requirements (epiclang for live diagnostics and the check; git for the static hint, the check and the hook; clangd for call sites in §9.15; Trouble optional). Keep the existing install spec working and add the blink.cmp snippet spec (§9.20) and a lualine example for the file budget.

---

## 12. Definition of done (every feature)

- [ ] Code in its module, wired through `config` and `setup()` without overriding the user's commands or keys
- [ ] Works without the optional plugins
- [ ] Tests added to `test/run`, passing without epiclang; gated tests wherever Banana's behaviour matters
- [ ] Generated C passes `format_buffer()` unchanged
- [ ] README section
- [ ] One conventional commit

---

## 13. Already done

- **`#pragma once` is no longer treated as an include guard.** `has_guard()` used to count it as one, so `:EpitechGuard` said "already has an include guard" on files using a construct the coding style lists as unsupported. Now `:EpitechGuard` removes `#pragma once` and wraps the file in `#ifndef`/`#define`/`#endif`, or only removes it when a real guard already exists, with a notification either way. Covered by three cases in `test/nvim.lua` and a "pragma once" case in `test/format-guard.lua`. Commit `fix: replace #pragma once instead of treating it as an include guard`.
- **§8.0.1 The formatter lives in `lua/epitech/format.lua`.** It requires nothing (a test in `test/nvim.lua` greps for `require`), exports `path`, `style_file` and `indent_preprocessor`, and `format_buffer(buf)` formats any buffer (current by default). `formatter()` runs `dofile` on it; `init.lua` re-exports `format_buffer` and `format_stdout` and may now require modules. Commit `refactor: move the formatter to lua/epitech/format.lua`.
- **§8.0.2 Headers and guards live in `lua/epitech/header.lua`.** It exports `comment_styles`, `header_lines`, `existing_header(lines)` (returns start row, style, project, description), `has_header(buf)`, `has_guard(lines)`, `insert_header` and `insert_guard`, and reuses `format.indent_preprocessor` for C-G3. `init.lua` re-exports `insert_header` and `insert_guard`. Commit `refactor: move headers and include guards to lua/epitech/header.lua`.
- **§8.0.5 `test/helpers.lua`** (done before §8.0.3 and §8.0.4, whose tests use it). Load it with `dofile(plugin .. "/test/helpers.lua")`. `assert_equal` moved out of `test/nvim.lua`; `temp_project(files)` returns the real path of the root; `with_fake_epiclang(lines, fn)` calls `fn(calls)`, where `calls()` returns the argument lists the fake was run with; `buffer(name, lines)` replaces any buffer with the same name. `test/helpers-check.lua` tests them. `test/run` now exports a temporary `XDG_DATA_HOME`. Commit `test: add shared test helpers`.
- **§8.0.3 `lua/epitech/config.lua`.** `defaults` (§7, plus `header.keymap` and `guard.keymap` so the existing mappings can be moved or disabled like the others), `merge(opts)`, `setup(opts)` and `options`. Lists (`args`, `events`, `allow`, `fail_on`, `verbs`, `vague_files`) replace the default and have their item types checked; `budget.file` and `check.fail_on` take only their listed values; any `keymap` is a string or `false`; `feature = false` is short for `{ enabled = false }`. Unknown keys: dropped, with one `vim.notify` warning listing all of them. Wrong type: `error()` naming the key path. `setup()` in `init.lua` goes through it. Tested in `test/config.lua`. Commit `feat: add setup options with defaults and validation`.
- **§8.0.4 `lua/epitech/project.lua`.** `root(buf_or_path)` (`.git` has priority over a nearer `Makefile`: `vim.fs.root` treats a marker list as a priority order in 0.11), `files(root, pathspecs)` (`git ls-files`, nil outside git), `name(root)` (`NAME` ignoring `$(…)` values and `#` comments, then the Makefile's header, then the first tracked C file's header, then the directory), `include_flags(root, file)` (`compile_commands.json` at the root or in `build/`, cached by mtime; `arguments` or a shell-split `command`; include paths made absolute against the entry's `directory`; a file without an entry, such as a header, uses the first entry), `state_file()`, `state(root)`, `save_state(root, tbl)` and `project_header(root, callback)` (async because of `vim.ui.select`; the choices are the tracked `.h` files plus `include/<name>.h`). Tested in `test/project.lua`. Commit `feat: add project detection and per-project state`.
- **§8.1 `lua/epitech/rules.lua`.** `rules` (42 entries in PDF order, own wording), `by_code`, `extensions`, `severity_rank`. Entries may carry `lang` (`"sh"`, `"text"`) when their examples aren't C. `notes` are all nil: epiclang wasn't available for the §10 calibration in the session that wrote it. Tested in `test/rules.lua` against a hard-coded copy of §5. Commit `feat: add the coding style rules table`.
- **§8.2 `lua/epitech/ts.lua`.** As specified, plus string variants for files that aren't open (`parse_string`, `collect_functions(root, source)`, `collect_prototypes`, `parse_file(path)` cached by mtime), `describe(node, source)`, `declared_name`, `is_void_param`, `has_storage_class` and `cached(buf, key, compute)`, the per-`changedtick` cache other modules reuse. Each function also carries its `declarator`. `body_lines` (lines strictly between the braces) has a `-- calibrate:` comment. Tested in `test/ts.lua` with `test/fixtures/ts/functions.c`. Commit `feat: add the Treesitter function finder`.
- **§8.3 `lua/epitech/lsp.lua` and `lua/epitech/fixes/init.lua`.** The skeleton, with one change: `terminate()` also calls `dispatchers.on_exit`, otherwise `client:stop(true)` leaves the client in the list forever. A failing fix returns an LSP error instead of an empty menu. `fixes/init.lua` holds `modules` (ids under `fixes/`, appended as each fix lands), `register`, `list`, `actions`, and helpers for fix modules: `range(node)`, `position_range`, `touches(node, range)` (row overlap), `action(title, rule, buf, edits, kind)` and `command_action(…)` (both put `data = { rule = … }` on the action), `apply(buf, edits)`, `indent(buf, row)`. A fix module may set `filetypes` (default `{ "c" }`). `test/helpers.lua` gained `rows`, `code_actions`, `apply_action`, `actions_for` and `check_fix(fix, case, row, title, rule)` (result, idempotence, formatter). Tested in `test/lsp.lua`. Commit `feat: add the epitech language server for code actions`.
- **§9.1 `lua/epitech/banana.lua`.** `ns`, `parse(stderr, file, root)` (file nil keeps every entry; entries are deduplicated on path, position, code and message; `user_data = { path, level }`), `command()`, `available()` (the once-per-session notice), `run(buf, on_done)`, `setup(options)`. After setting diagnostics it calls `require("epitech.hints").refresh(buf)` when that module is loaded, for the dedup. `test/banana.lua` (fake epiclang) and the gated `test/banana-real.lua` with `test/fixtures/banana/bad.c`. `test/run` now has a `run` helper and an epiclang-only gated block. Commit `feat: show Banana's reports as live diagnostics`.
- **§9.2 `lua/epitech/explain.lua`.** `lines(rule, diagnostic)` (header padded to 56 columns, a `› Source: message` line with a diagnostic, the summary wrapped without splitting `inline code`, `notes` as a "Measured:" line, then `✗` and `✓` each followed by a fenced block in the rule's `lang`), `show`, `pick`, `explain(code?)`, `complete`. Any diagnostic whose code is a rule code counts, whatever its source. `:EpitechExplain [code]`, `:EpitechRules`, `explain.keymap`. Tested in `test/explain.lua`. Commit `feat: explain coding style rules in a float`.
- **§9.3 `lua/epitech/budget.lua`, function budget.** `ns`, `highlights()` (the §7 groups, `default = true`, redefined on `ColorScheme`), `function_chunks(fn, options)`, `update(buf)`, `schedule(buf)` (150 ms timer per buffer), `setup`. A variadic whose `...` would be one parameter too many gets the warning color (`-- calibrate:`). `test/budget.lua` with `test/fixtures/budget/functions.c`. The gated `test/calibrate.lua` measures §10 items 1 (C-F4 with statements, declarations plus blank line, a continuation line, a comment line, at 20 and 21 lines) and 2 (C-F5 with `...`), printing Banana's verdict next to the plugin's and failing on disagreement. Commit `feat: show each function's line and parameter budget`.
- **§9.4 File budget in `budget.lua`.** `file_counts(buf)`, `file_text(buf)` (re-exported as `require("epitech").file_budget()`), `winbar()` (cached with `ts.cached(buf, "winbar", …)`), `WINBAR`, `update_winbar(win)` on `BufWinEnter`, `WinEnter` and `FileType`. The plugin owns a winbar only while `vim.w.epitech_winbar` is set and the value is still `WINBAR`; it sets it with `nvim_set_option_value(…, { scope = "local" })` because `vim.wo[win].winbar = …` would also set the global value. Window-local options are remembered per buffer, which the tests account for. Commit `feat: show the file budget in the winbar`.
- **§9.5 Depth meter in `budget.lua`.** `depth_ns`, `branches(if_node)`, `depths(body)` (entries `{ node, depth, else_if, branches }`), `depth_chunks(entry, options)` (depth `max_depth - 1` in the warning color, from `max_depth` in the error color with `✗ C-C1`), labels on one row joined with ` · `. `switch` counts as a level (`-- calibrate:`). `test/calibrate.lua` now also covers §10 items 3 and 4 (the table's rows, `switch`/`case`, `do while`, a plain `else { if }`, 3 and 4 branches). Commit `feat: show nesting depth and branch counts`.
- **§9.6 Hint runner and magic numbers.** `hints/init.lua`: `ns`, `modules` (ids under `hints/`, each `{ id, enabled(options), run(src, path, ctx) }`), `collect(src, path, ctx)` (ctx: `root`, optional `options`, `tree`, `buf`; adds severity and source), `dedup(hints, banana)` (keeps `user_data.keep`), `refresh(buf)` (uses the buffer's own tree), `schedule`, `toggle`, `is_active`, `setup`; `:EpitechHints [on|off]`. `fixes/init.lua` gained `hints(src, path, ctx)` for fix modules' optional `hints` (explanations of refused fixes, marked `keep`) and now loads `modules` even after a manual `register`. `hints/magic.lua`: `value(text)`, `literals(tree, source, allow)`; Treesitter parses `-5` as one `number_literal`, so negative literals are reported whole. `fixes/macro.lua` (command `epitech.macro`): `suggest`, `existing`, `insert_define` (a negative value gets parentheses), `extract`. New shared helpers: `util.lua` (`normalize`, `loaded_buffer`, `edit_file`, `read_lines`, `relative`, `ensure_include`, `notify`), `header.guard_name`, `header.guard_rows`, `header.new_header`, `project.include_name`. Tested in `test/magic.lua` with `test/fixtures/hints/magic.c`. Commit `feat: hint at magic numbers and extract them into macros`.
- **§9.7 `hints/static.lua` and `fixes/static.lua`.** One `git grep -o -w -F --untracked -e … -- '*.c'` for all candidates; `used_elsewhere(root, path, names, on_done?)` (synchronous without `on_done`, for the check), `search(buf, root, on_done)` on `BufWritePost`/`BufEnter`, `cache` per file holding the tick of the last search (the set stays usable while editing), `cached_used(buf)`, `candidates`. The runner passes `ctx.static_used`. Deviation from the spec, for ground rule 7: a static definition after a non-static prototype doesn't compile, so **Add static** also makes the file's own prototypes static and is only offered when no header declares the function; with a header prototype the only action is **Add static and remove the prototype from …** (when nothing uses the function before its definition), else nothing. `ts.header_prototypes(root)` added. Tested in `test/static.lua`. Commit `feat: hint at functions that could be static`.
- **§9.8 `hints/types.lua` and `fixes/const.lua`.** C-A1 classifies every use of the parameter and stays quiet when one is unclear. Beyond the spec's list: struct members read through the pointer are only safe in comparisons and arithmetic (a member could be an array that decays into a non-const pointer when copied out or passed on), `&p[i]` and `&p->f` are unclear, and a built-in table (`const_params`) covers the libc functions whose pointer parameters are const (`write` at 2, `strlen` at 1…); other callees are looked up in the file's prototypes and definitions and the project's headers. `const_text(param, source)` writes `T const *name`. The fix is `fixes/const.lua` (spec map had no file for it). `test/calibrate.lua` covers §10 item 7. Tested in `test/types.lua` with `test/fixtures/hints/types.c`. Commit `feat: hint at const pointers and size_t lengths`.
- **§9.9 `hints/naming.lua`.** `verbs`, `vague_files`, `classics` (the lib/my names, plus `main`), `has_verb`, `is_upper_snake` (leading underscores allowed, for `_GNU_SOURCE`), `upper_snake`. The verb suggestion is `get_<name>` and only shown for functions returning a value. Typedef suggestions drop a trailing `_s`/`_e`. A global constant is a top-level declaration whose object is const (`const int MAX = 4;`, not `const char *name;`). Tested in `test/naming.lua` with `test/fixtures/hints/naming.c`. Commit `feat: coach function, file, typedef and macro names`.
- **§9.10 `hints/makefile.lua` and `fixes/makefile.lua`.** The Makefile module has its own runner (`ns`, `refresh`, `schedule`, `setup`; not in `hints.modules`) and a pure `run(src, path, ctx)` on the text as on disk; `buffer_text(buf)` rebuilds that from `fileformat`, `eol` and `fixeol`. `width(line, tab_width)`. `header.existing_header` now accepts `###` inner lines and returns the canonical make style. The split keeps the original operator on its first line (so `SRC = …` still resets an earlier value) and refuses values with `$`, `(` or `)`. The header action runs `insert_header` in the buffer (command `epitech.makefile_header`). `test/calibrate.lua` now covers §10 items 5, 6 and 8 too, so it's complete. Tested in `test/makefile.lua`. Commit `feat: check Makefiles against the coding style`.
- **§9.11 `fixes/void.lua` and `:EpitechFixAll`.** `edits(tree, source)` skips function pointers and function typedefs (only `function_declarator`s naming an identifier): `(void)` would change which functions they accept. `fixes/init.lua` gained `fix_all(code, root)` and `fix_all_codes()`; a fix module opts in with `fix_all(buf) -> edits` and `fix_all_noun`. Unmodified loaded buffers are edited but not saved. Tested in `test/void.lua` with `test/fixtures/fixes/void/`. Commit `feat: add (void) to empty parameter lists`.
- **§9.12 `fixes/decl.lua`.** `plan(fn, source)` (nil, `{ refused = { node, reason } }` or `{ leading, moved, indent }`), `edits(fn, plan, source)`, `actions`, `hints`. Refusals beyond the spec's three: any `initializer_list`, a `static` with an initializer (runs once), `extern`, a variable-length array (size not a number, `sizeof` or an UPPER_SNAKE macro), a comment between the leading declarations, and a moved name already declared anywhere in the function (parameters included). The blank lines right after a moved declaration go with it (C-L6 allows only the top one). Tested in `test/decl.lua` with `test/fixtures/fixes/decl/`. Commit `feat: move declarations to the top of functions`.
- **§9.13 `fixes/one_stmt.lua`.** `findings(tree, source)` returns `{ node, title, edits }` or `{ node, refused }` per statement; actions and hints come from it. Chain targets must be side-effect free (`pure`), since the second form reads them again. Updates are written back postfix (`x = ++i;` gives `i++;` then `x = i;`). The `&&` form drops one pair of parentheses around its left side. Any assignment operator can leave an `if` condition, not just `=`. An update on the right of `&&`/`||` or in a ternary branch isn't moved (silently: the `&&`-to-`if` action covers it). Tested in `test/one_stmt.lua` with `test/fixtures/fixes/one_stmt/`. Commit `feat: split lines holding several statements`.
- **§9.14 `fixes/switch.lua`.** `plan(if_node, depth, source)` and `plans(tree, source)`, using `budget.depths` and the `budget` limits to decide what counts as a C-C1 problem. Beyond the spec: duplicate constants (compared by value for numbers) and a declaration in a branch (illegal after a case label before C23) refuse too; the refusal hints only cover chains whose conditions are otherwise eligible. Action kind `refactor.rewrite`. Tested in `test/switch.lua` with `test/fixtures/fixes/switch/`. Commit `feat: convert long if chains to switch`.
- **§9.15 `fixes/struct_ptr.lua`.** Command `epitech.struct_ptr` (args: uri, signature row, parameter index). Deviation for ground rule 7: the spec's `T *x` for a function that writes to its copy would make those writes reach the caller, so such functions (and ones taking `&x`, calling themselves, or declaring another `x`) get a hint, and the parameter is always `T const *x`. A dereference argument `f(*p)` becomes `f(p)` instead of `f(&*p)`. `struct_typedefs(root, tree, source)` caches each header's typedefs by its text. clangd's references are converted from its position encoding; any clangd failure falls back to `git grep -l -w -F --untracked`. Tested in `test/struct_ptr.lua` (the git grep path; no clangd in the test environment). Commit `feat: pass structs by pointer`.
- **§9.16 `lua/epitech/header_sync.lua`.** `BEGIN`, `END`, `prototype(fn, source)`, `collect(root, dirs)`, `block(groups, group_by_file)`, `update(buf, groups, group_by_file)` (returns counts, or nil and a reason when there's no guard), `summary`, `run(root, on_done)`. Directories are saved as `header_dirs` in the project state. Prototypes are compared with all whitespace removed, so a prototype the formatter wrapped still counts as unchanged; prototypes adopted from elsewhere in the header count as existing. A second run with nothing to do doesn't touch the file. Files under the directories are found with `git ls-files dir/*.c` and read from loaded buffers when open. Tested in `test/header_sync.lua`. Commit `feat: sync the project header's prototypes`.
- **§9.17 `fixes/move_header.lua`.** `items(tree, source)` (top-level only), `target(root, file)` (include/<basename>.h, else the remembered header, else asked at run time, which the title says), `insert(path, lines)`, `move(buf, row, path)`, `static_edits(tree, buf, item)` (or **Remove the static prototype** when the definition already comes first). The C-H1 hint comes from the fix module's `hints` with `user_data.keep = false`, so it's deduplicated against Banana like any guess; `fixes.hints` now only defaults `keep` to true. A directive's node ends at column 0 of the next row, which the row helpers account for. Global variables (C-G4) are not touched. Tested in `test/move_header.lua`. Commit `feat: move header content out of .c files`.
- **§9.18 `lua/epitech/scaffold.lua` and `lua/epitech/makefile.lua`.** `scaffold.templates(name)`, `new(name, dir, force)` (also remembers `include/<name>.h` and `{ "src" }` as the project header and its directories), `new_file(path, root, on_done)`. `main.c` and the test include the project header. The `.gitignore` writes `\#*#`: a line starting with `#` is a comment in `.gitignore`. `makefile.add_source(root, path, variable)` / `remove_source(root, path, variable)` (variable defaults to `SRC`; `:EpitechNewFile` uses `TESTS_SRC` under `tests/` when the Makefile has it); `remove_source` rebuilds continued lists so no dangling backslash is left. Tested in `test/scaffold.lua`. Commit `feat: scaffold projects and source files`.
- **§9.19 `lua/epitech/split.lua`.** `plan(buf, first, last)` (moved functions in file order, `shared` statics that must lose `static`, the moved functions' static prototypes) and `move_to(path, first, last, buf, on_done)`. A static helper follows when every function mentioning it moves (repeated until stable); a moved static function still used by the source is shared too. Function comments move with their function. `project.files(root, pathspecs, { untracked = true })` now exists, and header sync uses it so files created by the plugin count before `git add`. Tested in `test/split.lua`. Commit `feat: move functions to another file`.
- **§9.20 `snippets/` and `snippets_dir()`.** Every placeholder that ends up alone on a line has a default (`${5:return 0;}`, `${3:break;}`), because an empty indented line wouldn't survive the formatter; `$0` sits after the last `}`. `test/snippet_expand.lua` expands them and wraps the body snippets in a function; `test/snippets.lua` checks the JSON, the manifest, `vim.snippet.expand` (same text as the defaults) and the formatter; the gated `test/snippets-real.lua` checks Banana says nothing on the snippet lines. Commit `feat: add Epitech snippets`.
- **§9.21 `lua/epitech/check.lua` and `scripts/check.lua`.** `run(root, on_done)` (result: `entries` `{ path, lnum, col, level, code, message }` with 1-based positions and the code prefix stripped from messages, `counts`, `title`, `banana`), `repository(files)`, `unwanted_pattern`, `sort`, `title`, `format_entry`, `failures`, `open`, `untrack`. Beyond the spec: tracked Makefiles get the §9.10 checks at each rule's own severity; hints are read from disk like Banana and deduplicated against its entries; Banana entries outside the root are dropped. `scripts/check.lua` takes `--ci`, `--hook` (the push-stopped message for §9.22) and a root. `.gitignore` gets `\\#*#` for the `#*#` pattern. `test/run` now syntax-checks `scripts/` too. Tested in `test/check.lua` (fake epiclang, the script through `vim.system`). Commit `feat: check the whole project`.
- **§9.22 `lua/epitech/hooks.lua`.** `MARKER`, `script_path`, `hooks_dir` (`git rev-parse --git-path hooks`), `content(chain)`, `install(root, on_done)`, `remove(root)`, `stale(root)`, `check_stale()` (deferred from `setup()`, warns once), `lazygit_version`, `lazygit_yaml(version)`, `show_lazygit()` (a float). Chaining renames the existing hook to `pre-push.local`, which runs first with the same arguments and stdin; `remove` puts it back. The hook passes `--hook` to the check script for the push-stopped message. lazygit replaced `subprocess`/`stream`/`showOutput` with `output` in 0.51.0 (PR #4525), so older versions get `subprocess: true`. Tested in `test/hooks.lua` (the hook really runs, with the fake epiclang). Commit `feat: guard pushes with a pre-push hook`.
- **Caches for the hint runner.** `project.files` caches tracked-file lists until `.git/index` changes (never with `untracked`) and sorts its result; `ts.header_prototypes` parses each header text once. Hints run on every pause in typing, so these keep `git` and header parsing out of the loop. Commit `perf: cache file lists and header parses for hints`.
- **README reorganized** once every feature was in: intro, install and requirements (git, epiclang and the optional clangd, Trouble, blink.cmp/LuaSnip), a commands table, one section per feature in the order a user meets them, the full `setup()` defaults, highlight groups and namespaces. Commit `docs: reorganize the README around the finished features`.
- **Neovim 0.12 fixes** (§6.6): C-O1 patterns matched without `vim.glob`, and `project.files` returns nil for a missing root. Found by the first full run on Elliot's machine (Neovim 0.12.5, clang-format 22.1.8). Commit `fix: keep the project check working on Neovim 0.12`.
- **Type snippets checked in a header.** `test/snippets-real.lua` expanded `tdef` and `tenum` in a `.c` file, where Banana rightly reports C-H1 (typedefs belong in headers); they're now checked in a `.h` with an include guard. Commit `test: check the type snippets against Banana in a header`.
- **§10 calibration done** on Elliot's machine (results in §10 and §6.1, notes in `rules.lua` for C-O4, C-G9, C-F3, C-F4, C-F5, C-C1, C-A1, C-A2, C-A4). The only code change it called for: the function meter counts a variadic `...` as a parameter (`5/4 args (…)` in the error color). The `-- calibrate:` guesses in `ts.lua` and `budget.lua` became comments citing the measurement. `test/calibrate.lua` now pins C-F5 both ways, C-O4 not being reported, the 4-column tab and the Makefile being read as C. Commit `feat: calibrate the meters against the real epiclang`.
- **C-A1 false positive on `va_list *args` fixed** (Elliot's report: `va_arg(*args, int)` got the hint, but `va_list` is an array type, so `*args` decays into a pointer to his data, and `va_arg` writes through it). A dereference used as a value now only counts as a copy when the pointee is a primitive, a struct/union/enum, or a project typedef of one; `va_arg`, `va_start`, `va_end` and `va_copy` count as writes. The typedef scan moved from `fixes/struct_ptr.lua` to `ts.typedefs(root, tree, source)` (`{ [name] = "struct" | "union" | "enum" | "scalar" | "other" }`, aliases resolved, unknown names such as `va_list` are `other`); `struct_ptr.struct_typedefs` filters it. Tested in `test/types.lua`. Commit `fix: don't suggest const when a dereference may be an array`.
- **C-L1 splits keep brace-less bodies together.** `while (*src) *dest++ = *src++;` used to become three lines, two of them outside the loop. `replace_statement` now wraps the lines in braces when the statement is the body of an `if`, `else`, `while`, `for` or `do` without braces (from the end of the header to the `else` or `do`'s `while`), and gives up when a comment is in the way or the parent is a label. `(a = b) && f();` keeps the assignment's parentheses: `if ((a = b))`. Fixtures `loop_body`, `if_body`, `else_body`, `do_body`, `if_assign_body`, `and_assign` in `test/fixtures/fixes/one_stmt/`. Commit `fix: keep split statements inside brace-less bodies`.
- **C-A4 only for functions their file uses.** A function nothing calls got `only used in this file`, and **Add static** then gave `-Wunused-function` (an error with `-Werror`). `static.used_here(tree, source, fns)` counts any mention outside the function's own definition (recursion isn't a use) and its prototypes; `static.local_only(tree, source, used)` is what the hint and the fix offer. Tested in `test/static.lua`. Commit `fix: don't suggest static for functions nothing uses`.
- **No C-A1 or C-F7 change on functions stored as function pointers.** my_printf-style tables (`{'s', print_str}`) fix a function's parameter types: `const` or a pointer parameter made the table's initializer an incompatible pointer type, an error since GCC 14. `ts.value_names(node, source)` (identifiers neither called nor declared), `ts.project_value_names(root, except)` (tracked `.c` and `.h` files, cached with `parse_file`) and `ts.pointer_uses(root, path, tree, source)` (a predicate; other files only for non-static functions). C-A1 skips those functions silently; C-F7 refuses with a hint. `types.const_candidates` takes the file's path as a fourth argument. Tested in `test/types.lua` and `test/struct_ptr.lua`. Commit `fix: leave functions stored as function pointers alone`.
- **Fewer obvious magic numbers.** `if (ac != 2)`, `nb % 10` and `len / 2` lit up in every project. `magic.literals` now skips a number compared with `ac`/`argc`, used as an index of `av`/`argv`, 2 or 10 as either operand of `*` (`*=`) or the right one of `/` and `%` (`/=`, `%=`), and the whole initializer of a `const` local. The allow list (§7) is unchanged. Tested in `test/magic.lua`. Commit `fix: don't flag argument counts, halving and decimal digits as magic`.
- **More verbs for C-F2.** `dispatch`, `skip_spaces` and `shell_loop` got `no verb → get_dispatch?`. `naming.verbs` gained about 120 verbs from student projects, leaving out words that start common nouns (`play`, `win`, `map`, `link`, `hash`, `hit`, `use`, `pad`, `score`…), since `has_verb` matches prefixes. `has_verb` also accepts a conversion, a `to` word between two others (`str_to_int`). Tested in `test/naming.lua`. Commit `fix: know more verbs in function names`.
- **No errors without git or with a missing directory.** `vim.system` throws when the program or the working directory doesn't exist, so a new file in a directory not created yet (or a machine without git) raised an error on every pause in typing. `util.system(cmd, opts, on_exit)` turns that into a failed run (`code = -1`); `project.files`, the static search, `hooks.hooks_dir`, struct_ptr's `git grep` and `check.untrack` use it. A failed `git grep` (anything but exit 0 or 1) now means nothing is known: before, outside a repository, every function a file used got the C-A4 hint. Tested in `test/static.lua`. Commit `fix: stay quiet when git or the directory is missing`.
- **Extract to a function (`fixes/extract.lua`)**, asked for by Elliot (it was in §14). clangd's "Extract to function" is C++ only (checked with clangd 22.1.1: offered on a `.cpp`, nothing on the same `.c`). The code action **Extract to a function… (C-F4)** (kind `refactor.extract`, only for a real selection, not the cursor alone) and `:'<,'>EpitechExtract [name]` run `extract(buf, first, last, name?)`: `plan(buf, first, last)` (nil when the rows aren't statements of a function body, `{ refused = reason }`, or the plan), `check_name`, `texts(plan, name)`, `apply`. The selection snaps to the statements of the deepest block (compound statement or case) its rows fall in. Variables resolve to their innermost declaration in scope; each one declared outside the selection is moved (declared at the top, single declarator, literal or no initializer, used nowhere else, no loop around the selection), passed as a pointer (array), by pointer (struct or union by type, `.` applied to it, address taken, or written and read afterwards, where a loop around the selection counts as afterwards; uses become `*x`, `(*x)` before a postfix, `x->f`, `&x` becomes `x`), or by value. A selection reaching the end of the function keeps its returns (`return name(…);`, the outer return type). Refused, with the reason as the action's title and a notification: an earlier `return`, a `break`/`continue` leaving the selection, `goto` and labels, preprocessor lines, a variable declared inside and used after, two variables with one name, more than 4 parameters, part of the top declarations, `sizeof`/`&` on an array, multi-dimensional arrays, a `register` variable needing a pointer, an unnamed struct type, statements sharing a line with other code. The new function and, past 79 columns, the call go through `format_buffer` on a scratch buffer (the call inside as many bare blocks as it's deep). Neovim 0.11 ignores an action's `disabled` field, hence the refusal titles. Tested in `test/extract.lua` with `test/fixtures/fixes/extract/`. Commit `feat: extract statements into a new function`.
- **`:EpitechLazygit` edits lazygit's config** (Elliot asked for it instead of a float to copy from). `hooks.lazygit_config()` (first file of `$LG_CONFIG_FILE`, else `lazygit --print-config-dir`, else `$XDG_CONFIG_HOME/lazygit`), `LAZYGIT_MARKER` (a comment above the entry), `lazygit_add(lines, version)` (appends a `customCommands:` block, turns `customCommands: []` into one, or puts the entry first in an existing list with its indentation; an existing entry is replaced in place; nil and a reason when another command uses `B` or the list is inline), `lazygit_remove(lines)` (also drops a `customCommands:` left empty), `lazygit(remove)` (writes `config.yml.bak` first). `show_lazygit` is gone. Tested in `test/hooks.lua`. Commit `feat: add the check to lazygit's config`.
- **Elliot's Makefile template for `:EpitechNew`** (replaces the §9.18 template, which he found odd): `CC = epiclang` (`scaffold.cc`), `CPPFLAGS = -I./include`, an optional `CFLAGS` line (`scaffold.cflags`, now empty by default), `SRC = … \\` and `TEST_SRC = … \\` lists with two-tab continuation lines, `unit_tests` (coverage, Criterion) and `tests_run` (runs them, `fclean`, keeps the exit code), `clean` removing `.gcno`/`.gcda`, `re: fclean $(NAME)`. `scaffold.makefile(name, sources, tests)` and `scaffold.base(name)`: a `lib<x>.a` name builds with `ar rc` and links the tests with `-L. -l<x>`, with `include/<x>.h`, `src/<x>.c` and `tests/test_<x>.c`. Backslash continuations in Makefiles are fine (Banana doesn't read Makefiles, §10), so `makefile.add_source` now adds a line to a continued list in its indentation (a single `SRC += x` line still gets another one), `:EpitechNewFile` uses `TEST_SRC` or `TESTS_SRC`, and the Makefile split fix is only offered when a line is over 80 columns. Tested in `test/scaffold.lua` and `test/makefile.lua`. Commit `feat: use Elliot's Makefile template for new projects`.
- **New projects include their header through `include/`**: `src/main.c`, a library's `src/<x>.c` and `tests/test_<x>.c` write `#include "../include/<x>.h"` (Elliot's choice; it resolves from the file's own directory, with or without `-I`). Commit `feat: include the project header through include/ in new projects`.
- **`<leader>cN` creates a file** (`scaffold.keymap`): `scaffold.new_file()` without a path asks for it with `vim.ui.input` (`New file: `, empty), then for the description as before; `:EpitechNewFile` takes its path as optional. Tested in `test/scaffold.lua`. Commit `feat: add <leader>cN to create a source file`.
- **Header sync without markers** (Elliot didn't want plugin comments in his headers). `header_sync.update(buf, groups, owned)` returns the counts and the new owned set: a prototype of a wanted function is rewritten in place (a later duplicate is deleted), new ones go after the last synced prototype (or before `#endif` with a blank line around them), and a prototype is removed only when its name is in `owned`, the names the sync wrote or adopted on earlier runs, saved as `header_synced` in the project state. A hand-written prototype for a function that doesn't exist yet is never removed. Headers with the old `BEGIN`/`END` markers lose them (and their `/* file.c */` lines) on the next sync, their prototypes counting as owned. `header_sync.group_by_file` and `block()` are gone; `:EpitechNew` writes no markers; `move_header.insert` puts types before the header's first prototype. Supersedes the marker block of §9.16. Tested in `test/header_sync.lua`, `test/move_header.lua`, `test/scaffold.lua`. Commit `feat: sync header prototypes without markers`.
- **`:EpitechNew` writes `int main(void)`** (Elliot: unused `ac`/`av` don't belong in a fresh main; the `main` snippet keeps them for programs that read arguments). Commit `fix: start new projects with int main(void)`.

---

## 14. Not in scope

Considered and not picked: a habit tracker for broken rules, a guard for the other unsupported syntax (`__attribute__`, `\e`, `#if` in `.c` files), a fix that moves comments out of functions, a forbidden-functions checker, Valgrind results in quickfix, a Criterion test runner and a review by a local model. Don't build them unless Elliot asks.

---

## Appendix: dumping a Treesitter tree

Use this to confirm a node shape before writing a query (`nvim --clean --headless -l dump.lua file.c`):

```lua
local src = table.concat(vim.fn.readfile(arg[1]), "\n")
local root = vim.treesitter.get_string_parser(src, "c"):parse()[1]:root()

local function walk(node, depth)
  if node:named() then
    local row = node:range()
    local leaf = node:named_child_count() == 0
      and " " .. vim.treesitter.get_node_text(node, src):gsub("\n", "\\n")
      or ""
    print(string.rep("  ", depth) .. node:type() .. " [" .. (row + 1) .. "]" .. leaf)
  end
  for child in node:iter_children() do
    walk(child, depth + (node:named() and 1 or 0))
  end
end

walk(root, 0)
```
