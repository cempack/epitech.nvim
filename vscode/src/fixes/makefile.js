// Makefile fixes: split a SRC assignment with a line over 80 columns into
// one file per line (C-F3), remove trailing spaces (C-G7); the header
// (C-G1) is the Insert Epitech Header command. A port of
// lua/epitech/fixes/makefile.lua.
"use strict";

const { width } = require("../makefile");
const { point } = require("./edits");

function sourceAssignment(lines, row, tabWidth = 8) {
  let first = row;
  while (first > 0 && /\\\s*$/.test(lines[first - 1])) {
    first--;
  }
  const match = lines[first].match(/^([A-Za-z0-9_]*SRC)\s*([:+?]?=)\s*(.*?)\s*$/);
  if (!match) {
    return undefined;
  }
  let last = first;
  const values = [match[3]];
  while (/\\\s*$/.test(values[values.length - 1]) && lines[last + 1] !== undefined) {
    values[values.length - 1] = values[values.length - 1].replace(/\\\s*$/, "");
    last++;
    values.push(lines[last]);
  }
  if (last < row) {
    return undefined;
  }
  const words = [];
  for (const value of values) {
    for (const word of value.replace(/\\\s*$/, "").split(/\s+/).filter(Boolean)) {
      if (/[$()]/.test(word)) {
        return undefined;
      }
      words.push(word);
    }
  }
  let long = false;
  for (let i = first; i <= last; i++) {
    long = long || width(lines[i], tabWidth) + 1 > 80;
  }
  return { first, last, name: match[1], operator: match[2], words, long };
}

const splitLines = (assignment) => assignment.words.map((word, i) =>
  `${assignment.name} ${i === 0 ? assignment.operator : "+="} ${word}`);

function actions(text, range, tabWidth = 8) {
  const lines = text.split("\n");
  const result = [];
  const done = new Set();
  for (let row = range.start; row <= Math.min(range.end, lines.length - 1); row++) {
    const assignment = sourceAssignment(lines, row, tabWidth);
    if (assignment && assignment.long && assignment.words.length > 1 && !done.has(assignment.first)) {
      done.add(assignment.first);
      result.push({ title: `Split into ${assignment.name} += lines (C-F3)`, rule: "C-F3", edits: [{
        start: point(assignment.first, 0), end: point(assignment.last, lines[assignment.last].length),
        newText: splitLines(assignment).join("\n") }] });
    }
    const trailing = lines[row].search(/\s+$/);
    if (trailing >= 0) {
      result.push({ title: "Remove trailing spaces (C-G7)", rule: "C-G7",
        edits: [{ start: point(row, trailing), end: point(row, lines[row].length), newText: "" }] });
    }
  }
  return result;
}

module.exports = { sourceAssignment, splitLines, actions };
