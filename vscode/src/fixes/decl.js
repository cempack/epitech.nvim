// C-L5, C-L6: move a function's declarations to its top, one variable per
// declaration. A port of lua/epitech/fixes/decl.lua.
"use strict";

const ts = require("../ts");
const { lineEdit } = require("./edits");

const TITLE = "Move declarations to the top (C-L5)";

const hasChild = (node, type, text) => node.children.some((child) => child.type === type
  && (text === undefined || child.text === text));

function walkDeclarator(target, visit) {
  let node = target;
  while (node && node.type !== "identifier") {
    visit(node);
    node = node.childForFieldName("declarator") || node.namedChild(0);
  }
}

function objectConst(declaration, target) {
  let isConst = hasChild(declaration, "type_qualifier", "const");
  walkDeclarator(target, (node) => {
    if (node.type === "pointer_declarator") {
      isConst = hasChild(node, "type_qualifier", "const");
    }
  });
  return isConst;
}

function variableLength(target) {
  let result = false;
  walkDeclarator(target, (node) => {
    if (node.type === "array_declarator") {
      const size = node.childForFieldName("size");
      if (size && size.type !== "number_literal" && size.type !== "sizeof_expression"
        && !(size.type === "identifier" && /^[A-Z][A-Z0-9_]*$/.test(size.text))) {
        result = true;
      }
    }
  });
  return result;
}

function isArray(target) {
  let result = false;
  walkDeclarator(target, (node) => {
    result = result || node.type === "array_declarator";
  });
  return result;
}

const collapse = (text) => text.replace(/\s*\n\s*/g, " ");
const trim = (text) => text.replace(/^\s+|\s+$/g, "");

function parts(declaration) {
  const declarators = declaration.childrenForFieldName("declarator");
  const startRow = declaration.startPosition.row;
  const startCol = declaration.startPosition.column;
  const firstRow = declarators[0].startPosition.row;
  const firstCol = declarators[0].startPosition.column;
  const lines = declaration.text.split("\n");
  const typeLines = lines.slice(0, firstRow - startRow + 1);
  typeLines[typeLines.length - 1] = typeLines[typeLines.length - 1]
    .slice(0, firstCol - (firstRow === startRow ? startCol : 0));
  return {
    node: declaration,
    type: trim(typeLines.join(" ").replace(/\s+/g, " ")),
    declarators: declarators.map((declarator) => {
      let target = declarator;
      let value;
      if (declarator.type === "init_declarator") {
        target = declarator.childForFieldName("declarator");
        value = declarator.childForFieldName("value");
      }
      return { target, text: target.text, name: ts.declaredName(target), value };
    }),
  };
}

function refusal(declaration, decl) {
  if (hasChild(declaration, "storage_class_specifier", "extern")) {
    return "an extern declaration has to stay where it is";
  }
  for (const d of decl.declarators) {
    if (variableLength(d.target)) {
      return "the array's size isn't known at the top of the function";
    }
    if (d.value) {
      if (d.value.type === "initializer_list" || isArray(d.target)) {
        return `\`${collapse(declaration.text)}\` can't become an assignment`;
      } else if (objectConst(declaration, d.target)) {
        return "a const variable can't be assigned later";
      } else if (hasChild(declaration, "storage_class_specifier", "static")) {
        return "a static variable's initializer only runs once";
      }
    }
  }
  return undefined;
}

