// New projects and files, as in lua/epitech/scaffold.lua, lib.lua and
// makefile.lua. test/scaffold.test.js checks the files match the Neovim
// plugin's.
"use strict";

const fs = require("fs");
const path = require("path");
const data = require("./data");
const header = require("./header");
const ts = require("./ts");
const { formatText } = require("./format");

const year = () => String(new Date().getFullYear());
const cHeader = (name, description) => header.headerLines(header.styles.c, name, description, year());

const DEFAULTS = { cc: "epiclang", cflags: "", debug_cflags: "-g3", error_file: true };

const LIBRARIES = [
  { name: "CSFML graphics (graphics, window, system)", flags: ["-lcsfml-graphics", "-lcsfml-window", "-lcsfml-system"] },
  { name: "CSFML audio", flags: ["-lcsfml-audio", "-lcsfml-system"] },
  { name: "CSFML network", flags: ["-lcsfml-network", "-lcsfml-system"] },
  { name: "ncurses", flags: ["-lncurses"] },
  { name: "math (-lm)", flags: ["-lm"] },
];

function libraryFlags(chosen) {
  const flags = [];
  LIBRARIES.forEach((library, i) => {
    if (chosen.includes(i)) {
      for (const flag of library.flags) {
        if (!flags.includes(flag)) {
          flags.push(flag);
        }
      }
    }
  });
  return flags;
}

// `NAME = first \` then one value per line, two tabs in.
function list(variable, values) {
  return values.map((value, i) => {
    const text = i === 0 ? `${variable} = ${value}` : `\t\t${value}`;
    return i < values.length - 1 ? text + " \\" : text;
  });
}

function makefile(name, sources, tests, ldlibs, withLib, options = DEFAULTS) {
  const library = (name.match(/^lib(.+)\.a$/) || [])[1];
  const lines = ["##", `## EPITECH PROJECT, ${year()}`, `## ${name}`, "## File description:", "## Makefile", "##", "",
    `CC = ${options.cc}`, "", "CPPFLAGS = -I./include", ""];
  if (options.cflags !== "") {
    lines.push(`CFLAGS = ${options.cflags}`, "");
  }
  let libs = ldlibs || [];
  if (withLib) {
    lines.push("LDFLAGS = -L./lib/my", "");
    libs = ["-lmy", ...libs];
  }
  if (libs.length > 0) {
    const line = `LDLIBS = ${libs.join(" ")}`;
    lines.push(...(line.length < 80 ? [line] : list("LDLIBS", libs)), "");
  }
  lines.push(`NAME = ${name}`, "", ...list("SRC", sources), "", "OBJ = $(SRC:.c=.o)", "", ...list("TEST_SRC", tests),
    "", "all: $(NAME)", "", "$(NAME): $(OBJ)");
  if (library) {
    lines.push("\tar rc $(NAME) $(OBJ)", "", "unit_tests: CFLAGS += --coverage", "unit_tests: fclean $(NAME)",
      `\t$(CC) -o unit_tests $(TEST_SRC) $(CPPFLAGS) -L. -l${library} -lcriterion \\`, "\t$(LDLIBS) --coverage");
  } else if (withLib) {
    lines.push("\t$(MAKE) -C lib/my", "\t$(CC) -o $(NAME) $(OBJ) $(LDFLAGS) $(LDLIBS)", "", "unit_tests: fclean",
      "\t$(MAKE) -C lib/my", "\t$(CC) -o unit_tests $(filter-out src/main.c, $(SRC)) $(TEST_SRC) \\",
      "\t$(CPPFLAGS) $(CFLAGS) $(LDFLAGS) $(LDLIBS) -lcriterion --coverage");
  } else {
    lines.push("\t$(CC) -o $(NAME) $(OBJ) $(LDLIBS)", "", "unit_tests: fclean",
      "\t$(CC) -o unit_tests $(filter-out src/main.c, $(SRC)) $(TEST_SRC) \\",
      "\t$(CPPFLAGS) $(CFLAGS) $(LDLIBS) -lcriterion --coverage");
  }
  lines.push("", "tests_run: unit_tests", "\t./unit_tests; status=$$?; \\", "\t$(MAKE) --no-print-directory fclean; \\",
    "\texit $$status", "", "clean:");
  if (withLib) {
    lines.push("\t$(MAKE) -C lib/my clean");
  }
  lines.push("\trm -f $(OBJ)", "\trm -f $(OBJ:.o=.gcno) $(OBJ:.o=.gcda)", "\trm -f *.gcno *.gcda", "", "fclean: clean");
  if (withLib) {
    lines.push("\t$(MAKE) -C lib/my fclean");
  }
  lines.push("\trm -f $(NAME)", "\trm -f unit_tests", "", "re: fclean $(NAME)", "");
  let phony = "all clean fclean re unit_tests tests_run";
  if (options.debug_cflags !== "") {
    lines.push(`debug: CFLAGS += ${options.debug_cflags}`, "debug: re", "");
    phony += " debug";
  }
  lines.push(`.PHONY: ${phony}`);
  return lines;
}

