// The fixes behind the light bulb: each module's actions(ctx) returns
// { title, rule, kind?, edits, otherFiles? } (edits for this file,
// otherFiles { absolute path: edits }), and hints(ctx) explains where no
// fix is offered. Like lua/epitech/fixes/init.lua, an action whose result
// passes 79 columns gets the formatter's wrapping.
"use strict";

const ts = require("../ts");
const { wrapped } = require("./edits");

const MODULES = [require("./macro"), require("./static"), require("./const"), require("./void"), require("./decl"),
  require("./one_stmt"), require("./switch")];

// The actions for rows range.start..range.end of source. ctx: { file,
// projectRoot, staticUsed, formatOptions }.
function actions(source, range, ctx = {}) {
  const lines = source.split("\n");
  return ts.withTree(source, (root) => {
    const full = { ...ctx, root, source, lines, range };
    return MODULES.flatMap((module) => module.actions(full)).map((action) => ({
      ...action,
      kind: action.kind || "quickfix",
      edits: action.otherFiles || action.command ? action.edits : wrapped(lines, action.edits, ctx.formatOptions),
    }));
  });
}

// The hints explaining refused fixes (kept even where Banana reports).
function hints(source, ctx = {}) {
  const lines = source.split("\n");
  return ts.withTree(source, (root) => {
    const full = { ...ctx, root, source, lines };
    return MODULES.filter((module) => module.hints).flatMap((module) => module.hints(full));
  });
}

module.exports = { MODULES, actions, hints };
