// Text edits shared by the fixes: { start: { line, character }, end,
// newText }, 0-based with UTF-16 columns (VS Code's and web-tree-sitter's
// unit). A port of the helpers in lua/epitech/fixes/init.lua.
"use strict";

const { formatText } = require("../format");

const point = (line, character = 0) => ({ line, character });
const lineEdit = (startLine, endLine, newText) => ({ start: point(startLine), end: point(endLine), newText });
const nodeEdit = (node, newText) => ({
  start: point(node.startPosition.row, node.startPosition.column),
  end: point(node.endPosition.row, node.endPosition.column),
  newText,
});

function offset(lines, position) {
  let result = 0;
  for (let i = 0; i < position.line && i < lines.length; i++) {
    result += lines[i].length + 1;
  }
  return result + position.character;
}

// text with edits applied (they don't overlap).
function apply(text, edits) {
  const lines = text.split("\n");
  const sorted = edits.map((edit) => ({ edit, from: offset(lines, edit.start), to: offset(lines, edit.end) }))
    .sort((a, b) => b.from - a.from || b.to - a.to);
  let result = text;
  for (const { edit, from, to } of sorted) {
    result = result.slice(0, from) + edit.newText + result.slice(to);
  }
  return result;
}

function commonEnds(a, b) {
  let first = 0;
  while (first < a.length && first < b.length && a[first] === b[first]) {
    first++;
  }
  let last = 0;
  while (last < a.length - first && last < b.length - first && a[a.length - 1 - last] === b[b.length - 1 - last]) {
    last++;
  }
  return [first, last];
}

const bytes = (text) => Buffer.byteLength(text, "utf8");

// A fix that pushes a line past 79 columns (C-F3) gets the formatter's
// wrapping, when the formatter changes nothing else (see init.lua).
function wrapped(lines, edits, formatOptions) {
  const after = apply(lines.join("\n"), edits).split("\n");
  const [first, last] = commonEnds(lines, after);
  let long = false;
  for (let row = first; row < after.length - last; row++) {
    long = long || bytes(after[row]) > 79;
  }
  if (!long || !formatOptions) {
    return edits;
  }
  let formatted;
  try {
    formatted = formatText(after.join("\n") + "\n", formatOptions).replace(/\n$/, "").split("\n");
  } catch {
    return edits;
  }
  const [keptFirst, keptLast] = commonEnds(after, formatted);
  if (keptFirst < first || keptLast < last) {
    return edits;
  }
  const middle = formatted.slice(first, formatted.length - last);
  return [lineEdit(first, lines.length - last, middle.length > 0 ? middle.join("\n") + "\n" : "")];
}

module.exports = { point, lineEdit, nodeEdit, apply, wrapped };