const base = (name) => (name.match(/^lib(.+)\.a$/) || [])[1] || name;

const readTemplate = (...parts) => fs.readFileSync(path.join(data.templatesDir, ...parts), "utf8").replace(/\n$/, "")
  .split("\n");

function errorFile(name) {
  return cHeader(name, "Error messages")
    .concat(readTemplate("project", "print_error.c").map((line) => line.replace(/@BASE@/g, base(name))));
}

// libmy -----------------------------------------------------------------

let catalogCache;

const collapse = (text) => text.replace(/\s+/g, " ").replace(/\( /g, "(").replace(/ \)/g, ")").trim();

// { name: { lines, prototype, deps } } from templates/my/. Needs the parser.
function catalog() {
  if (catalogCache) {
    return catalogCache;
  }
  const dir = path.join(data.templatesDir, "my");
  const sources = {};
  for (const file of fs.readdirSync(dir)) {
    const match = file.match(/^(.+)\.c$/);
    if (match) {
      sources[match[1]] = readTemplate("my", file);
    }
  }
  catalogCache = {};
  for (const [name, lines] of Object.entries(sources)) {
    const source = lines.join("\n");
    const entry = { lines, deps: [] };
    ts.withTree(source, (root) => {
      for (const fn of ts.functions(root)) {
        if (fn.name === name) {
          const declarator = fn.node.childForFieldName("declarator");
          const bytes = Buffer.from(source, "utf8");
          entry.prototype = collapse(bytes.subarray(fn.node.startIndex, declarator.endIndex).toString("utf8")) + ";";
        }
      }
    });
    for (const other of Object.keys(sources)) {
      if (other !== name && new RegExp(`(?<![A-Za-z0-9_])${other}\\(`).test(source)) {
        entry.deps.push(other);
      }
    }
    entry.deps.sort();
    catalogCache[name] = entry;
  }
  return catalogCache;
}

function resolveLib(names) {
  const all = [];
  const visit = (name) => {
    const entry = catalog()[name];
    if (entry && !all.includes(name)) {
      all.push(name);
      entry.deps.forEach(visit);
    }
  };
  names.forEach(visit);
  return all.sort();
}

function libHeaderLines(project, names, formatOptions) {
  const lines = cHeader(project, "Prototypes of libmy").concat(["", "#ifndef MY_H_", "    #define MY_H_", ""],
    names.map((name) => catalog()[name].prototype), ["", "#endif"]);
  // C-F3: a long prototype is wrapped like the formatter does.
  try {
    return formatText(lines.join("\n") + "\n", formatOptions).replace(/\n$/, "").split("\n");
  } catch {
    return lines;
  }
}

function libMakefile(project, names, options = DEFAULTS) {
  return ["##", `## EPITECH PROJECT, ${year()}`, `## ${project}`, "## File description:", "## Makefile of libmy", "##",
    "", `CC = ${options.cc}`, "", "NAME = libmy.a", "",
    ...names.map((name, i) => {
      const text = (i === 0 ? "SRC = " : "\t\t") + name + ".c";
      return i < names.length - 1 ? text + " \\" : text;
    }),
    "", "OBJ = $(SRC:.c=.o)", "", "all: $(NAME)", "", "$(NAME): $(OBJ)", "\tar rc $(NAME) $(OBJ)", "", "clean:",
    "\trm -f $(OBJ)", "", "fclean: clean", "\trm -f $(NAME)", "", "re: fclean all", "", ".PHONY: all clean fclean re"];
}

function libTemplates(project, names, options = DEFAULTS, formatOptions) {
  const resolved = resolveLib(names);
  const files = {
    "lib/my/Makefile": libMakefile(project, resolved, options),
    "include/my.h": libHeaderLines(project, resolved, formatOptions),
  };
  for (const name of resolved) {
    files[`lib/my/${name}.c`] = cHeader(project, name).concat([""], catalog()[name].lines);
  }
  return files;
}

// Projects ----------------------------------------------------------------

const ERROR_FILE_LIB = ["my_strlen"];

