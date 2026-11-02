# notes.nvim

A small, dependency-free Neovim plugin for Markdown notes in **vaults**
(folders of `.md` files). One file is one note. Notes link to each other with
standard Markdown links — readable by any renderer — and the plugin keeps
those links honest when files move.

See [docs/spec.md](docs/spec.md) for the full design and non-goals.

## Features

- `:Note [@vault] [name]` — open or create a note (default template applied)
- `:NoteFromTemplate [@vault] [name]` — create a note from any of your templates
- `:DailyNote [@vault]` — today's note in the configured daily dir
- `:NoteCheckLinks` — diagnostic marks for broken links (also runs on open/save)
- `:NoteFixLink` — fix the link under the cursor, with suggested candidate notes
- `:NoteTodos [@vault]` — list to-dos across the vault
- `:NoteScope [behavior] [vault|global]` — show or set, per markdown
  behavior (`cr`, `toggle_todo`, `tab_indent`), whether it applies only
  in vault files (default) or in every Markdown buffer
- Markdown niceties: `<CR>` continues lists (same bullet, incrementing
  numbers, checkbox carried; empty item ends the list), `<leader>x`
  toggles checkboxes, and `<Tab>`/`<S-Tab>` indent/outdent list items
  (normal, insert, and visual modes; defaults preserved off-list)
- `require("notes").rename(old, new)` — public hook that rewrites all links
  to a moved file; wire it into your file manager

## Install

Requires Neovim 0.10+. With lazy.nvim:

```lua
{ 'you/notes.nvim', opts = {
    default_vault = (vim.env.XDG_DOCUMENTS_DIR or '~/Documents') .. '/notes',
    vaults = { research = '~/research/notes' },
    templates = { dir = '~/notes/templates', default = 'note.md' },
    daily = { dir = 'daily', filename = '{{date:YYYY-MM-DD}}.md' },
  } }
```

Or `require('notes').setup { ... }` after loading.

## Templates

Templates are `*.md` files in `templates.dir`. Variables (one small engine,
shared with daily notes): `{{title}}`, `{{date}}`, `{{time}}`, `{{vault}}`,
`{{date:STRFTIME}}` (e.g. `{{date:%Y-%m-%d %H:%M}}`).

## Vaults

Vaults resolve, in order: explicit `@name` prefix → vault containing `cwd` →
default vault.

```lua
:Note @research named-note    -- force the "research" vault
:DailyNote                    -- today in the vault implied by cwd
```

## Broken links & renames

There is no automatic rename interception — movement happens a dozen ways and
we can't see most of them. Instead:

1. **Diagnostics** flag broken links live (toggle off with
   `vim.diagnostic.disable(0)` / namespace `notes`).
2. `:NoteFixLink` on the cursor suggests candidate notes (name-similarity
   scoring; exact-basename hits are labeled `moved?`) and rewrites the link.
3. `require("notes").rename(old, new)` rewrites every link across the vault
   (safe to call after the file was already moved). Wire it into whatever
   renames files for you, e.g. neotree:

```lua
-- route neotree's rename through notes.rename (adjust to your setup's signal)
local notes = require('notes')
vim.api.nvim_create_autocmd('User', {
  pattern = 'NeoTreeRename', -- example only — use your file manager's event
  callback = function(args)
    local data = vim.api.nvim_get_vvar('args') -- { old, new } per your manager
    notes.rename(data.old, data.new)
  end,
})
```

## Picker

All picking goes through `vim.ui.select` — zero dependencies. With
[snacks.nvim](https://github.com/folke/snacks.nvim):

```lua
require('snacks').setup({ picker = { select = true } })
```

Telescope/fzf users get their native UX the same way.

## Tests

```sh
nvim --headless -l tests/run.lua
```

## Public API

- `require("notes").setup(opts)`
- `require("notes").rename(old, new)` → list of rewritten files

## Non-goals (v1)

See the spec: no backlinks, tags, grep, Zettelkasten IDs, sync, or automatic
move-tracking — the structure leaves room for all of them.