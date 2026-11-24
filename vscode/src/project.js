// Project facts, as in lua/epitech/project.lua: the root (the nearest
// Makefile directory, climbing past sub-builds like lib/my, inside the git
// repository), its name, its tracked files and the include flags epiclang
// and clangd need.
"use strict";

const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");
const { existingHeader } = require("./header");

const isFile = (file) => {
  try {
    return fs.statSync(file).isFile();
  } catch {
    return false;
  }
};
const isDir = (dir) => {
  try {
    return fs.statSync(dir).isDirectory();
  } catch {
    return false;
  }
};
const readLines = (file, count) => {
  try {
    const lines = fs.readFileSync(file, "utf8").split("\n");
    return count ? lines.slice(0, count) : lines;
  } catch {
    return [];
  }
};

// The nearest directory from `start` (a directory) up holding `marker`.
function findUp(start, marker) {
  let dir = path.resolve(start);
  for (;;) {
    if (fs.existsSync(path.join(dir, marker))) {
      return dir;
    }
    const parent = path.dirname(dir);
    if (parent === dir) {
      return undefined;
    }
    dir = parent;
  }
}

const inside = (dir, parent) => dir === parent || dir.startsWith(parent + path.sep);

// Whether the Makefile in dir is a sub-build of the project in parent.
function subBuild(dir, parent) {
  const relative = path.relative(parent, dir);
  if (/^libs?\//.test(relative + "/") || /\/libs?\//.test("/" + relative + "/")) {
    return true;
  }
  if (readLines(path.join(dir, "Makefile"), 200).some((line) => /^\s*NAME\s*:?=\s*lib[\w]*\.a\s*$/.test(line))) {
    return true;
  }
  return readLines(path.join(parent, "Makefile"), 500).some((line) => {
    let from = 0;
    for (;;) {
      const at = line.indexOf(relative, from);
      if (at < 0) {
        return false;
      }
      const before = line.charAt(at - 1);
      const after = line.charAt(at + relative.length);
      if (!/\w/.test(before) && !/\w/.test(after)) {
        return true;
      }
      from = at + relative.length;
    }
  });
}

// The project root of a file.
function root(file) {
  const start = isDir(file) ? file : path.dirname(path.resolve(file));
  const git = findUp(start, ".git");
  let make = findUp(start, "Makefile");
  if (make && (!git || inside(make, git))) {
    while (make !== git) {
      const parent = findUp(path.dirname(make), "Makefile");
      if (!parent || (git && !inside(parent, git)) || !subBuild(make, parent)) {
        break;
      }
      make = parent;
    }
    return make;
  }
  return git || start;
}

// Files under root matching the git pathspecs, relative to root and sorted,
// or undefined outside git.
function files(dir, pathspecs, options = {}) {
  if (!isDir(dir)) {
    return undefined;
  }
  const args = ["ls-files"];
  if (options.untracked) {
    args.push("--cached", "--others", "--exclude-standard");
  }
  args.push("--", ...(pathspecs || []));
  const result = spawnSync("git", args, { cwd: dir, encoding: "utf8" });
  if (result.status !== 0) {
    return undefined;
  }
  return result.stdout.split("\n").filter(Boolean).sort();
}

