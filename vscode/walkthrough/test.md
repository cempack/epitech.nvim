# Run the tests

The **Testing** view lists every `Test(suite, name)` of your `tests/`
folder. Run one, a file or all of them: the extension builds them with
`make unit_tests`, runs Criterion and shows each failure at its line.

**Run with Coverage** adds gcovr's line coverage to the editor and the
Explorer. Afterwards `make fclean` removes the build, as `tests_run`
does, so nothing compiled ends up committed.

**Terminal › Run Task…** has `make`, `make re`, `make debug`, `make clean`,
`make fclean` and `make tests_run`, with compiler errors in the Problems
panel.
