// C-A4: make a function static when no other file uses it; its own
// prototypes become static too, and a header prototype goes in the same
// action when nothing uses the function before its definition. A port of
// lua/epitech/fixes/static.lua.
"use strict";

const ts = require("../ts");
const staticHint = require("../hints/static");
const { point, lineEdit } = require("./edits");

const contains = (outer, node) => node.startIndex >= outer.startIndex && node.endIndex <= outer.endIndex;

function usedAfterDefinition(root, fn) {
  const fnRow = fn.node.startPosition.row;
  const fnCol = fn.node.startPosition.column;
  const prototypes = ts.prototypes(root).filter((proto) => proto.name === fn.name).map((proto) => proto.node);
  let ok = true;
  const walk = (node) => {
    for (const child of node.children) {
      if (child.type === "identifier" && child.text === fn.name && !prototypes.some((p) => contains(p, child))) {
        const { row, column } = child.startPosition;
        if (row < fnRow || (row === fnRow && column < fnCol)) {
          ok = false;
        }
      } else if (child.namedChildCount > 0) {
        walk(child);
      }
    }
  };
  walk(root);
  return ok;
}

// Deletes a header prototype's whole lines, when it's alone on them.
function deletePrototype(proto) {
  if (/\S/.test(proto.lines[proto.start.row].slice(0, proto.start.column))
    || /\S/.test(proto.lines[proto.end.row].slice(proto.end.column))) {
    return undefined;
  }
  return lineEdit(proto.start.row, proto.end.row + 1, "");
}

// ctx: { root, file, projectRoot, staticUsed, range }.
function actions(ctx) {
  if (!ctx.staticUsed || !/\.c$/.test(ctx.file || "")) {
    return [];
  }
  const result = [];
  let headers;
  for (const fn of staticHint.localOnly(ctx.root, ctx.staticUsed)) {
    const declarator = ts.functionDeclarator(fn.node.childForFieldName("declarator"));
    if (declarator.startPosition.row > ctx.range.end || declarator.endPosition.row < ctx.range.start) {
      continue;
    }
    const start = fn.node.startPosition;
    const edits = [{ start: point(start.row, start.column), end: point(start.row, start.column), newText: "static " }];
    for (const proto of ts.prototypes(ctx.root)) {
      if (proto.name === fn.name && !ts.hasStorageClass(proto.node, "static")) {
        const at = proto.node.startPosition;
        edits.unshift({ start: point(at.row, at.column), end: point(at.row, at.column), newText: "static " });
      }
    }
    headers = headers || (ctx.projectRoot ? ts.headerPrototypes(ctx.projectRoot) : []);
    const other = {};
    let removable = true;
    for (const proto of headers.filter((p) => p.name === fn.name)) {
      const deletion = deletePrototype(proto);
      if (!deletion) {
        removable = false;
      } else {
        (other[proto.file] = other[proto.file] || []).push(deletion);
      }
    }
    const files = Object.keys(other);
    if (files.length === 0 && removable) {
      result.push({ title: "Add static (C-A4)", rule: "C-A4", edits });
    } else if (removable && usedAfterDefinition(ctx.root, fn)) {
      const names = files.map((file) => require("path").relative(ctx.projectRoot, file));
      result.push({ title: `Add static and remove the prototype from ${names.join(", ")}`, rule: "C-A4", edits,
        otherFiles: other });
    }
  }
  return result;
}

module.exports = { id: "static", rules: ["C-A4"], actions };
