local h = require('tests.helper')
local t = require('notes.templates')

h.t('render substitutes simple variables', function()
  h.eq(t.render('title: {{title}} v={{vault}}', { title = 'x', vault = 't' }), 'title: x v=t')
end)

h.t('render ignores unknown variables', function()
  h.eq(t.render('a {{missing}}', {}), 'a ')
end)

h.t('render date accepts human tokens', function()
  local out = t.render('{{date:YYYY-MM-DD}}', {})
  h.eq(out, os.date('%Y-%m-%d'))
  h.eq(t.render('{{date:HH:mm}}', {}), os.date('%H:%M'))
end)

h.t('render date accepts strftime', function()
  h.eq(t.render('{{date:%Y-%m-%d}}', {}), os.date('%Y-%m-%d'))
end)

h.t('date token translation stays literal without codes', function()
  h.eq(t.render('{{date:YYYY}}', {}), os.date('%Y'))
end)