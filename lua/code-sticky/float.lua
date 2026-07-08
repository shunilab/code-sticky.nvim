local config = require("code-sticky.config")
local store = require("code-sticky.store")

local M = {}

--- Per-buffer state for flush/close/group bookkeeping. `slot` is the dedup
--- key for open_entry (equals `tostring(index)` once persisted, "primary"
--- for the single not-yet-saved sticky opened by plain :CodeSticky, or a
--- unique "newN" for extra siblings added via :CodeStickyNew). `order` is a
--- monotonic creation counter used to lay out and cycle through a group's
--- open windows left-to-right.
---@type table<integer, { root: string, path: string, lnum: integer, index: integer|nil, slot: string, order: integer, closing: boolean|nil }>
local state_by_buf = {}

local order_counter = 0
local function next_order()
  order_counter = order_counter + 1
  return order_counter
end

--- Find an already-open sticky buffer/window for (root, path, lnum, slot).
---@return { bufnr: integer, winid: integer }|nil
local function find_open(root, path, lnum, slot)
  for bufnr, st in pairs(state_by_buf) do
    if st.root == root and st.path == path and st.lnum == lnum and st.slot == slot then
      local winid = vim.fn.bufwinid(bufnr)
      if winid ~= -1 then
        return { bufnr = bufnr, winid = winid }
      end
    end
  end
  return nil
end

--- All currently open sticky windows sharing (root, path, lnum), ordered by
--- creation order (used for <Tab>/<S-Tab> cycling).
---@return { bufnr: integer, winid: integer, order: integer }[]
local function group_members(root, path, lnum)
  local members = {}
  for bufnr, st in pairs(state_by_buf) do
    if st.root == root and st.path == path and st.lnum == lnum then
      local winid = vim.fn.bufwinid(bufnr)
      if winid ~= -1 then
        table.insert(members, { bufnr = bufnr, winid = winid, order = st.order })
      end
    end
  end
  table.sort(members, function(a, b)
    return a.order < b.order
  end)
  return members
end

--- After an entry at `removed_index` is deleted/archived, every other open
--- sticky in the same group whose persisted index sits after it must shift
--- down by one to stay in sync with the on-disk group positions.
local function reindex_after_removal(root, path, lnum, removed_index)
  for _, st in pairs(state_by_buf) do
    if st.root == root and st.path == path and st.lnum == lnum and st.index and st.index > removed_index then
      st.index = st.index - 1
      st.slot = tostring(st.index)
    end
  end
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
      st.slot = tostring(st.index)
    end
  elseif blank then
    store.delete_notes(st.root, st.path, st.lnum, st.index)
    reindex_after_removal(st.root, st.path, st.lnum, st.index)
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
    state_by_buf[bufnr] = nil
  end
  if winid and vim.api.nvim_win_is_valid(winid) then
    pcall(vim.api.nvim_win_close, winid, true)
  end
end

--- Archive the entry backing the current sticky buffer, from inside the
--- float itself. Bails out (with a notify) for a not-yet-saved or blank
--- sticky, since there is no persisted entry to move to archive.md.
---@param bufnr integer
local function archive_current(bufnr)
  local st = state_by_buf[bufnr]
  if not st or st.index == nil then
    vim.notify("code-sticky: this sticky hasn't been saved yet", vim.log.levels.WARN)
    return
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  if store.is_blank(lines) then
    vim.notify("code-sticky: sticky is blank, nothing to archive", vim.log.levels.WARN)
    return
  end

  flush(bufnr) -- persist any pending edits before moving the entry
  local archived = store.archive(st.root, { path = st.path, lnum = st.lnum, index = st.index })
  if archived then
    reindex_after_removal(st.root, st.path, st.lnum, st.index)
  end
  st.closing = true
  local winid = vim.fn.bufwinid(bufnr)
  close_and_flush(bufnr, winid ~= -1 and winid or nil)

  local code_bufnr = vim.fn.bufnr(store.resolve_path(st.root, st.path))
  if code_bufnr ~= -1 then
    require("code-sticky.signs").refresh(code_bufnr)
  end
end

---@param bufnr integer
---@param display "float"|"window"
---@param anchor { winid: integer }|nil beside which to lay out this window; nil anchors at the cursor/opens a plain split
---@param enter boolean whether this window should take focus
---@return integer winid
local function create_window(bufnr, display, anchor, enter)
  if display == "window" then
    local prev_win = vim.api.nvim_get_current_win()
    if anchor then
      vim.api.nvim_set_current_win(anchor.winid)
      vim.cmd("vsplit")
    else
      vim.cmd("split")
    end
    vim.api.nvim_win_set_buf(0, bufnr)
    local winid = vim.api.nvim_get_current_win()
    if not enter then
      vim.api.nvim_set_current_win(prev_win)
    end
    return winid
  end
  local opts = config.options.float
  if not anchor then
    return vim.api.nvim_open_win(bufnr, enter, {
      relative = "cursor",
      row = 1,
      col = 0,
      width = opts.width,
      height = opts.height,
      border = opts.border,
      style = "minimal",
    })
  end

  -- Snapshot the anchor's on-screen position now and place this float with
  -- relative="editor" at a fixed offset from it, rather than relative="win"
  -- against the anchor's winid: a win-relative float is repositioned (often
  -- to a garbage location) the moment the window it targets closes, even
  -- though this float itself stays open.
  local pos = vim.api.nvim_win_get_position(anchor.winid)
  local border_pad = (opts.border and opts.border ~= "none") and 1 or 0
  return vim.api.nvim_open_win(bufnr, enter, {
    relative = "editor",
    row = pos[1],
    col = pos[2] + opts.width + border_pad + opts.gap,
    width = opts.width,
    height = opts.height,
    border = opts.border,
    style = "minimal",
  })
