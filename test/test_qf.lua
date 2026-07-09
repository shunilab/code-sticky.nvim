local h = dofile("test/helper.lua")
require("code-sticky").setup({})
local store = require("code-sticky.store")
local cs = require("code-sticky")

-- no arg: loads every entry, sorted by (path, lnum).
do
  local root = h.scaffold()
  vim.fn.writefile({ "l1", "l2", "l3" }, root .. "/lua/a.lua")
  vim.fn.writefile({ "l1", "l2", "l3" }, root .. "/lua/b.lua")

  store.upsert_notes(root, "lua/b.lua", 1, nil, { "just a memo" })
  store.upsert_notes(root, "lua/a.lua", 2, nil, { "! an issue" })
  store.upsert_notes(root, "lua/a.lua", 1, nil, { "? a question" })

  vim.cmd.edit(root .. "/lua/a.lua")
  cs.dispatch("qf")
  local qf = vim.fn.getqflist()
  h.eq(3, #qf, "qf has all 3 entries with no arg")
  h.ok(qf[1].text:match("question"), "first item is a.lua:1 (question)")
  h.ok(qf[2].text:match("issue"), "second item is a.lua:2 (issue)")
  h.ok(qf[3].text:match("memo"), "third item is b.lua:1 (memo), sorted after a.lua")
  h.eq(1, qf[1].lnum, "first item lnum")
  h.eq(2, qf[2].lnum, "second item lnum")
end

-- class filter: only matching entries are loaded.
do
  local root = h.scaffold()
  vim.fn.writefile({ "l1", "l2", "l3" }, root .. "/lua/sample.lua")
  store.upsert_notes(root, "lua/sample.lua", 1, nil, { "? a question" })
  store.upsert_notes(root, "lua/sample.lua", 2, nil, { "! an issue" })
  store.upsert_notes(root, "lua/sample.lua", 3, nil, { "just a memo" })

  vim.cmd.edit(root .. "/lua/sample.lua")
  cs.dispatch("qf issues")
  local qf = vim.fn.getqflist()
  h.eq(1, #qf, "qf issues filters to 1")
  h.ok(qf[1].text:match("issue"), "filtered qf item text")
end

-- invalid arg: errors without crashing, doesn't clobber the qf list.
do
  local root = h.scaffold()
  vim.fn.writefile({ "l1" }, root .. "/lua/sample.lua")
  store.upsert_notes(root, "lua/sample.lua", 1, nil, { "! an issue" })
  vim.cmd.edit(root .. "/lua/sample.lua")

  cs.dispatch("qf issues")
  local before = vim.fn.getqflist()

  local ok = pcall(cs.dispatch, "qf bogus")
  h.ok(ok, "invalid qf arg does not throw")

  local after = vim.fn.getqflist()
  h.eq(before, after, "invalid qf arg leaves the quickfix list untouched")
end

-- 0 entries: notify-only, no crash, no quickfix window forced open.
do
  local root = h.scaffold()
  vim.fn.writefile({ "l1" }, root .. "/lua/sample.lua")
  vim.cmd.edit(root .. "/lua/sample.lua")

  vim.fn.setqflist({}, "r", { title = "", items = {} })
  local ok = pcall(cs.dispatch, "qf")
  h.ok(ok, "qf with zero entries does not throw")
end

h.finish()
