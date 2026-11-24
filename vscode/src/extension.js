// The VS Code side: wires the modules ported from the Neovim plugin (format,
// banana, budget, hints, fixes, check, scaffold, tests…) to VS Code's APIs.
// Everything Epitech-specific lives in those modules, which have no VS Code
// dependency and are tested with plain node against the plugin's Lua code.
"use strict";

const vscode = require("vscode");
const fs = require("fs");
const path = require("path");
const { spawn } = require("child_process");
const parser = require("./parser");
const data = require("./data");
const format = require("./format");
const banana = require("./banana");
const budget = require("./budget");
const check = require("./check");
const fixes = require("./fixes");
const { apply } = require("./fixes/edits");
const macro = require("./fixes/macro");
const makefileFixes = require("./fixes/makefile");
const header = require("./header");
const hints = require("./hints");
const staticHint = require("./hints/static");
const ignore = require("./ignore");
const makefile = require("./makefile");
const project = require("./project");
const rules = require("./rules");
const scaffold = require("./scaffold");
const tests = require("./tests");
const ts = require("./ts");
const update = require("./update");

const C_FILES = [{ scheme: "file", pattern: "**/*.{c,h}" }, { language: "c" }];
const MAKEFILES = [{ scheme: "file", pattern: "**/Makefile" }, { language: "makefile" }];
const isC = (document) => document.uri.scheme === "file" && /\.[ch]$/.test(document.fileName);
const isMakefile = (document) => document.uri.scheme === "file" && path.basename(document.fileName) === "Makefile";
const config = () => vscode.workspace.getConfiguration("epitech");
const codeOf = (diagnostic) => (typeof diagnostic.code === "object" ? diagnostic.code.value : diagnostic.code);

let output;
let ignored;
const log = (message) => output && output.appendLine(message);

function formatOptions() {
  return { styleFile: data.styleFile, clangFormat: config().get("format.clangFormat") };
}

function scaffoldOptions() {
  const settings = config();
  return {
    cc: settings.get("scaffold.cc"),
    cflags: settings.get("scaffold.cflags"),
    debug_cflags: settings.get("scaffold.debugCflags"),
    error_file: settings.get("scaffold.errorFile"),
  };
}

function hintOptions() {
  const settings = config();
  return {
    magic_numbers: { enabled: settings.get("hints.magicNumbers"), allow: settings.get("hints.magicNumbersAllow") },
    static: settings.get("hints.static"),
    types: settings.get("hints.types"),
    naming: { enabled: settings.get("hints.naming") },
  };
}

const position = (point) => new vscode.Position(point.line, point.character);
const toRange = (edit) => new vscode.Range(position(edit.start), position(edit.end));

function isIgnored(document) {
  if (document.uri.scheme !== "file") {
    return true;
  }
  return ignored.ignored(project.root(document.fileName), document.fileName);
}

// Diagnostics ---------------------------------------------------------------

const SEVERITY = {
  fatal: vscode.DiagnosticSeverity.Error,
  major: vscode.DiagnosticSeverity.Error,
  minor: vscode.DiagnosticSeverity.Warning,
  info: vscode.DiagnosticSeverity.Information,
};

function hintSeverity() {
  return { information: vscode.DiagnosticSeverity.Information, warning: vscode.DiagnosticSeverity.Warning }[
    config().get("hints.severity")] ?? vscode.DiagnosticSeverity.Hint;
}

// A diagnostic whose code links to the rule's explanation.
function makeDiagnostic(range, message, severity, code, source) {
  const diagnostic = new vscode.Diagnostic(range, message, severity);
  diagnostic.source = source;
  diagnostic.code = rules.byCode[code]
    ? { value: code, target: vscode.Uri.parse(`command:epitech.explainRule?${encodeURIComponent(JSON.stringify([code]))}`) }
    : code;
  return diagnostic;
}

function bananaDiagnostic(entry, document) {
  const valid = document && entry.line < document.lineCount;
  const range = valid
    ? new vscode.Range(entry.line, entry.column, entry.line, document.lineAt(entry.line).text.length)
    : new vscode.Range(Math.max(entry.line, 0), entry.column, Math.max(entry.line, 0), entry.column + 1);
  return makeDiagnostic(range, entry.message, SEVERITY[entry.level], entry.code, "Banana");
}

// Banana on open and save, the hints and Makefile checks as you type.
function createDiagnostics(context) {
  const bananaCollection = vscode.languages.createDiagnosticCollection("banana");
  const hintCollection = vscode.languages.createDiagnosticCollection("epitech");
  context.subscriptions.push(bananaCollection, hintCollection);
  const jobs = new Map();
  const staticUsed = new Map();
  const timers = new Map();
  let warned = false;

  function bananaEntries(document) {
    return (bananaCollection.get(document.uri) || []).map((diagnostic) => ({ line: diagnostic.range.start.line,
      code: codeOf(diagnostic) }));
  }

  function refreshHints(document) {
    if (isIgnored(document)) {
      hintCollection.delete(document.uri);
      return;
    }
    if (isMakefile(document)) {
      if (!config().get("makefile.enabled")) {
        hintCollection.delete(document.uri);
        return;
      }
      hintCollection.set(document.uri, makefile.check(document.getText()).map((entry) =>
        makeDiagnostic(new vscode.Range(entry.line, entry.column, entry.endLine, entry.endColumn),
          entry.message, SEVERITY[entry.level], entry.code, "epitech")));
      return;
    }
    if (!isC(document)) {
      return;
    }
    if (!config().get("hints.enabled")) {
      hintCollection.delete(document.uri);
      return;
    }
    const source = document.getText();
    let list;
    try {
      const root = project.root(document.fileName);
      list = hints.collect(source, document.fileName, { root, staticUsed: staticUsed.get(document.fileName),
        options: hintOptions() });
      list = hints.dedup(list, bananaEntries(document)).concat(fixes.hints(source, { file: document.fileName }));
    } catch (error) {
      log(`hints: ${error.message}`);
      return;
    }
    const severity = hintSeverity();
    hintCollection.set(document.uri, list.map((hint) => makeDiagnostic(
      new vscode.Range(hint.line, hint.column, hint.endLine, hint.endColumn), hint.message, severity, hint.code,
      "epitech")));
  }

  function schedule(document, delay = 250) {
    const key = document.uri.toString();
    clearTimeout(timers.get(key));
    timers.set(key, setTimeout(() => refreshHints(document), delay));
  }

  async function searchStatic(document) {
    if (!isC(document) || !/\.c$/.test(document.fileName) || !config().get("hints.static")) {
      return;
    }
    const root = project.root(document.fileName);
    const names = ts.withTree(document.getText(), (tree) => staticHint.candidates(tree).map((fn) => fn.name));
    staticUsed.set(document.fileName, await staticHint.usedElsewhere(root, document.fileName, names));
    refreshHints(document);
  }

  async function runBanana(document) {
    if (!isC(document)) {
      return;
    }
    if (!config().get("diagnostics.enabled") || isIgnored(document)) {
      bananaCollection.delete(document.uri);
      return;
    }
    const file = document.fileName;
    if (jobs.has(file)) {
      jobs.get(file).kill();
    }
    const settings = config();
    const job = banana.run(file, { cmd: settings.get("diagnostics.command"), args: settings.get("diagnostics.args") });
    jobs.set(file, job);
    try {
      const entries = await job.promise;
      if (jobs.get(file) === job) {
        bananaCollection.set(document.uri, entries.map((entry) => bananaDiagnostic(entry, document)));
        refreshHints(document);
      }
    } catch (error) {
      if (error.code === "ENOENT" && !warned) {
        warned = true;
        const choice = await vscode.window.showWarningMessage(`${settings.get("diagnostics.command")} not found: `
          + "Banana's reports are off. epitech-dump-arch installs it on Arch and Ubuntu.", "How to install");
        if (choice) {
          vscode.commands.executeCommand("workbench.action.openWalkthrough", "cempack.epitech#epitech.start", false);
        }
      } else if (error.code !== "ENOENT" && error.code !== "KILLED") {
        log(`Banana: ${error.message}`);
      }
    } finally {
      if (jobs.get(file) === job) {
        jobs.delete(file);
      }
    }
  }

  function opened(document) {
    runBanana(document);
    searchStatic(document);
    refreshHints(document);
  }

  return {
    bananaCollection,
    hintCollection,
    opened,
    saved(document) {
      runBanana(document);
      searchStatic(document);
    },
    changed: schedule,
    staticUsedFor: (file) => staticUsed.get(file),
    closed(document) {
      bananaCollection.delete(document.uri);
      hintCollection.delete(document.uri);
      staticUsed.delete(document.fileName);
    },
    refreshAll() {
      vscode.workspace.textDocuments.forEach(opened);
    },
  };
}

