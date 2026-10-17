-- Shared by the snippet tests: expands each snippet with its placeholder
-- defaults (${1:x} -> x, mirrors and $0 -> their value or empty) in the
-- context it's meant for, a file or a function body.
local plugin = assert(vim.env.EPITECH_NVIM_DIR, "EPITECH_NVIM_DIR is required")
local M = {}

M.snippets = vim.json.decode(table.concat(vim.fn.readfile(plugin .. "/snippets/c.json"), "\n"))

function M.expand(body)
  local text = table.concat(body, "\n")
  local values = {}
  local count
  repeat
    text, count = text:gsub("%${(%d+):([^%$}{]*)}", function(index, default)
      values[index] = values[index] or default
      return default
    end)
  until count == 0
  text = text:gsub("%${(%d+)}", function(index)
    return values[index] or ""
  end)
  text = text:gsub("%$(%d+)", function(index)
    return values[index] or ""
  end)
  return vim.split(text, "\n", { plain = true })
end

-- Wrappers for the snippets that go in a function body.
local bodies = {
  sw = { "int run_switch(int value)", "{", nil, "    return value;", "}" },
  fori = { "int run_loop(int n)", "{", nil, "    return n;", "}" },
  ife = { "int run_if(int condition)", "{", nil, "}" },
  mal = { "char *run_malloc(int size)", "{", "    char *ptr;", "", nil, "    return ptr;", "}" },
}

-- { prefix = { lines, first, last } }: the expanded snippet in its context,
-- and the rows (1-based) the snippet itself covers.
function M.contexts()
  local result = {}
  for _, snippet in pairs(M.snippets) do
    local lines = M.expand(snippet.body)
    local wrapper = bodies[snippet.prefix]
    if wrapper then
      local context, first = {}, nil
      for i = 1, #wrapper + 1 do
        if wrapper[i] == nil and not first and i <= table.maxn(wrapper) + 1 then
          first = #context + 1
          for _, line in ipairs(lines) do
            context[#context + 1] = "    " .. line
          end
        elseif wrapper[i] then
          context[#context + 1] = wrapper[i]
        end
      end
      result[snippet.prefix] = { context, first, first + #lines - 1 }
    else
      result[snippet.prefix] = { lines, 1, #lines }
    end
  end
  return result
end

return M
