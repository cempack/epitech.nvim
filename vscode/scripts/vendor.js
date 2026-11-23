// Copies what the packaged extension needs and can't reach from a .vsix:
// the parser's runtime and grammar (vendor/) and the files shared with the
// Neovim plugin (data/). Both directories are generated: edit the files at
// the repository root.
"use strict";

const fs = require("fs");
const path = require("path");

const here = path.join(__dirname, "..");
const repo = path.join(here, "..");

function copy(from, to) {
  fs.mkdirSync(path.dirname(to), { recursive: true });
  fs.cpSync(from, to, { recursive: true });
}

fs.rmSync(path.join(here, "vendor"), { recursive: true, force: true });
fs.rmSync(path.join(here, "data"), { recursive: true, force: true });
copy(path.join(here, "node_modules/web-tree-sitter/tree-sitter.cjs"), path.join(here, "vendor/tree-sitter.cjs"));
copy(path.join(here, "node_modules/web-tree-sitter/tree-sitter.wasm"), path.join(here, "vendor/tree-sitter.wasm"));
copy(path.join(here, "node_modules/tree-sitter-c/tree-sitter-c.wasm"), path.join(here, "vendor/tree-sitter-c.wasm"));
// vsce wants a LICENSE next to package.json.
copy(path.join(repo, "LICENSE"), path.join(here, "LICENSE"));
for (const shared of ["shared", "snippets", "templates", "epitech.clang-format"]) {
  copy(path.join(repo, shared), path.join(here, "data", shared));
}
console.log("vendor/ and data/ are ready");