// Formatting ----------------------------------------------------------------

function formattingProvider() {
  return {
    provideDocumentFormattingEdits(document) {
      if (!config().get("format.enabled") || !isC(document)) {
        return [];
      }
      try {
        const text = document.getText();
        const formatted = format.formatText(text, formatOptions());
        if (formatted === text.replace(/\r\n/g, "\n")) {
          return [];
        }
        const all = new vscode.Range(document.positionAt(0), document.positionAt(text.length));
        return [vscode.TextEdit.replace(all, formatted)];
      } catch (error) {
        vscode.window.showErrorMessage(`Epitech formatter: ${error.message}`, "Check the setup").then((choice) => {
          if (choice) {
            vscode.commands.executeCommand("workbench.action.openWalkthrough", "cempack.epitech#epitech.start", false);
          }
        });
        return [];
      }
    },
  };
}

// Code actions ----------------------------------------------------------------

function toWorkspaceEdit(document, action) {
  const edit = new vscode.WorkspaceEdit();
  for (const change of action.edits) {
    edit.replace(document.uri, toRange(change), change.newText);
  }
  for (const [file, changes] of Object.entries(action.otherFiles || {})) {
    for (const change of changes) {
      edit.replace(vscode.Uri.file(file), toRange(change), change.newText);
    }
  }
  return edit;
}

function codeActionProvider(diagnostics) {
  return {
    provideCodeActions(document, range, context) {
      const result = [];
      if (isC(document)) {
        let found = [];
        try {
          found = fixes.actions(document.getText(), { start: range.start.line, end: range.end.line }, {
            file: document.fileName, projectRoot: project.root(document.fileName), formatOptions: formatOptions(),
            staticUsed: diagnostics.staticUsedFor(document.fileName),
          });
        } catch (error) {
          log(`fixes: ${error.message}`);
        }
        for (const found_ of found) {
          const kind = found_.kind === "refactor.rewrite" ? vscode.CodeActionKind.RefactorRewrite
            : vscode.CodeActionKind.QuickFix;
          const action = new vscode.CodeAction(found_.title, kind);
          if (found_.command) {
            action.command = { title: found_.title, command: found_.command.name,
              arguments: [document.uri, ...found_.command.arguments] };
          } else {
            action.edit = toWorkspaceEdit(document, found_);
          }
          action.diagnostics = context.diagnostics.filter((diagnostic) => codeOf(diagnostic) === found_.rule);
          action.isPreferred = action.diagnostics.length > 0;
          result.push(action);
        }
      } else if (isMakefile(document)) {
        for (const found_ of makefileFixes.actions(document.getText(), { start: range.start.line, end: range.end.line })) {
          const action = new vscode.CodeAction(found_.title, vscode.CodeActionKind.QuickFix);
          action.edit = toWorkspaceEdit(document, found_);
          result.push(action);
        }
        if (range.start.line === 0 && !header.existingHeader(document.getText().split(/\r?\n/).slice(0, 8))) {
          const action = new vscode.CodeAction("Add the Epitech header (C-G1)", vscode.CodeActionKind.QuickFix);
          action.command = { title: action.title, command: "epitech.insertHeader" };
          result.push(action);
        }
      }
      // Every rule-coded diagnostic can be explained.
      const explained = new Set();
      for (const diagnostic of context.diagnostics) {
        const code = codeOf(diagnostic);
        if (rules.byCode[code] && !explained.has(code)) {
          explained.add(code);
          const action = new vscode.CodeAction(`Explain ${code}: ${rules.byCode[code].title}`,
            vscode.CodeActionKind.Empty);
          action.command = { title: action.title, command: "epitech.explainRule", arguments: [code] };
          result.push(action);
        }
      }
      return result;
    },
  };
}