end

--- Add a new blank sibling sticky next to the float/window for `bufnr`,
--- focused. Used by :CodeStickyNew / the `new_sibling` float keymap.
---@param bufnr integer
local function new_sibling(bufnr)
  local st = state_by_buf[bufnr]
  if not st then
    return
  end
  local winid = vim.fn.bufwinid(bufnr)
  if winid == -1 then
    return
  end
  local display = vim.api.nvim_win_get_config(winid).relative == "" and "window" or "float"
  M.open_entry(st.root, st.path, st.lnum, nil, {}, display, {
    anchor = { winid = winid },
    enter = true,
    slot = "new" .. next_order(),
  })
end

--- Cycle focus among the open windows of the current sticky's group.
---@param bufnr integer
---@param direction 1|-1
local function focus_cycle(bufnr, direction)
  local st = state_by_buf[bufnr]
  if not st then
    return
  end
  local members = group_members(st.root, st.path, st.lnum)
  if #members <= 1 then
    return
  end
  local cur
  for i, m in ipairs(members) do
    if m.bufnr == bufnr then
      cur = i
      break
    end
  end
  if not cur then
    return
  end
  local target = members[((cur - 1 + direction) % #members) + 1]
  vim.api.nvim_set_current_win(target.winid)
end

--- Open (or focus) a single sticky's float/window.
---@param root string
---@param path string
---@param lnum integer
---@param index integer|nil nil means a brand-new, not-yet-persisted sticky
---@param body string[]
---@param display "float"|"window"|nil
---@param opts2 { anchor: { winid: integer }|nil, enter: boolean|nil, slot: string|nil }|nil
---@return { bufnr: integer, winid: integer }
function M.open_entry(root, path, lnum, index, body, display, opts2)
  opts2 = opts2 or {}
  local enter = opts2.enter
  if enter == nil then
    enter = true
  end
  display = display or "float"
  local slot = opts2.slot or (index and tostring(index)) or "primary"

  local existing = find_open(root, path, lnum, slot)
  if existing then
    if enter then
      vim.api.nvim_set_current_win(existing.winid)
    end
    return existing
  end

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, body)
  vim.bo[bufnr].buftype = "acwrite"
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].filetype = "markdown"
  vim.bo[bufnr].swapfile = false
  pcall(vim.api.nvim_buf_set_name, bufnr, ("code-sticky://%s:%d/%s"):format(path, lnum, slot))
  vim.bo[bufnr].modified = false

  local winid = create_window(bufnr, display, opts2.anchor, enter)
  state_by_buf[bufnr] = { root = root, path = path, lnum = lnum, index = index, slot = slot, order = next_order() }

  if enter then
    if config.options.float.enter_insert then
      vim.cmd("startinsert")
    else
      vim.cmd("stopinsert")
    end
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
  if keymaps.new_sibling then
    vim.keymap.set("n", keymaps.new_sibling, function()
      new_sibling(bufnr)
    end, { buffer = bufnr, desc = "code-sticky: new sibling sticky" })
  end
  if keymaps.focus_next then
    vim.keymap.set("n", keymaps.focus_next, function()
      focus_cycle(bufnr, 1)
    end, { buffer = bufnr, desc = "code-sticky: focus next sticky" })
  end
  if keymaps.focus_prev then
    vim.keymap.set("n", keymaps.focus_prev, function()
      focus_cycle(bufnr, -1)
    end, { buffer = bufnr, desc = "code-sticky: focus previous sticky" })
  end
  if keymaps.archive then
    vim.keymap.set("n", keymaps.archive, function()
      archive_current(bufnr)
    end, { buffer = bufnr, desc = "code-sticky: archive sticky" })
  end

  return { bufnr = bufnr, winid = winid }
end

--- Add a new blank sibling sticky to the group open in the current buffer.
--- Backs :CodeStickyNew.
function M.new_sibling_cmd()
  local bufnr = vim.api.nvim_get_current_buf()
  if not state_by_buf[bufnr] then
    vim.notify("code-sticky: not in a sticky buffer", vim.log.levels.WARN)
    return
  end
  new_sibling(bufnr)
end

--- Open the sticky/stickies on the current cursor line: a blank new one if
--- none exist yet, or every entry in the group laid out side by side (float:
--- anchored at the cursor with each successive one to the right; window:
--- horizontal split then successive vertical splits). Already-open entries
--- are focused rather than duplicated. Focus lands on the first entry.
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

  local first, anchor
  for i, e in ipairs(group) do
    local handle = M.open_entry(root, path, lnum, i, e.body, opts.display, {
      anchor = anchor,
      enter = (i == 1),
    })
    anchor = { winid = handle.winid }
    if i == 1 then
      first = handle
    end
  end
  return first
end

return M
