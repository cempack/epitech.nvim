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
    decorations: new Map(), inputs: [], picks: [], collections: {}, trees: {}, taskProviders: {}, controllers: [],
    applied: [], files: [] };
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
    "scaffold.errorFile": true, "hints.enabled": true, "hints.severity": "hint", "hints.magicNumbers": true,
    "hints.magicNumbersAllow": [0, 1, -1, 84], "hints.static": true, "hints.types": true, "hints.naming": true,
    "makefile.enabled": true, "updates.check": false,
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
    CodeActionKind: { QuickFix: "quickfix", RefactorRewrite: "refactor.rewrite", Empty: "" },
    EventEmitter: class {
      constructor() {
        this.listeners = [];
        this.event = (listener) => this.listeners.push(listener);
      }

      fire(value) {
        this.listeners.forEach((listener) => listener(value));
      }
    },
    TreeItem: class {
      constructor(label, collapsibleState) {
        this.label = label;
        this.collapsibleState = collapsibleState;
      }
    },
    TreeItemCollapsibleState: { None: 0, Collapsed: 1, Expanded: 2 },
    ThemeIcon: class {
      constructor(id) {
        this.id = id;
      }
    },
    Location: class {
      constructor(uri, range) {
        this.uri = uri;
        this.range = range;
      }
    },
    TestMessage: class {
      constructor(message) {
        this.message = message;
      }
    },
    TestRunProfileKind: { Run: 1, Debug: 2, Coverage: 3 },
    TestCoverageCount: class {
      constructor(covered, total) {
        this.covered = covered;
        this.total = total;
      }
    },
    FileCoverage: class {
      constructor(uri, statementCoverage) {
        this.uri = uri;
        this.statementCoverage = statementCoverage;
      }
    },
    StatementCoverage: class {
      constructor(executed, location) {
        this.executed = executed;
        this.location = location;
      }
    },
    Task: class {
      constructor(definition, scope, name, source, execution, problemMatchers) {
        Object.assign(this, { definition, scope, name, source, execution, problemMatchers });
      }
    },
    ShellExecution: class {
      constructor(command, args, options) {
        Object.assign(this, { command, args, options });
      }
    },
    TaskGroup: { Build: "build", Test: "test" },
    TaskScope: { Workspace: 2 },
    tasks: {
      registerTaskProvider: (type, provider) => {
        registry.taskProviders[type] = provider;
        return disposable;
      },
    },
    tests: {
      createTestController: (id, label) => {
        const items = new Map();
        const collection = (map) => ({
          get: (key) => map.get(key),
          add: (item) => map.set(item.id, item),
          delete: (key) => map.delete(key),
          replace: (list) => {
            map.clear();
            list.forEach((item) => map.set(item.id, item));
          },
          forEach: (fn) => map.forEach((item) => fn(item)),
          get size() {
            return map.size;
          },
          [Symbol.iterator]: () => map.entries(),
        });
        const controller = {
          id, label, items: collection(items), profiles: [],
          createTestItem: (itemId, itemLabel, uri) => ({ id: itemId, label: itemLabel, uri,
            children: collection(new Map()) }),
          createRunProfile(name, kind, handler) {
            const profile = { name, kind, handler };
            this.profiles.push(profile);
            return profile;
          },
          createTestRun() {
            const run = { results: {}, output: "", coverage: [] };
            run.started = () => {};
            run.passed = (item) => { run.results[item.label] = "passed"; };
            run.failed = (item, messages) => { run.results[item.label] = { failed: messages }; };
            run.errored = (item, message) => { run.results[item.label] = { errored: message }; };
            run.skipped = (item) => { run.results[item.label] = "skipped"; };
            run.appendOutput = (text) => { run.output += text; };
            run.addCoverage = (coverage) => run.coverage.push(coverage);
            run.end = () => { registry.lastRun = run; };
            return run;
          },
          dispose() {},
        };
        registry.controllers.push(controller);
        return controller;
      },
    },
    WorkspaceEdit: class {
      constructor() {
        this.edits = [];
      }

      replace(uri, range, text) {
        this.edits.push({ uri, range, text });
      }

      insert(uri, position, text) {
        this.edits.push({ uri, range: new Range(position, position), text });
      }

      createFile(uri) {
        this.edits.push({ uri, create: true });
      }
    },
    TextEdit: { replace: (range, text) => ({ range, text }) },
    StatusBarAlignment: { Left: 1, Right: 2 },
    ProgressLocation: { Notification: 15 },
    languages: {
      createDiagnosticCollection: (name) => {
        const own = new Map();
        registry.collections[name] = own;
        const all = () => {
          const merged = new Map();
          for (const collection of Object.values(registry.collections)) {
            for (const [key, list] of collection) {
              merged.set(key, (merged.get(key) || []).concat(list));
            }
          }
          diagnostics.clear();
          for (const [key, list] of merged) {
            diagnostics.set(key, list);
          }
        };
        return {
          set(uri, list) {
            own.set(uri.toString(), list);
            all();
          },
          get: (uri) => own.get(uri.toString()),
          delete(uri) {
            own.delete(uri.toString());
            all();
          },
          dispose() {},
        };
      },
      getDiagnostics: (uri) => diagnostics.get(uri.toString()) || [],
      registerDocumentFormattingEditProvider: (selector, provider) => registry.formatting.push(provider) && disposable,
      registerCodeActionsProvider: (selector, provider) => registry.codeActions.push(provider) && disposable,
      registerHoverProvider: (selector, provider) => registry.hovers.push(provider) && disposable,
    },
    workspace: {
      textDocuments: [],
      workspaceFolders: undefined,
      getConfiguration: () => ({ get: (key) => settings[key] }),
      findFiles: async () => registry.files.map((file) => Uri.file(file)),
      createFileSystemWatcher: () => ({ onDidCreate() {}, onDidChange() {}, onDidDelete() {}, dispose() {} }),
      openTextDocument: async (uri) => registry.openDocument(uri),
      applyEdit: async (edit) => {
        registry.applied.push(edit);
        return true;
      },
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
      createStatusBarItem: (id) => (id === "epitech.check" ? registry.checkStatus = { show() {
        this.visible = true;
      }, hide() {}, dispose() {} } : status),
      registerTreeDataProvider: (id, provider) => {
        registry.trees[id] = provider;
        return disposable;
      },
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

  // VS Code's globalState.
  const memento = (() => {
    const values = new Map();
    return { get: (key, fallback) => (values.has(key) ? values.get(key) : fallback),
      update: async (key, value) => values.set(key, value) };
  })();

  return { vscode, registry, settings, status, diagnostics, TextDocument, editor, apply, memento,
    readDocument: (file) => new TextDocument(file, fs.readFileSync(file, "utf8")) };
}

module.exports = { create };