// The number under a C-G9 hint into a macro in the project header.
async function extractMacro(uri, row, column, text) {
  const document = await vscode.workspace.openTextDocument(uri);
  const editor = await vscode.window.showTextDocument(document);
  const root = project.root(document.fileName);
  const headerFile = await projectHeader(root);
  if (!headerFile) {
    return;
  }
  let name;
  let define = true;
  let target = headerFile;
  const existing = macro.existing(root, text);
  if (existing.length > 0) {
    const picked = await vscode.window.showQuickPick([...existing.map((item) => ({ label: item.name,
      description: path.relative(root, item.file), item })), { label: "$(add) New macro…" }],
    { placeHolder: `Name ${text}` });
    if (!picked) {
      return;
    }
    if (picked.item) {
      name = picked.item.name;
      define = false;
      target = picked.item.file;
    }
  }
  if (!name) {
    const suggestion = ts.withTree(document.getText(), (tree) => macro.suggest(tree, row, column));
    name = await vscode.window.showInputBox({ prompt: `Macro name for ${text}`, value: suggestion,
      validateInput: (value) => (macro.isMacroName(value) ? undefined : "UPPER_SNAKE_CASE (C-V1)") });
    if (!name) {
      return;
    }
    const value = macro.definedValue(root, name);
    if (value !== undefined && value !== text) {
      vscode.window.showErrorMessage(`${name} is already defined as ${value}`);
      return;
    }
    define = value === undefined;
  }
  const literals = ts.withTree(document.getText(), (tree) => macro.literals(tree, hintOptions().magic_numbers.allow))
    .filter((literal) => literal.text === text);
  let chosen = literals.filter((literal) => literal.start.row === row && literal.start.column === column);
  if (literals.length > 1) {
    const all = `All ${literals.length} occurrences`;
    const scope = await vscode.window.showQuickPick(["This one", all], { placeHolder: `Replace ${text}` });
    if (!scope) {
      return;
    }
    if (scope === all) {
      chosen = literals;
    }
  }
  const edit = new vscode.WorkspaceEdit();
  for (const literal of chosen) {
    edit.replace(uri, new vscode.Range(literal.start.row, literal.start.column, literal.end.row, literal.end.column),
      name);
  }
  if (define) {
    const headerUri = vscode.Uri.file(target);
    let lines;
    try {
      lines = fs.readFileSync(target, "utf8").replace(/\n$/, "").split("\n");
    } catch {
      lines = header.newHeaderFile(target, project.name(root), `Declarations for ${project.name(root)}`,
        String(new Date().getFullYear()));
      edit.createFile(headerUri, { ignoreIfExists: true });
    }
    const next = macro.insertDefine(lines, name, text);
    edit.replace(headerUri, new vscode.Range(0, 0, lines.length, 0), next.join("\n") + "\n");
  }
  if (path.resolve(target) !== path.resolve(document.fileName)) {
    const include = includeName(root, document.fileName, target);
    const lines = document.getText().split("\n");
    if (!lines.some((line) => line.includes(`"${include}"`))) {
      edit.insert(uri, new vscode.Position(includeRow(lines), 0), `#include "${include}"\n`);
    }
  }
  await vscode.workspace.applyEdit(edit);
  void editor;
  vscode.window.showInformationMessage(`${name}: ${chosen.length} ${chosen.length === 1 ? "number" : "numbers"} replaced`);
}

// Where a new #include goes: after the last one, else after the header.
function includeRow(lines) {
  let last = -1;
  lines.forEach((line, i) => {
    if (/^\s*#\s*include/.test(line)) {
      last = i;
    }
  });
  if (last >= 0) {
    return last + 1;
  }
  const existing = header.existingHeader(lines);
  return existing ? existing.start + 7 : 0;
}

// How file includes headerFile: by name through a -I directory, else a path.
function includeName(root, file, headerFile) {
  for (const dir of project.buildIncludeDirs(root, file)) {
    const relative = path.relative(dir, headerFile);
    if (!relative.startsWith("..")) {
      return relative;
    }
  }
  return path.relative(path.dirname(file), headerFile);
}

// The project header: include/<name>.h, the only .h in include/, or asked.
async function projectHeader(root) {
  const name = scaffold.base(project.name(root));
  const preferred = path.join(root, "include", `${name}.h`);
  if (fs.existsSync(preferred)) {
    return preferred;
  }
  const headers = (project.files(root, ["*.h"]) || []).map((file) => path.join(root, file));
  if (headers.length === 1) {
    return headers[0];
  }
  const picked = await vscode.window.showQuickPick([...headers.map((file) => path.relative(root, file)),
    `include/${name}.h (new)`], { placeHolder: "Project header for the macro" });
  if (!picked) {
    return undefined;
  }
  return picked.endsWith(" (new)") ? preferred : path.join(root, picked);
}

// Rules -----------------------------------------------------------------------

const ruleUri = (code) => vscode.Uri.parse(`epitech-rule:${code}.md`);

async function explain(code) {
  if (!code) {
    const editor = vscode.window.activeTextEditor;
    const diagnostic = editor && ruleAt(editor.document, editor.selection.active);
    code = diagnostic && codeOf(diagnostic);
  }
  if (!code) {
    const picked = await vscode.window.showQuickPick(rules.rules.map((rule) => ({
      label: rule.code, description: `${rule.title} · ${rule.severity}`, detail: rule.summary,
    })), { placeHolder: "Coding style rule", matchOnDescription: true, matchOnDetail: true });
    if (!picked) {
      return;
    }
    code = picked.label;
  }
  await vscode.commands.executeCommand("markdown.showPreviewToSide", ruleUri(code));
}

function ruleAt(document, at) {
  return vscode.languages.getDiagnostics(document.uri).find((diagnostic) => diagnostic.range.contains(at)
    && rules.byCode[codeOf(diagnostic)]);
}

// Budgets ---------------------------------------------------------------------

const COLORS = {
  ok: new vscode.ThemeColor("editorCodeLens.foreground"),
  near: new vscode.ThemeColor("editorWarning.foreground"),
  over: new vscode.ThemeColor("editorError.foreground"),
};

function createBudgets(context) {
  const decoration = vscode.window.createTextEditorDecorationType({ after: { margin: "0 0 0 2em", fontStyle: "italic" } });
  const status = vscode.window.createStatusBarItem("epitech.budget", vscode.StatusBarAlignment.Right, 100);
  status.name = "Epitech file budget";
  status.tooltip = "C-O3: at most 10 functions per file, 5 of them non-static";
  context.subscriptions.push(decoration, status);
  let hidden = false;
  const timers = new Map();

  function update(editor) {
    if (!editor) {
      status.hide();
      return;
    }
    const document = editor.document;
    if (!isC(document) || isIgnored(document)) {
      editor.setDecorations(decoration, []);
      if (editor === vscode.window.activeTextEditor) {
        status.hide();
      }
      return;
    }
    const settings = config();
    const show = { functions: settings.get("budget.functions") && !hidden, depth: settings.get("budget.depth") && !hidden };
    let result;
    try {
      result = budget.analyze(document.getText(), budget.DEFAULTS, show);
    } catch (error) {
      log(`budget: ${error.message}`);
      return;
    }
    const decorations = [];
    for (const [row, chunks] of result.rows) {
      if (row >= document.lineCount) {
        continue;
      }
      const end = document.lineAt(row).range.end;
      for (const chunk of chunks) {
        decorations.push({ range: new vscode.Range(end, end),
          renderOptions: { after: { contentText: chunk.text, color: COLORS[chunk.level] } } });
      }
    }
    editor.setDecorations(decoration, decorations);
    if (editor !== vscode.window.activeTextEditor) {
      return;
    }
    const isHeader = document.fileName.endsWith(".h");
    if (settings.get("budget.file") && (!isHeader || result.functions > 0)) {
      const file = budget.fileText(result);
      status.text = (file.level === "ok" ? "$(symbol-function) " : "$(warning) ") + file.text;
      status.color = file.level === "ok" ? undefined : COLORS[file.level];
      status.show();
    } else {
      status.hide();
    }
  }

  function schedule(editor, delay = 150) {
    if (!editor) {
      return update(editor);
    }
    const key = editor.document.uri.toString();
    clearTimeout(timers.get(key));
    timers.set(key, setTimeout(() => update(editor), delay));
    return undefined;
  }

  return {
    update,
    schedule,
    toggle() {
      hidden = !hidden;
      vscode.window.visibleTextEditors.forEach((editor) => update(editor));
    },
  };
}

