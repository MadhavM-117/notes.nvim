-- notes.nvim — buffer keymaps for Markdown files.

local markdown = require('notes.markdown')
local notes = require('notes')
local cfg = notes.get_config()

-- Behaviors honor their configured scope: 'global' applies everywhere,
-- 'vault' only in buffers inside a configured vault. Checked per keypress
-- so :NoteScope applies to already-open buffers.
local function enabled(behavior)
  if notes.get_config().markdown[behavior] == 'global' then return true end
  local vault = require('notes.vault')
  return vault.containing(vim.api.nvim_buf_get_name(0)) ~= nil
end

vim.keymap.set('i', '<CR>', function()
  if not enabled('cr') then
    return vim.api.nvim_replace_termcodes('<CR>', true, false, true)
  end
  return markdown.cr()
end, { buffer = true, expr = true })

vim.keymap.set('n', cfg.keymaps.toggle_todo, function()
  if not enabled('toggle_todo') then return end
  local row = vim.api.nvim_win_get_cursor(0)[1]
  markdown.toggle_range(row, row)
end, { buffer = true })

vim.keymap.set('x', cfg.keymaps.toggle_todo, function()
  if not enabled('toggle_todo') then return end
  markdown.toggle_range(vim.fn.line("'<"), vim.fn.line("'>"))
end, { buffer = true })

-- Tab / Shift-Tab: indent one level on list items, default behavior elsewhere.
local function on_list_prefix()
  local e = markdown.marker_end(vim.api.nvim_get_current_line())
  return e ~= nil and vim.api.nvim_win_get_cursor(0)[2] < e or false
end

vim.keymap.set('n', '<Tab>', function()
  return enabled('tab_indent') and markdown.marker_end(vim.api.nvim_get_current_line()) and '>>' or '<Tab>'
end, { buffer = true, expr = true })

vim.keymap.set('n', '<S-Tab>', function()
  return enabled('tab_indent') and markdown.marker_end(vim.api.nvim_get_current_line()) and '<<' or '<S-Tab>'
end, { buffer = true, expr = true })

vim.keymap.set('x', '<Tab>', function()
  return enabled('tab_indent') and '>gv' or ''
end, { buffer = true, expr = true })

vim.keymap.set('x', '<S-Tab>', function()
  return enabled('tab_indent') and '<gv' or ''
end, { buffer = true, expr = true })

vim.keymap.set('i', '<Tab>', function()
  if enabled('tab_indent') and on_list_prefix() then
    return vim.api.nvim_replace_termcodes('<C-t>', true, false, true)
  end
  return vim.api.nvim_replace_termcodes('<Tab>', true, false, true)
end, { buffer = true, expr = true })

vim.keymap.set('i', '<S-Tab>', function()
  if enabled('tab_indent') and markdown.marker_end(vim.api.nvim_get_current_line()) then
    return vim.api.nvim_replace_termcodes('<C-d>', true, false, true)
  end
  return ''
end, { buffer = true, expr = true })
