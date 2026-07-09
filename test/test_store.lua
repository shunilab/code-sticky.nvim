local h = dofile("test/helper.lua")
local store = require("code-sticky.store")

-- parse/serialize round-trip: prelude, multi entries with same key, path
-- containing a colon, trailing blank trimming.
do
  local lines = {
    "prelude line 1",
    "prelude line 2",
    "",
    "## lua/sample.lua:10",
    "first note",
    "",
    "## lua/sample.lua:10",
    "second note on same line",
    "",
    "## weird:path.lua:5",
    "path itself contains a colon",
    "",
  }
  local doc = store.parse(lines)
  h.eq({ "prelude line 1", "prelude line 2" }, doc.prelude, "prelude parsed")
  h.eq(3, #doc.entries, "entry count")
  h.eq("lua/sample.lua", doc.entries[1].path, "entry1 path")
  h.eq(10, doc.entries[1].lnum, "entry1 lnum")
  h.eq({ "first note" }, doc.entries[1].body, "entry1 body")
  h.eq("lua/sample.lua", doc.entries[2].path, "entry2 path (same key)")
  h.eq({ "second note on same line" }, doc.entries[2].body, "entry2 body")
  h.eq("weird:path.lua", doc.entries[3].path, "colon-containing path parsed via last colon")
  h.eq(5, doc.entries[3].lnum, "entry3 lnum")

  local round = store.parse(store.serialize(doc))
  h.eq(doc.prelude, round.prelude, "round-trip prelude")
  for i, e in ipairs(doc.entries) do
    h.eq(e.path, round.entries[i].path, "round-trip path " .. i)
    h.eq(e.lnum, round.entries[i].lnum, "round-trip lnum " .. i)
    h.eq(e.body, round.entries[i].body, "round-trip body " .. i)
  end
end

-- classify: memo / question / issue / answered
do
  h.eq("memo", store.classify({ body = { "just a note" } }), "classify memo")
  h.eq("question", store.classify({ body = { "? why is this here" } }), "classify question")
  h.eq("issue", store.classify({ body = { "! this leaks a handle" } }), "classify issue")
  h.eq(
    "answered",
    store.classify({ body = { "? why is this here", "-> because of X" } }),
    "classify answered question"
  )
  h.eq(
    "answered",
    store.classify({ body = { "! leak", "-> fixed in a1b2c3" } }),
    "classify answered issue"
  )
  h.eq(
    "memo",
    store.classify({ body = { "just a note", "-> unrelated arrow-ish line" } }),
    "memo with -> stays memo (answered only applies to question/issue)"
  )
  h.eq("memo", store.classify({ body = {} }), "classify empty body")
end

-- lazy dir/file creation: read of missing notes.md seeds prelude, but
-- nothing touches disk until write.
do
  local root = h.scaffold()
  local notes_path = store.notes_path(root)
  h.ok(vim.fn.filereadable(notes_path) == 0, "notes.md not created by read")

  local doc = store.read_notes(root)
  h.eq(store.default_prelude(), doc.prelude, "missing file seeded with default prelude")
  h.eq({}, doc.entries, "missing file has no entries")

  store.write_notes(root, doc)
  h.ok(vim.fn.filereadable(notes_path) == 1, "notes.md created on write")
  h.ok(vim.fn.isdirectory(root .. "/.code-sticky") == 1, ".code-sticky dir created")

  local reread = store.read_notes(root)
  h.eq(store.default_prelude(), reread.prelude, "prelude persisted verbatim")
end

-- root/relpath resolution
do
  local root = h.scaffold()
  local abspath = root .. "/lua/sample.lua"
  vim.cmd.edit(abspath)
  h.eq(root, store.root(0), "root resolves via .git marker from an open buffer")
  h.eq("lua/sample.lua", store.relpath(root, abspath), "relpath strips root prefix")
  h.eq(nil, store.relpath(root, "/some/other/place.lua"), "relpath nil for outside file")
  vim.cmd("bwipeout!")
end

-- path_for_storage / resolve_path: in-root files use a relative path,
-- out-of-root files fall back to an absolute (~-collapsed) path.
do
  local root = h.scaffold()
  local inside = root .. "/lua/sample.lua"
  h.eq("lua/sample.lua", store.path_for_storage(root, inside), "in-root path stays relative")
  h.eq(inside, store.resolve_path(root, "lua/sample.lua"), "relative path resolves under root")

  local home = vim.uv.os_homedir()
  local outside = home .. "/somewhere/notes.txt"
  local stored = store.path_for_storage(root, outside)
  h.eq("~/somewhere/notes.txt", stored, "out-of-root path under $HOME is ~-collapsed")
  h.eq(outside, store.resolve_path(root, stored), "~ path resolves back to the absolute path")

  local abs_outside = "/tmp/definitely-outside-code-sticky.txt"
  local stored_abs = store.path_for_storage(root, abs_outside)
  h.eq(abs_outside, stored_abs, "out-of-root path outside $HOME stays a plain absolute path")
  h.eq(abs_outside, store.resolve_path(root, stored_abs), "absolute path resolves to itself")
end

-- end-to-end: an out-of-project file's note round-trips through upsert,
-- read, serialize/parse, and the same path_for_storage lookup signs.lua
-- uses, all staying consistent with each other.
do
  local root = h.scaffold()
  local home = vim.uv.os_homedir()
  local outside_abs = home .. "/somewhere-else/other.lua"
  local stored_path = store.path_for_storage(root, outside_abs)
  h.eq("~/somewhere-else/other.lua", stored_path, "out-of-root note key is ~-collapsed")

  store.upsert_notes(root, stored_path, 10, nil, { "? what does this do" })

  local doc = store.read_notes(root)
  h.eq(1, #doc.entries, "one entry written for the out-of-root file")
  h.eq("~/somewhere-else/other.lua", doc.entries[1].path, "entry stores the ~-collapsed path")
  h.eq(10, doc.entries[1].lnum, "entry stores the line number")

  -- serialize/parse round-trip preserves the ~ heading.
  local round = store.parse(store.serialize(doc))
  h.eq("~/somewhere-else/other.lua", round.entries[1].path, "round-trip keeps ~ path")

  -- the same lookup signs.lua performs (path_for_storage on the buffer's
  -- absolute name) finds the entry back.
  local status = store.line_status(root, store.path_for_storage(root, outside_abs))
  h.eq("question", status[10], "line_status finds the entry via path_for_storage")

  -- and resolve_path recovers the original absolute path.
  h.eq(outside_abs, store.resolve_path(root, doc.entries[1].path), "resolve_path recovers the absolute path")
end

-- collect: sorted by (path, lnum), filterable by classification.
do
  local root = h.scaffold()
  store.upsert_notes(root, "lua/b.lua", 5, nil, { "just a memo" })
  store.upsert_notes(root, "lua/a.lua", 20, nil, { "! second in a.lua" })
  store.upsert_notes(root, "lua/a.lua", 10, nil, { "? first in a.lua" })

  local all = store.collect(root)
  h.eq(3, #all, "collect returns every entry with no filter")
  h.eq("lua/a.lua", all[1].entry.path, "sorted by path first")
  h.eq(10, all[1].entry.lnum, "then by lnum within the same path")
  h.eq("question", all[1].class, "class computed via classify")
  h.eq("lua/a.lua", all[2].entry.path, "second item still a.lua")
  h.eq(20, all[2].entry.lnum, "second item is the higher lnum")
  h.eq("lua/b.lua", all[3].entry.path, "b.lua sorts after a.lua")

  local issues_only = store.collect(root, { issue = true })
  h.eq(1, #issues_only, "class_filter narrows to issues")
  h.eq({ "! second in a.lua" }, issues_only[1].entry.body, "filtered entry is the issue")
end

-- B-2: store.archive returns the removed entry's group index (1-based
-- position within its (path, lnum) group before removal), so callers can
-- reindex any open floats on surviving siblings.
do
  local root = h.scaffold()
  store.upsert_notes(root, "lua/sample.lua", 1, nil, { "first" })
  store.upsert_notes(root, "lua/sample.lua", 1, nil, { "second" })
  store.upsert_notes(root, "lua/sample.lua", 1, nil, { "third" })

  local doc = store.read_notes(root)
  local target = doc.entries[2] -- "second"
  local archived, group_index = store.archive(root, { heading_lnum = target.heading_lnum })
  h.eq({ "second" }, archived.body, "archive returns the removed entry")
  h.eq(2, group_index, "group_index is the entry's 1-based position within its group before removal")

  local remaining = store.read_notes(root)
  h.eq(2, #remaining.entries, "two entries remain")
  h.eq({ "first" }, remaining.entries[1].body, "first entry untouched")
  h.eq({ "third" }, remaining.entries[2].body, "third entry shifted down to index 2")
end

-- D-2: sort_notes stably sorts entries by (path, lnum), preserving prelude
-- and group-internal order for same-key duplicates.
do
  local root = h.scaffold()
  store.upsert_notes(root, "lua/b.lua", 5, nil, { "b memo" })
  store.upsert_notes(root, "lua/a.lua", 20, nil, { "a:20 first" })
  store.upsert_notes(root, "lua/a.lua", 20, nil, { "a:20 second" })
  store.upsert_notes(root, "lua/a.lua", 10, nil, { "a:10" })

  local count = store.sort_notes(root)
  h.eq(4, count, "sort_notes returns the entry count")

  local doc = store.read_notes(root)
  h.eq(store.default_prelude(), doc.prelude, "prelude preserved by sort")
  h.eq(4, #doc.entries, "entry count preserved")
  h.eq({ "lua/a.lua", 10 }, { doc.entries[1].path, doc.entries[1].lnum }, "a.lua:10 sorts first")
  h.eq({ "lua/a.lua", 20 }, { doc.entries[2].path, doc.entries[2].lnum }, "a.lua:20 sorts second")
  h.eq({ "a:20 first" }, doc.entries[2].body, "a.lua:20 group keeps original relative order (first)")
  h.eq({ "lua/a.lua", 20 }, { doc.entries[3].path, doc.entries[3].lnum }, "a.lua:20 second entry still adjacent")
  h.eq({ "a:20 second" }, doc.entries[3].body, "a.lua:20 group keeps original relative order (second)")
  h.eq({ "lua/b.lua", 5 }, { doc.entries[4].path, doc.entries[4].lnum }, "b.lua:5 sorts last")
end

-- D-3: sweep_answered batch-archives every answered entry in one write_notes
-- + one archive.md append, leaving unanswered entries untouched.
do
  local root = h.scaffold()
  store.upsert_notes(root, "lua/sample.lua", 1, nil, { "just a memo" })
  store.upsert_notes(root, "lua/sample.lua", 2, nil, { "? unanswered question" })
  store.upsert_notes(root, "lua/sample.lua", 3, nil, { "? answered question", "-> because X" })
  store.upsert_notes(root, "lua/sample.lua", 4, nil, { "! answered issue", "-> fixed in abc123" })

  local count = store.sweep_answered(root)
  h.eq(2, count, "sweep_answered reports the number of answered entries moved")

  local notes_doc = store.read_notes(root)
  h.eq(2, #notes_doc.entries, "two entries remain in notes.md")
  h.eq({ "just a memo" }, notes_doc.entries[1].body, "memo untouched")
  h.eq({ "? unanswered question" }, notes_doc.entries[2].body, "unanswered question untouched")

  local archive_doc = store.read_archive(root)
  h.eq(2, #archive_doc.entries, "two entries moved to archive.md")
  h.eq({ "? answered question", "-> because X" }, archive_doc.entries[1].body, "answered question archived")
  h.eq({ "! answered issue", "-> fixed in abc123" }, archive_doc.entries[2].body, "answered issue archived")
  h.ok(
    archive_doc.entries[1].heading_suffix and archive_doc.entries[1].heading_suffix:match("archived:"),
    "swept entry carries an archived-at timestamp"
  )

  -- second call: nothing left to sweep, no-op (no writes, count 0).
  h.eq(0, store.sweep_answered(root), "second sweep is a no-op")
end

h.finish()
