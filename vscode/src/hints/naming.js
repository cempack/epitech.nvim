// C-F2, C-O4, C-V1: function names without a verb, vague file names, typedef
// names without _t, and macros, enum values and global constants that
// aren't UPPER_SNAKE_CASE. A port of lua/epitech/hints/naming.lua, whose
// word lists it reads from shared/naming.json.
"use strict";

const path = require("path");
const ts = require("../ts");
const data = require("../data");
const { diagnostic } = require("./common");

const id = "naming";
const enabled = (options) => options.naming.enabled;
const lists = require(data.file("shared", "naming.json"));

function hasVerb(name, verbs = lists.verbs) {
  const words = name.toLowerCase().split("_").filter(Boolean);
  if (words[0] === "my") {
    words.shift();
  }
  for (let i = 1; i < words.length - 1; i++) {
    if (words[i] === "to") {
      return true;
    }
  }
  return words.some((word) => verbs.some((verb) => word.startsWith(verb)));
}

const isUpperSnake = (name) => /^_*[A-Z][A-Z0-9_]*$/.test(name);
const upperSnake = (name) => name.replace(/([a-z])([A-Z])/g, "$1_$2").replace(/(\d)([A-Z])/g, "$1_$2").toUpperCase();

function returnsValue(fn) {
  return fn.node.childForFieldName("declarator").type === "pointer_declarator"
    || fn.node.childForFieldName("type").text !== "void";
}

function upperHint(node, what) {
  const name = node.text;
  return isUpperSnake(name) ? undefined
    : diagnostic(node, `C-V1 ${what} in UPPER_SNAKE_CASE → ${upperSnake(name)}?`, "C-V1");
}

// The names of the constant objects a top-level declaration declares.
function constantDeclarators(declaration) {
  const isConst = ts.hasConst(declaration);
  const result = [];
  for (const declarator of declaration.childrenForFieldName("declarator")) {
    let node = declarator;
    let objectConst = isConst;
    if (node.type === "init_declarator") {
      node = node.childForFieldName("declarator");
    }
    while (node && node.type !== "identifier") {
      if (node.type === "pointer_declarator") {
        objectConst = ts.hasConst(node);
      } else if (node.type === "function_declarator") {
        node = null;
        break;
      }
      node = node.childForFieldName("declarator") || node.namedChild(0);
    }
    if (node && objectConst) {
      result.push(node);
    }
  }
  return result;
}

function run(root, source, file, ctx) {
  const options = ctx.options.naming;
  const verbs = options.verbs || lists.verbs;
  const result = [];
  const match = path.basename(file || "").match(/^(.*)\.([ch])$/);
  if (match && (options.vague_files || lists.vague_files).includes(match[1].toLowerCase())) {
    result.push({ line: 0, column: 0, endLine: 0, endColumn: 0, message: `C-O4 vague name: ${match[1]}.${match[2]}`,
      code: "C-O4" });
  }
  for (const fn of ts.functions(root)) {
    if (!lists.classics.includes(fn.name) && !hasVerb(fn.name, verbs)) {
      const name = ts.functionDeclarator(fn.node.childForFieldName("declarator")).childForFieldName("declarator");
      const message = returnsValue(fn) ? `C-F2 no verb → get_${fn.name}?` : `C-F2 no verb in ${fn.name}`;
      result.push(diagnostic(name, message, "C-F2"));
    }
  }
  const walk = (node, top) => {
    for (const child of node.children) {
      const type = child.type;
      let hint;
      if (type === "type_definition") {
        for (const declarator of child.childrenForFieldName("declarator")) {
          const name = ts.declaredName(declarator);
          if (name && !name.text.endsWith("_t")) {
            result.push(diagnostic(name, `C-V1 typedef names end in _t → ${name.text.replace(/_[se]$/, "")
              .toLowerCase()}_t?`, "C-V1"));
          }
        }
      } else if (type === "preproc_def" || type === "preproc_function_def") {
        hint = upperHint(child.childForFieldName("name"), "macros");
      } else if (type === "enumerator") {
        hint = upperHint(child.childForFieldName("name"), "enum values");
      } else if (type === "declaration" && top) {
        constantDeclarators(child).forEach((name) => {
          const constant = upperHint(name, "global constants");
          if (constant) {
            result.push(constant);
          }
        });
      }
      if (hint) {
        result.push(hint);
      }
      if (type !== "function_definition" && child.namedChildCount > 0) {
        walk(child, top && (type.startsWith("preproc_") || type === "declaration_list"));
      }
    }
  };
  walk(root, true);
  return result;
}

module.exports = { id, enabled, hasVerb, isUpperSnake, upperSnake, lists, run };
