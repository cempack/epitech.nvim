-- clangd adds an #include when a completion is accepted (LazyVim runs it with
-- --header-insertion=iwyu) or through its "Include … for symbol" quick fix.
-- It picks the header that declares the symbol, which on glibc and recent
-- clang is often an internal one: <bits/…>, <__stddef_size_t.h>,
-- <malloc.h>, <SFML/Graphics/RenderWindow.h>, <criterion/internal/…>. This
-- module rewrites those edits in clangd's answers before the completion
-- plugin or the code action menu sees them: the public header when the
-- symbol is known (malloc → <stdlib.h>), the library's umbrella header
-- (<SFML/Graphics.h>, <criterion/criterion.h>), else no #include at all.
local M = {}

-- Headers a C program includes directly: the C standard, POSIX, and a few
-- Linux ones students use (sys/ioctl.h for the terminal size, ncurses).
local PUBLIC = {}
for _, name in ipairs({
  "assert.h", "complex.h", "ctype.h", "errno.h", "fenv.h", "float.h", "inttypes.h", "iso646.h", "limits.h",
  "locale.h", "math.h", "setjmp.h", "signal.h", "stdalign.h", "stdarg.h", "stdatomic.h", "stdbool.h", "stddef.h",
  "stdint.h", "stdio.h", "stdlib.h", "stdnoreturn.h", "string.h", "tgmath.h", "threads.h", "time.h", "uchar.h",
  "wchar.h", "wctype.h",
  "aio.h", "arpa/inet.h", "cpio.h", "dirent.h", "dlfcn.h", "fcntl.h", "fnmatch.h", "glob.h", "grp.h", "iconv.h",
  "langinfo.h", "libgen.h", "monetary.h", "mqueue.h", "net/if.h", "netdb.h", "netinet/in.h", "netinet/tcp.h",
  "nl_types.h", "poll.h", "pthread.h", "pwd.h", "regex.h", "sched.h", "search.h", "semaphore.h", "spawn.h",
  "strings.h", "sys/ipc.h", "sys/mman.h", "sys/msg.h", "sys/resource.h", "sys/select.h", "sys/sem.h", "sys/shm.h",
  "sys/socket.h", "sys/stat.h", "sys/statvfs.h", "sys/time.h", "sys/times.h", "sys/types.h", "sys/uio.h",
  "sys/un.h", "sys/utsname.h", "sys/wait.h", "syslog.h", "tar.h", "termios.h", "unistd.h", "utime.h", "utmpx.h",
  "wordexp.h",
  "sys/ioctl.h", "sys/sysmacros.h", "sys/xattr.h", "getopt.h", "ncurses.h", "curses.h",
}) do
  PUBLIC[name] = true
end

-- Where the symbols students use most come from, for when clangd names an
-- internal header instead.
local SYMBOLS = {}
local function declare(header, names)
  for name in names:gmatch("%S+") do
    SYMBOLS[name] = header
  end
end
declare("stdio.h", "printf fprintf dprintf sprintf snprintf vprintf vfprintf vdprintf vsprintf vsnprintf puts"
  .. " putchar fputs fputc putc getchar fgetc getc fgets getline getdelim fopen fdopen fclose fflush fread fwrite"
  .. " fseek ftell rewind feof ferror perror remove rename scanf sscanf fscanf FILE EOF stdin stdout stderr BUFSIZ")
declare("stdlib.h", "malloc calloc realloc free exit _Exit abort atexit atoi atol atof strtol strtoul strtod abs"
  .. " labs rand srand qsort bsearch getenv setenv unsetenv system EXIT_SUCCESS EXIT_FAILURE RAND_MAX")
declare("unistd.h", "write read close lseek fork execve execvp execv dup dup2 pipe access isatty getpid getppid"
  .. " chdir getcwd unlink rmdir sleep usleep readlink link symlink getuid getgid STDIN_FILENO STDOUT_FILENO"
  .. " STDERR_FILENO F_OK R_OK W_OK X_OK")
declare("fcntl.h", "open creat O_RDONLY O_WRONLY O_RDWR O_CREAT O_TRUNC O_APPEND O_EXCL O_NONBLOCK")
declare("sys/stat.h", "stat fstat lstat chmod mkdir umask S_ISDIR S_ISREG S_ISLNK S_ISCHR S_ISBLK S_ISFIFO"
  .. " S_ISSOCK S_IRUSR S_IWUSR S_IXUSR S_IRGRP S_IWGRP S_IXGRP S_IROTH S_IWOTH S_IXOTH S_IFMT")
