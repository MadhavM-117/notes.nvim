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

-- Tab / Shift-Tab: indent one level on list items, default behavior elsewhere.
local function on_list_prefix()
  local e = markdown.marker_end(vim.api.nvim_get_current_line())
  return e ~= nil and vim.api.nvim_win_get_cursor(0)[2] < e or false
end

vim.keymap.set('n', '<Tab>', function()
  return markdown.marker_end(vim.api.nvim_get_current_line()) and '>>' or '<Tab>'
end, { buffer = true, expr = true })

vim.keymap.set('n', '<S-Tab>', function()
  return markdown.marker_end(vim.api.nvim_get_current_line()) and '<<' or '<S-Tab>'
end, { buffer = true, expr = true })

vim.keymap.set('x', '<Tab>', '>gv', { buffer = true, desc = 'Indent selection' })
vim.keymap.set('x', '<S-Tab>', '<gv', { buffer = true, desc = 'Outdent selection' })

vim.keymap.set('i', '<Tab>', function()
  if on_list_prefix() then
    return vim.api.nvim_replace_termcodes('<C-t>', true, false, true)
  end
  return vim.api.nvim_replace_termcodes('<Tab>', true, false, true)
end, { buffer = true, expr = true })

vim.keymap.set('i', '<S-Tab>', function()
  if markdown.marker_end(vim.api.nvim_get_current_line()) then
    return vim.api.nvim_replace_termcodes('<C-d>', true, false, true)
  end
  return ''
end, { buffer = true, expr = true })