-- The project check without an editor, for CI and the pre-push hook:
--   nvim --clean --headless -l scripts/check.lua [--ci] [--hook] [root]
-- --ci exits 1 when a level in check.fail_on occurs (Fatal and Major by
-- default; hints never fail it). --hook words that failure for git push.
local script = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p")
local plugin = vim.fs.dirname(vim.fs.dirname(script))
package.path = plugin .. "/lua/?.lua;" .. plugin .. "/lua/?/init.lua;" .. package.path

local ci, hook, root = false, false, nil
for _, argument in ipairs(arg) do
  if argument == "--ci" then
    ci = true
  elseif argument == "--hook" then
    hook = true
  else
    root = argument
  end
end
root = vim.fs.normalize(vim.fn.fnamemodify(root or vim.fn.getcwd(), ":p")):gsub("/$", "")

require("epitech.config").setup()
local check = require("epitech.check")

local result
check.run(root, function(r)
  result = r
end)
vim.wait(30 * 60 * 1000, function()
  return result ~= nil
end, 50)

if result.error then
  io.stderr:write("epitech.nvim: " .. result.error .. "\n")
  os.exit(ci and 1 or 0)
end
if not result.banana then
  io.stderr:write("epitech.nvim: epiclang not found, only the repository rules and hints were checked\n")
end
for _, entry in ipairs(result.entries) do
  io.stdout:write(check.format_entry(entry) .. "\n")
end
io.stdout:write(result.title .. "\n")

local failing = check.failures(result)
if ci and #failing > 0 then
  if hook then
    io.stderr:write(("epitech.nvim: %s left, push stopped. Run :EpitechCheck to see them, or git push --no-verify"
      .. " to skip.\n"):format(table.concat(failing, " and ")))
  end
  os.exit(1)
end
os.exit(0)
