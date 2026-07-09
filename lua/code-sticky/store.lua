local config = require("code-sticky.config")

local M = {}

---@class CodeSticky.Entry
---@field path string
---@field lnum integer
---@field body string[]
---@field heading_lnum integer|nil
---@field heading_suffix string|nil

---@class CodeSticky.Doc
---@field prelude string[]
---@field entries CodeSticky.Entry[]

--- Resolve the project root for a buffer.
---@param bufnr integer|nil
---@return string
function M.root(bufnr)
  bufnr = bufnr or 0
  local ok, found = pcall(vim.fs.root, bufnr, config.options.root_markers)
  if ok and found then
    return vim.fs.normalize(found)
  end
  return vim.fs.normalize(vim.uv.cwd())
end

--- Compute a project-relative path for an absolute path. Returns nil when
--- `abspath` is outside `root`.
---@param root string
---@param abspath string
---@return string|nil
function M.relpath(root, abspath)
  abspath = vim.fs.normalize(abspath)
  root = vim.fs.normalize(root)
  if root:sub(-1) ~= "/" then
    root = root .. "/"
  end
  if abspath:sub(1, #root) == root then
    return abspath:sub(#root + 1)
  end
  return nil
end

--- Path to store in notes.md/archive.md: project-relative when `abspath` is
--- inside `root`, otherwise an absolute path with the home directory
--- collapsed to `~` (via `fnamemodify(..., ':~')`) so entries for files
--- outside the project are still representable.
---@param root string
---@param abspath string
---@return string
function M.path_for_storage(root, abspath)
  local rel = M.relpath(root, abspath)
  if rel then
    return rel
  end
  return vim.fn.fnamemodify(vim.fs.normalize(abspath), ":~")
end

--- Resolve a path as stored in notes.md/archive.md back to an absolute path.
--- Absolute (`/...`) and home-relative (`~/...`) entries are expanded as-is;
--- anything else is treated as project-relative.
---@param root string
---@param stored_path string
---@return string
function M.resolve_path(root, stored_path)
  if stored_path:sub(1, 1) == "/" then
    return stored_path
  end
  if stored_path:sub(1, 1) == "~" then
    return vim.fn.expand(stored_path)
  end
  return root .. "/" .. stored_path
end

---@param root string
---@return string
function M.notes_path(root)
  return root .. "/" .. config.options.dir_name .. "/notes.md"
end

---@param root string
---@return string
function M.archive_path(root)
  return root .. "/" .. config.options.dir_name .. "/archive.md"
end

--- Default header written into a freshly created notes.md, explaining the
--- format to humans and AI agents reading the file.
---@return string[]
function M.default_prelude()
  return {
    "<!--",
    "code-sticky.nvim のメモファイルです。プラグインなしでも読めるプレーンな Markdown です。",
    "",
    "書式:",
    "  ## 相対パス:行番号",
    "  本文...",
    "",
    "プロジェクト外のファイルへのメモは絶対パス（ホーム配下は ~/ 表記）になります:",
    "  ## ~/other-project/file.lua:行番号",
    "",
    "本文の慣習（プラグインが軽くパースします）:",
    "  ? で始まる行  -> 疑問（sign: ?）",
    "  ! で始まる行  -> 指摘・レビューコメント（sign: !）",
    "  -> で始まる行 -> 疑問/指摘への回答（回答済み扱いになります）",
    "",
    "AI へ: 疑問/指摘に答える場合は該当エントリの本文に",
    '"-> 回答内容" の行を追記してください。',
    "回答済みは「解決した」とは限りません。内容を確認して解決したとみなせたら",
    "ga でアーカイブしてください。",
    "",
    "このファイルを Neovim で開いたときのキー操作:",
    "  K    エントリが指すコード行の周辺をプレビュー",
    "  <CR> 該当ファイル・行へジャンプ",
    "  ga   エントリをアーカイブ",
    "",
    "誤って内容を消してしまったときは :CodeSticky undo（元に戻すのは :CodeSticky redo）。",
    "-->",
  }
end

--- Parse notes.md / archive.md content into a Doc.
---@param lines string[]
---@return CodeSticky.Doc
function M.parse(lines)
  ---@type CodeSticky.Doc
  local doc = { prelude = {}, entries = {} }
  local current = nil
  for i, line in ipairs(lines) do
    local path, lnum, suffix
    local heading = line:match("^## (.*)$")
    if heading then
      -- `path:lnum` is the *first* ":<digits>" boundary (followed by end-of-
      -- line or whitespace) rather than the last one, so that colons inside
      -- an archived-at timestamp suffix (e.g. "12:34") don't get mistaken
      -- for the line-number separator. Paths containing ":<digits>" of
      -- their own (rare) still resolve correctly since the real separator
      -- always comes first.
      local search_from = 1
      while true do
        local s, e, digits = heading:find(":(%d+)", search_from)
        if not s then
          break
        end
        local after = heading:sub(e + 1, e + 1)
        if after == "" or after == " " then
          path = heading:sub(1, s - 1)
          lnum = digits
          suffix = heading:sub(e + 1)
          break
        end
        search_from = e + 1
      end
    end
    if path then
      if current then
        table.insert(doc.entries, current)
      end
      current = {
        path = path,
        lnum = tonumber(lnum),
        body = {},
        heading_lnum = i,
        heading_suffix = (suffix ~= "" and suffix) or nil,
      }
    elseif current then
      table.insert(current.body, line)
    else
      table.insert(doc.prelude, line)
    end
  end
  if current then
    table.insert(doc.entries, current)
  end
  for _, e in ipairs(doc.entries) do
    while #e.body > 0 and e.body[#e.body]:match("^%s*$") do
      table.remove(e.body)
    end
  end
  while #doc.prelude > 0 and doc.prelude[#doc.prelude]:match("^%s*$") do
    table.remove(doc.prelude)
  end
  return doc
end

--- Serialize a Doc back into lines. Round-trips with parse().
---@param doc CodeSticky.Doc
---@return string[]
function M.serialize(doc)
  local lines = {}
  for _, l in ipairs(doc.prelude) do
    table.insert(lines, l)
  end
  if #doc.prelude > 0 then
    table.insert(lines, "")
  end
  for _, e in ipairs(doc.entries) do
    table.insert(lines, ("## %s:%d%s"):format(e.path, e.lnum, e.heading_suffix or ""))
    for _, l in ipairs(e.body) do
      table.insert(lines, l)
    end
    table.insert(lines, "")
  end
  while #lines > 0 and lines[#lines]:match("^%s*$") do
    table.remove(lines)
  end
  return lines
end

--- Read a Doc from disk. Missing file yields an empty Doc, seeded with
--- `seed_prelude` if given (used to inject the format header on first write).
---@param path string
---@param seed_prelude string[]|nil
---@return CodeSticky.Doc
function M.read(path, seed_prelude)
  if vim.fn.filereadable(path) == 0 then
    return { prelude = seed_prelude and vim.deepcopy(seed_prelude) or {}, entries = {} }
  end
  return M.parse(vim.fn.readfile(path))
end

--- Write a Doc to disk, creating the parent directory lazily.
---@param path string
---@param doc CodeSticky.Doc
function M.write(path, doc)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  vim.fn.writefile(M.serialize(doc), path)
end

--- Read the current notes.md Doc. If notes.md is open in a loaded buffer
--- with unsaved changes (e.g. the user is hand-editing it, or `notes.md`
--- itself is the visible :CodeSticky-list buffer), that buffer's content is
--- treated as authoritative rather than what's on disk, so any plugin-driven
--- mutation (flush, archive, undo, ...) is built on top of the user's
--- in-progress edits instead of silently discarding them on the next write.
--- When the buffer is unmodified, disk is read as before (covers e.g. an AI
--- agent editing notes.md outside Neovim).
---@param root string
---@return CodeSticky.Doc
function M.read_notes(root)
  local path = M.notes_path(root)
  local bufnr = vim.fn.bufnr(path)
  if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].modified then
    return M.parse(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
  end
  return M.read(path, M.default_prelude())
end

--- Get (creating if needed) the hidden buffer backing notes.md, loaded from
--- disk. Routing writes through a real file buffer means every mutation
--- lands in Neovim's own undo tree for that buffer, and (with 'undofile',
--- as is the default in this setup) survives across restarts for free.
---@param root string
---@return integer bufnr
local function notes_bufnr(root)
  local bufnr = vim.fn.bufadd(M.notes_path(root))
  if vim.fn.bufloaded(bufnr) == 0 then
    vim.fn.bufload(bufnr)
  end
  return bufnr
end

---@param root string
---@param doc CodeSticky.Doc
function M.write_notes(root, doc)
  vim.fn.mkdir(vim.fs.dirname(M.notes_path(root)), "p")
  local bufnr = notes_bufnr(root)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, M.serialize(doc))
  vim.api.nvim_buf_call(bufnr, function()
    vim.cmd("silent noautocmd write")
    -- Force an undo-sync boundary. Without this, back-to-back write_notes
    -- calls with no intervening user input (CursorMoved/InsertLeave/etc, the
    -- normal triggers for u_sync()) get merged into a single undo step, so a
    -- single :undo would jump back past more than one logical mutation.
    -- Reassigning 'undolevels' is the standard idiom for forcing that sync.
    vim.bo.undolevels = vim.bo.undolevels
  end)
