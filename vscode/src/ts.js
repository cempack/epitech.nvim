// Treesitter helpers, as in lua/epitech/ts.lua: the function finder the
// meters and fixes share.
"use strict";

const parser = require("./parser");

const text = (node) => node.text;
const field = (node, name) => node.childForFieldName(name);

// Down a declarator chain to its function_declarator (pointer-returning
// functions wrap it).
function functionDeclarator(node) {
  while (node) {
    const type = node.type;
    if (type === "function_declarator") {
      return node;
    }
    if (type === "pointer_declarator" || type === "parenthesized_declarator" || type === "attributed_declarator") {
      node = field(node, "declarator") || node.namedChild(0);
    } else {
      return undefined;
    }
  }
  return undefined;
}

// (void) is a parameter_declaration too, but declares no parameter.
function isVoidParam(param) {
  const type = field(param, "type");
  return !field(param, "declarator") && type && type.type === "primitive_type" && text(type) === "void";
}

function hasStorageClass(node, word) {
  return node.children.some((child) => child.type === "storage_class_specifier" && text(child) === word);
}

function describe(node) {
  const declarator = functionDeclarator(field(node, "declarator"));
  const name = declarator && field(declarator, "declarator");
  const body = field(node, "body");
  if (!name || name.type !== "identifier" || !body) {
    return undefined;
  }
  const paramList = field(declarator, "parameters");
  const params = [];
  let variadic = false;
  for (const child of paramList.children) {
    if (child.type === "parameter_declaration" && !isVoidParam(child)) {
      params.push(child);
    } else if (child.type === "variadic_parameter") {
      variadic = true;
    }
  }
  return {
    name: text(name),
    node,
    isStatic: hasStorageClass(node, "static"),
    params,
    variadic,
    paramList,
    signatureRow: name.startPosition.row,
    body,
    // C-F4: every line between the braces counts (measured, CLAUDE.md §10).
    bodyLines: Math.max(body.endPosition.row - body.startPosition.row - 1, 0),
    startRow: node.startPosition.row,
    endRow: node.endPosition.row,
  };
}

function functions(root) {
  const result = [];
  const walk = (node) => {
    for (const child of node.children) {
      if (child.type === "function_definition") {
        const fn = describe(child);
        if (fn) {
          result.push(fn);
        }
      } else if (child.namedChildCount > 0) {
        walk(child);
      }
    }
  };
  walk(root);
  return result;
}

// Parses source and hands the tree to fn, freeing it afterwards.
function withTree(source, fn) {
  const tree = parser.parse(source);
  try {
    return fn(tree.rootNode);
  } finally {
    tree.delete();
  }
}

// A Treesitter point (byte column) as a { line, character } position in
// UTF-16 units, which is what VS Code counts.
function position(lines, point) {
  const line = lines[point.row] || "";
  const prefix = Buffer.from(line, "utf8").subarray(0, point.column).toString("utf8");
  return { line: point.row, character: prefix.length };
}

module.exports = { functionDeclarator, isVoidParam, hasStorageClass, describe, functions, withTree, position };
