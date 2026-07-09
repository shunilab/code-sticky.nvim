local config = require("code-sticky.config")
local store = require("code-sticky.store")

local M = {}

local preview_ns = vim.api.nvim_create_namespace("code_sticky_preview")
local preview_winid = nil

--- Open notes.md (or, with arg "archive", archive.md) in the current window
--- (created lazily on first save, same as everywhere else in the plugin).
---@param arg string|nil "archive" to open archive.md instead of notes.md
function M.open_list(arg)
  local root = store.root(0)
  if arg == "archive" then
    vim.cmd.edit(store.archive_path(root))
  else
    vim.cmd.edit(store.notes_path(root))
  end
end

--- notes.md vs archive.md is told apart by the current buffer's name, so K
--- and <CR> work the same way whichever of the two is open.
---@param root string
---@return CodeSticky.Doc
local function current_doc(root)
  if vim.api.nvim_buf_get_name(0) == store.archive_path(root) then
    return store.read_archive(root)
  end
  return store.read_notes(root)
end

--- Find the entry whose heading owns `lnum`: the last entry whose
--- heading_lnum is at or before the cursor.
---@param doc CodeSticky.Doc
---@param lnum integer
---@return CodeSticky.Entry|nil
local function entry_at_lnum(doc, lnum)
  local best = nil
  for _, e in ipairs(doc.entries) do
    if e.heading_lnum and e.heading_lnum <= lnum then
      if not best or e.heading_lnum > best.heading_lnum then
        best = e
      end
    end
  end
  return best
end

--- K: float-preview the noted code line (±config.preview.context lines) at
--- the cursor's entry. Pressing K again while the preview is open closes
--- it; otherwise it auto-closes on the next cursor move.
function M.preview()
  if preview_winid and vim.api.nvim_win_is_valid(preview_winid) then
    vim.api.nvim_win_close(preview_winid, true)
    preview_winid = nil
    return
  end

  local root = store.root(0)
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local entry = entry_at_lnum(current_doc(root), lnum)
  if not entry then
    vim.notify("code-sticky: no entry on this line", vim.log.levels.WARN)
    return
  end

  local abspath = store.resolve_path(root, entry.path)
  local code_bufnr = vim.fn.bufadd(abspath)
  vim.fn.bufload(code_bufnr)
  local total = vim.api.nvim_buf_line_count(code_bufnr)
  local ctx = config.options.preview.context
  local from = math.max(0, entry.lnum - 1 - ctx)
  local to = math.min(total, entry.lnum + ctx)
  local lines = vim.api.nvim_buf_get_lines(code_bufnr, from, to, false)

  local scratch = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(scratch, 0, -1, false, lines)
  vim.bo[scratch].filetype = vim.bo[code_bufnr].filetype
  vim.bo[scratch].modifiable = false

  local target_row = entry.lnum - 1 - from
  if target_row >= 0 and target_row < #lines then
    vim.api.nvim_buf_set_extmark(scratch, preview_ns, target_row, 0, {
      end_row = target_row + 1,
      hl_group = "Visual",
      hl_eol = true,
    })
  end

  local width = math.max(20, math.min(vim.o.columns - 10, 80))
  local height = math.max(1, math.min(#lines, 20))
  local notes_bufnr = vim.api.nvim_get_current_buf()
  preview_winid = vim.api.nvim_open_win(scratch, false, {
    relative = "cursor",
    row = 1,
    col = 0,
    width = width,
    height = height,
    border = "rounded",
    style = "minimal",
  })

  vim.api.nvim_create_autocmd({ "CursorMoved", "BufLeave" }, {
    buffer = notes_bufnr,
    once = true,
    callback = function()
      if preview_winid and vim.api.nvim_win_is_valid(preview_winid) then
        vim.api.nvim_win_close(preview_winid, true)
      end
      preview_winid = nil
    end,
  })
end

--- <CR>: jump to the noted file:line (clamped to the file's current length).
function M.jump()
  local root = store.root(0)
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local entry = entry_at_lnum(current_doc(root), lnum)
  if not entry then
    vim.notify("code-sticky: no entry on this line", vim.log.levels.WARN)
    return
  end

  vim.cmd.edit(store.resolve_path(root, entry.path))
  local total = vim.api.nvim_buf_line_count(0)
  vim.api.nvim_win_set_cursor(0, { math.max(1, math.min(entry.lnum, total)), 0 })
end

--- ga: archive the entry under the cursor. Flushes unsaved notes.md edits
--- first, then reloads the buffer so it reflects the post-archive file.
function M.archive_at_cursor()
  local bufnr = vim.api.nvim_get_current_buf()
  if vim.bo[bufnr].modified then
    vim.cmd("write")
  end

  local root = store.root(bufnr)
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local entry = entry_at_lnum(store.read_notes(root), lnum)
  if not entry then
    vim.notify("code-sticky: no entry on this line", vim.log.levels.WARN)
    return
  end

  local archived, group_index = store.archive(root, { heading_lnum = entry.heading_lnum })
  if archived and group_index then
    require("code-sticky.float").reindex_after_removal(root, archived.path, archived.lnum, group_index)
  end
  vim.cmd("edit!")

  local code_bufnr = vim.fn.bufnr(store.resolve_path(root, entry.path))
  if code_bufnr ~= -1 then
    require("code-sticky.signs").refresh(code_bufnr)
  end
end

--- Attach buffer-local keymaps to an open notes.md (or, with opts.archive,
--- archive.md) buffer. archive.md is read-only viewing: K/<CR> work but `ga`
--- (archive) is not bound, since entries there are already archived.
---@param bufnr integer
---@param opts { archive: boolean? }|nil
function M.attach(bufnr, opts)
  opts = opts or {}
  local km = config.options.notes_keymaps
  vim.keymap.set("n", km.preview, M.preview, { buffer = bufnr, desc = "code-sticky: preview noted code" })
  vim.keymap.set("n", km.jump, M.jump, { buffer = bufnr, desc = "code-sticky: jump to noted code" })
  if not opts.archive then
    vim.keymap.set("n", km.archive, M.archive_at_cursor, { buffer = bufnr, desc = "code-sticky: archive entry" })
  end
end

return M
