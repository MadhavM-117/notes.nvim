-- notes.nvim — create, find, and keep coherent Markdown notes in vaults.

local vault = require('notes.vault')
local links = require('notes.links')
local templates = require('notes.templates')
local ui = require('notes.ui')

local M = {}
-- Public submodules: importable for scripting and tests.
M.links = links
M.vault = vault
M.templates = templates
M.markdown = require('notes.markdown')
M.ui = ui

-- All config paths may be `~`-expanded; vault roots are absolutized on use.
---@class notes.Config
---@field default_vault string path of the unnamed default vault
---@field vaults table<string, string> extra vaults, name -> path
---@field templates notes.ConfigTemplates
---@field daily notes.ConfigDaily
---@field markdown notes.ConfigMarkdown
---@field keymaps notes.ConfigKeymaps
---@field ui notes.ConfigUi

---@class notes.Vault
---@field name string vault name ('default' for the unnamed one)
---@field root string absolute vault root

---@class notes.TodoItem
---@field path string absolute path of the note file
---@field lnum integer 1-based line number
---@field line string raw line text

---@class notes.OpenOpts
---@field vault? string|notes.Vault target vault; nil follows command resolution rules
---@field template? string template path; nil uses the configured default template

---@alias notes.Scope 'vault' | 'global'

---@class notes.ConfigMarkdown
---Scope of each Markdown editing behavior: 'vault' (only in vault files)
---or 'global' (any Markdown buffer).
---@field cr notes.Scope list continuation on <CR>
---@field toggle_todo notes.Scope checkbox toggling
---@field tab_indent notes.Scope Tab/Shift-Tab indenting

---@class notes.ConfigTemplates
---@field dir? string directory of `*.md` templates
---@field default string template file used by :Note when no template is given

---@class notes.ConfigDaily
---@field dir string daily dir, relative to the vault root or absolute
---@field filename string filename pattern, rendered through the template engine
---@field template? string template path for daily notes; falls back to `templates`

---@class notes.ConfigKeymaps
---@field toggle_todo string keymap that toggles Markdown checkboxes

local defaults = {
  default_vault = (vim.env.XDG_DOCUMENTS_DIR or vim.fn.expand('~/Documents')) .. '/notes',
  vaults = {}, -- extra named vaults: name = path
  templates = { dir = nil, default = 'note.md' },
  daily = { dir = 'daily', filename = '{{date:YYYY-MM-DD}}.md', template = nil },
  markdown = { cr = 'vault', toggle_todo = 'vault', tab_indent = 'vault' },
  keymaps = { toggle_todo = '<leader>x' },
  ui = {},
}
local user_opts = {}

M.behaviors = { 'cr', 'toggle_todo', 'tab_indent' }
local scopes = { vault = true, global = true }

---Returns the effective config: defaults merged with what setup() got.
---@return notes.Config
function M.get_config()
  return vim.tbl_deep_extend('force', {}, defaults, user_opts)
end

---@param opts? notes.Config
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

-- Ask for a note name through the configured ui.input hook; an empty or
-- cancelled answer calls back with nil, and no note is created.
local function ask_name(rest, cb)
  if #rest > 0 then return cb(table.concat(rest, ' ')) end
  ui.input({ prompt = 'Note name: ' }, function(name)
    if name and name ~= '' then cb(name) end
  end)
end

-- Accept a vault name, a notes.Vault table, or nil (cwd/default rules).
local function to_vault(v)
  if type(v) == 'table' then return v end
  return vault.resolve(v)
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
  local v = to_vault(prefix) -- fail fast on a bad @vault before prompting
  ask_name(rest, function(name) M.open(name, { vault = v }) end)
end

