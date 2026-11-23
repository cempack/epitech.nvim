// A stand-in for the `vscode` module, with just what extension.js uses, so
// its wiring is tested with plain node: activate() runs, providers and
// commands are registered and called like VS Code would call them.
"use strict";

const fs = require("fs");

class Position {
  constructor(line, character) {
    this.line = line;
    this.character = character;
  }
}

class Range {
  constructor(a, b, c, d) {
    if (a instanceof Position) {
      this.start = a;
      this.end = b;
    } else {
      this.start = new Position(a, b);
      this.end = new Position(c, d);
    }
  }

  contains(position) {
    const after = (p, q) => p.line > q.line || (p.line === q.line && p.character >= q.character);
    return after(position, this.start) && after(this.end, position);
  }
}

class Uri {
  constructor(scheme, path) {
    this.scheme = scheme;
    this.path = path;
    this.fsPath = path;
  }

  static file(path) {
    return new Uri("file", path);
  }

  static parse(text) {
    const [scheme, ...rest] = text.split(":");
    return new Uri(scheme, rest.join(":"));
  }

  toString() {
    return `${this.scheme}:${this.path}`;
  }
}

function offsetAt(text, position) {
  const lines = text.split("\n");
  let offset = 0;
  for (let i = 0; i < position.line; i++) {
    offset += lines[i].length + 1;
  }
  return offset + position.character;
}

class TextDocument {
  constructor(fileName, text, languageId = "c") {
    this.fileName = fileName;
    this.uri = Uri.file(fileName);
    this.text = text;
    this.languageId = languageId;
  }

  getText() {
    return this.text;
  }

  get lineCount() {
    return this.text.split("\n").length;
  }

  lineAt(line) {
    const text = this.text.split("\n")[line];
    return { text, range: new Range(line, 0, line, text.length) };
  }

  positionAt(offset) {
    const before = this.text.slice(0, offset).split("\n");
    return new Position(before.length - 1, before[before.length - 1].length);
  }
}

// Applies [{ range, text }] edits to a document's text.
function apply(document, edits) {
  const sorted = edits.slice().sort((a, b) => offsetAt(document.text, b.range.start) - offsetAt(document.text, a.range.start));
  for (const edit of sorted) {
    const start = offsetAt(document.text, edit.range.start);
    const end = offsetAt(document.text, edit.range.end);
    document.text = document.text.slice(0, start) + edit.text + document.text.slice(end);
  }
}

function create() {
  const registry = { commands: {}, formatting: [], codeActions: [], hovers: [], content: {}, events: {}, messages: [],
    decorations: new Map(), inputs: [], picks: [] };
  const diagnostics = new Map();
  const on = (name) => (listener) => {
    (registry.events[name] = registry.events[name] || []).push(listener);
    return { dispose() {} };
  };
  const disposable = { dispose() {} };
  const settings = {
    "diagnostics.enabled": true, "diagnostics.command": "epiclang", "diagnostics.args": ["-x", "c", "-fsyntax-only"],
    "format.enabled": true, "format.clangFormat": "clang-format", "budget.functions": true, "budget.depth": true,
    "budget.file": true, "scaffold.cc": "epiclang", "scaffold.cflags": "", "scaffold.debugCflags": "-g3",
    "scaffold.errorFile": true,
  };
  const message = (level) => async (text, ...items) => {
    registry.messages.push({ level, text });
    return items.find((item) => typeof item === "string");
  };
  const status = { show() {
    this.visible = true;
  }, hide() {
    this.visible = false;
  }, dispose() {} };

  const vscode = {
    Position, Range, Uri,
    ThemeColor: class {
      constructor(id) {
        this.id = id;
      }
    },
    MarkdownString: class {
      constructor(value) {
        this.value = value;
      }
    },
    Hover: class {
      constructor(contents, range) {
        this.contents = contents;
        this.range = range;
      }
    },
    Diagnostic: class {
      constructor(range, message, severity) {
        Object.assign(this, { range, message, severity });
      }
    },
    DiagnosticSeverity: { Error: 0, Warning: 1, Information: 2, Hint: 3 },
    CodeAction: class {
      constructor(title, kind) {
        this.title = title;
        this.kind = kind;
      }
    },
    CodeActionKind: { QuickFix: "quickfix" },
    WorkspaceEdit: class {
      constructor() {
        this.edits = [];
      }

      replace(uri, range, text) {
        this.edits.push({ uri, range, text });
      }
    },
    TextEdit: { replace: (range, text) => ({ range, text }) },
    StatusBarAlignment: { Left: 1, Right: 2 },
    ProgressLocation: { Notification: 15 },
    languages: {
      createDiagnosticCollection: () => ({
        set(uri, list) {
          diagnostics.set(uri.toString(), list);
        },
        delete(uri) {
          diagnostics.delete(uri.toString());
        },
        dispose() {},
      }),
      getDiagnostics: (uri) => diagnostics.get(uri.toString()) || [],
      registerDocumentFormattingEditProvider: (selector, provider) => registry.formatting.push(provider) && disposable,
      registerCodeActionsProvider: (selector, provider) => registry.codeActions.push(provider) && disposable,
      registerHoverProvider: (selector, provider) => registry.hovers.push(provider) && disposable,
    },
    workspace: {
      textDocuments: [],
      workspaceFolders: undefined,
      getConfiguration: () => ({ get: (key) => settings[key] }),
      registerTextDocumentContentProvider: (scheme, provider) => {
        registry.content[scheme] = provider;
        return disposable;
      },
      onDidOpenTextDocument: on("open"),
      onDidSaveTextDocument: on("save"),
      onDidCloseTextDocument: on("close"),
      onDidChangeTextDocument: on("change"),
      onDidChangeConfiguration: on("configuration"),
    },
    window: {
      activeTextEditor: undefined,
      visibleTextEditors: [],
      createOutputChannel: () => ({ appendLine() {}, dispose() {} }),
      createTextEditorDecorationType: () => ({ dispose() {} }),
      createStatusBarItem: () => status,
      showInformationMessage: message("info"),
      showWarningMessage: message("warning"),
      showErrorMessage: message("error"),
      showInputBox: async () => registry.inputs.shift(),
      showQuickPick: async (items) => {
        const pick = registry.picks.shift();
        return typeof pick === "function" ? pick(items) : pick;
      },
      showOpenDialog: async () => undefined,
      showTextDocument: async (uri) => {
        registry.shown = uri;
      },
      withProgress: async (options, task) => task({ report() {} }),
      onDidChangeActiveTextEditor: on("active"),
      onDidChangeVisibleTextEditors: on("visible"),
    },
    commands: {
      registerCommand: (name, fn) => {
        registry.commands[name] = fn;
        return disposable;
      },
      executeCommand: async (name, ...args) => {
        registry.executed = [name, ...args];
      },
    },
  };

  // An editor on a document, whose edit() applies to the document's text.
  function editor(document) {
    return {
      document,
      selection: { active: new Position(0, 0) },
      setDecorations(type, list) {
        registry.decorations.set(document.fileName, list);
      },
      async edit(callback) {
        const edits = [];
        callback({
          replace: (range, text) => edits.push({ range, text }),
          insert: (position, text) => edits.push({ range: new Range(position, position), text }),
        });
        apply(document, edits);
        return true;
      },
    };
  }

  return { vscode, registry, settings, status, diagnostics, TextDocument, editor, apply,
    readDocument: (file) => new TextDocument(file, fs.readFileSync(file, "utf8")) };
}

module.exports = { create };