// The project check and its sidebar -----------------------------------------------

function workspaceRoot() {
  const editor = vscode.window.activeTextEditor;
  if (editor && editor.document.uri.scheme === "file") {
    return project.root(editor.document.fileName);
  }
  const folder = vscode.workspace.workspaceFolders && vscode.workspace.workspaceFolders[0];
  return folder && project.root(folder.uri.fsPath);
}

// The tree in the Epitech sidebar: the last check's entries by rule.
class CheckTree {
  constructor() {
    this.entries = [];
    this.root = undefined;
    this.emitter = new vscode.EventEmitter();
    this.onDidChangeTreeData = this.emitter.event;
  }

  show(root, result) {
    this.root = root;
    this.entries = result.entries;
    this.emitter.fire(undefined);
  }

  getChildren(element) {
    if (!element) {
      const byCode = new Map();
      for (const entry of this.entries) {
        if (!byCode.has(entry.code)) {
          byCode.set(entry.code, []);
        }
        byCode.get(entry.code).push(entry);
      }
      return [...byCode.entries()].map(([code, entries]) => ({ kind: "rule", code, entries }));
    }
    return element.kind === "rule" ? element.entries.map((entry) => ({ kind: "entry", entry })) : [];
  }

  getTreeItem(element) {
    if (element.kind === "rule") {
      const rule = rules.byCode[element.code];
      const item = new vscode.TreeItem(`${element.code} ${rule ? rule.title : ""}`,
        vscode.TreeItemCollapsibleState.Expanded);
      const level = element.entries[0].level;
      item.description = `${element.entries.length} · ${level}`;
      item.iconPath = new vscode.ThemeIcon(level === "fatal" || level === "major" ? "error"
        : level === "minor" ? "warning" : level === "hint" ? "lightbulb" : "info");
      item.contextValue = "rule";
      item.tooltip = rule ? rule.summary : element.code;
      return item;
    }
    const entry = element.entry;
    const relative = this.root ? path.relative(this.root, entry.file) : entry.file;
    const item = new vscode.TreeItem(entry.message, vscode.TreeItemCollapsibleState.None);
    item.description = `${relative}:${entry.line + 1}`;
    item.command = { title: "Open", command: "vscode.open", arguments: [vscode.Uri.file(entry.file),
      { selection: new vscode.Range(entry.line, entry.column, entry.line, entry.column) }] };
    return item;
  }
}

async function checkProject(tree, statusItem, diagnostics) {
  const root = workspaceRoot();
  if (!root) {
    vscode.window.showWarningMessage("Open a project folder first");
    return;
  }
  if (!project.files(root, [])) {
    vscode.window.showWarningMessage(`${path.basename(root)} isn't a git repository: the check covers tracked files`);
    return;
  }
  const settings = config();
  const result = await vscode.window.withProgress({ location: vscode.ProgressLocation.Notification,
    title: "Epitech check", cancellable: false }, (progress) => check.run(root, {
    cmd: settings.get("diagnostics.command"), args: settings.get("diagnostics.args"),
    hints: settings.get("hints.enabled"), hintOptions: hintOptions(),
    progress: (done, total) => progress.report({ message: `${done}/${total} files`, increment: 100 / Math.max(total, 1) }),
  }));
  tree.show(root, result);
  const byFile = new Map();
  for (const entry of result.entries.filter((e) => e.source === "Banana")) {
    if (!byFile.has(entry.file)) {
      byFile.set(entry.file, []);
    }
    const document = vscode.workspace.textDocuments.find((doc) => doc.fileName === entry.file);
    byFile.get(entry.file).push(bananaDiagnostic(entry, document));
  }
  for (const [file, list] of byFile) {
    diagnostics.bananaCollection.set(vscode.Uri.file(file), list);
  }
  const failing = result.counts.fatal + result.counts.major;
  statusItem.text = failing > 0 ? `$(error) ${result.counts.fatal + result.counts.major} major`
    : result.counts.minor > 0 ? `$(warning) ${result.counts.minor} minor` : "$(pass) Epitech";
  statusItem.tooltip = `Epitech check: ${result.text}`;
  statusItem.show();
  if (result.bananaMissing) {
    vscode.window.showWarningMessage(`${settings.get("diagnostics.command")} not found: the check only has the `
      + "repository rules, Makefiles and hints");
  }
  const message = `Epitech check: ${result.text}`;
  (failing > 0 ? vscode.window.showWarningMessage : vscode.window.showInformationMessage)(message, "Show");
  vscode.commands.executeCommand("epitech.checkView.focus");
}

