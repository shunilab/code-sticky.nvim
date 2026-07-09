local h = dofile("test/helper.lua")
local store = require("code-sticky.store")
local notes = require("code-sticky.notes")

---@param root string
local function write_long_sample(root)
  vim.fn.writefile({
    "line1", "line2", "line3", "line4", "line5", "line6", "line7", "line8",
  }, root .. "/lua/sample.lua")
end

-- jump: <CR> on an entry opens the noted file at the noted line.
do
  local root = h.scaffold()
  write_long_sample(root)
  store.upsert_notes(root, "lua/sample.lua", 4, nil, { "? why" })

  -- open a buffer under `root` first so store.root(0) inside open_list()
  -- resolves to this project, not a leftover buffer from an earlier block.
  vim.cmd.edit(root .. "/lua/sample.lua")
  notes.open_list()
  local lnum = vim.fn.search("^## lua/sample.lua:4$")
  h.ok(lnum > 0, "heading found in notes.md")

  notes.jump()
  h.eq(root .. "/lua/sample.lua", vim.fs.normalize(vim.api.nvim_buf_get_name(0)), "jump opens the noted file")
  h.eq(4, vim.api.nvim_win_get_cursor(0)[1], "jump lands on the noted line")

  vim.cmd("%bwipeout!")
end

-- jump clamps to the file's current length when the noted line no longer exists.
do
  local root = h.scaffold()
  write_long_sample(root)
  store.upsert_notes(root, "lua/sample.lua", 100, nil, { "stale note" })

  vim.cmd.edit(root .. "/lua/sample.lua")
  notes.open_list()
  vim.fn.search("^## lua/sample.lua:100$")
  notes.jump()
  h.eq(8, vim.api.nvim_win_get_cursor(0)[1], "jump clamps to last line")

  vim.cmd("%bwipeout!")
end

-- archive_at_cursor: entry under cursor moves from notes.md to archive.md.
do
  local root = h.scaffold()
  write_long_sample(root)
  store.upsert_notes(root, "lua/sample.lua", 2, nil, { "! leaky handle" })
  store.upsert_notes(root, "lua/sample.lua", 6, nil, { "unrelated memo" })

  vim.cmd.edit(root .. "/lua/sample.lua")
  notes.open_list()
  vim.fn.search("^## lua/sample.lua:2$")
  notes.archive_at_cursor()

  local doc = store.read_notes(root)
  h.eq(1, #doc.entries, "one entry remains in notes.md")
  h.eq(6, doc.entries[1].lnum, "the untouched entry remains")

  local adoc = store.read_archive(root)
  h.eq(1, #adoc.entries, "one entry moved to archive.md")
  h.eq(2, adoc.entries[1].lnum, "archived entry has the right lnum")
  h.ok(adoc.entries[1].heading_suffix ~= nil, "archived entry has an archived-at stamp")

  vim.cmd("%bwipeout!")
end

-- archive_at_cursor flushes unsaved edits to notes.md before archiving.
do
  local root = h.scaffold()
  write_long_sample(root)
  store.upsert_notes(root, "lua/sample.lua", 3, nil, { "original" })

  vim.cmd.edit(root .. "/lua/sample.lua")
  notes.open_list()
  local lnum = vim.fn.search("^## lua/sample.lua:3$")
  vim.api.nvim_buf_set_lines(0, lnum, lnum + 1, false, { "edited before archive" })
  vim.api.nvim_win_set_cursor(0, { lnum, 0 })

  notes.archive_at_cursor()

  local adoc = store.read_archive(root)
  h.eq({ "edited before archive" }, adoc.entries[1].body, "archived entry reflects the unsaved edit")

  vim.cmd("%bwipeout!")
end

-- D-4: open_list("archive") opens archive.md instead of notes.md.
do
  local root = h.scaffold()
  write_long_sample(root)
  store.upsert_notes(root, "lua/sample.lua", 2, nil, { "archived note" })
  store.archive(root, { path = "lua/sample.lua", lnum = 2, index = 1 })

  vim.cmd.edit(root .. "/lua/sample.lua")
  notes.open_list("archive")
  h.eq(store.archive_path(root), vim.api.nvim_buf_get_name(0), "open_list(archive) opens archive.md")

  vim.cmd("%bwipeout!")
end

-- D-4: attach(bufnr, {archive=true}) binds K/<CR> but not `ga`, and jump()
-- reads entries from archive.md when the archive buffer is current.
do
  local root = h.scaffold()
  write_long_sample(root)
  store.upsert_notes(root, "lua/sample.lua", 5, nil, { "archived note" })
  store.archive(root, { path = "lua/sample.lua", lnum = 5, index = 1 })

  vim.cmd.edit(store.archive_path(root))
  local archive_bufnr = vim.api.nvim_get_current_buf()
  notes.attach(archive_bufnr, { archive = true })

  local km = require("code-sticky.config").options.notes_keymaps
  h.ok(vim.fn.maparg(km.jump, "n", false, true).buffer == 1, "jump keymap bound on archive buffer")
  h.ok(vim.fn.maparg(km.preview, "n", false, true).buffer == 1, "preview keymap bound on archive buffer")
  h.eq({}, vim.fn.maparg(km.archive, "n", false, true), "archive (ga) keymap NOT bound on archive buffer")

  local lnum = vim.fn.search("^## lua/sample.lua:5")
  vim.api.nvim_win_set_cursor(0, { lnum, 0 })
  notes.jump()
  h.eq(root .. "/lua/sample.lua", vim.fs.normalize(vim.api.nvim_buf_get_name(0)), "jump from archive.md opens the noted file")
  h.eq(5, vim.api.nvim_win_get_cursor(0)[1], "jump from archive.md lands on the noted line")

  vim.cmd("%bwipeout!")
end

h.finish()
