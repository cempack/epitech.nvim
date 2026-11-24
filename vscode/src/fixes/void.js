// Fixes that are plain text edits: { title, rule, range, newText } with
// ranges as { start, end } Treesitter points. A port of lua/epitech/fixes/.
"use strict";

const ts = require("./ts");

// C-F6: `()` becomes `(void)` on named functions (definitions, prototypes,
// main, pointer-returning ones). Function pointers and typedefs keep theirs.
function voidEdits(root) {
  const edits = [];
  const walk = (node) => {
    if (node.type === "function_declarator") {
      const params = node.childForFieldName("parameters");
      const name = node.childForFieldName("declarator");
      if (params && params.namedChildCount === 0 && name && name.type === "identifier") {
        edits.push({
          title: "Add void (C-F6)",
          rule: "C-F6",
          start: params.startPosition,
          end: params.endPosition,
          newText: "(void)",
        });
      }
    }
    for (const child of node.children) {
      walk(child);
    }
  };
  walk(root);
  return edits;
}

function edits(source) {
  return ts.withTree(source, (root) => voidEdits(root));
}

module.exports = { edits, voidEdits };
