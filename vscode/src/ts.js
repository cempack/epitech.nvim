// Treesitter helpers, as in lua/epitech/ts.lua: the function finder the
// meters and fixes share.
"use strict";

const fs = require("fs");
const path = require("path");
const parser = require("./parser");

const text = (node) => node.text;
const field = (node, name) => node.childForFieldName(name);

// Down a declarator chain to its function_declarator (pointer-returning
// functions wrap it).
function functionDeclarator(node) {
  while (node) {
    const type = node.type;
    if (type === "function_declarator") {
      return node;
    }
    if (type === "pointer_declarator" || type === "parenthesized_declarator" || type === "attributed_declarator") {
      node = field(node, "declarator") || node.namedChild(0);
    } else {
      return undefined;
    }
  }
  return undefined;
}

// (void) is a parameter_declaration too, but declares no parameter.
function isVoidParam(param) {
  const type = field(param, "type");
  return !field(param, "declarator") && type && type.type === "primitive_type" && text(type) === "void";
}

function hasStorageClass(node, word) {
  return node.children.some((child) => child.type === "storage_class_specifier" && text(child) === word);
}

function describe(node) {
  const declarator = functionDeclarator(field(node, "declarator"));
  const name = declarator && field(declarator, "declarator");
  const body = field(node, "body");
  if (!name || name.type !== "identifier" || !body) {
    return undefined;
  }
  const paramList = field(declarator, "parameters");
  const params = [];
  let variadic = false;
  for (const child of paramList.children) {
    if (child.type === "parameter_declaration" && !isVoidParam(child)) {
      params.push(child);
    } else if (child.type === "variadic_parameter") {
      variadic = true;
    }
  }
  return {
    name: text(name),
    node,
    isStatic: hasStorageClass(node, "static"),
    params,
    variadic,
    paramList,
    signatureRow: name.startPosition.row,
    body,
    // C-F4: every line between the braces counts (measured, CLAUDE.md §10).
    bodyLines: Math.max(body.endPosition.row - body.startPosition.row - 1, 0),
    startRow: node.startPosition.row,
    endRow: node.endPosition.row,
  };
}

function functions(root) {
  const result = [];
  const walk = (node) => {
    for (const child of node.children) {
      if (child.type === "function_definition") {
        const fn = describe(child);
        if (fn) {
          result.push(fn);
        }
      } else if (child.namedChildCount > 0) {
        walk(child);
      }
    }
  };
  walk(root);
  return result;
}

// The identifier a declarator declares (int *const a[4] -> a).
function declaredName(node) {
  while (node) {
    if (["identifier", "field_identifier", "type_identifier"].includes(node.type)) {
      return node;
    }
    node = field(node, "declarator") || (node.namedChildCount > 0 ? node.namedChild(0) : null);
  }
  return undefined;
}

const same = (a, b) => Boolean(a && b && a.id === b.id);

// Every function prototype outside function bodies: { name, node,
// declarator, row, emptyParams }.
function prototypes(root) {
  const result = [];
  const walk = (node) => {
    for (const child of node.children) {
      if (child.type === "declaration") {
        for (const declarator of child.childrenForFieldName("declarator")) {
          let fn = declarator;
          while (fn && fn.type === "pointer_declarator") {
            fn = field(fn, "declarator");
          }
          const name = fn && fn.type === "function_declarator" && field(fn, "declarator");
          if (name && name.type === "identifier") {
            result.push({ name: name.text, node: child, declarator: fn, row: name.startPosition.row,
              emptyParams: field(fn, "parameters").namedChildCount === 0 });
          }
        }
      } else if (child.type !== "function_definition" && child.namedChildCount > 0) {
        walk(child);
      }
    }
  };
  walk(root);
  return result;
}

const hasConst = (node) => node.children.some((child) => child.type === "type_qualifier" && child.text === "const");

// Which parameters of a parameter_list are const-qualified.
const paramConsts = (paramList) => paramList.children.filter((child) => child.type === "parameter_declaration")
  .map(hasConst);

const TYPE_KINDS = { struct_specifier: "struct", union_specifier: "union", enum_specifier: "enum",
  primitive_type: "scalar", sized_type_specifier: "scalar" };

// What each typedef under node names: "struct", "union", "enum", "scalar",
// "alias:<other>", or "other".
function scanTypedefs(node, into = {}) {
  for (const child of node.children) {
    if (child.type === "type_definition") {
      const type = field(child, "type");
      let kind = type && TYPE_KINDS[type.type];
      if (!kind && type && type.type === "type_identifier") {
        kind = "alias:" + type.text;
      }
      for (const declarator of child.childrenForFieldName("declarator")) {
        if (declarator.type === "type_identifier") {
          into[declarator.text] = kind || "other";
        } else {
          const name = declaredName(declarator);
          if (name) {
            into[name.text] = "other";
          }
        }
      }
    } else if (child.type !== "function_definition" && child.namedChildCount > 0) {
      scanTypedefs(child, into);
    }
  }
  return into;
}

const DECLARING = new Set(["declaration", "init_declarator", "parameter_declaration", "pointer_declarator",
  "array_declarator", "function_declarator", "parenthesized_declarator", "attributed_declarator"]);

