local config = require("code-sticky.config")
local store = require("code-sticky.store")

local M = {}

local ns = vim.api.nvim_create_namespace("code_sticky_signs")

--- Recompute and redraw signs for a buffer from notes.md. No-op for buffers
--- without a resolvable file, or that live outside any project root's
--- tracked file (still fine to scan; entries just won't match).
---@param bufnr integer
function M.refresh(bufnr)
  bufnr = bufnr or 0
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  if bufname == "" then
    return
  end

  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

  local root = store.root(bufnr)
  local relpath = store.path_for_storage(root, bufname)
  local status = store.line_status(root, relpath)

  local signs = config.options.signs
  local severity = { issue = 3, question = 2, memo = 1, answered = 1 }
  local kind_for = { issue = "issue", question = "question", memo = "memo", answered = "memo" }

  for lnum, cls in pairs(status) do
    local kind = kind_for[cls]
    local sign = signs[kind]
    local line_count = vim.api.nvim_buf_line_count(bufnr)
    if sign and lnum >= 1 and lnum <= line_count then
      vim.api.nvim_buf_set_extmark(bufnr, ns, lnum - 1, 0, {
        sign_text = sign.text,
        sign_hl_group = sign.hl,
        priority = severity[cls] or 1,
      })
    end
  end
end

--- Refresh signs in every currently loaded buffer under `root`. Used after
--- an undo, since we don't know in advance which file(s)' entries changed.
---@param root string
function M.refresh_all(root)
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      local bufname = vim.api.nvim_buf_get_name(bufnr)
      if bufname ~= "" and store.root(bufnr) == root then
        M.refresh(bufnr)
      end
    end
  end
end

--- Jump to the next/previous sticky-marked line in the current buffer,
--- `count` steps at a time, wrapping around (possibly more than once) and
--- echoing a message whenever the walk crosses the start/end boundary.
---@param direction "next"|"prev"
---@param count integer|nil defaults to 1
function M.jump(direction, count)
  count = count or 1
  local bufnr = vim.api.nvim_get_current_buf()
  local root = store.root(bufnr)
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  if bufname == "" then
    return
  end
  local relpath = store.path_for_storage(root, bufname)
  local status = store.line_status(root, relpath)

  local lnums = {}
  for lnum in pairs(status) do
    table.insert(lnums, lnum)
  end
  if #lnums == 0 then
    vim.notify("code-sticky: no stickies in this buffer", vim.log.levels.INFO)
    return
  end
  table.sort(lnums)
  if direction == "prev" then
    local desc = {}
    for i = #lnums, 1, -1 do
      table.insert(desc, lnums[i])
    end
    lnums = desc
  end

  local cur = vim.api.nvim_win_get_cursor(0)[1]
  local base, wrapped
  for i, lnum in ipairs(lnums) do
    if (direction == "next" and lnum > cur) or (direction == "prev" and lnum < cur) then
      base = i
      break
    end
  end
  if not base then
    base = 1
    wrapped = true
  end

  local n = #lnums
  local absolute = base + (count - 1)
  if absolute > n then
    wrapped = true
  end
  local target = lnums[((absolute - 1) % n) + 1]

  vim.api.nvim_win_set_cursor(0, { target, 0 })

  if wrapped then
    vim.notify(
      "code-sticky: wrapped to " .. (direction == "next" and "first" or "last") .. " sticky",
      vim.log.levels.INFO
    )
  end

  if config.options.jump_opens_float then
    require("code-sticky.float").open_at_cursor({ display = "float" })
  end
end

return M
