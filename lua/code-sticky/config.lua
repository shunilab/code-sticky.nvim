local M = {}

---@class CodeSticky.Config
M.defaults = {
  root_markers = { ".code-sticky", ".git" },
  dir_name = ".code-sticky",
  keymaps = {
    jump_next = "]n",
    jump_prev = "[n",
  },
  -- ]n / [n でジャンプした後、そのままフロートで付箋を開くかどうか
  jump_opens_float = false,
  float = {
    width = 40,
    height = 8,
    border = "rounded",
    enter_insert = false,
    gap = 2,
  },
  float_keymaps = {
    close = { "q", "<Esc>" },
    new_sibling = "<C-n>",
    focus_next = "<Tab>",
    focus_prev = "<S-Tab>",
    archive = "ga",
  },
  notes_keymaps = {
    preview = "K",
    jump = "<CR>",
    archive = "ga",
  },
  preview = {
    context = 8,
  },
  signs = {
    memo = { text = "N", hl = "DiagnosticSignInfo" },
    question = { text = "?", hl = "DiagnosticSignWarn" },
    issue = { text = "!", hl = "DiagnosticSignError" },
  },
}

---@type CodeSticky.Config
M.options = vim.deepcopy(M.defaults)

---@param opts table|nil
function M.setup(opts)
  if opts ~= nil then
    vim.validate({ opts = { opts, "table" } })
    for key, expected in pairs({
      root_markers = "table",
      dir_name = "string",
      keymaps = "table",
      jump_opens_float = "boolean",
      float = "table",
      float_keymaps = "table",
      notes_keymaps = "table",
      preview = "table",
      signs = "table",
    }) do
      if opts[key] ~= nil then
        vim.validate({ [key] = { opts[key], expected } })
      end
    end
  end
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
  return M.options
end

return M
