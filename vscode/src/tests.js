// Criterion tests, as in lua/epitech/tests.lua: finding the Test(suite,
// name) blocks of tests/*.c, reading Criterion's output, and gcovr's
// coverage.
"use strict";

const fs = require("fs");
const path = require("path");

// The tests declared in a source: { suite, name, line } (0-based line).
function discover(source) {
  const result = [];
  source.split("\n").forEach((line, row) => {
    const match = line.match(/^\s*(?:Test|ParameterizedTest|Theory)\s*\(\s*([A-Za-z_]\w*)\s*,\s*([A-Za-z_]\w*)/);
    if (match) {
      result.push({ suite: match[1], name: match[2], line: row });
    }
  });
  return result;
}

const stripColors = (line) => line.replace(/\x1b\[[\d;]*m/g, "");

// Criterion's output: { failures: [{ test ("suite::name"), file, line,
// message }], synthesis: { tested, passing, failing, crashing } }.
function parse(output, root) {
  const failures = [];
  let pending = [];
  let synthesis;
  for (const raw of output.split("\n")) {
    const line = stripColors(raw);
    const located = line.match(/^\[----\] ([^:\s][^:]*):(\d+): (.*)$/);
    const detail = !located && line.match(/^\[----\]\s+(.*?)\s*$/);
    const failed = line.match(/^\[FAIL\] ([^:]+)::(\S+): (.*)$/);
    const counts = line.match(/^\[====\] Synthesis: (.*?)\s*$/);
    if (located) {
      pending.push({ file: located[1], line: Number(located[2]), headline: located[3], details: [] });
    } else if (detail && detail[1] !== "" && pending.length > 0) {
      pending[pending.length - 1].details.push(detail[1]);
    } else if (failed) {
      const test = `${failed[1]}::${failed[2]}`;
      const status = failed[3].replace(/\(\d+\.\d+s\)/, "").trim();
      if (pending.length === 0) {
        failures.push({ test, message: status || "failed" });
      }
      for (const entry of pending) {
        const message = status === "CRASH!" ? "crashed below this line"
          : entry.details.length > 0 ? entry.details.join(" ") : entry.headline;
        failures.push({ test, file: path.isAbsolute(entry.file) ? entry.file : path.join(root, entry.file),
          line: entry.line, message });
      }
      pending = [];
    } else if (counts) {
      synthesis = {};
      for (const [, key, value] of counts[1].matchAll(/([A-Za-z]+): (\d+)/g)) {
        synthesis[key.toLowerCase()] = Number(value);
      }
    }
  }
  return { failures, synthesis };
}

// gcovr's JSON report, test files left out: { files: { path: { hit, missed
// (1-based line numbers) } }, lines, covered }.
function parseCoverage(json, root) {
  let report;
  try {
    report = JSON.parse(json);
  } catch {
    return undefined;
  }
  const files = {};
  let lines = 0;
  let covered = 0;
  for (const entry of report.files || []) {
    const file = path.normalize(path.isAbsolute(entry.file) ? entry.file : path.join(root, entry.file));
    if (/^tests?\//.test(path.relative(root, file))) {
      continue;
    }
    const result = { hit: [], missed: [] };
    for (const line of entry.lines || []) {
      if (!line["gcovr/noncode"]) {
        lines++;
        if ((line.count || 0) > 0) {
          covered++;
          result.hit.push(line.line_number);
        } else {
          result.missed.push(line.line_number);
        }
      }
    }
    files[file] = result;
  }
  return { files, lines, covered };
}

// The Makefile's rule names.
function targets(root) {
  let text;
  try {
    text = fs.readFileSync(path.join(root, "Makefile"), "utf8");
  } catch {
    return [];
  }
  const result = [];
  for (const line of text.split("\n")) {
    const match = line.match(/^([A-Za-z0-9_.-]+)\s*:(?!=)/);
    if (match && !match[1].startsWith(".") && !result.includes(match[1])) {
      result.push(match[1]);
    }
  }
  return result;
}

module.exports = { discover, parse, parseCoverage, targets };
