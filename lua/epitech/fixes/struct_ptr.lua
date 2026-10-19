-- C-F7: pass a struct by pointer instead of by copy. The parameter becomes
-- `T const *x`, `x.f` becomes `x->f`, other uses of x become `*x`, the
-- prototypes follow, and call sites get `&`. A function that modifies its
-- copy would modify the caller's struct through a pointer, and one that
-- takes the address of its copy can't be checked, so they get a hint. Call
-- sites come from clangd when it's attached, else from `git grep`; the ones
-- that can't take `&` (a struct returned by a call) go to the quickfix list.
local fixes = require("epitech.fixes")
local project = require("epitech.project")
local ts = require("epitech.ts")
local util = require("epitech.util")

local M = { id = "struct_ptr", rules = { "C-F7" } }

-- Typedef names that stand for a struct, from the project's headers and
-- the given tree.
function M.struct_typedefs(root, tree, source)
  local result = {}
  for name, kind in pairs(ts.typedefs(root, tree, source)) do
    if kind == "struct" then
      result[name] = true
    end
  end
  return result
end

local function is_struct_param(param, source, typedefs)
  local type = param:field("type")[1]
  local declarator = param:field("declarator")[1]
  if not type or not declarator or declarator:type() ~= "identifier" then
    return false
  end
  return type:type() == "struct_specifier" or (type:type() == "type_identifier" and typedefs[ts.text(type, source)])
end

local function operator_text(node, source)
  for child in node:iter_children() do
    if not child:named() then
      return ts.text(child, source), child
    end
  end
end

