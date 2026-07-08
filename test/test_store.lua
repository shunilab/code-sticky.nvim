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

h.finish()
