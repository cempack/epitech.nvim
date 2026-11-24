// C-A1: make a pointer parameter point to const when the function never
// modifies the data, in the definition and in every prototype (the file's
// and the headers'). A port of lua/epitech/fixes/const.lua.
"use strict";

const types = require("../hints/types");
const ts = require("../ts");
const { nodeEdit, point } = require("./edits");

function nthParam(declarator, index) {
  return declarator.childForFieldName("parameters").children
    .filter((child) => child.type === "parameter_declaration")[index - 1];
}

function actions(ctx) {
  const result = [];
  const headers = ctx.projectRoot ? ts.headerPrototypes(ctx.projectRoot) : [];
  for (const candidate of types.constCandidates(ctx.root, { root: ctx.projectRoot }, ctx.file)) {
    if (candidate.param.startPosition.row > ctx.range.end || candidate.param.endPosition.row < ctx.range.start) {
      continue;
    }
    const edits = [nodeEdit(candidate.param, candidate.text)];
    for (const proto of ts.prototypes(ctx.root)) {
      const param = proto.name === candidate.fn.name && nthParam(proto.declarator, candidate.index);
      if (param) {
        edits.push(nodeEdit(param, types.constText(param)));
      }
    }
    const otherFiles = {};
    for (const proto of headers) {
      const param = proto.name === candidate.fn.name && proto.params[candidate.index - 1];
      if (param) {
        (otherFiles[proto.file] = otherFiles[proto.file] || []).push({
          start: point(param.start.row, param.start.column), end: point(param.end.row, param.end.column),
          newText: param.constText,
        });
      }
    }
    result.push({ title: `Make ${candidate.name.text} const (C-A1)`, rule: "C-A1", edits,
      otherFiles: Object.keys(otherFiles).length > 0 ? otherFiles : undefined });
  }
  return result;
}

module.exports = { id: "const", rules: ["C-A1"], actions };
