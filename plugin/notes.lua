-- notes.nvim — commands and autocmds.

local notes = require('notes')

vim.api.nvim_create_user_command('Note', function(a)
  notes.note(a.fargs)
end, { nargs = '*', desc = 'Open or create a note in the current vault' })

vim.api.nvim_create_user_command('NoteFromTemplate', function(a)
  notes.note_from_template(a.fargs)
end, { nargs = '*', desc = 'Create a note from a chosen template' })

vim.api.nvim_create_user_command('DailyNote', function(a)
  notes.daily(a.fargs)
end, { nargs = '*', desc = 'Open or create today\'s daily note' })

vim.api.nvim_create_user_command('NoteCheckLinks', function()
  notes.links.check_buffer(0)
end, { desc = 'Re-check links in the current buffer' })

vim.api.nvim_create_user_command('NoteFixLink', function()
  notes.links.fix_link_at_cursor()
end, { desc = 'Fix the broken link under the cursor' })

vim.api.nvim_create_user_command('NoteTodos', function(a)
  notes.todos(a.fargs)
end, { nargs = '*', desc = 'List to-dos in the current vault' })

local group = vim.api.nvim_create_augroup('notes_links', { clear = true })
vim.api.nvim_create_autocmd({ 'BufReadPost', 'BufWritePost' }, {
  group = group,
  pattern = '*.md',
  callback = function(ev)
    notes.links.check_buffer(ev.buf)
  end,
})