async function untrack() {
  const root = workspaceRoot();
  const files = (project.files(root, []) || []).filter((file) => check.unwantedPattern(file));
  if (files.length === 0) {
    vscode.window.showInformationMessage("No compiled or temporary file is tracked (C-O1)");
    return;
  }
  const choice = await vscode.window.showWarningMessage(`Untrack ${files.length} file${files.length > 1 ? "s" : ""} `
    + `(git rm --cached) and add their patterns to .gitignore?\n${files.join(", ")}`, { modal: true }, "Untrack");
  if (choice !== "Untrack") {
    return;
  }
  await new Promise((resolve) => spawn("git", ["rm", "--cached", "-q", "--", ...files], { cwd: root })
    .on("close", resolve).on("error", resolve));
  const gitignore = path.join(root, ".gitignore");
  const lines = fs.existsSync(gitignore) ? fs.readFileSync(gitignore, "utf8").split("\n").filter(Boolean) : [];
  for (const file of files) {
    const pattern = check.unwantedPattern(file).replace(/^#/, "\\#");
    if (!lines.includes(pattern)) {
      lines.push(pattern);
    }
  }
  fs.writeFileSync(gitignore, lines.join("\n") + "\n");
  vscode.window.showInformationMessage(`Untracked ${files.join(", ")}; .gitignore updated`);
}

// Headers and guards ------------------------------------------------------------

const documentLines = (document) => document.getText().split(/\r?\n/);

async function insertHeader() {
  const editor = vscode.window.activeTextEditor;
  if (!editor) {
    return;
  }
  const document = editor.document;
  const style = header.styleFor(document.languageId)
    || (path.basename(document.fileName) === "Makefile" ? header.styles.make : undefined);
  if (!style) {
    vscode.window.showWarningMessage(`No Epitech header style for ${document.languageId} files`);
    return;
  }
  const lines = documentLines(document);
  const existing = header.existingHeader(lines);
  const year = String(new Date().getFullYear());
  if (existing) {
    if (existing.style.slice(0, 3).join() === style.slice(0, 3).join()) {
      vscode.window.showInformationMessage("This file already has an Epitech header");
      return;
    }
    const choice = await vscode.window.showQuickPick(["Replace", "Keep"], {
      placeHolder: `Replace the header with ${document.languageId} comment syntax?`,
    });
    if (choice === "Replace") {
      await editor.edit((builder) => builder.replace(new vscode.Range(existing.start, 0, existing.start + 6, 0),
        header.headerLines(style, existing.project, existing.description, year).join("\n") + "\n"));
    }
    return;
  }
  const root = document.uri.scheme === "file" ? project.root(document.fileName) : undefined;
  const projectName = await vscode.window.showInputBox({ prompt: "Project name", value: root ? project.name(root) : "" });
  if (projectName === undefined) {
    return;
  }
  const description = await vscode.window.showInputBox({ prompt: "File description" });
  if (description === undefined) {
    return;
  }
  const inserted = header.newHeader(documentLines(document), style, projectName, description, year);
  await editor.edit((builder) => builder.insert(new vscode.Position(inserted.at, 0), inserted.lines.join("\n") + "\n"));
}

async function insertGuard() {
  const editor = vscode.window.activeTextEditor;
  if (!editor || !editor.document.fileName.endsWith(".h")) {
    vscode.window.showWarningMessage("Open a .h file first");
    return;
  }
  const document = editor.document;
  const result = header.guard(documentLines(document), document.fileName);
  const messages = {
    present: "This file already has an include guard",
    "pragma-removed": "Removed #pragma once: the file already has an include guard",
    pragma: "Replaced #pragma once with an include guard",
  };
  if (result.result !== "present") {
    const all = new vscode.Range(document.positionAt(0), document.positionAt(document.getText().length));
    let text = result.lines.join("\n");
    if (!text.endsWith("\n")) {
      text += "\n";
    }
    await editor.edit((builder) => builder.replace(all, text));
  }
  if (messages[result.result]) {
    vscode.window.showInformationMessage(messages[result.result]);
  }
}

async function fixAllVoid() {
  const editor = vscode.window.activeTextEditor;
  if (!editor || !isC(editor.document)) {
    return;
  }
  const document = editor.document;
  const edits = require("./fixes/void").edits(document.getText());
  if (edits.length === 0) {
    vscode.window.showInformationMessage("No empty parameter list here");
    return;
  }
  await editor.edit((builder) => {
    for (const edit of edits) {
      builder.replace(new vscode.Range(edit.start.row, edit.start.column, edit.end.row, edit.end.column), edit.newText);
    }
  });
  vscode.window.showInformationMessage(`${edits.length} function${edits.length > 1 ? "s" : ""} fixed (C-F6)`);
}

// Projects ------------------------------------------------------------------------

async function newProject() {
  const folders = vscode.workspace.workspaceFolders || [];
  let dir = folders.length === 1 ? folders[0].uri.fsPath : undefined;
  if (!dir) {
    const picked = await vscode.window.showOpenDialog({ canSelectFolders: true, canSelectFiles: false,
      openLabel: "Create the project here" });
    if (!picked) {
      return;
    }
    dir = picked[0].fsPath;
  }
  if (fs.existsSync(path.join(dir, "Makefile"))) {
    const choice = await vscode.window.showWarningMessage(`${dir} already has a Makefile. Overwrite the project files?`,
      { modal: true }, "Overwrite");
    if (choice !== "Overwrite") {
      return;
    }
  }
  const name = await vscode.window.showInputBox({
    prompt: "Project name (libsomething.a for a library)", value: path.basename(dir),
    validateInput: (value) => (/^[\w.+-]+$/.test(value) ? undefined : "Letters, digits, _ . + - only"),
  });
  if (!name) {
    return;
  }
  const picked = await vscode.window.showQuickPick(scaffold.LIBRARIES.map((library, index) => ({
    label: library.name, description: library.flags.join(" "), index,
  })), { canPickMany: true, placeHolder: "Libraries to link (none is fine)" });
  if (!picked) {
    return;
  }
  const written = scaffold.create(dir, name, scaffold.libraryFlags(picked.map((item) => item.index)),
    scaffoldOptions(), formatOptions(), true);
  if (!fs.existsSync(path.join(dir, ".git"))) {
    await new Promise((resolve) => spawn("git", ["init", "-q"], { cwd: dir }).on("close", resolve).on("error", resolve));
  }
  vscode.window.showInformationMessage(`Created ${name}: ${written.join(", ")}`);
  const main = ["src/main.c", `src/${scaffold.base(name)}.c`].map((file) => path.join(dir, file)).find(fs.existsSync);
  if (main) {
    await vscode.window.showTextDocument(vscode.Uri.file(main));
  }
}

// The folder new paths are typed from: the active file's project, the
// folder right-clicked in the Explorer, else a project of the workspace
// (asked when it holds several).
async function baseFolder(target) {
  if (target && target.fsPath) {
    return fs.statSync(target.fsPath).isDirectory() ? target.fsPath : path.dirname(target.fsPath);
  }
  const editor = vscode.window.activeTextEditor;
  if (editor && editor.document.uri.scheme === "file") {
    return project.root(editor.document.fileName);
  }
  const folders = (vscode.workspace.workspaceFolders || []).map((folder) => folder.uri.fsPath);
  const found = folders.flatMap((folder) => project.projects(folder));
  if (found.length <= 1) {
    return found[0] || folders[0];
  }
  const picked = await vscode.window.showQuickPick(found.map((dir) => ({ label: path.basename(dir),
    description: dir, dir })), { placeHolder: "Which project?" });
  return picked && picked.dir;
}

async function newFile(target) {
  const base = await baseFolder(target);
  if (!base) {
    vscode.window.showWarningMessage("Open a folder first");
    return;
  }
  const baseRoot = project.root(base);
  const prefix = path.relative(baseRoot, base);
  const answer = await vscode.window.showInputBox({
    prompt: `New file in ${path.basename(baseRoot)}/`, value: prefix ? `${prefix}/` : "src/",
    validateInput: (value) => (/\.[ch]$/.test(value) ? undefined : "Give the file a .c or .h name"),
  });
  if (!answer) {
    return;
  }
  const file = path.isAbsolute(answer) ? answer : path.join(baseRoot, answer);
  // The project is the one the file lands in: typing bootstrap/src/x.c from
  // the repository's root puts it in bootstrap's Makefile.
  const root = project.root(file);
  if (fs.existsSync(file)) {
    vscode.window.showWarningMessage(`${answer} already exists`);
    await vscode.window.showTextDocument(vscode.Uri.file(file));
    return;
  }
  const description = await vscode.window.showInputBox({ prompt: "File description" });
  if (!description) {
    return;
  }
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, scaffold.newFile(file, project.name(root), description).join("\n") + "\n");
  const makefilePath = path.join(root, "Makefile");
  if (file.endsWith(".c") && fs.existsSync(makefilePath)) {
    const lines = fs.readFileSync(makefilePath, "utf8").replace(/\n$/, "").split("\n");
    const rel = path.relative(root, file);
    const result = scaffold.addSource(lines, rel, scaffold.sourceVariable(rel, lines));
    if (result.error) {
      vscode.window.showWarningMessage(result.error);
    } else if (result.lines !== lines) {
      fs.writeFileSync(makefilePath, result.lines.join("\n") + "\n");
    }
  }
  await vscode.window.showTextDocument(vscode.Uri.file(file));
}