// undefined when fn's declarations are fine; else { refused: { node,
// reason } } or { leading, moved, indent }.
function plan(fn) {
  const leading = [];
  for (const child of fn.body.children) {
    if (child.type === "declaration") {
      leading.push(child);
    } else if (child.isNamed) {
      break;
    }
  }
  const isLeading = (node) => leading.some((other) => ts.same(other, node));
  const moved = [];
  const walk = (node) => {
    for (const child of node.children) {
      if (child.type === "declaration" && !isLeading(child)) {
        if (node.type !== "for_statement") {
          moved.push(child);
        }
      } else if (child.namedChildCount > 0 && child.type !== "function_definition") {
        walk(child);
      }
    }
  };
  walk(fn.body);
  const needed = moved.length > 0 || leading.some((d) => d.childrenForFieldName("declarator").length > 1);
  if (!needed) {
    return undefined;
  }
  if (leading.length > 0) {
    const firstRow = leading[0].startPosition.row;
    const lastRow = leading[leading.length - 1].endPosition.row;
    for (const child of fn.body.children) {
      const row = child.startPosition.row;
      if (child.type === "comment" && row >= firstRow && row <= lastRow) {
        return { refused: { node: child, reason: "a comment sits between the declarations" } };
      }
    }
  }
  const names = new Set();
  for (const param of fn.params) {
    const name = ts.declaredName(param.childForFieldName("declarator"));
    if (name) {
      names.add(name.text);
    }
  }
  const result = { leading: [], moved: [] };
  for (const declaration of leading) {
    const decl = parts(declaration);
    result.leading.push(decl);
    decl.declarators.forEach((d) => d.name && names.add(d.name.text));
  }
  for (const declaration of moved) {
    const decl = parts(declaration);
    let reason = refusal(declaration, decl);
    for (const d of decl.declarators) {
      const name = d.name && d.name.text;
      if (!reason && (!name || names.has(name))) {
        reason = `\`${name || d.text}\` is declared twice in this function`;
      }
      if (name) {
        names.add(name);
      }
    }
    if (reason) {
      return { refused: { node: declaration, reason } };
    }
    result.moved.push(decl);
  }
  let first = fn.body.namedChild(0);
  while (first && first.type === "comment") {
    first = first.nextNamedSibling;
  }
  result.indent = " ".repeat(first ? first.startPosition.column : 4);
  return result;
}

function edits(fn, decided, lines) {
  const block = [];
  for (const decl of decided.leading) {
    if (decl.declarators.length === 1) {
      block.push(...lines.slice(decl.node.startPosition.row, decl.node.endPosition.row + 1));
    } else {
      for (const d of decl.declarators) {
        const value = d.value ? " = " + collapse(d.value.text) : "";
        block.push(`${decided.indent}${decl.type} ${d.text}${value};`);
      }
    }
  }
  for (const decl of decided.moved) {
    for (const d of decl.declarators) {
      block.push(`${decided.indent}${decl.type} ${d.text};`);
    }
  }
  const result = [];
  let afterRow;
  if (decided.leading.length > 0) {
    const firstRow = decided.leading[0].node.startPosition.row;
    const lastRow = decided.leading[decided.leading.length - 1].node.endPosition.row;
    afterRow = lastRow + 1;
    result.push([firstRow, lastRow + 1, block]);
  } else {
    afterRow = fn.body.startPosition.row + 1;
    result.push([afterRow, afterRow, block]);
  }
  const nextLine = lines[afterRow];
  if (nextLine !== undefined && !/^\s*$/.test(nextLine) && !/^\s*}/.test(nextLine)) {
    block.push("");
  }
  for (const decl of decided.moved) {
    const startRow = decl.node.startPosition.row;
    let endRow = decl.node.endPosition.row;
    const indent = lines[startRow].match(/^\s*/)[0];
    while (/^\s*$/.test(lines[endRow + 1] === undefined ? "x" : lines[endRow + 1])) {
      endRow++;
    }
    const assignments = decl.declarators.filter((d) => d.value)
      .map((d) => `${indent}${d.name.text} = ${collapse(d.value.text)};`);
    result.push([startRow, endRow + 1, assignments]);
  }
  return result.map(([from, to, text]) => lineEdit(from, to, text.length > 0 ? text.join("\n") + "\n" : ""));
}

function anchors(decided) {
  return [...decided.moved.map((decl) => decl.node),
    ...decided.leading.filter((decl) => decl.declarators.length > 1).map((decl) => decl.node)];
}

const touches = (node, range) => node.startPosition.row <= range.end && node.endPosition.row >= range.start;

function actions(ctx) {
  const result = [];
  for (const fn of ts.functions(ctx.root)) {
    const decided = plan(fn);
    if (decided && !decided.refused && anchors(decided).some((node) => touches(node, ctx.range))) {
      result.push({ title: TITLE, rule: "C-L5", edits: edits(fn, decided, ctx.lines) });
    }
  }
  return result;
}

function hints(ctx) {
  const result = [];
  for (const fn of ts.functions(ctx.root)) {
    const decided = plan(fn);
    if (decided && decided.refused) {
      const node = decided.refused.node;
      result.push({ line: node.startPosition.row, column: node.startPosition.column, endLine: node.endPosition.row,
        endColumn: node.endPosition.column, message: `C-L5 no automatic fix: ${decided.refused.reason}`,
        code: "C-L5", keep: true });
    }
  }
  return result;
}

module.exports = { id: "decl", rules: ["C-L5"], plan, edits, actions, hints, touches };
