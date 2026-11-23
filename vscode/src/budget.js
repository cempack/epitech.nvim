// Budget meters, as in lua/epitech/budget.lua: lines and parameters per
// function (C-F4, C-F5), functions per file (C-O3), nesting depth (C-C1).
// Chunks are { text, level } with level "ok", "near" or "over".
"use strict";

const ts = require("./ts");

const DEFAULTS = {
  max_lines: 20, warn_lines: 17, max_args: 4, max_functions: 10, max_non_static: 5,
  max_depth: 3, show_depth_from: 2, max_branches: 3,
};

// "13/20 lines · 2/4 args"; a variadic counts as a parameter (measured).
function functionChunks(fn, options = DEFAULTS) {
  let lines = "ok";
  if (fn.bodyLines > options.max_lines) {
    lines = "over";
  } else if (fn.bodyLines >= options.warn_lines) {
    lines = "near";
  }
  const args = fn.params.length + (fn.variadic ? 1 : 0);
  return [
    { text: `${fn.bodyLines}/${options.max_lines} lines`, level: lines },
    { text: " · ", level: "ok" },
    { text: `${args}/${options.max_args} args${fn.variadic ? " (…)" : ""}`, level: args > options.max_args ? "over" : "ok" },
  ];
}

// switch and do while count as levels (measured).
const CONTROL = new Set(["if_statement", "while_statement", "for_statement", "do_statement", "switch_statement"]);

function branches(ifNode) {
  let count = 1;
  let node = ifNode;
  for (;;) {
    const alternative = node.childForFieldName("alternative");
    if (!alternative) {
      return count;
    }
    count++;
    const inner = alternative.namedChild(0);
    if (!inner || inner.type !== "if_statement") {
      return count;
    }
    node = inner;
  }
}

// { node, depth, elseIf, branches } for each control statement of a body.
function depths(body) {
  const result = [];
  const walk = (node, depth) => {
    for (const child of node.children) {
      if (CONTROL.has(child.type)) {
        const entry = {
          node: child,
          depth: depth + 1,
          elseIf: child.type === "if_statement" && child.parent.type === "else_clause",
        };
        if (child.type === "if_statement" && !entry.elseIf) {
          entry.branches = branches(child);
        }
        result.push(entry);
        walk(child, depth + 1);
      } else if (child.namedChildCount > 0) {
        walk(child, depth);
      }
    }
  };
  walk(body, 0);
  return result;
}

function depthChunks(entry, options = DEFAULTS) {
  const chunks = [];
  if (entry.depth >= options.show_depth_from) {
    const label = `depth ${entry.depth}${entry.elseIf ? " (else + if)" : ""}`;
    if (entry.depth >= options.max_depth) {
      chunks.push({ text: `${label} ✗ C-C1`, level: "over" });
    } else {
      chunks.push({ text: label, level: entry.depth === options.max_depth - 1 ? "near" : "ok" });
    }
  }
  if (entry.branches && entry.branches > options.max_branches) {
    if (chunks.length > 0) {
      chunks.push({ text: " · ", level: "ok" });
    }
    chunks.push({ text: `${entry.branches} branches ✗ C-C1`, level: "over" });
  }
  return chunks;
}

// Everything the editor shows for a source: { rows: Map(row -> chunks),
// functions, nonStatic }.
function analyze(source, options = DEFAULTS, show = { functions: true, depth: true }) {
  return ts.withTree(source, (root) => {
    const fns = ts.functions(root);
    const rows = new Map();
    const add = (row, chunks) => {
      if (rows.has(row)) {
        rows.get(row).push({ text: " · ", level: "ok" }, ...chunks);
      } else {
        rows.set(row, chunks);
      }
    };
    for (const fn of fns) {
      if (show.functions) {
        add(fn.signatureRow, functionChunks(fn, options));
      }
      if (show.depth) {
        for (const entry of depths(fn.body)) {
          const chunks = depthChunks(entry, options);
          if (chunks.length > 0) {
            add(entry.node.startPosition.row, chunks);
          }
        }
      }
    }
    return { rows, functions: fns.length, nonStatic: fns.filter((fn) => !fn.isStatic).length };
  });
}

function level(count, limit) {
  if (count > limit) {
    return "over";
  }
  return count === limit ? "near" : "ok";
}

// "functions 8/10 · non-static 5/5" and the worst level.
function fileText(counts, options = DEFAULTS) {
  const levels = [level(counts.functions, options.max_functions), level(counts.nonStatic, options.max_non_static)];
  const worst = levels.includes("over") ? "over" : levels.includes("near") ? "near" : "ok";
  return {
    text: `functions ${counts.functions}/${options.max_functions} · non-static ${counts.nonStatic}/${options.max_non_static}`,
    level: worst,
  };
}

module.exports = { DEFAULTS, functionChunks, branches, depths, depthChunks, analyze, fileText };
