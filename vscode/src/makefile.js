// Checks for Makefiles, which the coding style covers too: the header
// (C-G1), 80 columns (C-F3), line endings (C-G6), trailing spaces (C-G7),
// leading and trailing empty lines (C-G8) and the final newline (C-A3). Not
// guesses: each uses its rule's own level. A port of
// lua/epitech/hints/makefile.lua.
"use strict";

const { existingHeader } = require("./header");

// The visible width of a line, tabs expanded to tab_width-column stops.
function width(line, tabWidth = 8) {
  let result = 0;
  for (const char of line) {
    result += char === "\t" ? tabWidth - (result % tabWidth) : 1;
  }
  return result;
}

const entry = (line, column, endColumn, level, code, message) =>
  ({ line, column, endLine: line, endColumn, level, code, message: `${code} ${message}` });

// The entries for a Makefile's text as on disk. level is "major", "minor"
// or "info".
function check(text, tabWidth = 8) {
  const finalNewline = text === "" || text.endsWith("\n");
  const lines = text === "" ? [] : (finalNewline ? text.slice(0, -1) : text).split("\n");
  const result = [];
  if (!existingHeader(lines.slice(0, 8).map((line) => line.replace(/\r$/, "")))) {
    result.push(entry(0, 0, 0, "minor", "C-G1", "missing Epitech header"));
  }
  lines.forEach((raw, row) => {
    let line = raw;
    if (line.includes("\r")) {
      result.push(entry(row, line.length - 1, line.length, "minor", "C-G6", "\\r line ending"));
      line = line.replace(/\r/g, "");
    }
    const columns = width(line, tabWidth);
    if (columns + 1 > 80) {
      result.push(entry(row, 0, line.length, "major", "C-F3", `${columns + 1}/80 columns`));
    }
    const trailing = line.search(/\s+$/);
    if (trailing >= 0) {
      result.push(entry(row, trailing, line.length, "minor", "C-G7", "trailing whitespace"));
    }
  });
  if (lines.length > 1 && /^\s*$/.test(lines[0])) {
    result.push(entry(0, 0, 0, "minor", "C-G8", "empty line at the start of the file"));
  }
  let last = lines.length;
  while (last > 0 && lines[last - 1] === "") {
    last--;
  }
  if (lines.length - last > 1) {
    result.push(entry(last + 1, 0, 0, "minor", "C-G8", "more than one empty line at the end of the file"));
  }
  if (!finalNewline) {
    const end = lines[lines.length - 1].length;
    result.push(entry(lines.length - 1, end, end, "info", "C-A3", "no newline at the end of the file"));
  }
  return result;
}

module.exports = { width, check };
