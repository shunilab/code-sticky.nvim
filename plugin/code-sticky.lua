if vim.g.loaded_code_sticky then
  return
end
vim.g.loaded_code_sticky = true

vim.api.nvim_create_user_command("CodeSticky", function(opts)
  require("code-sticky").dispatch(opts.args ~= "" and opts.args or nil)
end, {
  nargs = "?",
  complete = function(_, cmdline)
    if cmdline:match("^%s*CodeSticky%s+jumpfloat%s+%S*$") then
      return { "on", "off", "toggle" }
    end
    if cmdline:match("^%s*CodeSticky%s+qf%s+%S*$") then
      return { "questions", "issues", "memos", "answered" }
    end
    if cmdline:match("^%s*CodeSticky%s+list%s+%S*$") then
      return { "archive" }
    end
    return { "buffer", "list", "archive", "undo", "redo", "sort", "sweep", "jumpfloat", "qf" }
  end,
})

vim.api.nvim_create_user_command("CodeStickyNew", function()
  require("code-sticky.float").new_sibling_cmd()
end, {})

local augroup = vim.api.nvim_create_augroup("code_sticky", { clear = true })

vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile" }, {
  group = augroup,
  pattern = "*",
  callback = function(args)
    require("code-sticky.signs").refresh(args.buf)
  end,
})

vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile" }, {
  group = augroup,
  pattern = "*/.code-sticky/notes.md",
  callback = function(args)
    require("code-sticky.notes").attach(args.buf)
  end,
})

vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile" }, {
  group = augroup,
  pattern = "*/.code-sticky/archive.md",
  callback = function(args)
    require("code-sticky.notes").attach(args.buf, { archive = true })
  end,
})

-- Hand-editing notes.md directly (not through a sticky float) and saving it
-- should still refresh signs in every affected buffer and resync any open
-- sticky floats' indices, same as undo/redo/sort/sweep do.
vim.api.nvim_create_autocmd("BufWritePost", {
  group = augroup,
  pattern = "*/.code-sticky/notes.md",
  callback = function(args)
    local root = vim.fs.dirname(vim.fs.dirname(args.match))
    require("code-sticky.signs").refresh_all(root)
    require("code-sticky.float").resync(root)
  end,
})