// { relative path: lines } of a new project. formatOptions are the
// formatter's ({ styleFile, clangFormat }), for my.h.
function templates(name, ldlibs, options = DEFAULTS, formatOptions = { styleFile: data.styleFile }) {
  const b = base(name);
  const guard = header.guardName(b + ".h");
  const files = {};
  const library = b !== name;
  const errors = !library && options.error_file;
  const firstSource = library ? `src/${b}.c` : "src/main.c";
  const sources = [firstSource];
  if (errors) {
    sources.push("src/print_error.c");
    files["src/print_error.c"] = errorFile(name);
    Object.assign(files, libTemplates(name, ERROR_FILE_LIB, options, formatOptions));
  }
  files.Makefile = makefile(name, sources, [`tests/test_${b}.c`], ldlibs, errors, options);
  const projectHeader = cHeader(name, `Declarations for ${name}`).concat(["", `#ifndef ${guard}`, `    #define ${guard}`]);
  if (errors) {
    projectHeader.push(`    #define PROGRAM_NAME "${name}"`, "    #define EXIT_ERROR 84", "",
      "int print_error(char const *subject);", "int print_error_message(char const *message);");
  }
  projectHeader.push("", "#endif");
  files[`include/${b}.h`] = projectHeader;
  if (library) {
    files[firstSource] = cHeader(name, b).concat(["", `#include "${b}.h"`]);
  } else {
    files["src/main.c"] = cHeader(name, "Entry point").concat(["", `#include "${b}.h"`, "", "int main(void)", "{",
      "    return 0;", "}"]);
  }
  files[`tests/test_${b}.c`] = cHeader(name, "Unit tests").concat(["", "#include <criterion/criterion.h>",
    `#include "${b}.h"`, "", `Test(${b.replace(/[^A-Za-z0-9_]/g, "_")}, placeholder)`, "{", "    cr_assert_eq(1, 1);", "}"]);
  // A .gitignore line starting with # is a comment: \#*# is the pattern.
  files[".gitignore"] = ["*.o", "*.a", "*.so", "*.gcda", "*.gcno", "vgcore.*", "*~", "\\#*#", name, "unit_tests"];
  return files;
}

// Writes a new project in dir; refuses when a Makefile exists unless force.
// Returns the files written, or undefined.
function create(dir, name, ldlibs, options = DEFAULTS, formatOptions, force = false) {
  if (fs.existsSync(path.join(dir, "Makefile")) && !force) {
    return undefined;
  }
  const files = templates(name, ldlibs, options, formatOptions);
  for (const [relative, lines] of Object.entries(files)) {
    const file = path.join(dir, relative);
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, lines.join("\n") + "\n");
  }
  return Object.keys(files).sort();
}

// The Makefile ---------------------------------------------------------------

function assignments(lines, variable) {
  const pattern = new RegExp(`^${variable}\\s*[+:]?=\\s*(.*?)\\s*$`);
  const result = [];
  for (let i = 0; i < lines.length; i++) {
    const match = lines[i].match(pattern);
    if (!match) {
      continue;
    }
    const first = i;
    const values = [match[1]];
    while (/\\\s*$/.test(values[values.length - 1]) && lines[i + 1] !== undefined) {
      values[values.length - 1] = values[values.length - 1].replace(/\\\s*$/, "");
      i++;
      values.push(lines[i]);
    }
    const words = values.join(" ").split(/\s+/).filter(Boolean);
    result.push({ first, last: i, words, raw: values.join(" ") });
  }
  return result;
}

// Adds file to the last assignment to variable in the Makefile's lines.
// Returns { lines } (unchanged when it was there), or { error } when the
// Makefile has no such variable or uses $(wildcard …).
function addSource(lines, file, variable = "SRC") {
  const found = assignments(lines, variable);
  const line = `${variable} += ${file}`;
  if (found.length === 0) {
    return { error: `No ${variable} in the Makefile: add \`${line}\` yourself` };
  }
  for (const entry of found) {
    if (entry.raw.includes("$(wildcard")) {
      return { error: `${variable} uses $(wildcard …) in the Makefile: add \`${line}\` yourself if it doesn't pick the file up` };
    }
    if (entry.words.includes(file)) {
      return { lines };
    }
  }
  const result = lines.slice();
  const entry = found[found.length - 1];
  const operator = result[entry.first].match(new RegExp(`^${variable}\\s*([+:]?=)`))[1];
  if (operator === "+=" && entry.first === entry.last) {
    result.splice(entry.last + 1, 0, line);
  } else if (entry.words.length === 0) {
    result[entry.first] = result[entry.first].replace(/\s*$/, "") + " " + file;
  } else {
    const indent = entry.last > entry.first ? result[entry.last].match(/^\s*/)[0] : "\t\t";
    result.splice(entry.last, 1, result[entry.last].replace(/\s*$/, "") + " \\", indent + file);
  }
  return { lines: result };
}

// The lines of a new .c or .h file.
function newFile(file, project, description) {
  const lines = cHeader(project, description);
  if (file.endsWith(".h")) {
    const guard = header.guardName(file);
    lines.push("", `#ifndef ${guard}`, `    #define ${guard}`, "", "#endif");
  }
  return lines;
}

// The variable a new source goes in: TEST_SRC/TESTS_SRC under tests/.
function sourceVariable(relative, makefileLines) {
  if (relative.startsWith("tests/")) {
    const match = ("\n" + makefileLines.join("\n")).match(/\n(TESTS?_SRC)\s*[+:]?=/);
    if (match) {
      return match[1];
    }
  }
  return "SRC";
}

module.exports = {
  DEFAULTS, LIBRARIES, libraryFlags, makefile, base, errorFile, catalog, resolveLib, libTemplates, templates,
  create, assignments, addSource, newFile, sourceVariable, ERROR_FILE_LIB,
};