declare("sys/types.h", "ssize_t pid_t off_t mode_t uid_t gid_t ino_t dev_t nlink_t blksize_t blkcnt_t")
declare("stddef.h", "size_t NULL ptrdiff_t offsetof wchar_t")
declare("string.h", "strlen strcmp strncmp strcpy strncpy strdup strndup strcat strncat strchr strrchr strstr"
  .. " strtok strerror strspn strcspn memset memcpy memmove memcmp memchr")
declare("errno.h", "errno ENOENT EACCES EISDIR ENOTDIR ENOMEM EINVAL EIO EEXIST EPERM EBADF EAGAIN EINTR")
declare("stdarg.h", "va_list va_start va_arg va_end va_copy")
declare("stdint.h", "int8_t int16_t int32_t int64_t uint8_t uint16_t uint32_t uint64_t intptr_t uintptr_t"
  .. " INT8_MAX INT16_MAX INT32_MAX INT64_MAX UINT8_MAX UINT16_MAX UINT32_MAX UINT64_MAX SIZE_MAX")
declare("limits.h", "INT_MAX INT_MIN UINT_MAX LONG_MAX LONG_MIN CHAR_MAX CHAR_MIN CHAR_BIT SHRT_MAX PATH_MAX")
declare("stdbool.h", "bool true false")
declare("dirent.h", "opendir readdir closedir rewinddir DIR dirent")
declare("sys/wait.h", "wait waitpid WIFEXITED WEXITSTATUS WIFSIGNALED WTERMSIG WCOREDUMP WIFSTOPPED")
declare("signal.h", "signal kill sigaction raise SIGINT SIGTERM SIGSEGV SIGKILL SIGCHLD SIGQUIT SIGFPE SIGABRT"
  .. " SIG_IGN SIG_DFL")
declare("time.h", "time time_t ctime clock clock_t difftime localtime strftime nanosleep")
declare("pwd.h", "getpwuid getpwnam passwd")
declare("grp.h", "getgrgid getgrnam group")
declare("ctype.h", "isalpha isdigit isalnum isspace isupper islower isprint toupper tolower")
declare("math.h", "sqrt pow fabs floor ceil round cos sin tan atan2 M_PI")
declare("sys/sysmacros.h", "major minor makedev")

