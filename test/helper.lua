local M = {}

M.failures = {}

--- Assert equality, collecting failures instead of throwing so a single
--- bad assertion doesn't abort the rest of the test file.
function M.eq(expected, actual, msg)
  if not vim.deep_equal(expected, actual) then
    table.insert(
      M.failures,
      ("%s\n  expected: %s\n  actual:   %s"):format(
        msg or "assertion failed",
        vim.inspect(expected),
        vim.inspect(actual)
      )
    )
  end
end

function M.ok(cond, msg)
  if not cond then
    table.insert(M.failures, msg or "expected truthy value")
  end
end

--- Build a throwaway project directory with a sample source file and cd
--- into it, so store.root()/relpath() resolve predictably.
---@param opts { git: boolean? }|nil
---@return string root
function M.scaffold(opts)
  opts = opts or {}
  local root = vim.fn.tempname()
  vim.fn.mkdir(root, "p")
  -- Resolve symlinks (e.g. macOS /var -> /private/var) so the returned root
  -- matches what store.root() resolves via vim.fs.root/normalize.
  root = vim.fs.normalize(vim.uv.fs_realpath(root))
  if opts.git ~= false then
    vim.fn.mkdir(root .. "/.git", "p")
  end
  vim.fn.mkdir(root .. "/lua", "p")
  vim.fn.writefile({ "local M = {}", "", "return M" }, root .. "/lua/sample.lua")
  vim.uv.chdir(root)
  return root
end

function M.finish()
  if #M.failures > 0 then
    for _, f in ipairs(M.failures) do
      print("FAIL: " .. f)
    end
    vim.cmd("cquit 1")
  else
    print("PASS")
    vim.cmd("qall!")
  end
end

return M