// Make tasks --------------------------------------------------------------------

const TASK_TARGETS = ["", "re", "debug", "clean", "fclean", "tests_run", "unit_tests"];

function makeTask(root, target, folder) {
  const definition = { type: "epitech", target, cwd: root };
  const label = target === "" ? "make" : `make ${target}`;
  const task = new vscode.Task(definition, folder || vscode.TaskScope.Workspace, label, "epitech",
    new vscode.ShellExecution("make", target === "" ? [] : [target], { cwd: root }), ["$gcc"]);
  task.group = target === "" || target === "re" || target === "debug" ? vscode.TaskGroup.Build
    : target === "tests_run" ? vscode.TaskGroup.Test : undefined;
  task.detail = path.basename(root);
  return task;
}

function taskProvider() {
  return {
    provideTasks() {
      const result = [];
      for (const folder of vscode.workspace.workspaceFolders || []) {
        const roots = new Set([folder.uri.fsPath]);
        for (const document of vscode.workspace.textDocuments) {
          if (document.uri.scheme === "file" && document.fileName.startsWith(folder.uri.fsPath + path.sep)) {
            roots.add(project.root(document.fileName));
          }
        }
        for (const root of roots) {
          if (!fs.existsSync(path.join(root, "Makefile"))) {
            continue;
          }
          const available = tests.targets(root);
          for (const target of TASK_TARGETS) {
            if (target === "" || available.includes(target)) {
              result.push(makeTask(root, target, folder));
            }
          }
        }
      }
      return result;
    },
    resolveTask(task) {
      const definition = task.definition;
      return definition.cwd ? makeTask(definition.cwd, definition.target || "", task.scope) : undefined;
    },
  };
}

// Criterion in the Testing view -----------------------------------------------------

function exec(command, args, cwd, onOutput) {
  return new Promise((resolve) => {
    let stdout = "";
    let child;
    try {
      child = spawn(command, args, { cwd });
    } catch (error) {
      resolve({ code: -1, stdout: String(error) });
      return;
    }
    const collect = (chunk) => {
      stdout += chunk;
      if (onOutput) {
        onOutput(String(chunk));
      }
    };
    child.stdout.on("data", collect);
    child.stderr.on("data", collect);
    child.on("error", (error) => resolve({ code: -1, stdout: String(error) }));
    child.on("close", (code) => resolve({ code, stdout }));
  });
}

