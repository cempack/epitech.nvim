// C-L1: one statement per line: a chained assignment, an increment buried in
// a statement, an assignment inside an if condition, and `a && f();` used
// as an if. A port of lua/epitech/fixes/one_stmt.lua.
"use strict";

const ts = require("../ts");
const { point, nodeEdit } = require("./edits");

const PURE = new Set(["identifier", "number_literal", "char_literal", "string_literal", "concatenated_string", "null",
  "true", "false", "field_expression", "subscript_expression", "parenthesized_expression", "pointer_expression",
  "binary_expression", "unary_expression", "cast_expression", "sizeof_expression", "type_descriptor",
  "field_identifier", "primitive_type", "type_identifier", "sized_type_specifier", "abstract_pointer_declarator"]);

const pure = (node) => PURE.has(node.type) && node.children.every((child) => !child.isNamed || pure(child));
const constant = (node) => ["number_literal", "char_literal", "string_literal", "null", "true", "false",
  "identifier"].includes(node.type);
const operator = (node) => {
  const child = node.children.find((c) => !c.isNamed);
  return child && child.text;
};
const oneLine = (text) => text.replace(/\s*\n\s*/g, " ");

function conditional(node, stop) {
  let child = node;
  let parent = node.parent;
  while (parent && !ts.same(parent, stop)) {
    if (parent.type === "binary_expression") {
      const op = parent.child(1).type;
      if ((op === "&&" || op === "||") && ts.same(parent.childForFieldName("right"), child)) {
        return true;
      }
    } else if (parent.type === "conditional_expression" && !ts.same(parent.childForFieldName("condition"), child)) {
      return true;
    }
    child = parent;
    parent = parent.parent;
  }
  return false;
}

const lineIndent = (lines, row) => lines[row].match(/^\s*/)[0];

// The text of outer with nodes replaced: [[node, text], …].
function rewrite(source, outer, replacements) {
  let text = source.slice(outer.startIndex, outer.endIndex);
  const sorted = replacements.slice().sort((a, b) => b[0].startIndex - a[0].startIndex);
  for (const [node, replacement] of sorted) {
    const first = node.startIndex - outer.startIndex;
    const last = node.endIndex - outer.startIndex;
    text = text.slice(0, first) + replacement + text.slice(last);
  }
  return text;
}

const BODY_PARENTS = new Set(["if_statement", "else_clause", "while_statement", "for_statement", "do_statement"]);

// The edit replacing statement with lines; a brace-less body gets braces.
function replaceStatement(statement, newLines, source, lines) {
  const parent = statement.parent;
  const type = parent && parent.type;
  if (type === "compound_statement" || type === "case_statement") {
    const indent = lineIndent(lines, statement.startPosition.row);
    return nodeEdit(statement, newLines.join("\n" + indent));
  } else if (!BODY_PARENTS.has(type)) {
    return undefined;
  }
  const before = statement.previousSibling;
  const after = type === "if_statement" || type === "do_statement" ? statement.nextSibling : null;
  if (/\S/.test(source.slice(before.endIndex, statement.startIndex))
    || (after && /\S/.test(source.slice(statement.endIndex, after.startIndex)))) {
    return undefined;
  }
  const outer = lineIndent(lines, parent.startPosition.row);
  const inner = outer + "    ";
  const end = after ? after.startPosition : statement.endPosition;
  return {
    start: point(before.endPosition.row, before.endPosition.column),
    end: point(end.row, end.column),
    newText: ` {\n${inner}${newLines.join("\n" + inner)}\n${outer}}${after ? " " : ""}`,
  };
}

function chained(statement, source, lines) {
  const expression = statement.namedChild(0);
  if (!expression || expression.type !== "assignment_expression") {
    return undefined;
  }
  const targets = [];
  let node = expression;
  while (node.type === "assignment_expression" && operator(node) === "=") {
    targets.push(node.childForFieldName("left"));
    node = node.childForFieldName("right");
  }
  if (targets.length < 2 || node.type === "assignment_expression" || !targets.every(pure)) {
    return undefined;
  }
  const value = node.text;
  const newLines = [];
  if (constant(node)) {
    targets.forEach((target) => newLines.push(`${target.text} = ${value};`));
  } else {
    for (let i = targets.length - 1; i >= 0; i--) {
      newLines.push(`${targets[i].text} = ${i === targets.length - 1 ? value : targets[i + 1].text};`);
    }
  }
  const edit = replaceStatement(statement, newLines, source, lines);
  return edit && { title: "Split the chained assignment (C-L1)", edits: [edit] };
}

function increments(statement, source, lines) {
  const updates = [];
  const walk = (node) => {
    for (const child of node.children) {
      if (child.type === "update_expression") {
        updates.push(child);
      } else if (child.namedChildCount > 0) {
        walk(child);
      }
    }
  };
  walk(statement);
  let expression = statement.namedChild(0);
  while (expression && expression.type === "parenthesized_expression") {
    expression = expression.namedChild(0);
  }
  if (updates.length === 0 || (updates.length === 1 && expression && ts.same(updates[0], expression))) {
    return undefined;
  }
  const names = [];
  for (const update of updates) {
    const argument = update.childForFieldName("argument");
    if (argument.type !== "identifier" || conditional(update, statement)) {
      return undefined;
    }
    names.push(argument.text);
  }
  const counts = {};
  const count = (node) => {
    for (const child of node.children) {
      if (child.type === "identifier") {
        counts[child.text] = (counts[child.text] || 0) + 1;
      } else if (child.namedChildCount > 0) {
        count(child);
      }
    }
  };
  count(statement);
  for (const name of names) {
    if (counts[name] > 1) {
      return { refused: `${name} is used twice on this line, so its behaviour is undefined` };
    }
  }
  const before = [];
  const after = [];
  const replacements = [];
  updates.forEach((update, i) => {
    const prefix = update.child(0).type === "++" || update.child(0).type === "--";
    const op = prefix ? update.child(0).type : update.child(1).type;
    (prefix ? before : after).push(`${names[i]}${op};`);
    replacements.push([update, names[i]]);
  });
  const moved = [...before, ...after];
  const newLines = [...before, rewrite(source, statement, replacements), ...after];
  const edit = replaceStatement(statement, newLines, source, lines);
  return edit && { title: `Move ${moved.join(" ")} to its own line (C-L1)`, edits: [edit] };
}

