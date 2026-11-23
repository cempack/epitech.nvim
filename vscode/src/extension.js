// The VS Code side: wires the modules shared in spirit with the Neovim
// plugin (format, banana, budget, header, scaffold…) to VS Code's APIs.
// Everything Epitech-specific lives in those modules, which have no VS Code
// dependency and are tested with plain node.
"use strict";

const vscode = require("vscode");
const fs = require("fs");
const path = require("path");
const parser = require("./parser");
const data = require("./data");
const format = require("./format");
const banana = require("./banana");
const budget = require("./budget");
const fixes = require("./fixes");
const header = require("./header");
const project = require("./project");
const rules = require("./rules");
const scaffold = require("./scaffold");
const ts = require("./ts");

const C_FILES = [{ scheme: "file", pattern: "**/*.{c,h}" }, { language: "c" }];
const isC = (document) => document.uri.scheme === "file" && /\.[ch]$/.test(document.fileName);
const config = () => vscode.workspace.getConfiguration("epitech");

let output;
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

const lspPosition = (lines, point) => {
  const position = ts.position(lines, point);
  return new vscode.Position(position.line, position.character);
};

// Formatting ------------------------------------------------------------------

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
        vscode.window.showErrorMessage(`Epitech formatter: ${error.message}`);
        return [];
      }
    },
  };
}

// Banana ------------------------------------------------------------------------

const SEVERITY = {
  fatal: vscode.DiagnosticSeverity.Error,
  major: vscode.DiagnosticSeverity.Error,
  minor: vscode.DiagnosticSeverity.Warning,
  info: vscode.DiagnosticSeverity.Information,
};

function toDiagnostic(entry, document) {
  const line = document && entry.line < document.lineCount ? entry.line : Math.max(entry.line, 0);
  const range = document && entry.line < document.lineCount
    ? new vscode.Range(line, entry.column, line, document.lineAt(line).text.length)
    : new vscode.Range(line, entry.column, line, entry.column + 1);
  const diagnostic = new vscode.Diagnostic(range, entry.message, SEVERITY[entry.level]);
  diagnostic.source = "Banana";
  diagnostic.code = entry.code;
  return diagnostic;
}

function createBanana(collection) {
  const jobs = new Map();
  let warned = false;

  async function run(document) {
    if (!config().get("diagnostics.enabled") || !isC(document)) {
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
        collection.set(document.uri, entries.map((entry) => toDiagnostic(entry, document)));
      }
    } catch (error) {
      if (error.code === "ENOENT" && !warned) {
        warned = true;
        vscode.window.showWarningMessage(`${settings.get("diagnostics.command")} not found: Banana's reports are off. `
          + "Install it (epitech-dump-arch does) or set epitech.diagnostics.command.");
      } else if (error.code !== "ENOENT" && error.code !== "KILLED") {
        log(`Banana: ${error.message}`);
      }
    } finally {
      if (jobs.get(file) === job) {
        jobs.delete(file);
      }
    }
  }
  return { run };
}

// Rules ---------------------------------------------------------------------------

function ruleUri(code) {
  return vscode.Uri.parse(`epitech-rule:${code}.md`);
}

async function explain(code) {
  if (!code) {
    const picked = await vscode.window.showQuickPick(rules.rules.map((rule) => ({
      label: rule.code, description: rule.title, detail: rule.summary,
    })), { placeHolder: "Coding style rule", matchOnDescription: true, matchOnDetail: true });
    if (!picked) {
      return;
    }
    code = picked.label;
  }
  await vscode.commands.executeCommand("markdown.showPreviewToSide", ruleUri(code));
}

function ruleAt(document, position) {
  return vscode.languages.getDiagnostics(document.uri).find((diagnostic) => diagnostic.range.contains(position)
    && rules.byCode[typeof diagnostic.code === "object" ? diagnostic.code.value : diagnostic.code]);
}

// Budgets ---------------------------------------------------------------------------

const COLORS = {
  ok: new vscode.ThemeColor("editorCodeLens.foreground"),
  near: new vscode.ThemeColor("editorWarning.foreground"),
  over: new vscode.ThemeColor("editorError.foreground"),
};

