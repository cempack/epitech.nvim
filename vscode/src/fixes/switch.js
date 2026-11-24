// C-C1: an if chain with too many branches, or whose else ifs nest too deep,
// becomes a switch when every condition compares the same expression with
// constants. A port of lua/epitech/fixes/switch.lua.
"use strict";

const ts = require("../ts");
const budget = require("../budget");
const magic = require("../hints/magic");
const { nodeEdit } = require("./edits");

function unwrap(node) {
  while (node && node.type === "parenthesized_expression") {
    node = node.namedChild(0);
  }
  return node;
}

function subject(node) {
  node = unwrap(node);
  if (!node) {
    return false;
  } else if (node.type === "identifier") {
    return true;
  } else if (node.type === "field_expression") {
    return subject(node.childForFieldName("argument"));
  }
  return false;
}

function constant(node) {
  node = unwrap(node);
  const type = node && node.type;
  return type === "number_literal" || type === "char_literal"
    || (type === "identifier" && /^[A-Z][A-Z0-9_]*$/.test(node.text));
}

const squeeze = (text) => text.replace(/\s+/g, "");

// [subject text, constants] for x == K, K == x, or ||-joined ones.
function comparisons(node) {
  node = unwrap(node);
  if (!node || node.type !== "binary_expression") {
    return undefined;
  }
  const op = node.child(1).type;
  const left = node.childForFieldName("left");
  const right = node.childForFieldName("right");
  if (op === "||") {
    const a = comparisons(left);
    const b = comparisons(right);
    if (!a || !b || a[0] !== b[0]) {
      return undefined;
    }
    return [a[0], a[1].concat(b[1])];
  } else if (op === "==") {
    if (subject(left) && constant(right)) {
      return [squeeze(unwrap(left).text), [unwrap(right)]];
    } else if (subject(right) && constant(left)) {
      return [squeeze(unwrap(right).text), [unwrap(left)]];
    }
  }
  return undefined;
}

function branches(ifNode) {
  const result = [];
  let node = ifNode;
  while (node) {
    result.push({ condition: node.childForFieldName("condition"), body: node.childForFieldName("consequence"), node });
    const alternative = node.childForFieldName("alternative");
    const inner = alternative && alternative.namedChild(0);
    if (inner && inner.type === "if_statement") {
      node = inner;
    } else {
      if (inner) {
        result.push({ body: inner });
      }
      node = null;
    }
  }
  return result;
}

const statements = (body) => (body.type !== "compound_statement" ? [body] : body.children.filter((c) => c.isNamed));

function looseJump(body) {
  if (body.type === "break_statement" || body.type === "continue_statement") {
    return body;
  }
  let found;
  const walk = (node) => {
    for (const child of node.children) {
      const type = child.type;
      if (type === "break_statement" || type === "continue_statement") {
        found = found || child;
      } else if (!["while_statement", "for_statement", "do_statement", "switch_statement"].includes(type)
        && child.namedChildCount > 0) {
        walk(child);
      }
    }
  };
  walk(body);
  return found;
}

function endsFlow(last) {
  if (!last) {
    return false;
  }
  if (["return_statement", "break_statement", "continue_statement"].includes(last.type)) {
    return true;
  }
  const call = last.type === "expression_statement" && last.namedChild(0);
  const fn = call && call.type === "call_expression" && call.childForFieldName("function");
  return Boolean(fn && fn.text === "exit");
}

function reindent(node, lines, from, to) {
  const result = [];
  for (let row = node.startPosition.row; row <= node.endPosition.row; row++) {
    let line = lines[row];
    line = from !== undefined && line.startsWith(from) ? line.slice(from.length) : line.replace(/^\s+/, "");
    result.push(line === "" ? "" : to + line);
  }
  return result;
}

// undefined when the chain isn't a candidate; { refused, node } or
// { lines, node } otherwise.
function plan(ifNode, depth, lines, options = budget.DEFAULTS) {
  if (ifNode.parent.type === "else_clause") {
    return undefined;
  }
  const chain = branches(ifNode);
  const ifs = chain.length - (chain[chain.length - 1].condition ? 0 : 1);
  if (chain.length <= options.max_branches && depth + ifs - 1 < options.max_depth) {
    return undefined;
  }
  let x;
  const seen = new Set();
  for (const branch of chain) {
    if (branch.condition) {
      const found = comparisons(branch.condition);
      if (!found || (x && x !== found[0])) {
        return undefined;
      }
      x = found[0];
      branch.constants = found[1];
      for (const k of found[1]) {
        const key = k.type === "number_literal" ? String(magic.value(k.text)) : k.text;
        if (seen.has(key)) {
          return undefined;
        }
        seen.add(key);
      }
    }
  }
  if (ifs < 2) {
    return undefined;
  }
  for (const branch of chain) {
    const jump = looseJump(branch.body);
    if (jump) {
      return { refused: `a ${jump.type.replace("_statement", "")} in a branch would act on the switch`, node: ifNode };
    }
    if (statements(branch.body).some((statement) => statement.type === "declaration")) {
      return { refused: "a branch declares a variable, which can't follow a case label", node: ifNode };
    }
  }
  const indent = lines[ifNode.startPosition.row].match(/^\s*/)[0];
  const result = [`switch (${x}) {`];
  for (const branch of chain) {
    if (branch.constants) {
      branch.constants.forEach((k) => result.push(`${indent}    case ${k.text}:`));
    } else {
      result.push(`${indent}    default:`);
    }
    const body = statements(branch.body);
    const from = body[0] ? lines[body[0].startPosition.row].match(/^\s*/)[0] : undefined;
    body.forEach((statement) => result.push(...reindent(statement, lines, from, indent + "        ")));
    if (!endsFlow(body[body.length - 1])) {
      result.push(`${indent}        break;`);
    }
  }
  result.push(`${indent}}`);
  return { lines: result, node: ifNode, subject: x };
}

function plans(root, lines) {
  const result = [];
  for (const fn of ts.functions(root)) {
    for (const entry of budget.depths(fn.body)) {
      if (entry.node.type === "if_statement" && !entry.elseIf) {
        const decided = plan(entry.node, entry.depth, lines);
        if (decided) {
          result.push(decided);
        }
      }
    }
  }
  return result;
}

function actions(ctx) {
  return plans(ctx.root, ctx.lines).filter((decided) => decided.lines
    && decided.node.startPosition.row >= ctx.range.start && decided.node.startPosition.row <= ctx.range.end)
    .map((decided) => ({ title: "Convert to switch (C-C1)", rule: "C-C1", kind: "refactor.rewrite",
      edits: [nodeEdit(decided.node, decided.lines.join("\n"))] }));
}

function hints(ctx) {
  return plans(ctx.root, ctx.lines).filter((decided) => decided.refused).map((decided) => {
    const { row, column } = decided.node.startPosition;
    return { line: row, column, endLine: row, endColumn: column + 2,
      message: `C-C1 no automatic switch: ${decided.refused}`, code: "C-C1", keep: true };
  });
}

module.exports = { id: "switch", rules: ["C-C1"], plan, plans, actions, hints };
