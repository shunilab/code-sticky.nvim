local h = dofile("test/helper.lua")
require("code-sticky").setup({})
local store = require("code-sticky.store")
local cs = require("code-sticky")

-- upsert: append new, then replace by index, then a second sibling appends
-- at the next index.
do
  local root = h.scaffold()
  local idx1 = store.upsert_notes(root, "lua/sample.lua", 10, nil, { "first body" })
  h.eq(1, idx1, "first upsert appends at index 1")

  local doc = store.read_notes(root)
  local group = store.group(doc, "lua/sample.lua", 10)
  h.eq(1, #group, "one entry after first upsert")
  h.eq({ "first body" }, group[1].body, "body stored")

  local idx1b = store.upsert_notes(root, "lua/sample.lua", 10, 1, { "edited body" })
  h.eq(1, idx1b, "replace keeps same index")
  doc = store.read_notes(root)
  group = store.group(doc, "lua/sample.lua", 10)
  h.eq(1, #group, "still one entry after edit")
  h.eq({ "edited body" }, group[1].body, "body replaced")

  local idx2 = store.upsert_notes(root, "lua/sample.lua", 10, nil, { "sibling body" })
  h.eq(2, idx2, "sibling appends at index 2")
  doc = store.read_notes(root)
  group = store.group(doc, "lua/sample.lua", 10)
  h.eq(2, #group, "two entries for the same line")
  h.eq({ "edited body" }, group[1].body, "entry1 unaffected")
  h.eq({ "sibling body" }, group[2].body, "entry2 body")
end

-- delete: removes only the targeted index, siblings keep their relative
-- order (renumbering is the UI layer's job when it re-queries the group).
do
  local root = h.scaffold()
  store.upsert_notes(root, "lua/sample.lua", 20, nil, { "a" })
  store.upsert_notes(root, "lua/sample.lua", 20, nil, { "b" })
  store.upsert_notes(root, "lua/sample.lua", 20, nil, { "c" })

  local ok = store.delete_notes(root, "lua/sample.lua", 20, 2)
  h.ok(ok, "delete reports success")

  local doc = store.read_notes(root)
  local group = store.group(doc, "lua/sample.lua", 20)
  h.eq(2, #group, "one entry removed")
  h.eq({ "a" }, group[1].body, "survivor 1")
  h.eq({ "c" }, group[2].body, "survivor 2 shifted into index 2")

  local missing = store.delete_notes(root, "lua/sample.lua", 20, 99)
  h.ok(not missing, "deleting an out-of-range index reports failure")
end

-- archive by group locator: entry moves from notes.md to archive.md with a
-- timestamp comment, survivor order in notes.md is preserved.
do
  local root = h.scaffold()
  store.upsert_notes(root, "lua/sample.lua", 30, nil, { "keep me" })
  store.upsert_notes(root, "lua/sample.lua", 31, nil, { "? archive me" })

  local archived = store.archive(root, { path = "lua/sample.lua", lnum = 31, index = 1 })
  h.ok(archived ~= nil, "archive returns the removed entry")
  h.eq({ "? archive me" }, archived.body, "archived entry body preserved")

  local notes_doc = store.read_notes(root)
  h.eq(1, #notes_doc.entries, "one entry left in notes.md")
  h.eq(30, notes_doc.entries[1].lnum, "surviving entry is the untouched one")

  local archive_doc = store.read_archive(root)
  h.eq(1, #archive_doc.entries, "one entry in archive.md")
  h.ok(
    archive_doc.entries[1].heading_suffix ~= nil
      and archive_doc.entries[1].heading_suffix:match("archived:"),
    "archived heading carries a timestamp comment"
  )
  h.eq({ "? archive me" }, archive_doc.entries[1].body, "archived body preserved")
end

-- archive by heading_lnum locator (used when the caller is positioned
-- inside notes.md itself).
do
  local root = h.scaffold()
  store.upsert_notes(root, "lua/sample.lua", 40, nil, { "! needs fixing" })
  local doc = store.read_notes(root)
  local heading_lnum = doc.entries[1].heading_lnum
  h.ok(heading_lnum ~= nil, "parsed entry carries heading_lnum")

  local archived = store.archive(root, { heading_lnum = heading_lnum })
  h.ok(archived ~= nil, "archive by heading_lnum succeeds")
  h.eq({ "! needs fixing" }, archived.body, "archived body matches")

  local notes_doc = store.read_notes(root)
  h.eq(0, #notes_doc.entries, "notes.md empty after archiving its only entry")
end

-- undo: an accidental delete (blanking a sticky and closing it) can be
-- undone via store.undo_notes, restoring the lost entry.
do
  local root = h.scaffold()
  store.upsert_notes(root, "lua/sample.lua", 10, nil, { "keep me" })
  store.upsert_notes(root, "lua/sample.lua", 10, nil, { "! oops don't delete me" })
  h.eq(2, #store.read_notes(root).entries, "two entries exist before the accidental delete")

  store.delete_notes(root, "lua/sample.lua", 10, 2)
  h.eq(1, #store.read_notes(root).entries, "one entry left after the accidental delete")

  h.ok(store.undo_notes(root), "undo_notes reports a change")
  local doc = store.read_notes(root)
  h.eq(2, #doc.entries, "undo restores the deleted entry")
  h.eq({ "! oops don't delete me" }, doc.entries[2].body, "restored entry body matches")

  -- Each write_notes call is its own undo step, so undo is repeatable: the
  -- next call steps back one further mutation (undoes the second upsert),
  -- and after all three writes have been undone, there is nothing left.
  h.ok(store.undo_notes(root), "undo_notes steps back further (undoes second upsert)")
  h.eq(1, #store.read_notes(root).entries, "back to one entry after second undo")

  h.ok(store.undo_notes(root), "undo_notes steps back further still (undoes first upsert)")
  h.eq(0, #store.read_notes(root).entries, "back to zero entries after third undo")

  h.eq(false, store.undo_notes(root), "undo_notes is false once nothing is undoable this session")
end

-- redo: undoing then redoing returns to the post-mutation state.
do
  local root = h.scaffold()
  store.upsert_notes(root, "lua/sample.lua", 20, nil, { "will be archived" })
  store.archive(root, { path = "lua/sample.lua", lnum = 20, index = 1 })
  h.eq(0, #store.read_notes(root).entries, "entry archived out of notes.md")

  h.ok(store.undo_notes(root), "undo restores the archived entry to notes.md")
  h.eq(1, #store.read_notes(root).entries, "entry back in notes.md after undo")

  h.ok(store.redo_notes(root), "redo re-applies the archive")
  h.eq(0, #store.read_notes(root).entries, "entry gone again after redo")
end

-- D-3: M.sweep() confirms with the user, batch-archives answered entries,
-- and refreshes signs/floats afterwards. Cancelling the confirm leaves
-- notes.md untouched.
do
  local root = h.scaffold()
  store.upsert_notes(root, "lua/sample.lua", 1, nil, { "just a memo" })
  store.upsert_notes(root, "lua/sample.lua", 2, nil, { "? answered question", "-> because X" })

  vim.cmd.edit(root .. "/lua/sample.lua")

  local orig_confirm = vim.fn.confirm
  vim.fn.confirm = function()
    return 2 -- "No"
  end
  cs.sweep()
  vim.fn.confirm = orig_confirm
  h.eq(2, #store.read_notes(root).entries, "cancelling the confirm leaves notes.md untouched")

  vim.fn.confirm = function()
    return 1 -- "Yes"
  end
  cs.sweep()
  vim.fn.confirm = orig_confirm

  local notes_doc = store.read_notes(root)
  h.eq(1, #notes_doc.entries, "answered entry swept, memo remains")
  h.eq({ "just a memo" }, notes_doc.entries[1].body, "surviving entry is the memo")

  local archive_doc = store.read_archive(root)
  h.eq(1, #archive_doc.entries, "answered entry moved to archive.md")

  vim.cmd("bwipeout!")
end

-- D-3: sweeping with zero answered entries notifies without touching
-- notes.md or prompting for confirmation.
do
  local root = h.scaffold()
  store.upsert_notes(root, "lua/sample.lua", 1, nil, { "just a memo" })

  local confirm_called = false
  local orig_confirm = vim.fn.confirm
  vim.fn.confirm = function()
    confirm_called = true
    return 1
  end
  cs.sweep()
  vim.fn.confirm = orig_confirm

  h.ok(not confirm_called, "no confirm prompt when there is nothing to sweep")
  h.eq(1, #store.read_notes(root).entries, "notes.md untouched")
end

h.finish()