function M.note_from_template(args)
  local cfg = M.get_config()
  if not cfg.templates.dir then
    vim.notify('notes: no templates.dir configured', vim.log.levels.WARN)
    return
  end
  local prefix, rest = split_prefix(args)
  local v = to_vault(prefix)
  ask_name(rest, function(name)
    ui.select(templates.list(abs(cfg.templates.dir)), {
      prompt = 'Template:',
      format_item = function(t) return vim.fn.fnamemodify(t, ':t') end,
    }, function(chosen)
      if chosen then M.open(name, { vault = v, template = chosen }) end
    end)
  end)
end

function M.daily(args)
  local prefix = split_prefix(args)
  local v = to_vault(prefix)
  local cfg = M.get_config().daily

  local dir = cfg.dir
  if not (dir:sub(1, 1) == '/' or dir:sub(1, 1) == '~') then
    dir = v.root .. '/' .. dir
  end
  local fn = templates.render(cfg.filename, {
    date = os.date('%Y-%m-%d'),
    time = os.date('%H:%M'),
  })
  -- daily.template, else the default note template, else blank
  local path = cfg.template
  if not path then
    local t = M.get_config().templates
    if t.dir then path = t.dir .. '/' .. t.default end
  end
  M.open(dir .. '/' .. fn, { vault = v, template = path })
end

function M.todos(args)
  local prefix = split_prefix(args)
  local v = to_vault(prefix)
  local items = M.get_todos(v)
  if #items == 0 then
    vim.notify('notes: no to-dos in vault', vim.log.levels.INFO)
    return
  end
  ui.select(items, {
    prompt = 'To-dos in ' .. v.name,
    format_item = function(it)
      return string.format('%s:%d  %s', (it.path:match('([^/]+)$') or it.path), it.lnum, it.line)
    end,
  }, function(chosen)
    if chosen then
      vim.cmd.edit(vim.fn.fnameescape(chosen.path))
      vim.api.nvim_win_set_cursor(0, { chosen.lnum, 0 })
    end
  end)
end

-- Show behavior scopes, or set one: set_scope { behavior, 'vault'|'global' }.
-- Takes effect immediately, including in buffers that are already open.
function M.set_scope(args)
  local m = M.get_config().markdown
  if not args or #args == 0 then
    for _, b in ipairs(M.behaviors) do
      vim.notify(('notes: %s = %s'):format(b, m[b]))
    end
    return
  end
  local behavior, scope = args[1], args[2]
  if not vim.list_contains(M.behaviors, behavior) or not scopes[scope] then
    vim.notify('notes: usage :NoteScope [cr|toggle_todo|tab_indent] [vault|global]', vim.log.levels.WARN)
    return
  end
  user_opts.markdown = user_opts.markdown or {}
  user_opts.markdown[behavior] = scope
  vim.notify(('notes: %s = %s'):format(behavior, scope))
end

-- ---- public API ----

---Resolve a vault: nil or '' follows the command rules (@name > cwd > default).
---@param name? string vault name, or nil for the implicit vault
---@return notes.Vault
function M.resolve_vault(name)
  return to_vault(name)
end

---Open a note, creating it (and its directories) if missing. `name` is
---vault-relative; an absolute or `~/` path opens that file instead.
---@param name string note name ('.md' appended when missing)
---@param opts? notes.OpenOpts
---@return string path absolute path of the note
function M.open(name, opts)
  opts = opts or {}
  local v = to_vault(opts.vault)
  local full = abs(name:match('^[~/]') and name or v.root .. '/' .. ensure_md(name))
  open_or_create(full, render_template(M.get_config(), v, name, opts.template))
  return full
end

---Every checkbox item (`- [ ]` / `- [x]`) in a vault.
---@param v? string|notes.Vault vault name or table; nil resolves from cwd
---@return notes.TodoItem[]
function M.get_todos(v)
  v = to_vault(v)
  local items = {}
  for _, f in ipairs(vault.files(v.root)) do
    local lines = vim.fn.readfile(f)
    for i, line in ipairs(lines) do
      if line:match('^%s*[-*+]%s+%[[ xX]%]') then
        items[#items + 1] = { path = f, lnum = i, line = line }
      end
    end
  end
  return items
end

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