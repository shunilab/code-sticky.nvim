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
--- wrapping around and echoing a message when it does.
---@param direction "next"|"prev"
function M.jump(direction)
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

  local cur = vim.api.nvim_win_get_cursor(0)[1]
  local target

  if direction == "next" then
    for _, lnum in ipairs(lnums) do
      if lnum > cur then
        target = lnum
        break
      end
    end
    if not target then
      target = lnums[1]
      vim.notify("code-sticky: wrapped to first sticky", vim.log.levels.INFO)
    end
  else
    for i = #lnums, 1, -1 do
      if lnums[i] < cur then
        target = lnums[i]
        break
      end
    end
    if not target then
      target = lnums[#lnums]
      vim.notify("code-sticky: wrapped to last sticky", vim.log.levels.INFO)
    end
  end

  vim.api.nvim_win_set_cursor(0, { target, 0 })
end

return M