end

--- Undo the most recent notes.md mutation (upsert/delete/archive), restoring
--- the file to its previous full-file state. Repeatable: each call steps
--- back one further mutation, same as pressing `u` in the buffer itself.
---@param root string
---@return boolean changed
function M.undo_notes(root)
  local bufnr = notes_bufnr(root)
  local before = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  vim.api.nvim_buf_call(bufnr, function()
    pcall(vim.cmd, "silent undo")
  end)
  local after = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  if vim.deep_equal(before, after) then
    return false
  end
  vim.api.nvim_buf_call(bufnr, function()
    vim.cmd("silent noautocmd write")
  end)
  return true
end

--- Redo the most recently undone notes.md mutation. Mirror of `undo_notes`.
---@param root string
---@return boolean changed
function M.redo_notes(root)
  local bufnr = notes_bufnr(root)
  local before = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  vim.api.nvim_buf_call(bufnr, function()
    pcall(vim.cmd, "silent redo")
  end)
  local after = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  if vim.deep_equal(before, after) then
    return false
  end
  vim.api.nvim_buf_call(bufnr, function()
    vim.cmd("silent noautocmd write")
  end)
  return true
end

---@param root string
---@return CodeSticky.Doc
function M.read_archive(root)
  return M.read(M.archive_path(root), {})