// The names used as values under node (neither called nor declared): a
// function among them is stored as a function pointer.
function valueNames(node, result = new Set()) {
  for (const child of node.children) {
    if (child.type === "identifier") {
      const type = node.type;
      const called = type === "call_expression" && same(field(node, "function"), child);
      const value = field(node, "value");
      const declared = DECLARING.has(type) && !(type === "init_declarator" && same(value, child));
      if (!called && !declared) {
        result.add(child.text);
      }
    } else if (child.namedChildCount > 0) {
      valueNames(child, result);
    }
  }
  return result;
}

// Facts about a file on disk, cached by modification time: its prototypes'
// const parameters, its typedefs, the names it uses as values and its
// functions. Plain data, so no tree outlives its parse.
const factsCache = new Map();

function fileFacts(file) {
  let stat;
  try {
    stat = fs.statSync(file);
  } catch {
    return undefined;
  }
  const key = `${stat.mtimeMs}:${stat.size}`;
  const cached = factsCache.get(file);
  if (cached && cached.key === key) {
    return cached.facts;
  }
  const source = fs.readFileSync(file, "utf8");
  const facts = withTree(source, (root) => ({
    signatures: prototypes(root).map((proto) => ({ name: proto.name,
      consts: paramConsts(field(proto.declarator, "parameters")),
      params: field(proto.declarator, "parameters").children.filter((c) => c.type === "parameter_declaration")
        .map((param) => ({ start: param.startPosition, end: param.endPosition,
          constText: `${field(param, "type") ? field(param, "type").text : ""} const ${field(param, "declarator")
            ? field(param, "declarator").text : "*"}` })),
      start: proto.node.startPosition, end: proto.node.endPosition })),
    lines: source.split("\n"),
    typedefs: scanTypedefs(root),
    values: valueNames(root),
    functions: functions(root).map((fn) => ({ name: fn.name, isStatic: fn.isStatic, row: fn.signatureRow })),
  }));
  factsCache.set(file, { key, facts });
  return facts;
}

// The project's tracked files matching pathspecs, absolute.
function projectFiles(root, pathspecs) {
  const files = require("./project").files(root, pathspecs) || [];
  return files.map((file) => path.join(root, file));
}

// { name: kind } for the typedefs of the project's headers and of root (a
// tree), aliases resolved; an unknown alias (va_list) is "other".
function typedefs(projectRoot, root) {
  const raw = {};
  for (const file of projectRoot ? projectFiles(projectRoot, ["*.h"]) : []) {
    const facts = fileFacts(file);
    Object.assign(raw, facts ? facts.typedefs : {});
  }
  if (root) {
    scanTypedefs(root, raw);
  }
  const result = {};
  for (let [name, kind] of Object.entries(raw)) {
    for (let steps = 0; kind.startsWith("alias:") && steps < 10; steps++) {
      kind = raw[kind.slice(6)] || "other";
    }
    result[name] = kind.startsWith("alias:") ? "other" : kind;
  }
  return result;
}

// The signatures (name, consts) of the prototypes in the project's headers.
function headerSignatures(projectRoot) {
  return projectFiles(projectRoot, ["*.h"]).flatMap((file) => {
    const facts = fileFacts(file);
    return facts ? facts.signatures : [];
  });
}

// The prototypes of the project's headers: { name, consts, start, end,
// file (absolute), lines (the header's) }.
function headerPrototypes(projectRoot) {
  return projectFiles(projectRoot, ["*.h"]).flatMap((file) => {
    const facts = fileFacts(file);
    return facts ? facts.signatures.map((signature) => ({ ...signature, file, lines: facts.lines })) : [];
  });
}

// Whether a function of the file at `file` is used as a function pointer:
// in that file, or (non-static ones) in another tracked file.
function pointerUses(projectRoot, file, root) {
  let here;
  let elsewhere;
  return (fn) => {
    here = here || valueNames(root);
    if (here.has(fn.name)) {
      return true;
    }
    if (fn.isStatic || !projectRoot) {
      return false;
    }
    if (!elsewhere) {
      elsewhere = new Set();
      const own = file && path.resolve(file);
      for (const other of projectFiles(projectRoot, ["*.c", "*.h"])) {
        const facts = other !== own && fileFacts(other);
        (facts ? facts.values : []).forEach((name) => elsewhere.add(name));
      }
    }
    return elsewhere.has(fn.name);
  };
}

// { name: { file, isStatic, row } } over the project's tracked .c files; a
// non-static definition wins over a static one.
function projectFunctions(projectRoot) {
  const result = {};
  for (const file of projectFiles(projectRoot, ["*.c"])) {
    for (const fn of (fileFacts(file) || { functions: [] }).functions) {
      const known = result[fn.name];
      if (!known || (known.isStatic && !fn.isStatic)) {
        result[fn.name] = { file: path.relative(projectRoot, file), isStatic: fn.isStatic, row: fn.row };
      }
    }
  }
  return result;
}

// Parses source and hands the tree to fn, freeing it afterwards.
function withTree(source, fn) {
  const tree = parser.parse(source);
  try {
    return fn(tree.rootNode);
  } finally {
    tree.delete();
  }
}

// A Treesitter point as a { line, character } position. web-tree-sitter
// parses JavaScript strings, so its columns are already UTF-16 units, which
// is what VS Code counts (Neovim's Treesitter counts bytes instead).
function position(lines, point) {
  return { line: point.row, character: point.column };
}

module.exports = {
  functionDeclarator, isVoidParam, hasStorageClass, describe, functions, withTree, position, declaredName, same,
  prototypes, hasConst, paramConsts, scanTypedefs, valueNames, fileFacts, typedefs, headerSignatures, headerPrototypes,
  pointerUses,
  projectFunctions,
};
