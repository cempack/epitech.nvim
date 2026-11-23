// The C parser: Treesitter's C grammar compiled to WebAssembly, the same
// grammar Neovim bundles, so the formatter and the meters see the trees the
// Lua code sees. init() once (async), then parse() synchronously.
"use strict";

const fs = require("fs");
const path = require("path");

let TreeSitter;
let instance;

// The packaged extension carries the files in vendor/ (scripts/vendor.js);
// a checkout runs them from node_modules.
function locate(name, packageName) {
  const vendored = path.join(__dirname, "..", "vendor", name);
  if (fs.existsSync(vendored)) {
    return vendored;
  }
  return path.join(__dirname, "..", "node_modules", packageName, name);
}

function runtime() {
  const vendored = path.join(__dirname, "..", "vendor", "tree-sitter.cjs");
  return require(fs.existsSync(vendored) ? vendored : "web-tree-sitter");
}

async function init() {
  if (instance) {
    return instance;
  }
  TreeSitter = runtime();
  const wasm = locate("tree-sitter.wasm", "web-tree-sitter");
  await TreeSitter.Parser.init({ locateFile: () => wasm });
  const language = await TreeSitter.Language.load(locate("tree-sitter-c.wasm", "tree-sitter-c"));
  instance = new TreeSitter.Parser();
  instance.setLanguage(language);
  return instance;
}

function parse(text) {
  if (!instance) {
    throw new Error("the C parser isn't loaded: call parser.init() first");
  }
  return instance.parse(text);
}

module.exports = { init, parse };
