# epitech.nvim

Neovim support for the Epitech C Coding Style (v7.1), built for LazyVim and
usable with any lazy.nvim setup: a formatter whose output passes Banana
(`epiclang`), live Banana diagnostics, budget meters for function length,
parameters, functions per file and nesting, hints for the rules a grader
checks, code actions that fix violations, Epitech headers and include
guards, and project tools (header sync, scaffolding, a whole-project check
and a pre-push hook).

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
- `epiclang` (Epitech's Banana checker) for live diagnostics, the project
  check and the push guard; everything else works without it
- git, for the "could be static" hint, header sync, the project check and
  the push guard; without git, or outside a repository, those stay quiet
  instead of failing
- optional: clangd (LazyVim's clangd extra) finds call sites for **Pass x by
  pointer** (`git grep` otherwise), Trouble shows the project check (the
  quickfix list otherwise), blink.cmp or LuaSnip load the snippets

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

Formatting only changes layout. Structure and meaning (function length,
parameters, naming, `int f()` instead of `int f(void)`…) are what the
diagnostics, meters, hints and fixes below are for.

| Command or key | What it does |
|---|---|
| `<leader>cf` | Format the buffer (through conform.nvim) |
| `<leader>cH`, `:EpitechHeader` | Insert an Epitech header |
| `<leader>cG`, `:EpitechGuard` | Add an include guard |
| `<leader>cE`, `:EpitechExplain [code]` | Explain the rule under the cursor, or a given one |
| `:EpitechRules` | List the 42 rules |
| `<leader>ca` | Code actions: the fixes below, next to clangd's |
| `:EpitechFixAll C-F6` | Add `(void)` everywhere in the project |
| `:EpitechHints [on\|off]` | Show or hide the hints |
| `:EpitechSyncHeader` | Update the project header's prototypes |
| `:EpitechNew[!] [name]` | Create a project skeleton |
| `<leader>cN`, `:EpitechNewFile [path]` | Create a source file with its header, add it to `SRC` |
| `:'<,'>EpitechExtract [name]` | Move the selected statements into a new function |
| `:'<,'>EpitechMoveTo <path>` | Move the selected functions to another file |
| `<leader>cB`, `:EpitechCheck [untrack]` | Check the whole project (or untrack build files) |
| `:EpitechHooks [remove]` | Install (or remove) the pre-push hook |
| `:EpitechLazygit [remove]` | Add the check to lazygit on `B` (or remove it) |

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
title, its severity, who checks it (🍌 Banana, 👤 a grader), a short summary,
a bad and a good example, and what measuring the real `epiclang` showed about
it when that matters (how C-F4 counts lines, for instance). With several rules on the line, the one under
the cursor wins, else you choose; with none, you pick from the list.
`:EpitechExplain C-F6` explains a given rule, and `:EpitechRules` lists all
42 rules. Change or disable the key with `explain = { keymap = … }`.

### Budget meters

After each function's signature, a meter shows how much of its budget it
uses: `13/20 lines · 2/4 args` (C-F4, C-F5). It's dim below 17 lines, in the
warning color from 17 to 20 and in the error color past 20; the parameter
count turns red past 4. A variadic `...` counts as a parameter, as Banana
counts it: `int f(int a, ...)` shows `2/4 args (…)`. The colors
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
`4 branches ✗ C-C1`. A `switch` and a `do while` count as levels, and an
`else { if }` counts like an `else if`, as Banana counts them.

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

### Hints

Some rules are checked by a grader, not by Banana. For those, the plugin
shows hints (HINT diagnostics with `source = "epitech.nvim"`): guesses, so
read them as questions. A hint disappears when Banana reports the same rule
on the same line. `:EpitechHints off` hides them, `:EpitechHints on` brings
them back, and `:EpitechHints` toggles.

- **Magic numbers** (C-G9): a number inside a function body that isn't 0, 1,
  -1 or 84 (Epitech's error exit code) gets `C-G9 name this number?`.
  Numbers a grader reads as they are get nothing: argument counts and
  positions (`ac != 2`, `av[2]`), 2 and 10 as a factor, divisor or modulus
  (`len / 2`, `nb % 10`), and the value of a `const` variable. The
  code action **Extract 4096 into a macro…** asks for a name (suggesting
  `BUFFER_SIZE` for `char buffer[4096]`), offers the project's existing
  macros with the same value first, and can replace every identical number
  in the file. The `#define` goes in the project header, inside its include
  guard (C-H1), and the file gets the `#include` it needs.

- **Could be static** (C-A4, C-O3): a non-static function, other than
  `main`, that no other `.c` file of the project mentions, and that its own
  file calls or stores somewhere else than in itself, gets
  `C-A4 only used in this file`. A function nothing uses gets no hint:
  made static, it would only trade the hint for an unused-function
  warning. The project is searched with `git grep`
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
  returning it, `va_arg` and the other stdarg macros, or any use it can't
  classify means no hint. Passing `*p` to a function only counts as a copy
  when `p` points to a number, a struct, a union or an enum (or a project
  typedef of one); a type such as `va_list` or `jmp_buf` may be an array,
  which would hand the function a pointer to your data. A function stored
  as a function pointer (`{'s', print_str}`, `&handler`, in its own file or
  any other) gets no hint: the pointer's type sets its parameters, and
  `const` would no longer match it. An `int` set from
  `strlen`, `my_strlen` or `sizeof` gets `C-A2 holds a length → size_t?`
  (no automatic fix: changing a type ripples into comparisons and format
  strings).

- **Naming** (C-F2, C-O4, C-V1): a function name without a verb
  (`C-F2 no verb → get_vowels_number?`, with a suggestion when the function
  returns something), a vague file name such as `utils.c`, a typedef name
  that doesn't end in `_t`, and macros, enum values or global constants that
  aren't UPPER_SNAKE_CASE. A name counts as having a verb when one of its
  words (a leading `my` aside) is a verb or starts with one, like `putstr`,
  or when it's a conversion, `x_to_y` (`str_to_int`); the lib/my classics
  (`my_strlen`, `my_getnbr`…) and `main` are left alone. The built-in list
  covers about 200 verbs (`dispatch`, `skip`, `loop`, `execute`…), leaving
  out those that start common nouns (`play` for `player`, `win` for
  `window`, `map`).
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
for a `SRC` assignment with a line over 80 columns (the first line keeps its
`=`; a list of short `\` lines is fine), and **Remove trailing spaces**.

```lua
makefile = { enabled = true, tab_width = 8 },
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
  `if (!a) { … }`). When the statement is the body of a loop, `if`,
  `else` or `do` written without braces, the new lines get braces, so they
  all stay in that body. A hint explains the cases without a fix: a variable
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
  include guard, before the header's first prototype, with
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
  struct, or the change can't be checked. So does a function stored as a
  function pointer, whose parameters must keep matching the pointer's type.

### Header sync

`:EpitechSyncHeader` updates the project header's prototypes (C-H1) from the
non-static functions of the `.c` files that feed it, and reports
`1 added · 1 changed · 0 removed`. The first time, it asks which header (when
it isn't obvious) and which directories feed it (`src` by default; `lib/`
usually has its own header), and remembers both.

It adds no comments or markers to your header. A prototype whose function
changed is rewritten where it is, and new functions get their prototype
right after your last synced one (at the end of the include guard the first
time). When a function is deleted or renamed, its prototype is removed only
if the sync wrote or updated it before: the plugin remembers those names
outside your repository. A prototype you typed yourself is never deleted,
even for a function that doesn't exist yet. `static` functions and `main`
stay out. An open header is edited in its buffer (so undo works), then
formatted so long prototypes wrap at 80 columns. Headers from earlier
versions lose their `/* epitech.nvim: … */` markers on the next sync.

### New projects and files

`:EpitechNew [name]` creates a project in the current directory (named after
it by default): a `Makefile`, `include/<name>.h` with its guard, `src/main.c`, `tests/test_<name>.c` and a `.gitignore` for
build products. Everything has its Epitech header and passes the formatter.
It refuses when a `Makefile` exists; `:EpitechNew!` overwrites.

The Makefile sets `CC = epiclang` and `CPPFLAGS = -I./include`, lists the
files as `SRC = src/main.c \` with one file per line, and has `all`,
`clean`, `fclean`, `re`, `unit_tests` (built with `--coverage` and
Criterion) and `tests_run` (runs them, then `fclean`, keeping the tests'
exit code). A name ending in `.a` (`:EpitechNew libmy.a`) makes a library
instead: built with `ar rc`, with `include/my.h`, `src/my.c` and tests
linked with `-L. -lmy`.

`<leader>cN` (or `:EpitechNewFile` alone) asks for the path in a small
window. `:EpitechNewFile src/parse_args.c` creates a file with its Epitech header
(asking for the description), adds it to the Makefile and opens it: one more
line of the `SRC = … \` list (`TEST_SRC` for files under `tests/`), or a
`SRC += …` line when the Makefile uses those. A `.h` gets an include guard
instead. When `SRC` is built with `$(wildcard …)` or doesn't exist, the
Makefile is left alone and you're told what to add.

```lua
scaffold = { keymap = "<leader>cN", cc = "epiclang", cflags = "" }, -- cflags: a CFLAGS line when set
```

### Extracting a function

When a function gets too long (C-F4: 20 lines), select some of its
statements in visual mode and pick **Extract to a function…** in the code
actions (`<leader>ca`), or run `:'<,'>EpitechExtract [name]`. You type the
new function's name, and the statements move into a `static` function just
above the current one, with a call where they were. clangd's own "Extract to
function" only works on C++ files.

```c
// before, with the while loop selected
int count_text(char const *str)
{
    int count = 0;
    int i = 0;

    while (str[i] != '\0') {
        count += str[i] == ' ';
        i++;
    }
    return count;
}

// after, named count_spaces
static void count_spaces(char const *str, int *count)
{
    int i = 0;

    while (str[i] != '\0') {
        *count += str[i] == ' ';
        i++;
    }
}

int count_text(char const *str)
{
    int count = 0;

    count_spaces(str, &count);
    return count;
}
```

Each variable the statements use but don't declare is handled so the
program does the same thing:

- **moved** into the new function, with its declaration, when nothing else
  uses it, it's declared at the top with a literal value (or none), and no
  loop around the selection repeats it (`i` above);
- passed **as a pointer** when it's an array;
- passed **by pointer** when it's a struct (C-F7, fields become `p->x`), its
  address is taken, or the statements change it and something reads it
  afterwards (`count` above, `*count += …`); inside a loop, the next turn
  counts as afterwards;
- passed **by value** otherwise.

A selection that runs to the end of the function keeps its `return`s: the
call becomes `return search_word(str, word, len);`. The new function's
signature and the call are wrapped at 80 columns like the formatter does.
When the move would change what the program does, the action's title says
why and nothing happens: a `return` before the end of the function, a
`break` or `continue` leaving the selection, `goto`, preprocessor lines, a
variable declared in the selection and used after it, more than 4
parameters (C-F5), part of the declarations at the top of the function, or
`sizeof` on an array that would become a pointer. The name must be
snake_case and not already taken.

### Splitting a file

Select whole functions in a `.c` file (visual mode), then
`:'<,'>EpitechMoveTo src/print_long.c` (C-O3: at most 10 functions per file).
The functions move to that file, new or existing, with their comments and
the static helpers only they use. A static helper both files would need has
to become non-static, which counts against the 5 non-static functions per
file, so you're asked first. A new file gets its Epitech header (you give
the description) and the source's `#include` lines. Then the file is added
to `SRC` and `:EpitechSyncHeader` updates the project header.

### Snippets

Snippets that follow the style, in VS Code's format under `snippets/`:

| Prefix | Expands to |
|---|---|
| `main` | `int main(int ac, char **av)` returning 0 |
| `fn` | a `/* ** description */` comment above a function taking `(void)` |
| `sfn` | the same, `static` |
| `tdef` | `typedef struct name_s { … } name_t;` |
| `tenum` | `typedef enum name_e { VALUE, } name_t;` |
| `sw` | a `switch` with two cases, `default:` and their `break;` |
| `fori` | `for (int i = 0; i < n; i++) { … }` |
| `ife` | `if` / `else` with braces |
| `mal` | `ptr = malloc(sizeof(char) * (size));` and a `NULL` check returning `NULL` |

With blink.cmp (LazyVim's default completion), add the folder to its snippet
search paths, keeping the default one:

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

### Project check

`<leader>cB` (or `:EpitechCheck`) checks every tracked `.c` and `.h` file
with `epiclang`, runs the hints and the Makefile checks, and adds the
repository rules: compiled or temporary files tracked by git (C-O1),
C sources with another extension such as `.cpp` (C-O2), and file or folder
names that aren't snake_case (C-O4). The result opens in Trouble when it's
installed, else in the quickfix list, sorted by severity, then file, then
line, titled `Epitech check: 0 fatal · 3 major · 5 minor · 2 info · 4 hints`.
A header's problems are listed once, however many files include it.
`:EpitechCheck untrack` runs `git rm --cached` on the C-O1 files and adds
their patterns to `.gitignore`, after asking.

The same check runs without an editor, for CI:

```sh
nvim --clean --headless -l /path/to/epitech.nvim/scripts/check.lua --ci .
```

It prints `path:line:col: [Level] message (CODE)` lines and the summary, and
exits 1 when a level in `check.fail_on` occurs (hints never fail it). It
needs git, and `epiclang` for the Banana part.

```lua
check = { keymap = "<leader>cB", fail_on = { "fatal", "major" } },
```

### Push guard

`:EpitechHooks` installs a git pre-push hook in the current repository. A
`git push`, from the terminal or lazygit, then runs the project check and
stops while a Fatal or Major is left:

```
epitech.nvim: 2 Major left, push stopped. Run :EpitechCheck to see them, or git push --no-verify to skip.
```

The hook lives in `.git/hooks`, which git never tracks. When the repository
already has a pre-push hook, you choose to chain it (it runs first), replace
it, or cancel. `:EpitechHooks remove` deletes the plugin's hook and puts a
chained one back. The hook uses absolute paths to Neovim and the plugin; if
the plugin moves, you're warned once to run `:EpitechHooks` again.

`:EpitechLazygit` adds a custom command to lazygit's `config.yml` (the file
`$LG_CONFIG_FILE` names, else the one in `lazygit --print-config-dir`):
`B` in the files panel runs the check. The rest of the config stays as it
is, and the previous version is kept as `config.yml.bak`. Running it again
updates the entry (after the plugin moved, for example), and
`:EpitechLazygit remove` takes it out. It uses `output: terminal` (lazygit
0.51 and later) or `subprocess: true` for older versions. It changes nothing
when another custom command already uses `B`, or when `customCommands` is
written on a single line.

## Configuration

`require("epitech").setup(opts)` takes an optional table. Every option has a
default, so `setup()` alone is enough. The defaults:

```lua
require("epitech").setup({
  header = { keymap = "<leader>cH" }, -- :EpitechHeader
  guard = { keymap = "<leader>cG" }, -- :EpitechGuard
  diagnostics = {
    enabled = true,
    cmd = "epiclang",
    args = { "-x", "c", "-fsyntax-only" }, -- include flags are added per project
    events = { "BufWritePost", "BufReadPost" },
  },
  explain = { keymap = "<leader>cE" },
  budget = {
    functions = true, -- "13/20 lines · 2/4 args" after each signature
    file = "winbar", -- "winbar", "lualine" (component only) or false
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
  check = { keymap = "<leader>cB", fail_on = { "fatal", "major" } },
  scaffold = { keymap = "<leader>cN", cc = "epiclang", cflags = "" },
})
```

Set a `keymap` to `false` for no mapping. Mappings are only set when their
keys are still free, and commands only when you haven't defined one with the
same name. A feature with an `enabled` key can be turned off with
`feature = false` (`hints = { magic_numbers = false }`). Lists replace the
default list instead of extending it. Unknown options are ignored with a
warning, and an option of the wrong type stops `setup()` with an error
naming it.

Highlight groups, defined as defaults so your colorscheme can override
them: `EpitechBudgetOk` (→ `Comment`), `EpitechBudgetNear`
(→ `DiagnosticWarn`), `EpitechBudgetOver` (→ `DiagnosticError`) and
`EpitechWinbar` (→ `WinBar`). Diagnostic namespaces: `epitech.banana`,
`epitech.hints`, `epitech.makefile`; extmark namespaces: `epitech.budget`,
`epitech.depth`.

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
- `require("epitech").snippets_dir()` is the snippet folder.
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

Tests that need the real `epiclang` are skipped when it is missing: the
formatter tests (which also need `~/.vim/epitech.vim`), a Banana diagnostics
test, a snippet check, and `test/calibrate.lua`, which measures how Banana
counts lines, parameters, depth and branches and fails where the plugin's
meters disagree with it. The rest of the suite uses a stand-in.

The suite runs with a temporary `XDG_DATA_HOME`, so it never touches the
plugin's state in your own data directory. Test scripts share the helpers in
`test/helpers.lua`: `assert_equal`, `temp_project` (a temp git repository
built from a table of files), `with_fake_epiclang` (a stand-in `epiclang` that
prints canned Banana output), `buffer`, and helpers that run code actions
through the real language server.
