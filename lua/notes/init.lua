-- notes.nvim — create, find, and keep coherent Markdown notes in vaults.

local vault = require('notes.vault')
local links = require('notes.links')
local templates = require('notes.templates')

local M = {}
M.links = links

local defaults = {
  default_vault = (vim.env.XDG_DOCUMENTS_DIR or vim.fn.expand('~/Documents')) .. '/notes',
  vaults = {}, -- extra named vaults: name = path
  templates = { dir = nil, default = 'note.md' },
  daily = { dir = 'daily', filename = '{{date:YYYY-MM-DD}}.md', template = nil },
  keymaps = { toggle_todo = '<leader>x' },
}
local user_opts = {}

function M.get_config()
  return vim.tbl_deep_extend('force', {}, defaults, user_opts)
end

function M.setup(opts)
  user_opts = opts or {}
  return M
end

-- ---- helpers ----

local function abs(path)
  return vim.fn.fnamemodify(vim.fn.expand(path), ':p')
end

local function ensure_md(name)
  if name:match('%.[%w]+$') then return name end
  return name .. '.md'
end

-- First arg may be "@vaultname"; everything after is the note name.
local function split_prefix(args)
  local prefix
  if args[1] and args[1]:sub(1, 1) == '@' then
    prefix = args[1]:sub(2)
    args = { unpack(args, 2) }
  end
  return prefix, args
end

local function ask_name(rest)
  if #rest > 0 then return table.concat(rest, ' ') end
  local name = vim.fn.input('Note name: ')
  return (name == '' and nil) or name
end

local function template_vars(v, name)
  local title = (name:match('([^/]+)$') or name):gsub('%.md$', '')
  return {
    title = title,
    date = os.date('%Y-%m-%d'),
    time = os.date('%H:%M'),
    vault = v.name,
  }
end

-- Content for a new note: explicit template path > configured default > ''.
local function render_template(cfg, v, name, explicit)
  local path = explicit
  if not path and cfg.templates.dir then
    path = cfg.templates.dir .. '/' .. cfg.templates.default
  end
  if not path then return '' end
  local full = abs(path)
  if vim.fn.filereadable(full) ~= 1 then return '' end
  return templates.render(table.concat(vim.fn.readfile(full), '\n') .. '\n', template_vars(v, name))
end

local function open_or_create(full, content)
  if vim.fn.filereadable(full) == 1 then
    vim.cmd.edit(vim.fn.fnameescape(full))
    return
  end
  vim.fn.mkdir(vim.fn.fnamemodify(full, ':h'), 'p')
  if content ~= '' then
    vim.fn.writefile(vim.split(content, '\n', { plain = true }), full)
  end
  vim.cmd.edit(vim.fn.fnameescape(full))
end

-- ---- commands ----

function M.note(args)
  local prefix, rest = split_prefix(args)
  local v = vault.resolve(prefix)
  local name = ask_name(rest)
  if not name then return end
  local full = abs(v.root .. '/' .. ensure_md(name))
  open_or_create(full, render_template(M.get_config(), v, name))
end

function M.note_from_template(args)
  local cfg = M.get_config()
  if not cfg.templates.dir then
    vim.notify('notes: no templates.dir configured', vim.log.levels.WARN)
    return
  end
  local prefix, rest = split_prefix(args)
  local v = vault.resolve(prefix)
  local name = ask_name(rest)
  if not name then return end

  local tpls = templates.list(abs(cfg.templates.dir))
  vim.ui.select(tpls, {
    prompt = 'Template:',
    format_item = function(t) return vim.fn.fnamemodify(t, ':t') end,
  }, function(chosen)
    if not chosen then return end
    local full = abs(v.root .. '/' .. ensure_md(name))
    open_or_create(full, render_template(cfg, v, name, chosen))
  end)
end

function M.daily(args)
  local prefix = split_prefix(args)
  local v = vault.resolve(prefix)
  local cfg = M.get_config().daily

  local dir = cfg.dir
  if not (dir:sub(1, 1) == '/' or dir:sub(1, 1) == '~') then
    dir = v.root .. '/' .. dir
  end
  local fn = templates.render(cfg.filename, {
    date = os.date('%Y-%m-%d'),
    time = os.date('%H:%M'),
  })
  local title = fn:gsub('%.md$', '')
  local full = abs(dir .. '/' .. ensure_md(fn))

  -- daily.template, else the default note template, else blank
  local path = cfg.template
  if not path then
    local t = M.get_config().templates
    if t.dir then path = t.dir .. '/' .. t.default end
  end
  open_or_create(full, render_template(M.get_config(), v, title, path))
end

function M.todos(args)
  local prefix = split_prefix(args)
  local v = vault.resolve(prefix)
  local items = {}
  for _, f in ipairs(vault.files(v.root)) do
    local lines = vim.fn.readfile(f)
    for i, line in ipairs(lines) do
      if line:match('^%s*[-*+]%s+%[[ xX]%]') then
        items[#items + 1] = { f = f, lines = lines, lnum = i, line = line }
      end
    end
  end
  if #items == 0 then
    vim.notify('notes: no to-dos in vault', vim.log.levels.INFO)
    return
  end
  vim.ui.select(items, {
    prompt = 'To-dos in ' .. v.name,
    format_item = function(it)
      return string.format('%s:%d  %s', (it.f:match('([^/]+)$') or it.f), it.lnum, it.line)
    end,
  }, function(chosen)
    if chosen then
      vim.cmd.edit(vim.fn.fnameescape(chosen.f))
      vim.api.nvim_win_set_cursor(0, { chosen.lnum, 0 })
    end
  end)
end

-- ---- public API ----

-- Move a file and rewrite every link that pointed at it, across its vault.
-- Also safe when the file was already moved (just rewrites). Returns the
-- list of rewritten files. Wire this into your file manager's rename path.
function M.rename(old_path, new_path)
  -- canonicalize so symlinked paths (/var vs /private/var) compare equal
  local old, new = vault.canon(abs(old_path)), vault.canon(abs(new_path))
  if old == new then return {} end
  if vim.fn.filereadable(old) == 1 then
    vim.fn.mkdir(vim.fn.fnamemodify(new, ':h'), 'p')
    vim.fn.rename(old, new)
  end
  if vim.fn.filereadable(new) ~= 1 then
    error('notes.rename: ' .. new .. ' does not exist', 0)
  end
  local root
  for _, v in ipairs(vault.all()) do
    if vault.is_under(v.root, new) then
      root = v.root
      break
    end
  end
  if not root then
    vim.notify('notes.rename: no vault contains ' .. new, vim.log.levels.WARN)
    return {}
  end
  return links.rewrite_vault(root, old, new)
end

return M