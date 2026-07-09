local telescope = require("telescope")
local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local previewers = require("telescope.previewers")

local store = require("code-sticky.store")

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

---@param opts table|nil
---@param class_filter table<string, boolean>|nil
---@param prompt_title string
local function picker(opts, class_filter, prompt_title)
  opts = opts or {}
  local root = store.root(0)
  local items = store.collect(root, class_filter)

  pickers
    .new(opts, {
      prompt_title = prompt_title,
      finder = finders.new_table({
        results = items,
        entry_maker = function(item)
          local e = item.entry
          local display = ("[%s] %s:%d  %s"):format(icons[item.class] or "N", e.path, e.lnum, first_line(e))
          return {
            value = item,
            display = display,
            ordinal = display,
            path = store.resolve_path(root, e.path),
            lnum = e.lnum,
          }
        end,
      }),
      sorter = conf.generic_sorter(opts),
      previewer = previewers.new_buffer_previewer({
        title = "code-sticky preview",
        define_preview = function(self, entry)
          if vim.fn.filereadable(entry.path) == 0 then
            vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, { "(file not found: " .. entry.path .. ")" })
            return
          end
          conf.buffer_previewer_maker(entry.path, self.state.bufnr, {
            bufname = self.state.bufname,
            winid = self.state.winid,
            callback = function(bufnr)
              pcall(vim.api.nvim_win_set_cursor, self.state.winid, { entry.lnum, 0 })
              pcall(vim.api.nvim_buf_call, bufnr, function()
                vim.cmd("normal! zz")
              end)
            end,
          })
        end,
      }),
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          local selection = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          if selection then
            vim.cmd.edit(selection.path)
            local total = vim.api.nvim_buf_line_count(0)
            vim.api.nvim_win_set_cursor(0, { math.max(1, math.min(selection.lnum, total)), 0 })
          end
        end)
        return true
      end,
    })
    :find()
end

return telescope.register_extension({
  exports = {
    code_sticky = function(opts)
      picker(opts, nil, "code-sticky: all")
    end,
    questions = function(opts)
      picker(opts, { question = true }, "code-sticky: questions")
    end,
    issues = function(opts)
      picker(opts, { issue = true }, "code-sticky: issues")
    end,
    memos = function(opts)
      picker(opts, { memo = true }, "code-sticky: memos")
    end,
    answered = function(opts)
      picker(opts, { answered = true }, "code-sticky: answered")
    end,
  },
})
