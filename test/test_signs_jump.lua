local h = dofile("test/helper.lua")
local store = require("code-sticky.store")
local signs = require("code-sticky.signs")

local ns = vim.api.nvim_create_namespace("code_sticky_signs")

local function extmark_lines(bufnr)
  local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})
  local lines = {}
  for _, m in ipairs(marks) do
    table.insert(lines, m[2] + 1) -- extmark row is 0-based
  end
  table.sort(lines)
  return lines
end

-- refresh: places one sign per sticky-marked line, with the right kind.
do
  local root = h.scaffold()
  vim.fn.writefile({
    "line1",
    "line2",
    "line3",
    "line4",
    "line5",
  }, root .. "/lua/sample.lua")

  store.upsert_notes(root, "lua/sample.lua", 2, nil, { "just a memo" })
  store.upsert_notes(root, "lua/sample.lua", 4, nil, { "? unresolved question" })

  vim.cmd.edit(root .. "/lua/sample.lua")
  local bufnr = vim.api.nvim_get_current_buf()
  signs.refresh(bufnr)

  h.eq({ 2, 4 }, extmark_lines(bufnr), "signs placed on the two noted lines")

  local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })
  local by_line = {}
  for _, m in ipairs(marks) do
    by_line[m[2] + 1] = m[4]
  end
  h.eq("N", vim.trim(by_line[2].sign_text), "memo line gets the memo sign")
  h.eq("?", vim.trim(by_line[4].sign_text), "question line gets the question sign")

  vim.cmd("bwipeout!")
end

-- jump: ]n/[n style next/prev over sticky lines, wrapping around.
do
  local root = h.scaffold()
  vim.fn.writefile({
    "l1", "l2", "l3", "l4", "l5", "l6", "l7", "l8",
  }, root .. "/lua/sample.lua")

  store.upsert_notes(root, "lua/sample.lua", 3, nil, { "memo a" })
  store.upsert_notes(root, "lua/sample.lua", 6, nil, { "memo b" })

  vim.cmd.edit(root .. "/lua/sample.lua")
  vim.api.nvim_win_set_cursor(0, { 1, 0 })

  signs.jump("next")
  h.eq(3, vim.api.nvim_win_get_cursor(0)[1], "jump next lands on first sticky after cursor")

  signs.jump("next")
  h.eq(6, vim.api.nvim_win_get_cursor(0)[1], "jump next lands on second sticky")

  signs.jump("next")
  h.eq(3, vim.api.nvim_win_get_cursor(0)[1], "jump next wraps back to the first sticky")

  signs.jump("prev")
  h.eq(6, vim.api.nvim_win_get_cursor(0)[1], "jump prev wraps to the last sticky")

  signs.jump("prev")
  h.eq(3, vim.api.nvim_win_get_cursor(0)[1], "jump prev lands on the earlier sticky")

  vim.cmd("bwipeout!")
end

h.finish()
