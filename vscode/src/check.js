// The whole-project check, as in lua/epitech/check.lua: Banana on every
// tracked .c and .h, the hints, the Makefile checks and the repository rules
// (C-O1, C-O2, C-O4), in entries { file (absolute), line, column, level,
// code, message } with 0-based positions.
"use strict";

const fs = require("fs");
const os = require("os");
const path = require("path");
const banana = require("./banana");
const hints = require("./hints");
const makefile = require("./makefile");
const project = require("./project");
const staticHint = require("./hints/static");
const ts = require("./ts");

const UNWANTED = ["*.o", "*.a", "*.so", "*~", "#*#", "vgcore.*", "*.gcda", "*.gcno"];
const FOREIGN = ["cpp", "cc", "cxx", "hpp", "hh", "inl", "inc"];
const NAME_EXCEPTIONS = ["Makefile", "README.md", "LICENSE"];
const RANK = { fatal: 1, major: 2, minor: 3, info: 4, hint: 5 };

const globMatch = (pattern, name) => new RegExp(`^${pattern.replace(/[.+^${}()|[\]\\?]/g, "\\$&")
  .replace(/\*/g, ".*")}$`).test(name);

function unwantedPattern(file) {
  return UNWANTED.find((pattern) => globMatch(pattern, path.basename(file)));
}

// Repository entries for the tracked files (relative paths): C-O1, C-O2, C-O4.
function repository(files) {
  const result = [];
  const entry = (file, level, code, message) => ({ file, line: 0, column: 0, level, code, message });
  for (const file of files) {
    const unwanted = unwantedPattern(file);
    const extension = (file.match(/\.([^./]+)$/) || [])[1];
    if (unwanted) {
      result.push(entry(file, "major", "C-O1", "compiled or temporary file in the repository"));
    } else if (extension && FOREIGN.includes(extension)) {
      result.push(entry(file, "major", "C-O2", "C sources use the .c and .h extensions"));
    }
    if (!unwanted) {
      const segments = file.split("/");
      for (let i = 0; i < segments.length; i++) {
        const segment = segments[i];
        const last = i === segments.length - 1;
        if (segment.startsWith(".") || (last && NAME_EXCEPTIONS.includes(segment))) {
          break;
        }
        const name = last ? segment.replace(/\.[^.]+$/, "") : segment;
        if (!/^[a-z0-9_]+$/.test(name)) {
          result.push(entry(file, "minor", "C-O4", `${last ? path.basename(file) : segment + "/"} isn't snake_case`));
          break;
        }
      }
    }
  }
  return result;
}

function sort(entries) {
  return entries.sort((a, b) => RANK[a.level] - RANK[b.level] || a.file.localeCompare(b.file)
    || a.line - b.line || a.column - b.column);
}

function title(entries) {
  const counts = { fatal: 0, major: 0, minor: 0, info: 0, hint: 0 };
  entries.forEach((entry) => counts[entry.level]++);
  return { counts, text: `${counts.fatal} fatal · ${counts.major} major · ${counts.minor} minor · ${counts.info} info`
    + ` · ${counts.hint} hints` };
}

// Runs the check on the project at root. options: { cmd, args, hints
// (true/false), hintOptions, limit, progress(done, total) }. Resolves to
// { entries, counts, text, bananaMissing }.
async function run(root, options = {}) {
  const tracked = project.files(root, []) || [];
  const sources = tracked.filter((file) => /\.[ch]$/.test(file));
  const entries = repository(tracked).map((entry) => ({ ...entry, file: path.join(root, entry.file) }));
  let bananaMissing = false;
  let done = 0;
  const queue = sources.slice();
  const bananaByFile = new Map();
  const worker = async () => {
    while (queue.length > 0) {
      const file = path.join(root, queue.shift());
      try {
        const found = await banana.run(file, { root, cmd: options.cmd, args: options.args, all: true }).promise;
        for (const entry of found) {
          if (entry.path.startsWith(root + path.sep)) {
            const key = `${entry.path}|${entry.line}|${entry.column}|${entry.code}`;
            if (!bananaByFile.has(key)) {
              bananaByFile.set(key, { file: entry.path, line: entry.line, column: entry.column, level: entry.level,
                code: entry.code, message: entry.message, source: "Banana" });
            }
          }
        }
      } catch (error) {
        if (error.code === "ENOENT") {
          bananaMissing = true;
          queue.length = 0;
        }
      }
      done++;
      if (options.progress) {
        options.progress(done, sources.length);
      }
    }
  };
  await Promise.all(Array.from({ length: Math.min(options.limit || os.cpus().length, 8) }, worker));
  const bananaEntries = [...bananaByFile.values()];
  entries.push(...bananaEntries);
  if (options.hints !== false) {
    for (const relative of sources) {
      const file = path.join(root, relative);
      const source = fs.readFileSync(file, "utf8");
      const names = /\.c$/.test(file)
        ? ts.withTree(source, (tree) => staticHint.candidates(tree).map((fn) => fn.name)) : [];
      const used = names.length > 0 ? await staticHint.usedElsewhere(root, file, names) : undefined;
      const fileHints = hints.dedup(hints.collect(source, file, { root, staticUsed: used,
        options: options.hintOptions }), bananaEntries.filter((entry) => entry.file === file));
      for (const hint of fileHints) {
        entries.push({ file, line: hint.line, column: hint.column, level: "hint", code: hint.code,
          message: hint.message.replace(/^C-[A-Z]\d+ /, ""), source: "epitech" });
      }
    }
  }
  for (const relative of tracked.filter((file) => path.basename(file) === "Makefile")) {
    const file = path.join(root, relative);
    for (const entry of makefile.check(fs.readFileSync(file, "utf8"))) {
      entries.push({ file, line: entry.line, column: entry.column, level: entry.level, code: entry.code,
        message: entry.message.replace(/^C-[A-Z]\d+ /, ""), source: "epitech" });
    }
  }
  sort(entries);
  return { entries, ...title(entries), bananaMissing };
}

module.exports = { UNWANTED, unwantedPattern, repository, sort, title, run };
