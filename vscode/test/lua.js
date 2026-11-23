// Runs Lua code in the Neovim plugin and returns what it prints as JSON:
// the reference the JS ports are checked against.
"use strict";

const { spawnSync } = require("child_process");
const path = require("path");

const repo = path.join(__dirname, "..", "..");
const hasNvim = spawnSync("sh", ["-c", "command -v nvim"]).status === 0;

function lua(code) {
  const script = `package.path = ${JSON.stringify(repo + "/lua/?.lua;" + repo + "/lua/?/init.lua;")} .. package.path
vim.opt.runtimepath:prepend(${JSON.stringify(repo)})
local ok, result = pcall(function() ${code} end)
if not ok then io.stderr:write(tostring(result)) os.exit(1) end
io.stdout:write(vim.json.encode(result))`;
  const result = spawnSync("nvim", ["--clean", "--headless", "-u", "NONE", "-l", "-"], {
    input: script, encoding: "utf8", env: { ...process.env, XDG_DATA_HOME: path.join(require("os").tmpdir(), "epitech-vscode-test") },
  });
  if (result.status !== 0) {
    throw new Error(result.stderr || result.stdout);
  }
  return JSON.parse(result.stdout);
}

module.exports = { lua, hasNvim, repo };
