# Fix with the light bulb

Put the cursor on a report and press **Ctrl+.**:

| Rule | Fix |
|---|---|
| C-F6 | `int f()` → `int f(void)` |
| C-L5 | declarations moved to the top of the function, one per line |
| C-L1 | `a = b = 0;`, `s[i++] = c;`, `if ((fd = open(…)) == -1)`, `a && f();` split into one statement per line |
| C-C1 | a long `if` / `else if` chain on one variable → `switch` |
| C-A1 | `char *str` → `char const *str`, in the header too |
| C-A4 | `static` on a function only its file uses |
| C-G9 | a number → a macro in your header |
| C-F3, C-G7 | Makefile: one `SRC +=` per line, trailing spaces |

A fix is only offered when it keeps your program's meaning; otherwise a
hint says why. Every report also has **Explain** in the same menu.
