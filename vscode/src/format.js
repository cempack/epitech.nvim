// The formatter: a line-for-line port of lua/epitech/format.lua, so both
// editors format a file the same way. test/format.test.js checks that, on
// every fixture, against the Neovim plugin when nvim is installed: change one
// only together with the other.
//
// Rows are 1-based and lengths are counted in bytes, as in the Lua code
// (C-F3 counts columns the way Lua's # does).
"use strict";

const { spawnSync } = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");
const parser = require("./parser");

// Lua's %s.
const SPACE = "[ \\t\\n\\v\\f\\r]";
const bytes = (text) => Buffer.byteLength(text, "utf8");

function clangFormat(input, options, styleArg) {
  const result = spawnSync(options.clangFormat || "clang-format", [styleArg, "--assume-filename=epitech.c"], {
    input,
    encoding: "utf8",
  });
  if (result.error) {
    throw new Error(`clang-format failed: ${result.error.message}`);
  }
  if (result.status !== 0) {
    throw new Error(`clang-format failed: ${result.stderr || ""}`);
  }
  return result.stdout;
}

function splitOutput(stdout) {
  return stdout.replace(/\n$/, "").split("\n");
}

function hasHeader(lines) {
  return lines.length >= 6
    && lines[0] === "/*"
    && /^ ?\*\* EPITECH PROJECT, \d\d\d\d$/.test(lines[1])
    && /^ ?\*\* .*$/.test(lines[2])
    && /^ ?\*\* File description:$/.test(lines[3])
    && /^ ?\*\* .*$/.test(lines[4])
    && /^ ?\*\/$/.test(lines[5]);
}

const DIRECTIVE = new RegExp(`^${SPACE}*#${SPACE}*([A-Za-z_][A-Za-z0-9_]*)`);
const LEADING = new RegExp(`^${SPACE}*`);

// C-G3: conditional preprocessor nesting, independent of C block nesting.
function indentPreprocessor(lines) {
  let depth = 0;
  return lines.map((line) => {
    const match = line.match(DIRECTIVE);
    if (!match) {
      return line;
    }
    const directive = match[1];
    const branch = ["else", "elif", "elifdef", "elifndef"].includes(directive);
    if (branch || directive === "endif") {
      depth = Math.max(depth - 1, 0);
    }
    const normalized = "    ".repeat(depth) + line.replace(LEADING, "");
    if (["if", "ifdef", "ifndef"].includes(directive) || branch) {
      depth += 1;
    }
    return normalized;
  });
}

// C-L3 inside #define bodies, formatted without a column limit so they never
// get backslashes (C-G6).
function formatMacros(lines, options) {
  const rows = [];
  const defines = [];
  const define = new RegExp(`^${SPACE}*#${SPACE}*define${SPACE}`);
  lines.forEach((line, i) => {
    if (define.test(line) && !/\\$/.test(line)) {
      rows.push(i);
      defines.push(line.replace(new RegExp(`^${SPACE}+`), ""));
    }
  });
  if (rows.length === 0) {
    return lines;
  }
  const style = fs.readFileSync(options.styleFile, "utf8").replace(/\n$/, "").split("\n").filter((line) =>
    !/^OneLineFormatOffRegex:/.test(line) && !/^SkipMacroDefinitionBody:/.test(line) && !/^ColumnLimit:/.test(line));
  style.push("ColumnLimit: 0");
  const stylePath = path.join(fs.mkdtempSync(path.join(os.tmpdir(), "epitech-")), "style");
  fs.writeFileSync(stylePath, style.join("\n") + "\n");
  let stdout;
  try {
    stdout = clangFormat(defines.join("\n") + "\n", options, `--style=file:${stylePath}`);
  } finally {
    fs.rmSync(path.dirname(stylePath), { recursive: true, force: true });
  }
  const formatted = splitOutput(stdout);
  if (formatted.length !== rows.length) {
    return lines;
  }
  const result = lines.slice();
  rows.forEach((row, i) => {
    result[row] = formatted[i];
  });
  return result;
}

function walk(node, visit) {
  visit(node);
  for (const child of node.children) {
    walk(child, visit);
  }
}

// Rows (1-based) covered by comments, and the tree.
function commentRows(lines) {
  const tree = parser.parse(lines.join("\n") + "\n");
  const rows = new Set();
  walk(tree.rootNode, (node) => {
    if (node.type === "comment") {
      for (let row = node.startPosition.row + 1; row <= node.endPosition.row + 1; row++) {
        rows.add(row);
      }
    }
  });
  return { comments: rows, root: tree.rootNode, tree };
}

// The byte of text at byte offset `offset`, as a character.
function byteAt(text, offset) {
  const buffer = Buffer.from(text, "utf8");
  return offset < buffer.length ? String.fromCharCode(buffer[offset]) : "";
}