function createBudgets(context) {
  const decoration = vscode.window.createTextEditorDecorationType({
    after: { margin: "0 0 0 2em", fontStyle: "italic" },
  });
  const status = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Right, 100);
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
    if (!isC(document)) {
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
        decorations.push({
          range: new vscode.Range(end, end),
          renderOptions: { after: { contentText: chunk.text, color: COLORS[chunk.level] } },
        });
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

// Code actions -------------------------------------------------------------------

function codeActionProvider() {
  return {
    provideCodeActions(document, range) {
      if (!isC(document)) {
        return [];
      }
      const lines = document.getText().split(/\r?\n/);
      const actions = [];
      for (const edit of fixes.edits(document.getText())) {
        if (edit.start.row > range.end.line || edit.end.row < range.start.line) {
          continue;
        }
        const action = new vscode.CodeAction(edit.title, vscode.CodeActionKind.QuickFix);
        action.edit = new vscode.WorkspaceEdit();
        action.edit.replace(document.uri, new vscode.Range(lspPosition(lines, edit.start), lspPosition(lines, edit.end)),
          edit.newText);
        action.diagnostics = vscode.languages.getDiagnostics(document.uri).filter((diagnostic) =>
          diagnostic.code === edit.rule && diagnostic.range.start.line === edit.start.row);
        action.isPreferred = true;
        actions.push(action);
      }
      return actions;
    },
  };
}

async function fixAllVoid() {
  const editor = vscode.window.activeTextEditor;
  if (!editor || !isC(editor.document)) {
    return;
  }
  const document = editor.document;
  const lines = document.getText().split(/\r?\n/);
  const edits = fixes.edits(document.getText());
  if (edits.length === 0) {
    vscode.window.showInformationMessage("No empty parameter list here");
    return;
  }
  await editor.edit((builder) => {
    for (const edit of edits) {
      builder.replace(new vscode.Range(lspPosition(lines, edit.start), lspPosition(lines, edit.end)), edit.newText);
    }
  });
  vscode.window.showInformationMessage(`${edits.length} function${edits.length > 1 ? "s" : ""} fixed (C-F6)`);
}

// Headers --------------------------------------------------------------------------

function documentLines(document) {
  return document.getText().split(/\r?\n/);
}

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

// Projects -------------------------------------------------------------------------

function workspaceDir() {
  const editor = vscode.window.activeTextEditor;
  if (editor && editor.document.uri.scheme === "file") {
    return project.root(editor.document.fileName);
  }
  const folder = vscode.workspace.workspaceFolders && vscode.workspace.workspaceFolders[0];
  return folder && folder.uri.fsPath;
}

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
  const exists = fs.existsSync(path.join(dir, "Makefile"));
  if (exists) {
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
  vscode.window.showInformationMessage(`Created ${name}: ${written.join(", ")}`);
  const main = ["src/main.c", `src/${scaffold.base(name)}.c`].map((file) => path.join(dir, file)).find(fs.existsSync);
  if (main) {
    await vscode.window.showTextDocument(vscode.Uri.file(main));
  }
}

async function newFile() {
  const root = workspaceDir();
  if (!root) {
    vscode.window.showWarningMessage("Open a folder first");
    return;
  }
  const relative = await vscode.window.showInputBox({
    prompt: `New file in ${path.basename(root)}/`, placeHolder: "src/parse_args.c",
    validateInput: (value) => (/\.[ch]$/.test(value) ? undefined : "Give the file a .c or .h name"),
  });
  if (!relative) {
    return;
  }
  const file = path.isAbsolute(relative) ? relative : path.join(root, relative);
  if (fs.existsSync(file)) {
    vscode.window.showWarningMessage(`${relative} already exists`);
    await vscode.window.showTextDocument(vscode.Uri.file(file));
    return;
  }
  const description = await vscode.window.showInputBox({ prompt: "File description" });
  if (!description) {
    return;
  }
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, scaffold.newFile(file, project.name(root), description).join("\n") + "\n");
  const makefile = path.join(root, "Makefile");
  if (file.endsWith(".c") && fs.existsSync(makefile)) {
    const lines = fs.readFileSync(makefile, "utf8").replace(/\n$/, "").split("\n");
    const rel = path.relative(root, file);
    const result = scaffold.addSource(lines, rel, scaffold.sourceVariable(rel, lines));
    if (result.error) {
      vscode.window.showWarningMessage(result.error);
    } else if (result.lines !== lines) {
      fs.writeFileSync(makefile, result.lines.join("\n") + "\n");
    }
  }
  await vscode.window.showTextDocument(vscode.Uri.file(file));
}