function createTesting(context) {
  const controller = vscode.tests.createTestController("epitech.criterion", "Criterion");
  context.subscriptions.push(controller);
  const coverageDetails = new WeakMap();

  function readFile(uri) {
    const id = uri.toString();
    const source = vscode.workspace.textDocuments.find((doc) => doc.uri.toString() === id);
    let text;
    try {
      text = source ? source.getText() : fs.readFileSync(uri.fsPath, "utf8");
    } catch {
      controller.items.delete(id);
      return;
    }
    const found = tests.discover(text);
    if (found.length === 0) {
      controller.items.delete(id);
      return;
    }
    let fileItem = controller.items.get(id);
    if (!fileItem) {
      fileItem = controller.createTestItem(id, path.basename(uri.fsPath), uri);
      controller.items.add(fileItem);
    }
    fileItem.children.replace(found.map((test) => {
      const item = controller.createTestItem(`${id}::${test.suite}::${test.name}`, `${test.suite}::${test.name}`, uri);
      item.range = new vscode.Range(test.line, 0, test.line, 0);
      return item;
    }));
  }

  async function discoverAll() {
    for (const uri of await vscode.workspace.findFiles("**/tests/**/*.c", "**/node_modules/**", 200)) {
      readFile(uri);
    }
  }

  controller.resolveHandler = async (item) => {
    if (!item) {
      await discoverAll();
    }
  };
  controller.refreshHandler = discoverAll;
  const watcher = vscode.workspace.createFileSystemWatcher("**/tests/**/*.c");
  watcher.onDidCreate(readFile);
  watcher.onDidChange(readFile);
  watcher.onDidDelete((uri) => controller.items.delete(uri.toString()));
  context.subscriptions.push(watcher, vscode.workspace.onDidChangeTextDocument((event) => {
    if (/\/tests?\/.*\.c$/.test(event.document.fileName)) {
      readFile(event.document.uri);
    }
  }));

  async function run(request, token, withCoverage) {
    const testRun = controller.createTestRun(request);
    const queue = [];
    const collect = (item) => {
      if (item.children.size > 0) {
        item.children.forEach(collect);
      } else {
        queue.push(item);
      }
    };
    (request.include || [...controller.items].map(([, item]) => item)).forEach(collect);
    const excluded = new Set((request.exclude || []).map((item) => item.id));
    const byRoot = new Map();
    for (const item of queue.filter((test) => !excluded.has(test.id))) {
      const root = project.root(item.uri.fsPath);
      if (!byRoot.has(root)) {
        byRoot.set(root, []);
      }
      byRoot.get(root).push(item);
    }
    const write = (text) => testRun.appendOutput(text.replace(/\r?\n/g, "\r\n"));
    for (const [root, items] of byRoot) {
      if (token.isCancellationRequested) {
        break;
      }
      items.forEach((item) => testRun.started(item));
      const available = tests.targets(root);
      let outputText;
      if (available.includes("unit_tests")) {
        write(`$ make unit_tests (${path.basename(root)})\n`);
        const build = await exec("make", ["unit_tests"], root, write);
        if (build.code !== 0) {
          items.forEach((item) => testRun.errored(item, new vscode.TestMessage("The tests don't build: see the output")));
          continue;
        }
        const filter = items.length === 1 ? [`--filter=${items[0].label.replace("::", "/")}`] : [];
        write(`$ ./unit_tests --verbose ${filter.join(" ")}\n`);
        outputText = (await exec(path.join(root, "unit_tests"), ["--verbose", ...filter], root, write)).stdout;
      } else if (available.includes("tests_run")) {
        write(`$ make tests_run (${path.basename(root)})\n`);
        outputText = (await exec("make", ["tests_run"], root, write)).stdout;
      } else {
        items.forEach((item) => testRun.errored(item,
          new vscode.TestMessage("The Makefile has no unit_tests or tests_run rule")));
        continue;
      }
      const parsed = tests.parse(outputText, root);
      const passed = new Set([...outputText.matchAll(/^\[PASS\] (\S+?)::(\S+?)(?::|\s|$)/gm)]
        .map((match) => `${match[1]}::${match[2]}`));
      for (const item of items) {
        const failures = parsed.failures.filter((failure) => failure.test === item.label);
        if (failures.length > 0) {
          testRun.failed(item, failures.map((failure) => {
            const message = new vscode.TestMessage(failure.message);
            if (failure.file) {
              message.location = new vscode.Location(vscode.Uri.file(failure.file),
                new vscode.Position(Math.max(failure.line - 1, 0), 0));
            }
            return message;
          }));
        } else if (passed.has(item.label) || (parsed.synthesis && !outputText.includes(`${item.label}:`)
          && parsed.synthesis.failing === 0 && parsed.synthesis.crashing === 0)) {
          testRun.passed(item);
        } else {
          testRun.skipped(item);
        }
      }
      if (withCoverage && available.includes("unit_tests")) {
        const report = await exec("gcovr", ["-r", root, "--json", "-"], root);
        const coverage = report.code === 0 ? tests.parseCoverage(report.stdout, root) : undefined;
        if (!coverage) {
          write("\r\nNo coverage: gcovr isn't installed or found no data\r\n");
        } else {
          for (const [file, lines] of Object.entries(coverage.files)) {
            const total = lines.hit.length + lines.missed.length;
            const fileCoverage = new vscode.FileCoverage(vscode.Uri.file(file),
              new vscode.TestCoverageCount(lines.hit.length, total));
            coverageDetails.set(fileCoverage, [
              ...lines.hit.map((line) => new vscode.StatementCoverage(1, new vscode.Position(line - 1, 0))),
              ...lines.missed.map((line) => new vscode.StatementCoverage(0, new vscode.Position(line - 1, 0))),
            ]);
            testRun.addCoverage(fileCoverage);
          }
        }
      }
      // Leave no build products behind, as tests_run does (C-O1).
      if (available.includes("unit_tests") && available.includes("fclean")) {
        await exec("make", ["fclean"], root);
      }
    }
    testRun.end();
  }

  controller.createRunProfile("Run", vscode.TestRunProfileKind.Run, (request, token) => run(request, token, false),
    true);
  const coverageProfile = controller.createRunProfile("Coverage", vscode.TestRunProfileKind.Coverage,
    (request, token) => run(request, token, true), true);
  coverageProfile.loadDetailedCoverage = async (testRun, fileCoverage) => coverageDetails.get(fileCoverage) || [];
  discoverAll();
  return controller;
}

// Updates -------------------------------------------------------------------------

const INSTALL_COMMAND = "bash <(curl -fsSL https://raw.githubusercontent.com/cempack/epitech-dump-arch/main/install.sh)";

// Checks the latest release; offers to install it when it's newer. silent:
// says nothing when up to date or offline (the daily check).
async function checkForUpdates(context, silent) {
  const current = (context.extension && context.extension.packageJSON.version) || require("../package.json").version;
  let release;
  try {
    release = await update.latest();
  } catch (error) {
    if (!silent) {
      vscode.window.showWarningMessage(`Couldn't check for updates: ${error.message}`);
    }
    return;
  }
  await context.globalState.update("epitech.lastUpdateCheck", Date.now());
  if (!release || !update.newer(release.version, current)) {
    if (!silent) {
      vscode.window.showInformationMessage(`The Epitech extension is up to date (${current})`);
    }
    return;
  }
  const dump = update.managedByDump();
  const choices = dump ? ["Update now", "Run epitech-upgrade"] : ["Update now", "Install all the tools"];
  const message = dump
    ? `Epitech extension ${release.version} is out (you have ${current}). epitech-upgrade installs it weekly, or now.`
    : `Epitech extension ${release.version} is out (you have ${current}).`;
  const choice = await vscode.window.showInformationMessage(message, ...choices);
  if (choice === "Update now") {
    await vscode.window.withProgress({ location: vscode.ProgressLocation.Notification,
      title: `Installing the Epitech extension ${release.version}` }, async () => {
      try {
        const file = await update.download(release.url);
        await vscode.commands.executeCommand("workbench.extensions.installExtension", vscode.Uri.file(file));
      } catch (error) {
        vscode.window.showErrorMessage(`The update failed: ${error.message}. Get it from ${update.PAGE}`);
        return;
      }
      const reload = await vscode.window.showInformationMessage(
        `Epitech extension ${release.version} installed: reload the window to use it.`, "Reload");
      if (reload) {
        vscode.commands.executeCommand("workbench.action.reloadWindow");
      }
    });
  } else if (choice === "Run epitech-upgrade") {
    const terminal = vscode.window.createTerminal("epitech-upgrade");
    terminal.show();
    terminal.sendText("epitech-upgrade");
  } else if (choice === "Install all the tools") {
    // epitech-dump-arch would install epiclang, clang-format, Criterion…
    // and keep this extension current; it runs on Arch and Ubuntu.
    const terminal = vscode.window.createTerminal("Epitech tools");
    terminal.show();
    terminal.sendText(INSTALL_COMMAND, false);
    vscode.window.showInformationMessage("Press Enter in the terminal to run the installer (Arch or Ubuntu; it asks "
      + "for sudo). It also updates this extension every week.");
  }
}

