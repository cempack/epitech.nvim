// The hint runner: every hint module on a C source, deduplicated against
// Banana (same code on the same line), like lua/epitech/hints/init.lua.
// Hints are guesses at what a grader would flag: the editor shows them as
// hints, and turning them off is one setting.
"use strict";

const ts = require("../ts");

const MODULES = [require("./magic"), require("./static"), require("./types"), require("./naming")];

const DEFAULTS = {
  magic_numbers: { enabled: true, allow: [0, 1, -1, 84] },
  static: true,
  types: true,
  naming: { enabled: true, verbs: undefined, vague_files: undefined },
};

// The hints of a source: ctx holds root (the project root), staticUsed (from
// static.usedElsewhere, or undefined) and options.
function collect(source, file, ctx = {}) {
  const options = ctx.options || DEFAULTS;
  return ts.withTree(source, (root) => {
    const result = [];
    for (const module of MODULES) {
      if (module.enabled(options)) {
        result.push(...module.run(root, source, file, { ...ctx, options }));
      }
    }
    if (ctx.extra) {
      result.push(...ctx.extra(root, source, file, ctx));
    }
    return result;
  });
}

// Drops the hints Banana already reports; the ones marked keep (why a fix
// isn't offered) stay.
function dedup(hints, banana) {
  const reported = new Set(banana.map((entry) => `${entry.line}:${entry.code}`));
  return hints.filter((hint) => hint.keep || !reported.has(`${hint.line}:${hint.code}`));
}

module.exports = { MODULES, DEFAULTS, collect, dedup };
