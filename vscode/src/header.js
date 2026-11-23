// Epitech file headers (C-G1) and include guards (C-H2), as in
// lua/epitech/header.lua. Works on arrays of lines.
"use strict";

const path = require("path");
const data = require("./data");
const { indentPreprocessor, hasHeader } = require("./format");

const styles = data.commentStyles();

// VS Code language ids that differ from Neovim's filetypes.
const LANGUAGES = {
  makefile: "make", shellscript: "sh", dockercompose: "yaml", latex: "tex", "objective-c": "c",
};

function styleFor(languageId) {
  return styles[LANGUAGES[languageId] || languageId];
}

function headerLines(style, project, description, year) {
  return [
    style[0],
    `${style[1]} EPITECH PROJECT, ${year}`,
    `${style[1]} ${project}`,
    `${style[1]} File description:`,
    `${style[1]} ${description}`,
    style[2],
  ];
}

// The PDF's Makefile writes "###" inside where Epitech's Vim config writes "##".
const INNER = { "##": ["##", "###"] };

// { start (0-based), style, project, description } of the header in the
// first two lines, or undefined.
function existingHeader(lines) {
  for (let start = 0; start <= Math.min(1, lines.length - 6); start++) {
    for (const style of Object.values(styles)) {
      let [first, second, third, fourth, fifth, last] = lines.slice(start, start + 6);
      if (style[0] === "/*") {
        [second, third, fourth, fifth, last] = [second, third, fourth, fifth, last].map((line) =>
          line.replace(/^ /, ""));
      }
      if (first !== style[0] || !/EPITECH PROJECT, \d\d\d\d$/.test(second)) {
        continue;
      }
      for (const inner of INNER[style[1]] || [style[1]]) {
        const prefix = inner + " ";
        if (second.startsWith(prefix) && third.startsWith(prefix) && fourth === inner + " File description:"
          && fifth.startsWith(prefix) && last === style[2]) {
          return { start, style, project: third.slice(prefix.length), description: fifth.slice(prefix.length) };
        }
      }
    }
  }
  return undefined;
}

// The lines to insert at `at` (0-based) for a new header in `lines`.
function newHeader(lines, style, project, description, year) {
  const header = headerLines(style, project, description, year);
  let at = 0;
  if (lines[0] && lines[0].startsWith("#!")) {
    at = 1;
  } else if (style[3]) {
    header.unshift(style[3]);
  }
  if (lines[at] !== "") {
    header.push("");
  }
  return { at, lines: header };
}

// my_macro_abs.h gives MY_MACRO_ABS_H_.
function guardName(filename) {
  let guard = path.basename(filename).replace(/[^A-Za-z0-9]/g, "_").toUpperCase() + "_";
  if (!/^[A-Z]/.test(guard)) {
    guard = "HEADER_" + guard;
  }
  return guard;
}

function hasGuard(lines) {
  for (let i = 0; i < Math.min(lines.length, 30); i++) {
    const match = lines[i].match(/^\s*#\s*ifndef\s+([A-Za-z_][A-Za-z0-9_]*)\s*$/);
    if (match) {
      const define = new RegExp(`^\\s*#\\s*define\\s+${match[1]}\\s*$`);
      for (let j = i + 1; j <= Math.min(i + 5, lines.length - 1); j++) {
        if (define.test(lines[j])) {
          return true;
        }
      }
    }
  }
  return false;
}

// The guarded lines of a header, and what was done: "added", "pragma"
// (#pragma once replaced), "pragma-removed" (a guard was there already) or
// "present".
function guard(lines, filename) {
  let current = lines.slice();
  const pragma = current.slice(0, 30).findIndex((line) => /^\s*#\s*pragma\s+once\s*$/.test(line));
  if (pragma >= 0) {
    const last = current[pragma + 1] === "" && (pragma === 0 || current[pragma - 1] === "") ? pragma + 1 : pragma;
    current.splice(pragma, last - pragma + 1);
  }
  if (hasGuard(current)) {
    return { lines: current, result: pragma >= 0 ? "pragma-removed" : "present" };
  }
  const name = guardName(filename);
  let wrapped = [];
  let bodyStart = 0;
  if (hasHeader(current)) {
    wrapped = current.slice(0, 6).concat([""]);
    bodyStart = 6;
  }
  wrapped.push(`#ifndef ${name}`, `#define ${name}`, "");
  const cursor = wrapped.length - 1;
  if (current[bodyStart] === "") {
    bodyStart++;
  }
  wrapped = wrapped.concat(current.slice(bodyStart));
  if (wrapped[wrapped.length - 1] !== "") {
    wrapped.push("");
  }
  wrapped.push("#endif");
  return { lines: indentPreprocessor(wrapped), result: pragma >= 0 ? "pragma" : "added", cursor };
}

// A new header file: the Epitech header, then an empty guard.
function newHeaderFile(file, project, description, year) {
  const name = guardName(file);
  return headerLines(styles.c, project, description, year)
    .concat(["", `#ifndef ${name}`, `    #define ${name}`, "", "#endif"]);
}

module.exports = { styles, styleFor, headerLines, existingHeader, newHeader, guardName, hasGuard, guard, newHeaderFile };
