local h = dofile("test/helper.lua")
local store = require("code-sticky.store")
local float = require("code-sticky.float")
local notes = require("code-sticky.notes")

--- scaffold() only seeds a 3-line sample.lua; tests below need more lines
--- than that to place stickies on, so overwrite it with a longer file.
---@param root string
local function write_long_sample(root)
  vim.fn.writefile({
    "line1", "line2", "line3", "line4", "line5", "line6", "line7", "line8",
  }, root .. "/lua/sample.lua")
end

-- new blank sticky, filled in, then closed: persisted to notes.md.
do
  local root = h.scaffold()
  write_long_sample(root)
  vim.cmd.edit(root .. "/lua/sample.lua")
  vim.api.nvim_win_set_cursor(0, { 2, 0 })

  local handle = float.open_at_cursor({ display = "window" })
  h.ok(handle ~= nil, "open_at_cursor returns a handle")
  h.eq("acwrite", vim.bo[handle.bufnr].buftype, "sticky buffer is acwrite")
  h.eq(false, vim.bo[handle.bufnr].modified, "freshly opened blank sticky is not modified")

  vim.api.nvim_buf_set_lines(handle.bufnr, 0, -1, false, { "? why is this like this" })
  vim.api.nvim_win_close(handle.winid, true) -- simulates the `q` keymap

  local doc = store.read_notes(root)
  h.eq(1, #doc.entries, "one entry persisted")
  h.eq("lua/sample.lua", doc.entries[1].path, "entry path")
  h.eq(2, doc.entries[1].lnum, "entry lnum")
  h.eq({ "? why is this like this" }, doc.entries[1].body, "entry body")

  vim.cmd("bwipeout!")
end

-- new sticky left blank and closed: nothing written, no notes.md created.
do
  local root = h.scaffold()
  write_long_sample(root)
  vim.cmd.edit(root .. "/lua/sample.lua")
  vim.api.nvim_win_set_cursor(0, { 1, 0 })

  local handle = float.open_at_cursor({ display = "window" })
  vim.api.nvim_win_close(handle.winid, true)

  h.ok(vim.fn.filereadable(store.notes_path(root)) == 0, "blank sticky never touches notes.md")

  vim.cmd("bwipeout!")
end

-- reopening the same line loads the existing body, and edits round-trip.
do
  local root = h.scaffold()
  write_long_sample(root)
  store.upsert_notes(root, "lua/sample.lua", 3, nil, { "existing note" })

  vim.cmd.edit(root .. "/lua/sample.lua")
  vim.api.nvim_win_set_cursor(0, { 3, 0 })

  local handle = float.open_at_cursor({ display = "window" })
  h.eq({ "existing note" }, vim.api.nvim_buf_get_lines(handle.bufnr, 0, -1, false), "existing body preloaded")

  vim.api.nvim_buf_set_lines(handle.bufnr, 0, -1, false, { "existing note", "-> resolved now" })
  vim.api.nvim_win_close(handle.winid, true)

  local doc = store.read_notes(root)
  h.eq(1, #doc.entries, "still one entry (edited in place, not duplicated)")
  h.eq({ "existing note", "-> resolved now" }, doc.entries[1].body, "edited body persisted")

  vim.cmd("bwipeout!")
end

-- emptying out an existing sticky and closing deletes the entry.
do
  local root = h.scaffold()
  write_long_sample(root)
  store.upsert_notes(root, "lua/sample.lua", 4, nil, { "to be cleared" })

  vim.cmd.edit(root .. "/lua/sample.lua")
  vim.api.nvim_win_set_cursor(0, { 4, 0 })

  local handle = float.open_at_cursor({ display = "window" })
  vim.api.nvim_buf_set_lines(handle.bufnr, 0, -1, false, { "", "  " })
  vim.api.nvim_win_close(handle.winid, true)

  local doc = store.read_notes(root)
  h.eq(0, #doc.entries, "emptied-out entry is deleted, not left blank")

  vim.cmd("bwipeout!")
end

-- :w saves without closing the float; the buffer and window stay open.
do
  local root = h.scaffold()
  write_long_sample(root)
  vim.cmd.edit(root .. "/lua/sample.lua")
  vim.api.nvim_win_set_cursor(0, { 5, 0 })

  local handle = float.open_at_cursor({ display = "window" })
  vim.api.nvim_buf_set_lines(handle.bufnr, 0, -1, false, { "saved via :w" })
  vim.api.nvim_buf_call(handle.bufnr, function()
    vim.cmd("write")
  end)

  h.ok(vim.api.nvim_win_is_valid(handle.winid), "window stays open after :w")
  h.eq(false, vim.bo[handle.bufnr].modified, ":w clears modified")

  local doc = store.read_notes(root)
  h.eq({ "saved via :w" }, doc.entries[1].body, ":w persisted the body")

  vim.api.nvim_win_close(handle.winid, true)
  vim.cmd("bwipeout!")
end

-- reopening an already-open sticky focuses the existing window instead of
-- creating a duplicate.
do
  local root = h.scaffold()
  write_long_sample(root)
  vim.cmd.edit(root .. "/lua/sample.lua")
  local code_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_cursor(code_win, { 6, 0 })

  local first = float.open_at_cursor({ display = "window" })

  -- switch focus back to the code window before asking to reopen
  vim.api.nvim_set_current_win(code_win)
  vim.api.nvim_win_set_cursor(code_win, { 6, 0 })

  local second = float.open_at_cursor({ display = "window" })
  h.eq(first.bufnr, second.bufnr, "reopening focuses the same sticky buffer")
  h.eq(first.winid, second.winid, "reopening focuses the same sticky window")

  vim.api.nvim_win_close(first.winid, true)
  vim.cmd("bwipeout!")
end

-- smoke: the default display (no opts) takes the nvim_open_win float path,
-- not the "window"/split path every test above uses.
do
  local root = h.scaffold()
  write_long_sample(root)
  vim.cmd.edit(root .. "/lua/sample.lua")
  vim.api.nvim_win_set_cursor(0, { 2, 0 })

  local handle = float.open_at_cursor()
  h.ok(handle ~= nil, "open_at_cursor (default display) returns a handle")
  h.ok(vim.api.nvim_win_get_config(handle.winid).relative ~= "", "default display opens a floating window")

  vim.api.nvim_buf_set_lines(handle.bufnr, 0, -1, false, { "? via default float" })
  vim.api.nvim_win_close(handle.winid, true)

  local doc = store.read_notes(root)
  h.eq(1, #doc.entries, "entry persisted via the default float path")

  vim.cmd("%bwipeout!")
end

-- smoke: notes.preview() (K) opens a floating preview window of the noted
-- code line, and pressing it again closes that same float.
do
  local root = h.scaffold()
  write_long_sample(root)
  store.upsert_notes(root, "lua/sample.lua", 4, nil, { "? why" })

  vim.cmd.edit(root .. "/lua/sample.lua")
  notes.open_list()
  vim.fn.search("^## lua/sample.lua:4$")

  local before = vim.api.nvim_list_wins()
  notes.preview()
  local after = vim.api.nvim_list_wins()
  h.eq(#before + 1, #after, "K opens one new floating window")

  notes.preview()
  h.eq(#before, #vim.api.nvim_list_wins(), "K again closes the preview window")

  vim.cmd("%bwipeout!")
end

-- group: opening a line with 2 existing entries opens both side by side,
-- floating, with focus on the first.
do
  local root = h.scaffold()
  write_long_sample(root)
  store.upsert_notes(root, "lua/sample.lua", 3, nil, { "first" })
  store.upsert_notes(root, "lua/sample.lua", 3, nil, { "second" })

  vim.cmd.edit(root .. "/lua/sample.lua")
  vim.api.nvim_win_set_cursor(0, { 3, 0 })

  local before = vim.api.nvim_list_wins()
  local handle = float.open_at_cursor()
  local after = vim.api.nvim_list_wins()
  h.eq(#before + 2, #after, "opening a 2-entry group opens 2 floats")
  h.eq(vim.api.nvim_get_current_win(), handle.winid, "focus lands on the first entry's window")
  h.eq({ "first" }, vim.api.nvim_buf_get_lines(handle.bufnr, 0, -1, false), "first entry's body preloaded")

  vim.cmd("%bwipeout!")
end

-- group: closing the anchor float (the first one, which siblings were
-- positioned relative to) must not move/garble the still-open sibling's
-- on-screen position.
do
  local root = h.scaffold()
  write_long_sample(root)
  store.upsert_notes(root, "lua/sample.lua", 3, nil, { "first" })
  store.upsert_notes(root, "lua/sample.lua", 3, nil, { "second" })

  vim.cmd.edit(root .. "/lua/sample.lua")
  vim.api.nvim_win_set_cursor(0, { 3, 0 })

  local first = float.open_at_cursor()
  local members = vim.api.nvim_list_wins()
  local second_winid
  for _, w in ipairs(members) do
    if w ~= first.winid and vim.api.nvim_win_get_config(w).relative ~= "" then
      second_winid = w
    end
  end
  h.ok(second_winid ~= nil, "second float found")

  local pos_before = vim.api.nvim_win_get_position(second_winid)
  vim.api.nvim_win_close(first.winid, true) -- close the anchor float first
  h.ok(vim.api.nvim_win_is_valid(second_winid), "sibling float survives anchor close")
  local pos_after = vim.api.nvim_win_get_position(second_winid)
  h.eq(pos_before, pos_after, "sibling float keeps its position after the anchor float closes")

  vim.cmd("%bwipeout!")
end

-- group: <Tab>/<S-Tab> cycle focus between a group's open floats.
do
  local root = h.scaffold()
  write_long_sample(root)
  store.upsert_notes(root, "lua/sample.lua", 3, nil, { "first" })
  store.upsert_notes(root, "lua/sample.lua", 3, nil, { "second" })

  vim.cmd.edit(root .. "/lua/sample.lua")
  vim.api.nvim_win_set_cursor(0, { 3, 0 })

  local first = float.open_at_cursor()
  local win_after_first_open = vim.api.nvim_get_current_win()

  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Tab>", true, false, true), "x", false)
  h.ok(vim.api.nvim_get_current_win() ~= win_after_first_open, "<Tab> moves focus to the sibling float")

  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<S-Tab>", true, false, true), "x", false)
  h.eq(first.winid, vim.api.nvim_get_current_win(), "<S-Tab> cycles focus back to the first float")

  vim.cmd("%bwipeout!")
end

-- group: <C-n> (new_sibling) adds a fresh blank sticky beside the current
-- one and moves focus to it; saving it appends a 2nd entry to the group.
do
  local root = h.scaffold()
  write_long_sample(root)

  vim.cmd.edit(root .. "/lua/sample.lua")
  vim.api.nvim_win_set_cursor(0, { 7, 0 })

  local first = float.open_at_cursor()
  local before = vim.api.nvim_list_wins()

  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-n>", true, false, true), "x", false)

  local after = vim.api.nvim_list_wins()
  h.eq(#before + 1, #after, "<C-n> opens one additional float")
  h.ok(vim.api.nvim_get_current_win() ~= first.winid, "<C-n> moves focus to the new sibling")

  local sibling_bufnr = vim.api.nvim_get_current_buf()
  local sibling_winid = vim.api.nvim_get_current_win()
  vim.api.nvim_buf_set_lines(sibling_bufnr, 0, -1, false, { "second sticky on the same line" })
  vim.api.nvim_win_close(sibling_winid, true)

  local doc = store.read_notes(root)
  h.eq(1, #doc.entries, "closing the sibling (still blank until now) persists it")
  h.eq({ "second sticky on the same line" }, doc.entries[1].body, "sibling body persisted")

  vim.cmd("%bwipeout!")
end

-- group: archiving an entry from inside its float (ga) removes it from
-- notes.md and reindexes the remaining sibling so it still round-trips.
do
  local root = h.scaffold()
  write_long_sample(root)
  store.upsert_notes(root, "lua/sample.lua", 8, nil, { "! fix this" })
  store.upsert_notes(root, "lua/sample.lua", 8, nil, { "keep me" })

  vim.cmd.edit(root .. "/lua/sample.lua")
  vim.api.nvim_win_set_cursor(0, { 8, 0 })

  local first = float.open_at_cursor()
  h.eq({ "! fix this" }, vim.api.nvim_buf_get_lines(first.bufnr, 0, -1, false), "first entry is the one being archived")

  vim.api.nvim_set_current_win(first.winid)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("ga", true, false, true), "x", false)

  local doc = store.read_notes(root)
  h.eq(1, #doc.entries, "archived entry removed from notes.md, sibling remains")
  h.eq({ "keep me" }, doc.entries[1].body, "surviving sibling is now at index 1")

  local adoc = store.read_archive(root)
  h.eq(1, #adoc.entries, "archived entry moved to archive.md")
  h.eq({ "! fix this" }, adoc.entries[1].body, "archived entry body preserved")

  -- the surviving sibling was reindexed in place: emptying it out and
  -- closing should delete the (now sole) entry, not a nonexistent index 2.
  vim.cmd("%bwipeout!")
  vim.cmd.edit(root .. "/lua/sample.lua")
  vim.api.nvim_win_set_cursor(0, { 8, 0 })
  local remaining = float.open_at_cursor()
  vim.api.nvim_buf_set_lines(remaining.bufnr, 0, -1, false, { "" })
  vim.api.nvim_win_close(remaining.winid, true)

  doc = store.read_notes(root)
  h.eq(0, #doc.entries, "reindexed sibling deletes cleanly after archive")

  vim.cmd("%bwipeout!")
end

h.finish()
