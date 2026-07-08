local h = dofile("test/helper.lua")
local store = require("code-sticky.store")

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

h.finish()
