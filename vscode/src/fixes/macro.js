// C-G9: extract a number into a macro in the project header, inside its
// include guard. The editor asks for the name; this module finds the
// literals, suggests a name, finds macros that already hold the value and
// writes the #define. A port of lua/epitech/fixes/macro.lua.
"use strict";

const fs = require("fs");
const path = require("path");
const magic = require("../hints/magic");
const ts = require("../ts");
const { indentPreprocessor } = require("../format");

const DEFINE = /^\s*#\s*define\s+([A-Za-z_][A-Za-z0-9_]*)\s+(.*?)\s*$/;

// The literals the magic-number hint flags, as { text, start, end }.
function literals(root, allow = [0, 1, -1, 84]) {
  return magic.literals(root, allow).map((literal) => ({ text: literal.text, start: literal.node.startPosition,
    end: literal.node.endPosition }));
}

// Actions: one per flagged literal on the rows; the editor runs the command.
function actions(ctx) {
  const seen = new Set();
  return literals(ctx.root).filter((literal) => {
    const key = `${literal.start.row}:${literal.text}`;
    const keep = literal.start.row <= ctx.range.end && literal.end.row >= ctx.range.start && !seen.has(key);
    seen.add(key);
    return keep;
  }).map((literal) => ({ title: `Extract ${literal.text} into a macro…`, rule: "C-G9",
    command: { name: "epitech.extractMacro", arguments: [literal.start.row, literal.start.column, literal.text] } }));
}

// The obvious name for the literal at row, column: BUFFER_SIZE for
// `char buffer[4096]`, WIDTH for `width = 1920`, or "".
function suggest(root, row, column) {
  const node = root.namedDescendantForPosition({ row, column });
  const parent = node && node.parent;
  if (!parent) {
    return "";
  }
  let name;
  if (parent.type === "array_declarator" && ts.same(parent.childForFieldName("size"), node)) {
    const declared = ts.declaredName(parent);
    name = declared && declared.text + "_size";
  } else if (parent.type === "init_declarator") {
    const declared = ts.declaredName(parent);
    name = declared && declared.text;
  } else if (parent.type === "assignment_expression" && parent.childForFieldName("left").type === "identifier") {
    name = parent.childForFieldName("left").text;
  }
  return !name || name.length < 3 ? "" : name.toUpperCase();
}

const readLines = (file) => {
  try {
    return fs.readFileSync(file, "utf8").split("\n");
  } catch {
    return [];
  }
};

// Macros in the project's headers holding this number: { name, file }.
function existing(projectRoot, text) {
  const value = magic.value(text);
  const result = [];
  for (const file of require("../project").files(projectRoot, ["*.h"]) || []) {
    for (const line of readLines(path.join(projectRoot, file))) {
      const match = line.match(DEFINE);
      const body = match && match[2].replace(/^\((.*)\)$/, "$1");
      if (match && (body === text || (/^[A-Za-z0-9.']+$/.test(body) && magic.value(body) === value))) {
        result.push({ name: match[1], file: path.join(projectRoot, file) });
      }
    }
  }
  return result;
}

// The value a macro already has in the project's headers.
function definedValue(projectRoot, name) {
  for (const file of require("../project").files(projectRoot, ["*.h"]) || []) {
    for (const line of readLines(path.join(projectRoot, file))) {
      const match = line.match(DEFINE);
      if (match && match[1] === name) {
        return match[2];
      }
    }
  }
  return undefined;
}

// A header's lines with `#define name value` after its guard's last
// #define (C-G3 indentation); a negative value gets parentheses.
function insertDefine(lines, name, value) {
  const header = require("../header");
  const result = lines.slice();
  let define;
  let endif;
  for (let i = 0; i < Math.min(result.length, 30) && define === undefined; i++) {
    const match = result[i].match(/^\s*#\s*ifndef\s+([A-Za-z_][A-Za-z0-9_]*)\s*$/);
    if (match) {
      for (let j = i + 1; j <= Math.min(i + 5, result.length - 1); j++) {
        if (new RegExp(`^\\s*#\\s*define\\s+${match[1]}\\s*$`).test(result[j])) {
          define = j;
          for (let k = result.length - 1; k > j; k--) {
            if (/^\s*#\s*endif/.test(result[k])) {
              endif = k;
              break;
            }
          }
          break;
        }
      }
    }
  }
  let at = define === undefined ? -1 : define;
  for (let i = (define === undefined ? -1 : define) + 1; i < (endif === undefined ? result.length : endif); i++) {
    if (/^\s*#\s*define\s/.test(result[i])) {
      at = i;
    }
  }
  if (at === -1) {
    at = result.length - 1;
  }
  result.splice(at + 1, 0, `#define ${name} ${value.startsWith("-") ? `(${value})` : value}`);
  void header;
  return indentPreprocessor(result);
}

const isMacroName = (name) => /^[A-Z][A-Z0-9_]*$/.test(name);

module.exports = { id: "macro", rules: ["C-G9"], literals, actions, suggest, existing, definedValue, insertDefine,
  isMacroName };