// NAME from the Makefile, else an Epitech header's project line, else the
// directory name.
function name(dir) {
  const makefile = path.join(dir, "Makefile");
  if (isFile(makefile)) {
    const lines = readLines(makefile);
    for (const line of lines) {
      const match = line.replace(/\s*#.*$/, "").match(/^\s*NAME\s*[:?]?=\s*(\S+)\s*$/);
      if (match && !match[1].includes("$")) {
        return match[1];
      }
    }
    const header = existingHeader(lines.slice(0, 8));
    if (header && header.project) {
      return header.project;
    }
  }
  const sources = files(dir, ["*.c", "*.h"]) || [];
  for (const source of sources.slice(0, 20)) {
    const header = existingHeader(readLines(path.join(dir, source), 8));
    if (header && header.project) {
      return header.project;
    }
  }
  return path.basename(dir);
}

// Splits a shell command line into words.
function shellWords(command) {
  const words = [];
  let word;
  let quote;
  for (let i = 0; i < command.length; i++) {
    const c = command[i];
    if (quote) {
      if (c === quote) {
        quote = undefined;
      } else if (c === "\\" && quote === '"' && i < command.length - 1) {
        word += command[++i];
      } else {
        word += c;
      }
    } else if (c === "'" || c === '"') {
      quote = c;
      word = word || "";
    } else if (c === "\\" && i < command.length - 1) {
      word = (word || "") + command[++i];
    } else if (/\s/.test(c)) {
      if (word !== undefined) {
        words.push(word);
        word = undefined;
      }
    } else {
      word = (word || "") + c;
    }
  }
  if (word !== undefined) {
    words.push(word);
  }
  return words;
}

function readDatabase(dir) {
  for (const file of [path.join(dir, "compile_commands.json"), path.join(dir, "build", "compile_commands.json")]) {
    if (isFile(file)) {
      try {
        const entries = JSON.parse(fs.readFileSync(file, "utf8"));
        if (Array.isArray(entries)) {
          return entries;
        }
      } catch {
        // An unreadable database is as good as none.
      }
    }
  }
  return undefined;
}

function entryFlags(entry) {
  const args = entry.arguments || shellWords(entry.command || "");
  const directory = entry.directory || ".";
  const absolute = (value) => (value.startsWith("/") ? value : path.normalize(path.join(directory, value)));
  const flags = [];
  for (let i = 1; i < args.length; i++) {
    const arg = args[i];
    if ((arg === "-I" || arg === "-isystem" || arg === "-D") && args[i + 1] !== undefined) {
      if (arg === "-I") {
        flags.push("-I" + absolute(args[i + 1]));
      } else if (arg === "-isystem") {
        flags.push("-isystem", absolute(args[i + 1]));
      } else {
        flags.push("-D" + args[i + 1]);
      }
      i++;
    } else if (arg === "-o") {
      i++;
    } else if (arg.startsWith("-isystem")) {
      flags.push("-isystem", absolute(arg.slice(8)));
    } else if (arg.startsWith("-I")) {
      flags.push("-I" + absolute(arg.slice(2)));
    } else if (arg.startsWith("-D") || arg.startsWith("-std=")) {
      flags.push(arg);
    }
  }
  return flags;
}

// The flags epiclang needs to resolve the project's includes for file.
function includeFlags(dir, file) {
  const entries = readDatabase(dir);
  if (entries && entries.length > 0) {
    const target = file && path.resolve(file);
    const chosen = entries.find((entry) => entry.file
      && path.resolve(entry.directory || dir, entry.file) === target) || entries[0];
    return entryFlags(chosen);
  }
  const flags = [];
  if (isDir(path.join(dir, "include"))) {
    flags.push("-I" + path.join(dir, "include"));
  }
  flags.push("-I" + dir);
  return flags;
}

// The -I directories the build really passes for file.
function buildIncludeDirs(dir, file) {
  const dirs = [];
  const add = (value) => {
    const absolute = path.normalize(value.startsWith("/") ? value : path.join(dir, value)).replace(/\/$/, "");
    if (!dirs.includes(absolute)) {
      dirs.push(absolute);
    }
  };
  const entries = readDatabase(dir);
  if (entries && entries.length > 0) {
    for (const flag of includeFlags(dir, file)) {
      if (flag.startsWith("-I")) {
        add(flag.slice(2));
      }
    }
    return dirs;
  }
  for (const line of readLines(path.join(dir, "Makefile"))) {
    for (const match of line.replace(/#.*$/, "").matchAll(/-I\s*([^\s$()]+)/g)) {
      add(match[1]);
    }
  }
  return dirs;
}

// The projects under folder: directories holding a Makefile that are their
// own root (a lib/my is part of its project), sorted, at most 4 levels down.
function projects(folder, depth = 4) {
  const found = [];
  const walk = (dir, level) => {
    if (fs.existsSync(path.join(dir, "Makefile")) && root(dir) === dir) {
      found.push(dir);
    }
    if (level >= depth) {
      return;
    }
    let entries = [];
    try {
      entries = fs.readdirSync(dir, { withFileTypes: true });
    } catch {
      return;
    }
    for (const entry of entries) {
      if (entry.isDirectory() && !entry.name.startsWith(".") && entry.name !== "node_modules") {
        walk(path.join(dir, entry.name), level + 1);
      }
    }
  };
  walk(path.resolve(folder), 0);
  return found.sort();
}

module.exports = { root, projects, files, name, includeFlags, buildIncludeDirs, shellWords, readDatabase };