-- How the body uses parameter `name`: the edits that switch it to a
-- pointer, or a reason not to.
local function body_edits(fn, name, source)
  local edits, reason = {}, nil
  local function write(node)
    local parent = node:parent()
    while parent and (parent:type() == "parenthesized_expression"
      or (parent:type() == "field_expression" and parent:field("argument")[1]:id() == node:id())
      or (parent:type() == "subscript_expression" and parent:field("argument")[1]:id() == node:id())) do
      node, parent = parent, parent:parent()
    end
    if not parent then
      return false
    end
    return parent:type() == "update_expression"
      or (parent:type() == "assignment_expression" and parent:field("left")[1]:id() == node:id())
  end
  local function walk(node)
    for child in node:iter_children() do
      if reason then
        return
      end
      local type = child:type()
      if type == "declaration" or type == "parameter_declaration" then
        for _, declarator in ipairs(child:field("declarator")) do
          local id = ts.declared_name(declarator)
          if id and ts.text(id, source) == name then
            reason = ("another variable named %s hides it"):format(name)
          end
        end
        walk(child)
      elseif type == "call_expression" and ts.text(child:field("function")[1], source) == fn.name then
        reason = "the function calls itself"
      elseif type == "identifier" and ts.text(child, source) == name then
        local parent = child:parent()
        if write(child) then
          reason = ("the function modifies its copy of %s, which a pointer would make the caller's"):format(name)
        elseif parent:type() == "field_expression" and parent:field("argument")[1]:id() == child:id() then
          local op, token = operator_text(parent, source)
          if op == "." then
            edits[#edits + 1] = { range = fixes.range(token), newText = "->" }
          end
        elseif parent:type() == "pointer_expression" and operator_text(parent, source) == "&" then
          reason = ("the address of %s is taken, and what's done with it can't be checked"):format(name)
        else
          edits[#edits + 1] = { range = fixes.range(child), newText = "*" .. name }
        end
      elseif child:named_child_count() > 0 then
        walk(child)
      end
    end
  end
  walk(fn.body)
  return edits, reason
end

-- `point_t p` as `point_t const *p` (`point_t const *` without a name).
local function pointer_text(param, source)
  local type = param:field("type")[1]
  local declarator = param:field("declarator")[1]
  return ts.text(type, source) .. " const *" .. (declarator and ts.text(declarator, source) or "")
end

-- Struct parameters passed by value in the function definitions under tree:
-- { fn, param, index, name, edits } or { fn, param, refused }.
function M.candidates(tree, source, typedefs)
  local result = {}
  for _, fn in ipairs(ts.collect_functions(tree, source)) do
    for index, param in ipairs(fn.params) do
      if is_struct_param(param, source, typedefs) then
        local name = ts.text(param:field("declarator")[1], source)
        local edits, reason = body_edits(fn, name, source)
        local candidate = { fn = fn, param = param, index = index, name = name }
        if reason then
          candidate.refused = reason
        else
          table.insert(edits, 1, { range = fixes.range(param), newText = pointer_text(param, source) })
          candidate.edits = edits
        end
        result[#result + 1] = candidate
      end
    end
  end
  return result
end

local function nth_param(declarator, index)
  local count = 0
  for child in declarator:field("parameters")[1]:iter_children() do
    if child:type() == "parameter_declaration" then
      count = count + 1
      if count == index then
        return child
      end
    end
  end
end

local function nth_argument(call, index)
  local count = 0
  for child in call:field("arguments")[1]:iter_children() do
    if child:named() and child:type() ~= "comment" then
      count = count + 1
      if count == index then
        return child
      end
    end
  end
end

local LVALUES = { identifier = true, field_expression = true, subscript_expression = true }

-- The edits and manual entries for the uses of function `name` in one file:
-- calls get & on their argument, other mentions that aren't declarations go
-- to the quickfix list. `rows` limits it to the given positions (clangd).
local function call_site_edits(path, name, index, positions)
  local src = table.concat(util.read_lines(path), "\n")
  local tree = ts.parse_string(src)
  local edits, manual = {}, {}
  if not tree then
    return edits, manual
  end
  local function wanted(node)
    if not positions then
      return true
    end
    local row, col = node:range()
    for _, position in ipairs(positions) do
      if position[1] == row and position[2] == col then
        return true
      end
    end
    return false
  end
  local function walk(node)
    for child in node:iter_children() do
      if child:type() == "identifier" and ts.text(child, src) == name and wanted(child) then
        local parent = child:parent()
        local row, col = child:range()
        if parent:type() == "call_expression" and parent:field("function")[1]:id() == child:id() then
          local argument = nth_argument(parent, index)
          if argument and LVALUES[argument:type()] then
            local arow, acol = argument:range()
            edits[#edits + 1] = { range = fixes.position_range(arow, acol), newText = "&" }
          elseif argument and argument:type() == "pointer_expression" and operator_text(argument, src) == "*" then
            local operator = argument:child(0)
            edits[#edits + 1] = { range = fixes.range(operator), newText = "" }
          else
            manual[#manual + 1] = { filename = path, lnum = row + 1, col = col + 1,
              text = "pass a pointer here: the argument isn't a variable" }
          end
        elseif parent:type() ~= "function_declarator" then
          manual[#manual + 1] = { filename = path, lnum = row + 1, col = col + 1,
            text = "check this use: " .. name .. " now takes a pointer" }
        end
      elseif child:named_child_count() > 0 then
        walk(child)
      end
    end
  end
  walk(tree)
  return edits, manual
end

-- The workspace edit for a candidate, given the call sites by file
-- ({ [path] = positions or false for every mention }).
local function workspace_edit(buf, root, candidate, sites)
  local changes = { [fixes.uri(buf)] = vim.deepcopy(candidate.edits) }
  local manual = {}
  for _, proto in ipairs(ts.prototypes(buf)) do
    local param = proto.name == candidate.fn.name and nth_param(proto.declarator, candidate.index)
    if param then
      table.insert(changes[fixes.uri(buf)], { range = fixes.range(param), newText = pointer_text(param, buf) })
    end
  end
  for _, proto in ipairs(ts.header_prototypes(root)) do
    local param = proto.name == candidate.fn.name and nth_param(proto.declarator, candidate.index)
    if param then
      local uri = vim.uri_from_fname(root .. "/" .. proto.file)
      changes[uri] = changes[uri] or {}
      table.insert(changes[uri], { range = fixes.range(param), newText = pointer_text(param, proto.source) })
    end
  end
  local own = util.normalize(vim.api.nvim_buf_get_name(buf))
  for path, positions in pairs(sites) do
    if util.normalize(path) ~= own then
      local edits, entries = call_site_edits(path, candidate.fn.name, candidate.index, positions or nil)
      if #edits > 0 then
        local uri = vim.uri_from_fname(path)
        changes[uri] = changes[uri] or {}
        vim.list_extend(changes[uri], edits)
      end
      vim.list_extend(manual, entries)
    else
      -- calls from the definition's own file, outside the function
      local edits, entries = call_site_edits(path, candidate.fn.name, candidate.index, positions or nil)
      vim.list_extend(changes[fixes.uri(buf)], edits)
      vim.list_extend(manual, entries)
    end
  end
  return { changes = changes }, manual
end

-- The files mentioning name, from git grep: { [path] = false }.
local function grep_sites(root, name)
  local result = vim.system({ "git", "grep", "-l", "-w", "-F", "--untracked", "-e", name, "--", "*.c" },
    { cwd = root, text = true }):wait()
  local sites = {}
  for file in vim.gsplit(result.stdout or "", "\n", { plain = true, trimempty = true }) do
    sites[root .. "/" .. file] = false
  end
  return sites
end

-- Call sites from clangd's references: { [path] = { { row, col } } } in
-- byte columns.
local function clangd_sites(client, buf, fn, on_done)
  local name = fn.declarator:field("declarator")[1]
  local row, col = name:range()
  local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
  local params = {
    textDocument = { uri = fixes.uri(buf) },
    position = { line = row, character = vim.str_utfindex(line, client.offset_encoding, col, false) },
    context = { includeDeclaration = false },
  }
  client:request("textDocument/references", params, function(err, result)
    if err or type(result) ~= "table" then
      return on_done(nil)
    end
    local sites = {}
    for _, location in ipairs(result) do
      local path = vim.uri_to_fname(location.uri)
      local lines = util.read_lines(path)
      local loc_line = lines[location.range.start.line + 1] or ""
      local ok, byte = pcall(vim.str_byteindex, loc_line, client.offset_encoding, location.range.start.character, false)
      sites[path] = sites[path] or {}
      table.insert(sites[path], { location.range.start.line, ok and byte or location.range.start.character })
    end
    on_done(sites)
  end, buf)
end

-- The epitech.struct_ptr command: gathers the call sites, then applies
-- everything as one workspace edit.
function M.convert(buf, row, index)
  local tree = ts.root(buf)
  local root = project.root(buf)
  local candidate
  for _, c in ipairs(M.candidates(tree, buf, M.struct_typedefs(root, tree, buf))) do
    if c.fn.signature_row == row and c.index == index and not c.refused then
      candidate = c
    end
  end
  if not candidate then
    return util.notify("Nothing to pass by pointer here anymore", vim.log.levels.WARN)
  end
  local function finish(sites)
    local edit, manual = workspace_edit(buf, root, candidate, sites)
    vim.lsp.util.apply_workspace_edit(edit, "utf-8")
    local message = ("%s is passed by pointer"):format(candidate.name)
    if #manual > 0 then
      vim.fn.setqflist({}, " ", { title = "Epitech: pass " .. candidate.name .. " by pointer", items = manual })
      message = message .. ("; %d %s to fix by hand in the quickfix list"):format(#manual,
        #manual == 1 and "place" or "places")
    end
    util.notify(message)
  end
  local clangd = vim.lsp.get_clients({ bufnr = buf, name = "clangd" })[1]
  if clangd then
    clangd_sites(clangd, buf, candidate.fn, function(sites)
      finish(sites or grep_sites(root, candidate.fn.name))
    end)
  else
    finish(grep_sites(root, candidate.fn.name))
  end
end

local function candidates(buf)
  local tree = ts.root(buf)
  if not tree then
    return {}
  end
  return M.candidates(tree, buf, M.struct_typedefs(project.root(buf), tree, buf))
end

function M.actions(buf, range)
  local actions = {}
  for _, candidate in ipairs(candidates(buf)) do
    if not candidate.refused and fixes.touches(candidate.param, range) then
      actions[#actions + 1] = fixes.command_action(("Pass %s by pointer (C-F7)"):format(candidate.name), "C-F7",
        "epitech.struct_ptr", { fixes.uri(buf), candidate.fn.signature_row, candidate.index })
    end
  end
  return actions
end

function M.hints(src, _, ctx)
  local result = {}
  for _, candidate in ipairs(M.candidates(ctx.tree, src, M.struct_typedefs(ctx.root, ctx.tree, src))) do
    if candidate.refused then
      local row, col, end_row, end_col = candidate.param:range()
      result[#result + 1] = {
        lnum = row,
        col = col,
        end_lnum = end_row,
        end_col = end_col,
        message = "C-F7 no automatic fix: " .. candidate.refused,
        code = "C-F7",
      }
    end
  end
  return result
end

M.commands = {
  ["epitech.struct_ptr"] = function(command)
    local uri, row, index = unpack(command.arguments)
    M.convert(vim.uri_to_bufnr(uri), row, index)
  end,
}

return M
