local M = {}

---@class CodeSticky.Config
M.defaults = {
  root_markers = { ".code-sticky", ".git" },
  dir_name = ".code-sticky",
  keymaps = {
    jump_next = "]n",
    jump_prev = "[n",
  },
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
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
  return M.options
end

return M
