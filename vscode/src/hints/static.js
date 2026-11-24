// C-A4 (grader), C-O3: non-static functions no other file uses, and this one
// does, could be static. Whether another .c file mentions a name comes from
// `git grep`, run on save; until then there's no hint. A port of
// lua/epitech/hints/static.lua.
"use strict";

const path = require("path");
const { spawn } = require("child_process");
const ts = require("../ts");
const { diagnostic } = require("./common");

const id = "static";
const enabled = (options) => options.static;

function candidates(root) {
  return ts.functions(root).filter((fn) => !fn.isStatic && fn.name !== "main");
}

const contains = (outer, node) => node.startIndex >= outer.startIndex && node.endIndex <= outer.endIndex;

// The names of fns this source uses outside their own definition.
function usedHere(root, fns) {
  const wanted = new Map(fns.map((fn) => [fn.name, fn.node]));
  const result = new Set();
  const walk = (node) => {
    for (const child of node.children) {
      if (child.type === "identifier") {
        const definition = wanted.get(child.text);
        if (definition && !result.has(child.text) && child.parent.type !== "function_declarator"
          && !contains(definition, child)) {
          result.add(child.text);
        }
      } else if (child.namedChildCount > 0) {
        walk(child);
      }
    }
  };
  walk(root);
  return result;
}

function localOnly(root, used) {
  const list = candidates(root).filter((fn) => !used.has(fn.name));
  const here = usedHere(root, list);
  return list.filter((fn) => here.has(fn.name));
}

// Which of names other .c files mention: a Set, or undefined when git grep
// failed (no git, not a repository): then nothing is known.
function usedElsewhere(projectRoot, file, names) {
  const own = path.relative(projectRoot, file);
  if (names.length === 0) {
    return Promise.resolve(new Set());
  }
  const args = ["grep", "-o", "-w", "-F", "--untracked", ...names.flatMap((name) => ["-e", name]), "--", "*.c"];
  return new Promise((resolve) => {
    let stdout = "";
    let child;
    try {
      child = spawn("git", args, { cwd: projectRoot });
    } catch {
      resolve(undefined);
      return;
    }
    child.stdout.on("data", (chunk) => {
      stdout += chunk;
    });
    child.on("error", () => resolve(undefined));
    child.on("close", (code) => {
      if (code !== 0 && code !== 1) {
        resolve(undefined);
        return;
      }
      const used = new Set();
      for (const line of stdout.split("\n")) {
        const match = line.match(/^(.*):([A-Za-z0-9_]+)$/);
        if (match && match[1] !== own) {
          used.add(match[2]);
        }
      }
      resolve(used);
    });
  });
}

function run(root, source, file, ctx) {
  const used = ctx.staticUsed;
  if (!used || !/\.c$/.test(file || "")) {
    return [];
  }
  return localOnly(root, used).map((fn) =>
    diagnostic(ts.functionDeclarator(fn.node.childForFieldName("declarator")).childForFieldName("declarator"),
      "C-A4 only used in this file", "C-A4"));
}

module.exports = { id, enabled, candidates, usedHere, localOnly, usedElsewhere, run };
