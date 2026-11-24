# Install the tools

The extension works on its own, but two programs make it complete:

| Program | For | Check |
|---|---|---|
| **clang-format 21+** | formatting C files | `clang-format --version` |
| **epiclang** (Banana) | the coding style reports | `epiclang --version` |
| git | the project check, the static hint | `git --version` |
| gcovr | test coverage (optional) | `gcovr --version` |

**Arch or Ubuntu:** one command installs everything, this extension included,
and updates it every week:

```sh
bash <(curl -fsSL https://raw.githubusercontent.com/cempack/epitech-toolkit/main/install.sh)
```

**Elsewhere:** `pipx install clang-format` gives a recent clang-format;
epiclang comes from Epitech's own dump. If clang-format isn't on VS Code's
`PATH`, set **Epitech › Format: Clang Format** to its full path.