// Activation ---------------------------------------------------------------------

async function activate(context) {
  output = vscode.window.createOutputChannel("Epitech");
  context.subscriptions.push(output);
  ignored = ignore.create(context.globalState);
  try {
    await parser.init();
  } catch (error) {
    log(`The C parser didn't load: ${error.message}`);
    vscode.window.showErrorMessage(`Epitech: the C parser didn't load (${error.message})`);
    return;
  }

  const diagnostics = createDiagnostics(context);
  const budgets = createBudgets(context);
  const tree = new CheckTree();
  const checkStatus = vscode.window.createStatusBarItem("epitech.check", vscode.StatusBarAlignment.Left, 50);
  checkStatus.name = "Epitech check";
  checkStatus.text = "$(beaker) Epitech";
  checkStatus.tooltip = "Check the whole project with Banana";
  checkStatus.command = "epitech.checkProject";
  context.subscriptions.push(checkStatus);
  const showStatus = () => {
    const editor = vscode.window.activeTextEditor;
    if (editor && (isC(editor.document) || isMakefile(editor.document))) {
      checkStatus.show();
    }
  };

  const setIgnored = async (projectWide, value) => {
    const editor = vscode.window.activeTextEditor;
    if (!editor || editor.document.uri.scheme !== "file") {
      vscode.window.showWarningMessage("Open a file of the project first");
      return;
    }
    const root = project.root(editor.document.fileName);
    await ignored.set(root, projectWide ? undefined : editor.document.fileName, value);
    diagnostics.refreshAll();
    vscode.window.visibleTextEditors.forEach((visible) => budgets.update(visible));
    vscode.window.showInformationMessage(`Epitech warnings ${value ? "off" : "back on"} for `
      + (projectWide ? path.basename(root) : path.basename(editor.document.fileName)));
  };

  context.subscriptions.push(
    vscode.languages.registerDocumentFormattingEditProvider(C_FILES, formattingProvider()),
    vscode.languages.registerCodeActionsProvider([...C_FILES, ...MAKEFILES], codeActionProvider(diagnostics), {
      providedCodeActionKinds: [vscode.CodeActionKind.QuickFix, vscode.CodeActionKind.RefactorRewrite,
        vscode.CodeActionKind.Empty],
    }),
    vscode.languages.registerHoverProvider(C_FILES, {
      provideHover(document, at) {
        const diagnostic = ruleAt(document, at);
        if (!diagnostic) {
          return undefined;
        }
        const markdown = new vscode.MarkdownString(rules.markdown(rules.byCode[codeOf(diagnostic)], diagnostic));
        return new vscode.Hover(markdown, diagnostic.range);
      },
    }),
    vscode.workspace.registerTextDocumentContentProvider("epitech-rule", {
      provideTextDocumentContent(uri) {
        const rule = rules.byCode[uri.path.replace(/\.md$/, "")];
        return rule ? rules.markdown(rule) : "Unknown rule";
      },
    }),
    vscode.window.registerTreeDataProvider("epitech.checkView", tree),
    vscode.tasks.registerTaskProvider("epitech", taskProvider()),
    vscode.workspace.onDidOpenTextDocument((document) => diagnostics.opened(document)),
    vscode.workspace.onDidSaveTextDocument((document) => {
      diagnostics.saved(document);
      if (isMakefile(document)) {
        vscode.window.visibleTextEditors.forEach((editor) => budgets.update(editor));
      }
    }),
    vscode.workspace.onDidCloseTextDocument((document) => diagnostics.closed(document)),
    vscode.window.onDidChangeActiveTextEditor((editor) => {
      budgets.update(editor);
      showStatus();
    }),
    vscode.window.onDidChangeVisibleTextEditors((editors) => editors.forEach((editor) => budgets.update(editor))),
    vscode.workspace.onDidChangeTextDocument((event) => {
      diagnostics.changed(event.document);
      for (const editor of vscode.window.visibleTextEditors) {
        if (editor.document === event.document) {
          budgets.schedule(editor);
        }
      }
    }),
    vscode.workspace.onDidChangeConfiguration((event) => {
      if (event.affectsConfiguration("epitech")) {
        diagnostics.refreshAll();
        vscode.window.visibleTextEditors.forEach((editor) => budgets.update(editor));
      }
    }),
    vscode.commands.registerCommand("epitech.insertHeader", insertHeader),
    vscode.commands.registerCommand("epitech.insertGuard", insertGuard),
    vscode.commands.registerCommand("epitech.newProject", newProject),
    vscode.commands.registerCommand("epitech.newFile", newFile),
    vscode.commands.registerCommand("epitech.checkProject", () => checkProject(tree, checkStatus, diagnostics)),
    vscode.commands.registerCommand("epitech.untrack", untrack),
    vscode.commands.registerCommand("epitech.explainRule", (code) => explain(typeof code === "string" ? code
      : code && code.code)),
    vscode.commands.registerCommand("epitech.extractMacro", extractMacro),
    vscode.commands.registerCommand("epitech.fixAllVoid", fixAllVoid),
    vscode.commands.registerCommand("epitech.toggleBudgets", () => budgets.toggle()),
    vscode.commands.registerCommand("epitech.ignoreFile", () => setIgnored(false, true)),
    vscode.commands.registerCommand("epitech.unignoreFile", () => setIgnored(false, false)),
    vscode.commands.registerCommand("epitech.ignoreProject", () => setIgnored(true, true)),
    vscode.commands.registerCommand("epitech.unignoreProject", () => setIgnored(true, false)),
    vscode.commands.registerCommand("epitech.checkForUpdates", () => checkForUpdates(context, false)),
    vscode.commands.registerCommand("epitech.openWalkthrough", () => vscode.commands.executeCommand(
      "workbench.action.openWalkthrough", "cempack.epitech#epitech.start", false)),
  );
  if (vscode.tests && vscode.tests.createTestController) {
    createTesting(context);
  }

  diagnostics.refreshAll();
  vscode.window.visibleTextEditors.forEach((editor) => budgets.update(editor));
  showStatus();
  // Once a day at most, quietly.
  const last = context.globalState.get("epitech.lastUpdateCheck", 0);
  if (config().get("updates.check") && Date.now() - last > 24 * 3600 * 1000) {
    setTimeout(() => checkForUpdates(context, true), 10000);
  }
}

function deactivate() {}

module.exports = { activate, deactivate, includeRow, includeName, apply, checkForUpdates };
