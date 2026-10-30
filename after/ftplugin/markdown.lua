-- notes.nvim — buffer keymaps for Markdown files.

local markdown = require('notes.markdown')
local cfg = require('notes').get_config()

vim.keymap.set('i', '<CR>', function()
  return markdown.cr()
end, { buffer = true, expr = true })

vim.keymap.set('n', cfg.keymaps.toggle_todo, function()
  local row = vim.api.nvim_win_get_cursor(0)[1]
  markdown.toggle_range(row, row)
end, { buffer = true })

vim.keymap.set('x', cfg.keymaps.toggle_todo, function()
  markdown.toggle_range(vim.fn.line("'<"), vim.fn.line("'>"))
end, { buffer = true })