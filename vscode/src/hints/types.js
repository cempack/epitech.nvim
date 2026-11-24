// C-A1 and C-A2 (grader, Info): pointer parameters whose data is never
// modified could point to const, and an int holding strlen() or sizeof
// would be a size_t. Conservative: any use it can't classify means no hint.
// A port of lua/epitech/hints/types.lua.
"use strict";

const ts = require("../ts");
const { diagnostic } = require("./common");

const id = "types";
const enabled = (options) => options.types;

// Library functions whose pointer parameters at these positions are const.
const CONST_PARAMS = {
  write: [2], strlen: [1], strcmp: [1, 2], strncmp: [1, 2], strdup: [1], strndup: [1], strchr: [1], strrchr: [1],
  strstr: [1, 2], strcpy: [2], strncpy: [2], strcat: [2], strncat: [2], memcmp: [1, 2], memcpy: [2], memmove: [2],
  printf: [1], dprintf: [2], puts: [1], fputs: [1], atoi: [1], atol: [1], open: [1], access: [1], stat: [1],
  opendir: [1], execve: [1], getenv: [1], perror: [1],
};

const operator = (node) => node.child(0) && node.child(0).text;
const same = ts.same;

function up(node) {
  let parent = node.parent;
  while (parent && parent.type === "parenthesized_expression") {
    node = parent;
    parent = parent.parent;
  }
  return [parent, node];
}

function constArgument(call, arg, lookup) {
  const name = call.childForFieldName("function");
  if (!name || name.type !== "identifier") {
    return false;
  }
  let index = 0;
  for (const child of call.childForFieldName("arguments").children) {
    if (child.isNamed && child.type !== "comment") {
      index++;
      if (same(child, arg)) {
        break;
      }
    }
  }
  if (CONST_PARAMS[name.text]) {
    return CONST_PARAMS[name.text].includes(index);
  }
  return lookup(name.text, index) === true;
}

const VA_MACROS = new Set(["va_arg", "va_start", "va_end", "va_copy"]);

// What happens to the data node designates: "write", "unclear" or "read".
function access(node, lookup, decays) {
  for (;;) {
    const [parent, child] = up(node);
    const type = parent && parent.type;
    if (type === "assignment_expression") {
      if (same(parent.childForFieldName("left"), child)) {
        return "write";
      }
      return decays ? "unclear" : "read";
    } else if (type === "update_expression") {
      return "write";
    } else if (type === "pointer_expression" && operator(parent) === "&") {
      return "unclear";
    } else if ((type === "field_expression" || type === "subscript_expression")
      && same(parent.childForFieldName("argument"), child)) {
      decays = decays || type === "field_expression";
      node = parent;
    } else if (type === "pointer_expression") {
      node = parent;
    } else if (type === "argument_list") {
      const fn = parent.parent.childForFieldName("function");
      if (fn && VA_MACROS.has(fn.text)) {
        return "write";
      } else if (!decays) {
        return "read";
      }
      return constArgument(parent.parent, child, lookup) ? "read" : "unclear";
    } else if (decays && ["init_declarator", "return_statement", "cast_expression", "conditional_expression"]
      .includes(type)) {
      return "unclear";
    } else {
      return "read";
    }
  }
}

function safeUse(identifier, lookup, copyable) {
  const [parent, child] = up(identifier);
  const type = parent && parent.type;
  if (type === "pointer_expression") {
    return operator(parent) === "*" && access(parent, lookup, !copyable) === "read";
  } else if (type === "subscript_expression" && same(parent.childForFieldName("argument"), child)) {
    return access(parent, lookup, !copyable) === "read";
  } else if (type === "field_expression" && same(parent.childForFieldName("argument"), child)) {
    return parent.child(1).text === "->" && access(parent, lookup, true) === "read";
  } else if (type === "update_expression" || type === "sizeof_expression") {
    return true;
  } else if (type === "assignment_expression") {
    return same(parent.childForFieldName("left"), child);
  } else if (type === "unary_expression") {
    return operator(parent) === "!";
  } else if (type === "binary_expression") {
    const op = parent.child(1).text;
    if (["==", "!=", "<", ">", "<=", ">=", "&&", "||"].includes(op)) {
      return true;
    } else if (op === "+" || op === "-") {
      const [outer, inner] = up(parent);
      if (outer && outer.type === "pointer_expression" && operator(outer) === "*") {
        return access(outer, lookup, !copyable) === "read";
      } else if (outer && outer.type === "argument_list") {
        return constArgument(outer.parent, inner, lookup);
      }
    }
    return false;
  } else if (type === "argument_list") {
    return constArgument(parent.parent, child, lookup);
  } else if (type === "if_statement" || type === "while_statement" || type === "do_statement") {
    return true;
  } else if (type === "conditional_expression") {
    return same(parent.childForFieldName("condition"), child);
  }
  return false;
}

function pointerParam(param) {
  const declarator = param.childForFieldName("declarator");
  const name = declarator && declarator.type === "pointer_declarator" && declarator.childForFieldName("declarator");
  if (!name || name.type !== "identifier" || ts.hasConst(param)) {
    return undefined;
  }
  if (declarator.children.some((child) => child.type === "type_qualifier")) {
    return undefined;
  }
  return name;
}

