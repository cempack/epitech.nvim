// Ignored files and projects, like lua/epitech/ignore.lua: an ignored file
// gets no Banana report, hint, meter or Makefile check (formatting and
// fixes still work). Stored per machine, keyed by project root, in a
// Memento (VS Code's globalState), never in the student's repository.
"use strict";

const path = require("path");

const KEY = "epitech.ignored";

function create(memento) {
  const read = () => memento.get(KEY, {});
  return {
    ignored(root, file) {
      const entry = read()[root];
      if (!entry) {
        return false;
      }
      return entry.project === true || (file !== undefined && (entry.files || []).includes(path.relative(root, file)));
    },
    async set(root, file, ignore) {
      const all = { ...read() };
      const entry = { project: false, files: [], ...(all[root] || {}) };
      if (file === undefined) {
        entry.project = ignore;
      } else {
        const relative = path.relative(root, file);
        entry.files = entry.files.filter((name) => name !== relative);
        if (ignore) {
          entry.files.push(relative);
        }
      }
      all[root] = entry;
      await memento.update(KEY, all);
    },
  };
}

module.exports = { create };
