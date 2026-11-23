// Banana through epiclang, as in lua/epitech/banana.lua: run it on a file
// and parse what it prints on stderr.
"use strict";

const fs = require("fs");
const path = require("path");
const { spawn } = require("child_process");
const project = require("./project");

const WITH_POS = /^(.*?):(\d+):(\d+): [A-Za-z]+: \[Banana\] \[([A-Za-z]+)\] (.*?) \((C-[A-Z]\d+)\)\s*$/;
const NO_POS = /^(.*?): [A-Za-z]+: \[Banana\] \[([A-Za-z]+)\] (.*?) \((C-[A-Z]\d+)\)\s*$/;
const LEVELS = new Set(["Fatal", "Major", "Minor", "Info"]);

function resolve(file, root) {
  const absolute = path.normalize(path.isAbsolute(file) ? file : path.join(root, file));
  try {
    return fs.realpathSync(absolute);
  } catch {
    return absolute;
  }
}

// Entries { path, line, column (0-based), level ("fatal"…), message, code }
// about `file` (every file when it's undefined), deduplicated: epiclang
// prints each warning twice, and a header's for every file including it.
function parse(stderr, file, root) {
  const target = file && resolve(file, root);
  const seen = new Set();
  const result = [];
  for (const line of (stderr || "").split("\n")) {
    let match = line.match(WITH_POS);
    let entry;
    if (match) {
      entry = { path: match[1], line: Number(match[2]) - 1, column: Math.max(Number(match[3]) - 1, 0),
        level: match[4], message: match[5], code: match[6] };
    } else if ((match = line.match(NO_POS))) {
      entry = { path: match[1], line: 0, column: 0, level: match[2], message: match[3], code: match[4] };
    }
    if (!entry || !LEVELS.has(entry.level)) {
      continue;
    }
    entry.path = resolve(entry.path, root);
    const key = [entry.path, entry.line, entry.column, entry.code, entry.message].join("\0");
    if ((!target || entry.path === target) && !seen.has(key)) {
      seen.add(key);
      // A fatal means the project isn't graded at all.
      if (entry.level === "Fatal") {
        entry.message = "FATAL: " + entry.message;
      }
      entry.level = entry.level.toLowerCase();
      result.push(entry);
    }
  }
  return result;
}

// Runs the checker on file; resolves to its entries, or rejects with an
// error whose code is "ENOENT" when the checker isn't installed. Returns
// { promise, kill }.
function run(file, options = {}) {
  const root = options.root || project.root(file);
  const args = (options.args || ["-x", "c", "-fsyntax-only"]).concat(project.includeFlags(root, file), [file]);
  let child;
  const promise = new Promise((resolvePromise, reject) => {
    let stderr = "";
    child = spawn(options.cmd || "epiclang", args, { cwd: root });
    child.stderr.on("data", (chunk) => {
      stderr += chunk;
    });
    child.stdout.resume();
    child.on("error", reject);
    child.on("close", (code, signal) => {
      if (signal) {
        reject(Object.assign(new Error("killed"), { code: "KILLED" }));
      } else {
        resolvePromise(parse(stderr, options.all ? undefined : file, root));
      }
    });
  });
  return { promise, kill: () => child && child.kill() };
}

module.exports = { parse, run };