const PLAIN_TYPES = new Set(["primitive_type", "sized_type_specifier", "struct_specifier", "union_specifier",
  "enum_specifier"]);
const PLAIN_TYPEDEFS = new Set(["struct", "union", "enum", "scalar"]);

function copyable(param, typedefs) {
  const type = param.childForFieldName("type");
  if (!type) {
    return false;
  } else if (PLAIN_TYPES.has(type.type)) {
    return true;
  }
  return type.type === "type_identifier" && PLAIN_TYPEDEFS.has(typedefs()[type.text]);
}

// `char *str` with const after the type, as the PDF writes it.
function constText(param) {
  const declarator = param.childForFieldName("declarator");
  return `${param.childForFieldName("type").text} const ${declarator ? declarator.text : "*"}`;
}

function makeLookup(root, ctx) {
  let signatures;
  return (name, index) => {
    if (!signatures) {
      signatures = {};
      const add = (fname, consts) => {
        signatures[fname] = signatures[fname] || consts;
      };
      for (const proto of ts.prototypes(root)) {
        add(proto.name, ts.paramConsts(proto.declarator.childForFieldName("parameters")));
      }
      for (const fn of ts.functions(root)) {
        add(fn.name, ts.paramConsts(fn.paramList));
      }
      if (ctx.root) {
        for (const signature of ts.headerSignatures(ctx.root)) {
          add(signature.name, signature.consts);
        }
      }
    }
    return signatures[name] && signatures[name][index - 1];
  };
}

// C-A1 candidates: { fn, param, index, name, text }.
function constCandidates(root, ctx = {}, file) {
  const lookup = makeLookup(root, ctx);
  const pointer = ts.pointerUses(ctx.root, file, root);
  let known;
  const typedefs = () => {
    known = known || ts.typedefs(ctx.root, root);
    return known;
  };
  const result = [];
  for (const fn of ts.functions(root)) {
    fn.params.forEach((param, i) => {
      const name = pointerParam(param);
      if (!name || pointer(fn)) {
        return;
      }
      const plain = copyable(param, typedefs);
      let uses = 0;
      let safe = true;
      const walk = (node) => {
        for (const child of node.children) {
          if (!safe) {
            return;
          }
          if (child.type === "identifier" && child.text === name.text) {
            uses++;
            safe = safeUse(child, lookup, plain);
          } else if (child.namedChildCount > 0) {
            walk(child);
          }
        }
      };
      walk(fn.body);
      if (safe && uses > 0) {
        result.push({ fn, param, index: i + 1, name, text: constText(param) });
      }
    });
  }
  return result;
}

const LENGTH_FUNCTIONS = { strlen: "length", my_strlen: "length" };

function measure(value) {
  while (value && value.type === "parenthesized_expression") {
    value = value.namedChild(0);
  }
  if (!value) {
    return undefined;
  } else if (value.type === "sizeof_expression") {
    return "size";
  } else if (value.type === "call_expression") {
    const fn = value.childForFieldName("function");
    return fn && fn.type === "identifier" ? LENGTH_FUNCTIONS[fn.text] : undefined;
  }
  return undefined;
}

function isPlainInt(declaration) {
  const type = declaration.childForFieldName("type");
  return type && type.type === "primitive_type" && type.text === "int";
}

// C-A2: { node, what } for int variables set from strlen, my_strlen or sizeof.
function intLengths(root) {
  const result = [];
  for (const fn of ts.functions(root)) {
    const ints = new Set();
    for (const param of fn.params) {
      const declarator = param.childForFieldName("declarator");
      if (isPlainInt(param) && declarator && declarator.type === "identifier") {
        ints.add(declarator.text);
      }
    }
    const walk = (node) => {
      for (const child of node.children) {
        const type = child.type;
        if (type === "declaration" && isPlainInt(child)) {
          for (const declarator of child.childrenForFieldName("declarator")) {
            if (declarator.type === "identifier") {
              ints.add(declarator.text);
            } else if (declarator.type === "init_declarator") {
              const name = declarator.childForFieldName("declarator");
              if (name.type === "identifier") {
                ints.add(name.text);
                const what = measure(declarator.childForFieldName("value"));
                if (what) {
                  result.push({ node: name, what });
                }
              }
            }
          }
        } else if (type === "assignment_expression" && child.child(1).text === "=") {
          const left = child.childForFieldName("left");
          const what = left.type === "identifier" && ints.has(left.text) && measure(child.childForFieldName("right"));
          if (what) {
            result.push({ node: left, what });
          }
        }
        if (child.namedChildCount > 0) {
          walk(child);
        }
      }
    };
    walk(fn.body);
  }
  return result;
}

function run(root, source, file, ctx) {
  const result = constCandidates(root, ctx, file).map((candidate) =>
    diagnostic(candidate.name, `C-A1 ${candidate.name.text} is never modified → ${candidate.text}`, "C-A1"));
  for (const int of intLengths(root)) {
    result.push(diagnostic(int.node, `C-A2 holds a ${int.what} → size_t?`, "C-A2"));
  }
  return result;
}

module.exports = { id, enabled, CONST_PARAMS, constCandidates, constText, intLengths, run };