// The whole project through Banana, into the Problems panel.
async function checkProject(collection) {
  const root = workspaceDir();
  if (!root) {
    vscode.window.showWarningMessage("Open a folder first");
    return;
  }
  const files = project.files(root, ["*.c", "*.h"]);
  if (!files) {
    vscode.window.showWarningMessage(`${root} isn't a git repository: the check covers tracked files`);
    return;
  }
  const settings = config();
  const counts = { fatal: 0, major: 0, minor: 0, info: 0 };
  await vscode.window.withProgress({ location: vscode.ProgressLocation.Notification, title: "Banana",
    cancellable: false }, async (progress) => {
    let done = 0;
    const queue = files.slice();
    const worker = async () => {
      while (queue.length > 0) {
        const relative = queue.shift();
        const file = path.join(root, relative);
        try {
          const entries = await banana.run(file, { root, cmd: settings.get("diagnostics.command"),
            args: settings.get("diagnostics.args") }).promise;
          const document = vscode.workspace.textDocuments.find((doc) => doc.fileName === file);
          collection.set(vscode.Uri.file(file), entries.map((entry) => toDiagnostic(entry, document)));
          entries.forEach((entry) => counts[entry.level]++);
        } catch (error) {
          if (error.code === "ENOENT") {
            queue.length = 0;
            throw error;
          }
        }
        done++;
        progress.report({ message: `${done}/${files.length} files`, increment: 100 / files.length });
      }
    };
    await Promise.all(Array.from({ length: Math.min(require("os").cpus().length, 8) }, worker));
  }).then(() => {
    const summary = `${counts.fatal} fatal · ${counts.major} major · ${counts.minor} minor · ${counts.info} info`;
    const failed = counts.fatal + counts.major > 0;
    (failed ? vscode.window.showWarningMessage : vscode.window.showInformationMessage)(`Epitech check: ${summary}`);
    vscode.commands.executeCommand("workbench.actions.view.problems");
  }, (error) => {
    vscode.window.showWarningMessage(`${settings.get("diagnostics.command")} not found: ${error.message}`);
  });
}

// Activation --------------------------------------------------------------------------

async function activate(context) {
  output = vscode.window.createOutputChannel("Epitech");
  context.subscriptions.push(output);
  try {
    await parser.init();
  } catch (error) {
    log(`The C parser didn't load: ${error.message}`);
    vscode.window.showErrorMessage(`Epitech: the C parser didn't load (${error.message})`);
    return;
  }

  const collection = vscode.languages.createDiagnosticCollection("banana");
  const runner = createBanana(collection);
  const budgets = createBudgets(context);
  context.subscriptions.push(collection);

  context.subscriptions.push(
    vscode.languages.registerDocumentFormattingEditProvider(C_FILES, formattingProvider()),
    vscode.languages.registerCodeActionsProvider(C_FILES, codeActionProvider(), {
      providedCodeActionKinds: [vscode.CodeActionKind.QuickFix],
    }),
    vscode.languages.registerHoverProvider(C_FILES, {
      provideHover(document, position) {
        const diagnostic = ruleAt(document, position);
        if (!diagnostic) {
          return undefined;
        }
        const code = typeof diagnostic.code === "object" ? diagnostic.code.value : diagnostic.code;
        const markdown = new vscode.MarkdownString(rules.markdown(rules.byCode[code], diagnostic));
        return new vscode.Hover(markdown, diagnostic.range);
      },
    }),
    vscode.workspace.registerTextDocumentContentProvider("epitech-rule", {
      provideTextDocumentContent(uri) {
        const rule = rules.byCode[uri.path.replace(/\.md$/, "")];
        return rule ? rules.markdown(rule) : "Unknown rule";
      },
    }),
    vscode.workspace.onDidOpenTextDocument((document) => runner.run(document)),
    vscode.workspace.onDidSaveTextDocument((document) => {
      runner.run(document);
      if (path.basename(document.fileName) === "Makefile") {
        vscode.window.visibleTextEditors.forEach((editor) => budgets.update(editor));
      }
    }),
    vscode.workspace.onDidCloseTextDocument((document) => collection.delete(document.uri)),
    vscode.window.onDidChangeActiveTextEditor((editor) => budgets.update(editor)),
    vscode.window.onDidChangeVisibleTextEditors((editors) => editors.forEach((editor) => budgets.update(editor))),
    vscode.workspace.onDidChangeTextDocument((event) => {
      for (const editor of vscode.window.visibleTextEditors) {
        if (editor.document === event.document) {
          budgets.schedule(editor);
        }
      }
    }),
    vscode.workspace.onDidChangeConfiguration((event) => {
      if (event.affectsConfiguration("epitech")) {
        vscode.window.visibleTextEditors.forEach((editor) => budgets.update(editor));
      }
    }),
    vscode.commands.registerCommand("epitech.insertHeader", insertHeader),
    vscode.commands.registerCommand("epitech.insertGuard", insertGuard),
    vscode.commands.registerCommand("epitech.newProject", newProject),
    vscode.commands.registerCommand("epitech.newFile", newFile),
    vscode.commands.registerCommand("epitech.checkProject", () => checkProject(collection)),
    vscode.commands.registerCommand("epitech.explainRule", () => {
      const editor = vscode.window.activeTextEditor;
      const diagnostic = editor && ruleAt(editor.document, editor.selection.active);
      return explain(diagnostic && (typeof diagnostic.code === "object" ? diagnostic.code.value : diagnostic.code));
    }),
    vscode.commands.registerCommand("epitech.fixAllVoid", fixAllVoid),
    vscode.commands.registerCommand("epitech.toggleBudgets", () => budgets.toggle()),
  );

  vscode.workspace.textDocuments.forEach((document) => runner.run(document));
  vscode.window.visibleTextEditors.forEach((editor) => budgets.update(editor));
}

function deactivate() {}

module.exports = { activate, deactivate };