// Adjacent string literals and a wrapped ternary's ':' go one level below
// the line they continue (C-L2), not aligned under it.
function indentContinuations(lines, comments) {
  let previous;
  let previousNew;
  let previousAligned;
  return lines.map((line, index) => {
    if (line === "" || comments.has(index + 1) || /^\s*#/.test(line)) {
      return line;
    }
    const indent = line.match(/^ */)[0].length;
    const first = byteAt(line, indent);
    const above = previous === undefined ? undefined : byteAt(previous, indent);
    const aligned = (first === '"' && above === '"') || (first === ":" && above === "?");
    let result = line;
    let fresh = indent;
    if (aligned) {
      fresh = previousAligned ? previousNew : previousNew + 4;
      if (fresh !== indent) {
        result = " ".repeat(fresh) + line.slice(indent);
      }
    }
    previous = result;
    previousNew = fresh;
    previousAligned = aligned;
    return result;
  });
}

const CONTROL = new Set(["if_statement", "while_statement", "for_statement", "do_statement", "switch_statement"]);
const SIMPLE = new Set(["type_definition", "expression_statement", "return_statement", "declaration",
  "field_declaration"]);
const BLOCKS = new Set(["field_declaration_list", "enumerator_list", "initializer_list", "compound_statement"]);
const JOINED_OPERATORS = ["==", "!=", "<=", ">=", "<", ">"];

function hasType(node, types) {
  if (types.has(node.type)) {
    return true;
  }
  return node.children.some((child) => hasType(child, types));
}

function sameNode(a, b) {
  return a && b && a.startIndex === b.startIndex && a.endIndex === b.endIndex && a.type === b.type;
}

// { first, last } rows (1-based) of each statement, control header or
// function signature, outermost first.
function continuationUnits(root) {
  const units = [];
  const add = (first, last) => {
    if (last > first) {
      units.push({ first: first + 1, last: last + 1 });
    }
  };
  const visit = (node) => {
    const kind = node.type;
    if (CONTROL.has(kind)) {
      let first = node.startPosition.row;
      let last = first;
      const condition = node.childForFieldName("condition");
      if (kind === "do_statement" && condition) {
        first = condition.startPosition.row;
        last = condition.endPosition.row;
      } else if (kind === "for_statement") {
        for (const child of node.children) {
          if (child.type === ")") {
            last = child.startPosition.row;
          }
        }
      } else if (condition) {
        last = condition.endPosition.row;
      }
      add(first, last);
      for (const child of node.children) {
        if (!condition || !sameNode(child, condition)) {
          visit(child);
        }
      }
    } else if (kind === "function_definition") {
      const declarator = node.childForFieldName("declarator");
      if (declarator) {
        add(node.startPosition.row, declarator.endPosition.row);
      }
      const body = node.childForFieldName("body");
      if (body) {
        visit(body);
      }
    } else if (SIMPLE.has(kind) && !hasType(node, BLOCKS)) {
      add(node.startPosition.row, node.endPosition.row);
    } else {
      for (const child of node.children) {
        visit(child);
      }
    }
  };
  visit(root);
  return units;
}

function startsWithOperator(text, operators) {
  return operators.some((operator) => text.startsWith(operator + " "));
}

function joinedLine(previous, text) {
  const glue = /[([]$/.test(previous) || /^[)\],;]/.test(text) ? "" : " ";
  const wanted = startsWithOperator(text, JOINED_OPERATORS) || /^\)/.test(text) || /[,(]$/.test(previous);
  if (wanted && bytes(previous) + bytes(glue) + bytes(text) <= 79) {
    return previous + glue + text;
  }
  return undefined;
}

// ( and [ opened minus closed, outside string and character literals.
function bracketDelta(text) {
  let delta = 0;
  for (let i = 0; i < text.length; i++) {
    const char = text[i];
    if (char === '"' || char === "'") {
      i++;
      while (i < text.length && text[i] !== char) {
        i += text[i] === "\\" ? 2 : 1;
      }
    } else if (char === "(" || char === "[") {
      delta++;
    } else if (char === ")" || char === "]") {
      delta--;
    }
  }
  return delta;
}

const trim = (text) => text.replace(new RegExp(`^${SPACE}+|${SPACE}+$`, "g"), "");

// C-L2: each wrapped line one level below its statement per parenthesis
// still open, after joining what fits in 79 columns (see format.lua).
function flattenContinuations(lines, comments, root) {
  const claimed = new Set();
  const units = [];
  for (const unit of continuationUnits(root)) {
    let usable = true;
    for (let row = unit.first; row <= unit.last; row++) {
      const line = lines[row - 1];
      if (claimed.has(row) || comments.has(row) || /^\s*#/.test(line) || /\\$/.test(line)) {
        usable = false;
      }
    }
    if (usable) {
      for (let row = unit.first; row <= unit.last; row++) {
        claimed.add(row);
      }
      units.push(unit);
    }
  }

  let result = lines.slice();
  let joined = false;
  units.sort((a, b) => b.first - a.first);
  for (const unit of units) {
    const base = result[unit.first - 1].match(/^ */)[0].length;
    let fresh = [result[unit.first - 1]];
    let depth = bracketDelta(result[unit.first - 1]);
    let unitJoined = false;
    let tooLong = false;
    for (let row = unit.first + 1; row <= unit.last; row++) {
      const text = trim(result[row - 1]);
      const line = joinedLine(fresh[fresh.length - 1], text);
      if (line !== undefined) {
        fresh[fresh.length - 1] = line;
        unitJoined = true;
      } else {
        // calibrate: same guess as format.lua for a line outside parentheses.
        fresh.push(" ".repeat(base + 4 * Math.max(1, depth)) + text);
        tooLong = tooLong || bytes(fresh[fresh.length - 1]) > 79;
      }
      depth += bracketDelta(text);
    }
    const old = result.slice(unit.first - 1, unit.last);
    if (tooLong) {
      fresh = old;
    } else if (unitJoined) {
      joined = true;
    }
    if (fresh.join("\n") !== old.join("\n") || fresh.length !== old.length) {
      result = result.slice(0, unit.first - 1).concat(fresh, result.slice(unit.last));
    }
  }
  return { lines: result, joined };
}

