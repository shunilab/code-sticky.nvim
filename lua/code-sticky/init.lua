local config = require("code-sticky.config")
local store = require("code-sticky.store")

local M = {}

---@param opts table|nil
function M.setup(opts)
  config.setup(opts)
end

--- :CodeSticky [buffer|list|archive]
---@param subcmd string|nil
function M.dispatch(subcmd)
  local float = require("code-sticky.float")
  local notes = require("code-sticky.notes")

  if subcmd == "list" then
    notes.open_list()
  elseif subcmd == "buffer" then
    float.open_at_cursor({ display = "window" })
  elseif subcmd == "archive" then
    M.archive_at_cursor()
  elseif subcmd == "undo" then
    M.undo()
  elseif subcmd == "redo" then
    M.redo()
  elseif subcmd == nil or subcmd == "" then
    float.open_at_cursor({ display = "float" })
  else
    vim.notify("code-sticky: unknown subcommand '" .. subcmd .. "'", vim.log.levels.ERROR)
  end
end

--- Archive the sticky/stickies on the current cursor line. When several
--- entries share the line, prompt the user to pick one via vim.ui.select.
function M.archive_at_cursor()
  local bufname = vim.api.nvim_buf_get_name(0)
  if bufname == "" then
    vim.notify("code-sticky: buffer has no name", vim.log.levels.ERROR)
    return
  end
  local root = store.root(0)
  local relpath = store.path_for_storage(root, bufname)
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local doc = store.read_notes(root)
  local group = store.group(doc, relpath, lnum)

  if #group == 0 then
    vim.notify("code-sticky: no sticky on this line", vim.log.levels.WARN)
    return
  end

  local function do_archive(index)
    store.archive(root, { path = relpath, lnum = lnum, index = index })
    require("code-sticky.signs").refresh(0)
  end

  if #group == 1 then
    do_archive(1)
    return
  end

  local items = {}
  for i, e in ipairs(group) do
    local first = e.body[1] or ""
    items[i] = ("[%d] %s"):format(i, first)
  end
  vim.ui.select(items, { prompt = "Archive which sticky?" }, function(_, idx)
    if idx then
      do_archive(idx)
    end
  end)
end

--- Undo the most recent notes.md mutation (upsert/delete/archive) for the
--- current project. Repeatable: calling it again steps back one further
--- mutation. Backed by Neovim's own (persistent, with 'undofile') undo tree
--- for the notes.md buffer, so it survives across restarts.
function M.undo()
  local root = store.root(0)
  if store.undo_notes(root) then
    require("code-sticky.signs").refresh_all(root)
    vim.notify("code-sticky: undid last notes.md change", vim.log.levels.INFO)
  else
    vim.notify("code-sticky: nothing to undo", vim.log.levels.INFO)
  end
end

--- Redo the most recently undone notes.md mutation. Mirror of `M.undo`.
function M.redo()
  local root = store.root(0)
  if store.redo_notes(root) then
    require("code-sticky.signs").refresh_all(root)
    vim.notify("code-sticky: redid notes.md change", vim.log.levels.INFO)
  else
    vim.notify("code-sticky: nothing to redo", vim.log.levels.INFO)
  end
end

return M
