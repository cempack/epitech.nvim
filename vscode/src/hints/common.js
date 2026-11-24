// Shared by the hint modules: a diagnostic { line, column, endLine,
// endColumn, message, code } (0-based, UTF-16 columns) from a node.
"use strict";

function diagnostic(node, message, code) {
  return {
    line: node.startPosition.row,
    column: node.startPosition.column,
    endLine: node.endPosition.row,
    endColumn: node.endPosition.column,
    message,
    code,
  };
}

module.exports = { diagnostic };