// Keeps the Epitech "**" prefix on every line of a comment that uses it.
function keepCommentPrefix(lines, comments) {
  const result = lines.slice();
  let i = 1;
  while (i <= result.length) {
    if (comments.has(i) && /^\s*\/\*/.test(result[i - 1])) {
      let last = i;
      let double = false;
      while (comments.has(last + 1) && !/\*\/\s*$/.test(result[last - 1])) {
        last++;
        double = double || /^\s*\*\*/.test(result[last - 1]);
      }
      if (double) {
        for (let row = i + 1; row <= last; row++) {
          const match = result[row - 1].match(/^(\s*)\*( .*)$/);
          if (match && !/^\s*\*\*/.test(result[row - 1])) {
            result[row - 1] = match[1] + "**" + match[2];
          }
        }
      }
      i = last + 1;
    } else {
      i++;
    }
  }
  return result;
}

// C-L6: the only blank line in a function separates its declarations from
// the rest.
function normalizeFunctionBlankLines(lines, comments, root) {
  const drop = new Set();
  const blankAfter = new Set();
  walk(root, (node) => {
    if (node.type !== "function_definition") {
      return;
    }
    const body = node.childForFieldName("body");
    if (!body || body.type !== "compound_statement") {
      return;
    }
    const firstRow = body.startPosition.row;
    const lastRow = body.endPosition.row;
    for (let row = firstRow + 2; row <= lastRow; row++) {
      if (/^\s*$/.test(lines[row - 1]) && !comments.has(row)) {
        drop.add(row);
      }
    }
    let lastDeclaration;
    let hasStatement = false;
    for (const child of body.children) {
      if (child.isNamed && child.type !== "comment") {
        if (child.type === "declaration" && !hasStatement) {
          lastDeclaration = child.endPosition.row + 1;
        } else {
          hasStatement = true;
        }
      }
    }
    if (lastDeclaration !== undefined && hasStatement) {
      blankAfter.add(lastDeclaration);
    }
  });
  const result = [];
  lines.forEach((line, index) => {
    const row = index + 1;
    if (!drop.has(row)) {
      result.push(line);
    }
    if (blankAfter.has(row)) {
      result.push("");
    }
  });
  return result;
}

// Formats C source text. options: { styleFile, clangFormat }. Returns the
// formatted text, ending with a newline. Needs parser.init() first.
function formatText(text, options) {
  let lines = text.replace(/\r?\n$/, "").split(/\r?\n/);
  lines = lines.map((line) => line.replace(new RegExp(`${SPACE}+$`), ""));
  while (lines.length > 1 && lines[0] === "") {
    lines.shift();
  }

  let header = [];
  let bodyStart = 0;
  if (hasHeader(lines)) {
    header = lines.slice(0, 6).map((line, i) => (i === 0 ? line : line.replace(/^ /, "")));
    bodyStart = 6;
  }

  let body = lines.slice(bodyStart);
  body = splitOutput(clangFormat(body.join("\n") + "\n", options, `--style=file:${options.styleFile}`));
  while (body.length > 0 && body[0] === "") {
    body.shift();
  }
  while (body.length > 0 && body[body.length - 1] === "") {
    body.pop();
  }

  let formatted = header.slice();
  if (header.length > 0 && body.length > 0) {
    formatted.push("");
  }
  formatted = formatted.concat(body);
  if (formatted.length === 0) {
    formatted = [""];
  }
  formatted = formatMacros(formatted, options);
  formatted = indentPreprocessor(formatted);

  let { comments, root, tree } = commentRows(formatted);
  formatted = indentContinuations(formatted, comments);
  formatted = keepCommentPrefix(formatted, comments);
  const flattened = flattenContinuations(formatted, comments, root);
  formatted = flattened.lines;
  if (flattened.joined) {
    tree.delete();
    ({ comments, root, tree } = commentRows(formatted));
  }
  formatted = normalizeFunctionBlankLines(formatted, comments, root);
  tree.delete();
  return formatted.join("\n") + "\n";
}

module.exports = { formatText, indentPreprocessor, hasHeader, bracketDelta };
