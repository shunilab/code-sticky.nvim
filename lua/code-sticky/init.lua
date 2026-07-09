local config = require("code-sticky.config")
local store = require("code-sticky.store")

local M = {}

--- lhs values from the previous setup() call's default jump mappings, so a
--- re-setup() (e.g. hot-reload, or lazy.nvim re-running config) can unbind
--- the old ones before binding the new ones instead of leaving stale maps.
---@type string[]
local bound_jump_lhs = {}

local function apply_default_mappings()
  for _, lhs in ipairs(bound_jump_lhs) do
    pcall(vim.keymap.del, "n", lhs)
  end
  bound_jump_lhs = {}

  if vim.g.code_sticky_default_mappings == false then
    return
  end

  local km = config.options.keymaps
  vim.keymap.set("n", km.jump_next, function()
    require("code-sticky.signs").jump("next", vim.v.count1)
  end, { desc = "code-sticky: jump to next sticky" })
  vim.keymap.set("n", km.jump_prev, function()
    require("code-sticky.signs").jump("prev", vim.v.count1)
  end, { desc = "code-sticky: jump to previous sticky" })
  bound_jump_lhs = { km.jump_next, km.jump_prev }
end

---@param opts table|nil
function M.setup(opts)
  config.setup(opts)
  -- Bound here (not in plugin/) so plugin managers that source() plugin/
  -- before running opts/config (e.g. lazy.nvim) still end up with keymaps
  -- bound to the final `keymaps` table, not the defaults.
  apply_default_mappings()
end

--- :CodeSticky [buffer|list [archive]|archive|undo|redo|sort|sweep|jumpfloat [on|off|toggle]|qf [questions|issues|memos|answered]]
---@param subcmd string|nil
function M.dispatch(subcmd)
  local float = require("code-sticky.float")
  local notes = require("code-sticky.notes")

  local jumpfloat_arg
  if subcmd and subcmd:match("^jumpfloat") then
    jumpfloat_arg = vim.trim(subcmd:sub(#"jumpfloat" + 1))
    subcmd = "jumpfloat"
  end

  local qf_arg
  if subcmd and subcmd:match("^qf") then
    qf_arg = vim.trim(subcmd:sub(#"qf" + 1))
    subcmd = "qf"
  end

  local list_arg
  if subcmd and subcmd:match("^list") then
    list_arg = vim.trim(subcmd:sub(#"list" + 1))
    subcmd = "list"
  end

  if subcmd == "list" then
    notes.open_list(list_arg ~= "" and list_arg or nil)
  elseif subcmd == "buffer" then
    float.open_at_cursor({ display = "window" })
  elseif subcmd == "archive" then
    M.archive_at_cursor()
  elseif subcmd == "undo" then
    M.undo()
  elseif subcmd == "redo" then
    M.redo()
  elseif subcmd == "jumpfloat" then
    M.set_jump_opens_float(jumpfloat_arg ~= "" and jumpfloat_arg or nil)
  elseif subcmd == "qf" then
    require("code-sticky.qf").open(qf_arg ~= "" and qf_arg or nil)
  elseif subcmd == "sort" then
    M.sort()
  elseif subcmd == "sweep" then
    M.sweep()
  elseif subcmd == nil or subcmd == "" then
    float.open_at_cursor({ display = "float" })
  else
    vim.notify("code-sticky: unknown subcommand '" .. subcmd .. "'", vim.log.levels.ERROR)
  end
end

--- Toggle or explicitly set `jump_opens_float` at runtime, without touching
--- `setup()`'s config table (so it doesn't need a restart to try out).
---@param arg "on"|"off"|"toggle"|nil  nil/"toggle" flips the current value
function M.set_jump_opens_float(arg)
  local opts = config.options
  local new_value
  if arg == "on" then
    new_value = true
  elseif arg == "off" then
    new_value = false
  elseif arg == nil or arg == "toggle" then
    new_value = not opts.jump_opens_float
  else
    vim.notify("code-sticky: jumpfloat expects on/off/toggle, got '" .. arg .. "'", vim.log.levels.ERROR)
    return
  end
  opts.jump_opens_float = new_value
  vim.notify("code-sticky: jump_opens_float " .. (new_value and "on" or "off"), vim.log.levels.INFO)
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
    require("code-sticky.float").reindex_after_removal(root, relpath, lnum, index)
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
    require("code-sticky.float").resync(root)
    vim.notify("code-sticky: undid last notes.md change", vim.log.levels.INFO)
  else
    vim.notify("code-sticky: nothing to undo", vim.log.levels.INFO)
  end
end

--- Sort notes.md entries by (path, lnum). Undo-able via `:CodeSticky undo`.
function M.sort()
  local root = store.root(0)
  local count = store.sort_notes(root)
  require("code-sticky.float").resync(root)
  vim.notify("code-sticky: sorted " .. count .. " entries", vim.log.levels.INFO)
end

--- Batch-archive every `answered` entry after confirming with the user.
function M.sweep()
  local root = store.root(0)
  local answered = store.collect(root, { answered = true })
  if #answered == 0 then
    vim.notify("code-sticky: no answered entries to sweep", vim.log.levels.INFO)
    return
  end
  local choice = vim.fn.confirm(#answered .. " 件を archive.md へ移動しますか？", "&Yes\n&No", 2)
  if choice ~= 1 then
    return
  end
  local count = store.sweep_answered(root)
  require("code-sticky.signs").refresh_all(root)
  require("code-sticky.float").resync(root)
  vim.notify("code-sticky: swept " .. count .. " entries to archive.md", vim.log.levels.INFO)
end

--- Redo the most recently undone notes.md mutation. Mirror of `M.undo`.
function M.redo()
  local root = store.root(0)
  if store.redo_notes(root) then
    require("code-sticky.signs").refresh_all(root)
    require("code-sticky.float").resync(root)
    vim.notify("code-sticky: redid notes.md change", vim.log.levels.INFO)
  else
    vim.notify("code-sticky: nothing to redo", vim.log.levels.INFO)
  end
end

return M
