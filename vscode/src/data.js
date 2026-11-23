// Where the files shared with the Neovim plugin live: the repository root in
// a checkout (even after scripts/vendor.js made a copy), data/ in the
// packaged extension. Edit them at the repository root, never under data/.
"use strict";

const fs = require("fs");
const path = require("path");

const checkout = path.join(__dirname, "..", "..");
const root = fs.existsSync(path.join(checkout, "shared", "rules.json")) ? checkout : path.join(__dirname, "..", "data");

const file = (...parts) => path.join(root, ...parts);
const json = (...parts) => JSON.parse(fs.readFileSync(file(...parts), "utf8"));

module.exports = {
  root,
  file,
  styleFile: file("epitech.clang-format"),
  rules: () => json("shared", "rules.json"),
  commentStyles: () => json("shared", "comment_styles.json"),
  templatesDir: file("templates"),
};
