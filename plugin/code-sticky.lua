if vim.g.loaded_code_sticky then
  return
end
vim.g.loaded_code_sticky = true

vim.api.nvim_create_user_command("CodeSticky", function(opts)
  require("code-sticky").dispatch(opts.args ~= "" and opts.args or nil)
end, {
  nargs = "?",
  complete = function()
    return { "buffer", "list", "archive" }
  end,
})

local augroup = vim.api.nvim_create_augroup("code_sticky", { clear = true })

vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile" }, {
  group = augroup,
  pattern = "*",
  callback = function(args)
    require("code-sticky.signs").refresh(args.buf)
  end,
})

vim.api.nvim_create_autocmd("BufReadPost", {
  group = augroup,
  pattern = "*/.code-sticky/notes.md",
  callback = function(args)
    require("code-sticky.notes").attach(args.buf)
  end,
})

if vim.g.code_sticky_default_mappings ~= false then
  local config = require("code-sticky.config")
  vim.keymap.set("n", config.options.keymaps.jump_next, function()
    require("code-sticky.signs").jump("next")
  end, { desc = "code-sticky: jump to next sticky" })
  vim.keymap.set("n", config.options.keymaps.jump_prev, function()
    require("code-sticky.signs").jump("prev")
  end, { desc = "code-sticky: jump to previous sticky" })
end