-- Libraries with one header to include (CSFML's <SFML/Graphics.h>) and
-- small internal ones clangd tends to pick.
local CRITERION_PUBLIC = {
  ["criterion/criterion.h"] = true,
  ["criterion/redirect.h"] = true,
  ["criterion/parameterized.h"] = true,
  ["criterion/theories.h"] = true,
  ["criterion/logging.h"] = true,
  ["criterion/new/assert.h"] = true,
}

-- Headers no program should include: glibc's and clang's internals.
local function internal(path)
  return path:match("^bits/") or path:match("^asm/") or path:match("^asm%-generic/") or path:match("^linux/")
    or path:match("^gnu/") or path:match("^__") or path:match("^[%w_]+%-linux%-gnu/")
    or vim.list_contains({ "sys/cdefs.h", "features.h", "stdc-predef.h", "malloc.h", "alloca.h" }, path)
end

-- The header to include instead of path for symbol: path itself when it's
-- fine, another header, or nil for none.
function M.header(path, symbol)
  if PUBLIC[path] then
    return path
  end
  local module = path:match("^SFML/(%a+)/")
  if module then
    return "SFML/" .. module .. ".h"
  end
  if path:match("^criterion/") then
    return CRITERION_PUBLIC[path] and path or "criterion/criterion.h"
  end
  if internal(path) then
    return symbol and SYMBOLS[symbol] or nil
  end
  return path
end

-- The text of a buffer's #include lines, to drop an edit that would include
-- a header twice.
local function included(bufnr)
  local headers = {}
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    for _, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
      local header = line:match('^%s*#%s*include%s*[<"]([^>"]+)[>"]')
      if header then
        headers[header] = true
      end
    end
  end
  return headers
end

-- Rewrites the #include edits in a list of text edits. Returns the new list
-- and whether an include was changed or removed.
local function fix_edits(edits, symbol, headers)
  local result, changed = {}, false
  for _, edit in ipairs(edits or {}) do
    local open, path, close = (edit.newText or ""):match('#include%s*([<"])([^>"]+)([>"])')
    if not path or open == '"' then
      result[#result + 1] = edit
    else
      local header = M.header(path, symbol)
      if header == path then
        result[#result + 1] = edit
      else
        changed = true
        if header and not headers[header] then
          headers[header] = true
          result[#result + 1] = vim.tbl_extend("force", edit, {
            newText = edit.newText:gsub("#include%s*<[^>]+>", "#include <" .. header .. ">", 1),
          })
        end
      end
    end
  end
  return result, changed
end

local function symbol_of(item)
  return (item.filterText or item.label or ""):match("[%a_][%w_]*")
end

-- Fixes the items of a textDocument/completion (or completionItem/resolve)
-- result in place.
function M.fix_completion(result, bufnr)
  if type(result) ~= "table" then
    return result
  end
  local items = result.items or (result.label and { result }) or result
  local headers = included(bufnr)
  for _, item in ipairs(items) do
    if item.additionalTextEdits then
      local edits, changed = fix_edits(item.additionalTextEdits, symbol_of(item), vim.deepcopy(headers))
      if changed then
        item.additionalTextEdits = #edits > 0 and edits or nil
        -- clangd marks items that insert an include with a bullet.
        if not item.additionalTextEdits and item.label then
          item.label = item.label:gsub("^•", " ")
        end
      end
    end
  end
  return result
end

-- clangd's quick fix: "Include <bits/…> for symbol malloc".
local INCLUDE_TITLE = '^Include ([<"])([^>"]+)([>"]) for symbol ([%a_][%w_]*)$'

-- Fixes or drops the include quick fixes of a textDocument/codeAction
-- result.
function M.fix_code_actions(result, bufnr)
  if type(result) ~= "table" then
    return result
  end
  local kept = {}
  for _, action in ipairs(result) do
    local open, path, _, symbol = (action.title or ""):match(INCLUDE_TITLE)
    local header = path
    if open == "<" then
      header = M.header(path, symbol)
    end
    if header == path or not action.edit then
      kept[#kept + 1] = action
    elseif header and not included(bufnr)[header] then
      action.title = ("Include <%s> for symbol %s"):format(header, symbol)
      for _, edits in pairs(action.edit.changes or {}) do
        local fixed = fix_edits(edits, symbol, {})
        for i, edit in ipairs(fixed) do
          edits[i] = edit
        end
      end
      for _, change in ipairs(action.edit.documentChanges or {}) do
        change.edits = (fix_edits(change.edits, symbol, {}))
      end
      kept[#kept + 1] = action
    end
  end
  return kept
end

local FIXERS = {
  ["textDocument/completion"] = M.fix_completion,
  ["completionItem/resolve"] = M.fix_completion,
  ["textDocument/codeAction"] = M.fix_code_actions,
}

-- Wraps a clangd client's request() so the handlers (blink.cmp's, nvim-cmp's,
-- the code action menu's) get the fixed results. Both client:request(…) and
-- the older client.request(…) keep working.
function M.attach(client)
  if client.name ~= "clangd" or client._epitech_includes then
    return
  end
  client._epitech_includes = true
  local request = client.request
  client.request = function(...)
    local args = { ... }
    if getmetatable(args[1]) ~= getmetatable(client) then
      table.insert(args, 1, client)
    end
    local _, method, params, handler, bufnr = unpack(args, 1, 5)
    -- Read at each call: setup() may have turned the option off since.
    local fix = require("epitech.config").options.clangd.fix_includes and FIXERS[method]
    handler = handler or client.handlers[method] or vim.lsp.handlers[method]
    if fix and handler then
      local inner = handler
      handler = function(err, result, ctx, config)
        local ok, fixed = pcall(fix, result, ctx and ctx.bufnr or bufnr)
        return inner(err, ok and fixed or result, ctx, config)
      end
    end
    return request(client, method, params, handler, bufnr)
  end
end

function M.setup(options)
  local group = vim.api.nvim_create_augroup("epitech.clangd", { clear = true })
  if not options.clangd.fix_includes then
    return
  end
  vim.api.nvim_create_autocmd("LspAttach", {
    group = group,
    callback = function(args)
      local client = vim.lsp.get_client_by_id(args.data.client_id)
      if client then
        M.attach(client)
      end
    end,
  })
  for _, client in ipairs(vim.lsp.get_clients({ name = "clangd" })) do
    M.attach(client)
  end
end

return M
