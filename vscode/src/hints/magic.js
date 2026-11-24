// C-G9 (grader): numbers inside function bodies that deserve a name. A port
// of lua/epitech/hints/magic.lua.
"use strict";

const ts = require("../ts");
const { diagnostic } = require("./common");

const id = "magic";
const enabled = (options) => options.magic_numbers.enabled;

// The value of a C number literal (12, 0x1F, 010, 0b11, 1.5f, 42UL), or undefined.
function value(text) {
  const literal = text.toLowerCase().replace(/'/g, "");
  let result;
  if (literal.startsWith("0x")) {
    result = parseInt(literal.slice(2).replace(/[ul]+$/, ""), 16);
  } else if (literal.startsWith("0b")) {
    result = parseInt(literal.slice(2).replace(/[ul]+$/, ""), 2);
  } else if (/^0\d+[ul]*$/.test(literal)) {
    result = parseInt(literal.replace(/[ul]+$/, ""), 8);
  } else {
    const plain = literal.replace(/[ulf]+$/, "");
    result = /^-?[0-9.]+(e[+-]?\d+)?$/.test(plain) ? Number(plain) : NaN;
  }
  return Number.isNaN(result) ? undefined : result;
}

function insidePreprocessor(node, stop) {
  for (let parent = node.parent; parent && !ts.same(parent, stop); parent = parent.parent) {
    if (parent.type.startsWith("preproc_")) {
      return true;
    }
  }
  return false;
}

const COMPARISONS = new Set(["==", "!=", "<", ">", "<=", ">="]);
const ARGUMENTS = new Set(["ac", "argc", "av", "argv"]);
const FACTORS = new Set([2, 10]);
const FD_CALLS = new Set(["write", "read", "close", "dup", "dup2", "isatty", "fstat"]);

// Numbers every program writes that a grader reads as they are (see magic.lua).
function obvious(node, number) {
  let child = node;
  let parent = node.parent;
  if (parent.type === "unary_expression") {
    child = parent;
    parent = parent.parent;
  }
  const type = parent.type;
  if (type === "binary_expression" || type === "assignment_expression") {
    const op = parent.child(1).text;
    const left = parent.childForFieldName("left");
    const right = parent.childForFieldName("right");
    const other = ts.same(left, child) ? right : left;
    if (COMPARISONS.has(op) && other.type === "identifier" && ARGUMENTS.has(other.text)) {
      return true;
    }
    const isRight = ts.same(right, child);
    return FACTORS.has(number) && (op === "*" || op === "*=" || (isRight && ["/", "%", "/=", "%="].includes(op)));
  } else if (type === "subscript_expression") {
    const argument = parent.childForFieldName("argument");
    return !ts.same(argument, child) && argument.type === "identifier" && ARGUMENTS.has(argument.text);
  } else if (type === "argument_list") {
    const fn = parent.parent.childForFieldName("function");
    return number >= 0 && number <= 2 && ts.same(parent.namedChild(0), child) && fn.type === "identifier"
      && FD_CALLS.has(fn.text);
  } else if (type === "init_declarator" && ts.same(parent.childForFieldName("value"), child)) {
    return parent.parent.children.some((qualifier) => qualifier.type === "type_qualifier" && qualifier.text === "const");
  }
  return false;
}

// The number literals of function bodies worth a name: { node, text, value }.
function literals(root, allow) {
  const allowed = new Set(allow);
  const result = [];
  const walk = (node, body) => {
    for (const child of node.children) {
      if (child.type === "number_literal") {
        let number = value(child.text);
        const parent = child.parent;
        if (number !== undefined && parent.type === "unary_expression" && parent.child(0).text === "-") {
          number = -number;
        }
        if (number !== undefined && !allowed.has(number) && !insidePreprocessor(child, body) && !obvious(child, number)) {
          result.push({ node: child, text: child.text, value: number });
        }
      } else if (child.namedChildCount > 0) {
        walk(child, body);
      }
    }
  };
  for (const fn of ts.functions(root)) {
    walk(fn.body, fn.body);
  }
  return result;
}

function run(root, source, file, ctx) {
  return literals(root, ctx.options.magic_numbers.allow)
    .map((literal) => diagnostic(literal.node, "C-G9 name this number?", "C-G9"));
}

module.exports = { id, enabled, value, literals, run };
