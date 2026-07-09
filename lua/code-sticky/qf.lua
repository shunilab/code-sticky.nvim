local store = require("code-sticky.store")

local M = {}

local icons = { memo = "N", question = "?", issue = "!", answered = "N" }

---@param entry CodeSticky.Entry
---@return string
local function first_line(entry)
  for _, l in ipairs(entry.body) do
    if l:match("%S") then
      return l
    end
  end
  return ""
end

local VALID_CLASSES = { questions = "question", issues = "issue", memos = "memo", answered = "answered" }

--- :CodeSticky qf [questions|issues|memos|answered]
--- Loads matching notes.md entries into the quickfix list (path -> lnum ->
--- first non-blank body line) and opens it. No argument = every entry.
---@param arg string|nil
function M.open(arg)
  local class_filter
  if arg and arg ~= "" then
    local class = VALID_CLASSES[arg]
    if not class then
      vim.notify("code-sticky: qf expects questions/issues/memos/answered, got '" .. arg .. "'", vim.log.levels.ERROR)
      return
    end
    class_filter = { [class] = true }
  end

  local root = store.root(0)
  local items = store.collect(root, class_filter)

  if #items == 0 then
    vim.notify("code-sticky: no entries" .. (arg and arg ~= "" and " for " .. arg or ""), vim.log.levels.INFO)
    return
  end

  local qf_items = {}
  for _, item in ipairs(items) do
    local e = item.entry
    table.insert(qf_items, {
      filename = store.resolve_path(root, e.path),
      lnum = e.lnum,
      text = ("[%s] %s"):format(icons[item.class] or "N", first_line(e)),
    })
  end

  vim.fn.setqflist({}, " ", { title = "code-sticky", items = qf_items })
  vim.cmd("copen")
end

return M