end

---@param root string
---@param doc CodeSticky.Doc
function M.write_archive(root, doc)
  M.write(M.archive_path(root), doc)
end

--- Entries sharing (path, lnum), in file order, plus their positions in
--- doc.entries (needed to mutate the underlying array).
---@param doc CodeSticky.Doc
---@param path string
---@param lnum integer
---@return CodeSticky.Entry[], integer[]
function M.group(doc, path, lnum)
  local entries, positions = {}, {}
  for idx, e in ipairs(doc.entries) do
    if e.path == path and e.lnum == lnum then
      table.insert(entries, e)
      table.insert(positions, idx)
    end
  end
  return entries, positions
end

---@param lines string[]
---@return boolean
function M.is_blank(lines)
  for _, l in ipairs(lines) do
    if l:match("%S") then
      return false
    end
  end
  return true
end

--- Create or replace an entry. `index` is the 1-based position within the
--- (path, lnum) group, as previously returned by this function or by
--- group(). Pass nil (or an index past the current group size) to append a
--- new entry; the assigned index is returned.
---@param root string
---@param path string
---@param lnum integer
---@param index integer|nil
---@param body string[]
---@return integer assigned_index
function M.upsert_notes(root, path, lnum, index, body)
  local doc = M.read_notes(root)
  local group, positions = M.group(doc, path, lnum)
  local assigned
  if index and group[index] then
    doc.entries[positions[index]].body = body
    assigned = index
  else
    table.insert(doc.entries, { path = path, lnum = lnum, body = body })
    assigned = #group + 1
  end
  M.write_notes(root, doc)
  return assigned
end

--- Delete the entry at `index` within the (path, lnum) group.
---@param root string
---@param path string
---@param lnum integer
---@param index integer
---@return boolean deleted
function M.delete_notes(root, path, lnum, index)
  local doc = M.read_notes(root)
  local group, positions = M.group(doc, path, lnum)
  if not group[index] then
    return false
  end
  table.remove(doc.entries, positions[index])
  M.write_notes(root, doc)
  return true
end

--- Move an entry from notes.md to archive.md, stamping the heading with an
--- archived-at comment. locator is either {path=, lnum=, index=} (group
--- identity) or {heading_lnum=} (raw line position in notes.md, used when
--- the caller is editing notes.md directly).
---@param root string
---@param locator { path: string?, lnum: integer?, index: integer?, heading_lnum: integer? }
---@return CodeSticky.Entry|nil entry
---@return integer|nil group_index the entry's 1-based position within its (path, lnum) group *before* removal, so callers can float.reindex_after_removal any siblings still open
function M.archive(root, locator)
  local doc = M.read_notes(root)
  local pos = nil
  if locator.heading_lnum then
    for idx, e in ipairs(doc.entries) do
      if e.heading_lnum == locator.heading_lnum then
        pos = idx
        break
      end
    end
  else
    local group, positions = M.group(doc, locator.path, locator.lnum)
    if group[locator.index] then
      pos = positions[locator.index]
    end
  end
  if not pos then
    return nil
  end

  local removed_path, removed_lnum = doc.entries[pos].path, doc.entries[pos].lnum
  local _, group_positions = M.group(doc, removed_path, removed_lnum)
  local group_index
  for gi, gpos in ipairs(group_positions) do
    if gpos == pos then
      group_index = gi
      break
    end
  end

  local entry = table.remove(doc.entries, pos)
  M.write_notes(root, doc)

  local adoc = M.read_archive(root)
  local stamped = vim.deepcopy(entry)
  stamped.heading_lnum = nil
  stamped.heading_suffix = (" <!-- archived: %s -->"):format(os.date("%Y-%m-%d %H:%M"))
  table.insert(adoc.entries, stamped)
  M.write_archive(root, adoc)

  return entry, group_index
