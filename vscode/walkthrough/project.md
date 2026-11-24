# Start a project

**Epitech: New Project** asks for a name and the libraries to link (CSFML,
ncurses, math), then writes:

```
Makefile            all clean fclean re unit_tests tests_run debug
include/<name>.h    header, include guard, PROGRAM_NAME, EXIT_ERROR 84
src/main.c          int main(void)
src/print_error.c   error messages on stderr, returning 84
lib/my/             the part of your libmy it uses
tests/test_<name>.c a Criterion test
.gitignore          build products, vgcore, coverage files
```

Call it `libsomething.a` to make a library instead. **Epitech: New Source
File** (or right-click a folder in the Explorer) adds a file with its
header and its line in the Makefile.
