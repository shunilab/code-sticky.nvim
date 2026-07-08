local config = require("code-sticky.config")
local store = require("code-sticky.store")

local M = {}

--- Open float/window registry, keyed by (root, path, lnum, index) so
--- re-invoking :CodeSticky on an already-open sticky focuses it instead of
--- opening a duplicate.
---@type table<string, { bufnr: integer, winid: integer }>
local registry = {}

--- Per-buffer state for flush/close bookkeeping.
---@type table<integer, { root: string, path: string, lnum: integer, index: integer|nil, key: string, closing: boolean|nil }>
local state_by_buf = {}

local function reg_key(root, path, lnum, index)
  return table.concat({ root, path, tostring(lnum), tostring(index or 0) }, "\0")
end

--- Persist buffer content to notes.md: upsert if non-blank, delete if an
--- existing entry was emptied out, no-op if a brand-new sticky was left
--- blank. Safe to call more than once (idempotent from the caller's view).
---@param bufnr integer
local function flush(bufnr)
  local st = state_by_buf[bufnr]
  if not st or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local blank = store.is_blank(lines)

  if st.index == nil then
    if not blank then
      st.index = store.upsert_notes(st.root, st.path, st.lnum, nil, lines)
    end
  elseif blank then
    store.delete_notes(st.root, st.path, st.lnum, st.index)
  else
    store.upsert_notes(st.root, st.path, st.lnum, st.index, lines)
  end

  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.bo[bufnr].modified = false
  end

  local code_bufnr = vim.fn.bufnr(store.resolve_path(st.root, st.path))
  if code_bufnr ~= -1 then
    require("code-sticky.signs").refresh(code_bufnr)
  end
end

--- Flush (once) and close the float/window for a sticky buffer. Called from
--- the close keymap, WinClosed, and BufWipeout alike; the `closing` flag
--- keeps the flush itself from running twice when those fire in sequence.
---@param bufnr integer
---@param winid integer|nil
local function close_and_flush(bufnr, winid)
  local st = state_by_buf[bufnr]
  if st then
    if not st.closing then
      st.closing = true
      flush(bufnr)
    end
    registry[st.key] = nil
    state_by_buf[bufnr] = nil
  end
  if winid and vim.api.nvim_win_is_valid(winid) then
    pcall(vim.api.nvim_win_close, winid, true)
  end
end

---@param bufnr integer
---@param display "float"|"window"
---@return integer winid
local function create_window(bufnr, display)
  if display == "window" then
    vim.cmd("split")
    vim.api.nvim_win_set_buf(0, bufnr)
    return vim.api.nvim_get_current_win()
  end
  local opts = config.options.float
  return vim.api.nvim_open_win(bufnr, true, {
    relative = "cursor",
    row = 1,
    col = 0,
    width = opts.width,
    height = opts.height,
    border = opts.border,
    style = "minimal",
  })
end

--- Open (or focus) a single sticky's float/window.
---@param root string
---@param path string
---@param lnum integer
---@param index integer|nil nil means a brand-new, not-yet-persisted sticky
---@param body string[]
---@param display "float"|"window"|nil
---@return { bufnr: integer, winid: integer }
function M.open_entry(root, path, lnum, index, body, display)
  display = display or "float"
  local key = reg_key(root, path, lnum, index)
  local existing = registry[key]
  if existing and vim.api.nvim_win_is_valid(existing.winid) then
    vim.api.nvim_set_current_win(existing.winid)
    return existing
  end

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, body)
  vim.bo[bufnr].buftype = "acwrite"
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].filetype = "markdown"
  vim.bo[bufnr].swapfile = false
  pcall(vim.api.nvim_buf_set_name, bufnr, ("code-sticky://%s:%d/%d"):format(path, lnum, index or 0))
  vim.bo[bufnr].modified = false

  local winid = create_window(bufnr, display)
  registry[key] = { bufnr = bufnr, winid = winid }
  state_by_buf[bufnr] = { root = root, path = path, lnum = lnum, index = index, key = key }

  if config.options.float.enter_insert then
    vim.cmd("startinsert")
  else
    vim.cmd("stopinsert")
  end

  local bufaugroup = vim.api.nvim_create_augroup("code_sticky_float_" .. bufnr, { clear = true })

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    group = bufaugroup,
    buffer = bufnr,
    callback = function()
      flush(bufnr)
    end,
  })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = bufaugroup,
    pattern = tostring(winid),
    callback = function()
      close_and_flush(bufnr, nil)
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = bufaugroup,
    buffer = bufnr,
    callback = function()
      close_and_flush(bufnr, nil)
    end,
  })

  local keymaps = config.options.float_keymaps
  local close_lhs = keymaps.close
  if type(close_lhs) ~= "table" then
    close_lhs = { close_lhs }
  end
  for _, lhs in ipairs(close_lhs) do
    vim.keymap.set("n", lhs, function()
      vim.api.nvim_win_close(winid, true)
    end, { buffer = bufnr, desc = "code-sticky: close sticky" })
  end

  return { bufnr = bufnr, winid = winid }
end

--- Open the sticky/stickies on the current cursor line. Task-#4 scope opens
--- a single unit (the first entry, or a blank new one); side-by-side
--- multi-entry layout is added in the follow-up group-features pass.
---@param opts { display: "float"|"window"|nil }|nil
---@return { bufnr: integer, winid: integer }|nil
function M.open_at_cursor(opts)
  opts = opts or {}
  local bufname = vim.api.nvim_buf_get_name(0)
  if bufname == "" then
    vim.notify("code-sticky: buffer has no name", vim.log.levels.ERROR)
    return nil
  end
  local root = store.root(0)
  local path = store.path_for_storage(root, bufname)
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local doc = store.read_notes(root)
  local group = store.group(doc, path, lnum)

  if #group == 0 then
    return M.open_entry(root, path, lnum, nil, {}, opts.display)
  end
  return M.open_entry(root, path, lnum, 1, group[1].body, opts.display)
end

return M