end

--- Classify an entry from its body conventions.
--- 'question': first non-blank body line starts with '?'
--- 'issue':    first non-blank body line starts with '!'
--- 'answered': a question/issue entry that also contains a '->' line
--- 'memo':     anything else
---@param entry CodeSticky.Entry
---@return "memo"|"question"|"issue"|"answered"
function M.classify(entry)
  local first
  for _, l in ipairs(entry.body) do
    if l:match("%S") then
      first = l
      break
    end
  end
  local base = "memo"
  if first then
    if first:match("^%s*%?") then
      base = "question"
    elseif first:match("^%s*!") then
      base = "issue"
    end
  end
  if base == "question" or base == "issue" then
    for _, l in ipairs(entry.body) do
      if l:match("^%s*%->") then
        return "answered"
      end
    end
  end
  return base
end

--- Per-line classification for a file, used by signs.lua. When several
--- entries share a line, the most severe classification wins
--- (issue > question > memo/answered).
---@param root string
---@param relpath string
---@return table<integer, "memo"|"question"|"issue"|"answered">
function M.line_status(root, relpath)
  local doc = M.read_notes(root)
  local status = {}
  local severity = { issue = 3, question = 2, answered = 1, memo = 1 }
  for _, e in ipairs(doc.entries) do
    if e.path == relpath then
      local cls = M.classify(e)
      local cur = status[e.lnum]
      if not cur or severity[cls] > severity[cur] then
        status[e.lnum] = cls
      end
    end
  end
  return status
end

--- Collect notes.md entries with their classification, sorted by
--- (path, lnum). Shared by the Telescope extension and :CodeSticky qf.
---@param root string
---@param class_filter table<string, boolean>|nil filter to these classifications, nil = no filter
---@return { entry: CodeSticky.Entry, class: string }[]
function M.collect(root, class_filter)
  local doc = M.read_notes(root)
  local items = {}
  for _, e in ipairs(doc.entries) do
    local class = M.classify(e)
    if not class_filter or class_filter[class] then
      table.insert(items, { entry = e, class = class })
    end
  end
  table.sort(items, function(a, b)
    if a.entry.path ~= b.entry.path then
      return a.entry.path < b.entry.path
    end
    return a.entry.lnum < b.entry.lnum
  end)
  return items
end

--- Batch-move every `answered` entry from notes.md to archive.md in a single
--- write_notes + single archive.md append (archiving one at a time via
--- M.archive would shift heading_lnum out from under the entries still to be
--- processed). Mirrors M.archive's archived-at stamping.
---@param root string
---@return integer count number of entries swept
function M.sweep_answered(root)
  local doc = M.read_notes(root)
  local remaining, swept = {}, {}
  for _, e in ipairs(doc.entries) do
    if M.classify(e) == "answered" then
      table.insert(swept, e)
    else
      table.insert(remaining, e)
    end
  end
  if #swept == 0 then
    return 0
  end
  doc.entries = remaining
  M.write_notes(root, doc)

  local adoc = M.read_archive(root)
  local stamp = (" <!-- archived: %s -->"):format(os.date("%Y-%m-%d %H:%M"))
  for _, e in ipairs(swept) do
    local stamped = vim.deepcopy(e)
    stamped.heading_lnum = nil
    stamped.heading_suffix = stamp
    table.insert(adoc.entries, stamped)
  end
  M.write_archive(root, adoc)

  return #swept
end

--- Stably sort notes.md entries by (path, lnum), preserving the prelude and
--- each group's internal ordering (table.sort is not stable, so ties break
--- on original position). Undo-able via :CodeSticky undo since it goes
--- through write_notes.
---@param root string
---@return integer count number of entries sorted
function M.sort_notes(root)
  local doc = M.read_notes(root)
  local indexed = {}
  for i, e in ipairs(doc.entries) do
    indexed[i] = { entry = e, orig = i }
  end
  table.sort(indexed, function(a, b)
    if a.entry.path ~= b.entry.path then
      return a.entry.path < b.entry.path
    end
    if a.entry.lnum ~= b.entry.lnum then
      return a.entry.lnum < b.entry.lnum
    end
    return a.orig < b.orig
  end)
  local sorted = {}
  for i, item in ipairs(indexed) do
    sorted[i] = item.entry
  end
  doc.entries = sorted
  M.write_notes(root, doc)
  return #doc.entries
end

return M
