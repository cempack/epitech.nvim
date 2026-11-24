# Write

- **Saving formats the file** the way Banana wants it: indentation,
  spaces, braces, the blank line after declarations, wrapped lines at the
  depth Banana counts, preprocessor nesting.
- **Banana's reports** appear when you open or save a file. Hover one to
  read the rule with a bad and a good example.
- **Meters** after each function: `13/20 lines · 2/4 args`, yellow at the
  limit, red past it; `depth 2`, `depth 3 ✗ C-C1` on nested blocks; and
  `functions 8/10 · non-static 5/5` in the status bar.
- **Hints** (faint dots) for what only graders check: magic numbers, a
  function only its file uses, a pointer that could be `const`, an `int`
  holding a length, names without a verb.

Snippets: `main`, `fn`, `sfn`, `tdef`, `tenum`, `sw`, `fori`, `ife`, `mal`.