function ifAssignment(statement, source, lines) {
  const condition = statement.childForFieldName("condition");
  const assignments = [];
  const walk = (node) => {
    for (const child of node.children) {
      if (child.type === "assignment_expression") {
        assignments.push(child);
      } else if (child.namedChildCount > 0) {
        walk(child);
      }
    }
  };
  walk(condition);
  if (assignments.length === 0) {
    return undefined;
  }
  if (statement.parent.type === "else_clause") {
    return { refused: "in an else if, the assignment would run before the earlier conditions" };
  }
  if (statement.startPosition.column !== lineIndent(lines, statement.startPosition.row).length) {
    return undefined;
  }
  const before = [];
  const replacements = [];
  for (const assignment of assignments) {
    if (conditional(assignment, condition)) {
      return { refused: "the assignment only runs when the condition before it allows" };
    }
    const left = assignment.childForFieldName("left");
    if (!pure(left)) {
      return undefined;
    }
    before.push(oneLine(assignment.text) + ";");
    let node = assignment;
    while (node.parent.type === "parenthesized_expression" && !ts.same(node.parent, condition)) {
      node = node.parent;
    }
    replacements.push([node, left.text]);
  }
  before.push(rewrite(source, statement, replacements));
  const edit = replaceStatement(statement, before, source, lines);
  return edit && { title: "Move the assignment out of the condition (C-L1)", edits: [edit] };
}

const LOOPS = new Set(["while_statement", "do_statement", "for_statement"]);

function loopAssignment(statement) {
  const condition = statement.childForFieldName("condition");
  if (!condition) {
    return undefined;
  }
  let found = false;
  const walk = (node) => {
    for (const child of node.children) {
      if (child.type === "assignment_expression") {
        found = true;
      } else if (child.namedChildCount > 0) {
        walk(child);
      }
    }
  };
  walk(condition);
  return found ? { refused: "the assignment would have to be repeated before the loop and at the end of its body,"
    + " and a continue would skip it" } : undefined;
}

const SIMPLE = new Set(["identifier", "call_expression", "field_expression", "subscript_expression",
  "parenthesized_expression"]);

function logical(statement, source, lines) {
  const expression = statement.namedChild(0);
  if (!expression || expression.type !== "binary_expression") {
    return undefined;
  }
  const op = expression.child(1).type;
  if (op !== "&&" && op !== "||") {
    return undefined;
  }
  const left = expression.childForFieldName("left");
  const right = expression.childForFieldName("right");
  let condition = oneLine(left.text);
  if (op === "&&" && left.type === "parenthesized_expression" && left.namedChild(0).type !== "assignment_expression") {
    condition = oneLine(left.namedChild(0).text);
  } else if (op === "||") {
    condition = SIMPLE.has(left.type) ? "!" + condition : `!(${condition})`;
  }
  const indent = lineIndent(lines, statement.startPosition.row);
  return {
    title: `Turn the ${op} into an if (C-L1)`,
    edits: [nodeEdit(statement, [`if (${condition}) {`, `    ${oneLine(right.text)};`, "}"].join("\n" + indent))],
  };
}

// Every C-L1 finding: { node, title, edits } or { node, refused }.
function findings(root, source) {
  const lines = source.split("\n");
  const result = [];
  const add = (node, finding) => finding && result.push({ ...finding, node });
  const walk = (node) => {
    for (const child of node.children) {
      const type = child.type;
      if (type === "expression_statement") {
        add(child, chained(child, source, lines));
        add(child, increments(child, source, lines));
        add(child, logical(child, source, lines));
      } else if (type === "if_statement") {
        add(child, ifAssignment(child, source, lines));
      } else if (LOOPS.has(type)) {
        add(child, loopAssignment(child));
      }
      if (child.namedChildCount > 0) {
        walk(child);
      }
    }
  };
  ts.functions(root).forEach((fn) => walk(fn.body));
  return result;
}

function actions(ctx) {
  return findings(ctx.root, ctx.source).filter((finding) => finding.edits
    && finding.node.startPosition.row >= ctx.range.start && finding.node.startPosition.row <= ctx.range.end)
    .map((finding) => ({ title: finding.title, rule: "C-L1", edits: finding.edits }));
}

function hints(ctx) {
  const lines = ctx.source.split("\n");
  return findings(ctx.root, ctx.source).filter((finding) => finding.refused).map((finding) => {
    const { row, column } = finding.node.startPosition;
    return { line: row, column, endLine: row, endColumn: (lines[row] || "").length,
      message: `C-L1 no automatic fix: ${finding.refused}`, code: "C-L1", keep: true };
  });
}

module.exports = { id: "one_stmt", rules: ["C-L1"], findings, actions, hints };
