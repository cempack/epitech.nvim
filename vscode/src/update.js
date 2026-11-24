// Updates of the extension itself: the latest release of cempack/epitech.nvim
// tagged vscode-v<version> holds epitech.vsix. epitech-toolkit installs
// that weekly (epitech-upgrade); an extension installed by hand checks for
// itself and installs the new .vsix when asked.
"use strict";

const fs = require("fs");
const os = require("os");
const path = require("path");

const LATEST = "https://api.github.com/repos/cempack/epitech.nvim/releases/latest";
const PAGE = "https://github.com/cempack/epitech.nvim/releases/latest";
const DIRECT = "https://github.com/cempack/epitech.nvim/releases/latest/download/epitech.vsix";

// Tests replace it.
let fetchImpl = (...args) => fetch(...args);
const setFetch = (fn) => {
  fetchImpl = fn;
};

// Whether version a is newer than b (x.y.z).
function newer(a, b) {
  const pa = String(a).split(".").map(Number);
  const pb = String(b).split(".").map(Number);
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
    const x = pa[i] || 0;
    const y = pb[i] || 0;
    if (x !== y) {
      return x > y;
    }
  }
  return false;
}

// { version, url } from GitHub's latest-release JSON, or undefined.
function parseRelease(json) {
  const match = String(json.tag_name || "").match(/^vscode-v(\d+(?:\.\d+)*)$/);
  if (!match) {
    return undefined;
  }
  const asset = (json.assets || []).find((item) => item.name === "epitech.vsix");
  return { version: match[1], url: asset ? asset.browser_download_url : DIRECT };
}

async function latest() {
  const response = await fetchImpl(LATEST, { headers: { Accept: "application/vnd.github+json" } });
  if (!response.ok) {
    throw new Error(`GitHub answered ${response.status}`);
  }
  return parseRelease(await response.json());
}

// Downloads the .vsix into a temporary file and returns its path.
async function download(url) {
  const response = await fetchImpl(url);
  if (!response.ok) {
    throw new Error(`download failed (${response.status})`);
  }
  const file = path.join(fs.mkdtempSync(path.join(os.tmpdir(), "epitech-vsix-")), "epitech.vsix");
  fs.writeFileSync(file, Buffer.from(await response.arrayBuffer()));
  return file;
}

// Whether epitech-toolkit manages this machine (its updater is installed).
function managedByDump(home = os.homedir()) {
  return fs.existsSync(path.join(home, ".local", "bin", "epitech-upgrade"));
}

module.exports = { LATEST, PAGE, newer, parseRelease, latest, download, managedByDump, setFetch };
