# notes.nvim — specification

Status: v1 scope, agreed in design conversation. This file is the source of
truth; implementation follows it. When the two disagree, fix the code.

## 1. Purpose

A small, dependency-free Neovim plugin for Markdown notes organized in
*vaults* (folders of `.md` files). One file is one note; the filename is the
note's identity. Notes link to each other with standard Markdown links, and
the plugin keeps those links honest when files move.

## 2. Decisions

| # | Question | Decision |
|---|----------|----------|
| 1 | Storage | Plain Markdown files, one per note. No database, no special binary format. Optional YAML-less frontmatter is fine (it's just text). |
| 2 | Where notes live | **Multi-vault.** Default vault is `$XDG_DOCUMENTS_DIR/notes` (falls back to `~/Documents/notes`). Extra named vaults registered in config. Command resolution order: explicit `@vault` arg → vault containing `cwd` → default vault. |
| 3 | Links | Standard `[label](path)` links, resolved **relative to the note that contains them**, so any Markdown renderer (GitHub, preview pane, other apps) can follow them. Externals are ignored by checks: `http(s)://`, `mailto:`, fragment-only links (`#x`). |
| 4 | Broken links | **No automatic rename interception.** Three cooperating pieces: (a) a diagnostic namespace marks broken links in the buffer live (open + save); (b) `:NoteFixLink` proposes candidate notes (scored by name similarity; exact-basename hits are labeled as likely moves) and applies the chosen one; (c) public `require("notes").rename(old, new)` rewrites every link that pointed at the moved file, across the vault. The user wires (c) into their file manager's rename path (docs snippet for neotree etc.). |
| 5 | Daily notes | `:DailyNote` opens/creates today's note. Configurable directory (default `daily/` under the vault root), filename template (default `{{date:YYYY-MM-DD}}.md`), and either its own template or the default note template. |
| 6 | Templates | A `templates.dir` anywhere on disk (top-level `*.md` files are the template list). `templates.default` is applied by `:Note`; `:NoteFromTemplate` lists all templates and creates from the chosen one. One small variable engine shared by note + daily templates: `{{title}}`, `{{date}}`, `{{time}}`, `{{vault}}`, `{{date:STRFTIME}}`. |
| 7 | Picker | `vim.ui.select` only — zero dependencies. snacks users get the native UX with their one-liner (`snacks.picker.select` as `vim.ui.select`); Telescope/fzf users get theirs via the same mechanism. We never call a picker directly. |
| 8 | Markdown interactions | (a) `<CR>` on a list item continues the list: same indentation, same bullet type; numbered lists increment (width preserved, `01.` → `02.`); a `[ ]`/`[x]` checkbox carries to the next item; pressing `<CR>` on an *empty* item ends the list (strips the marker). (b) A checkbox toggle in normal/visual mode (`<leader>x`, configurable) flips the first `[ ]`/`[x]` on the line(s). Both apply to Markdown buffers only. |
| 9 | Rename honesty | Only renames routed through `notes.rename` can be tracked. Moves via Finder, shell `mv`, or plugins that don't call the API are invisible to us — that is exactly why (4a) diagnostics and (4b) fix suggestions exist. |

## 3. Commands

| Command | Behavior |
|---|---|
| `:Note [@vault] [name]` | Open the note; create it (with default template) if missing. Prompts for name when omitted. |
| `:NoteFromTemplate [@vault] [name]` | Pick a template, then create/open the note with it. |
| `:DailyNote [@vault]` | Open or create today's daily note in the configured daily dir. |
| `:NoteCheckLinks` | Re-run the broken-link check on the current buffer. |
| `:NoteFixLink` | Fix the broken link under the cursor: pick a candidate note. |
| `:NoteTodos [@vault]` | List to-do items (`- [ ]`/`- [x]`) across the vault; enter jumps to the file/line. |

## 4. Link semantics

- Parsed syntax: `[label](target)`, `[label](<target>)`, optional `"title"`,
  optional `#fragment`.
- Resolution is relative to the *reading note's directory*; `.`/`..` are
  normalized lexically.
- Extensionless targets are treated as `<target>.md` (both for existence
  checks and for matching against moved files).
- On rename: the path portion is recomputed from each reader's directory to
  the new location; label and title are preserved; a `#fragment` is kept only
  when the target file did not change.
- Diagnostics are byte→character-offset corrected and live in the `notes`
  namespace so they can be flipped off independently of LSP.

## 5. Configuration

```lua
require('notes').setup({
  default_vault = (vim.env.XDG_DOCUMENTS_DIR or '~/Documents') .. '/notes',
  vaults = { research = '~/research/notes' },          -- extra named vaults
  templates = { dir = '~/notes/templates', default = 'note.md' },
  daily = {
    dir      = 'daily',                                -- relative to vault root, or absolute
    filename = '{{date:YYYY-MM-DD}}.md',
    template = nil,                                    -- explicit file; falls back to templates.default
  },
  keymaps = { toggle_todo = '<leader>x' },
})
```

## 6. Public API

- `require("notes").setup(opts)` — merge into defaults (deep-extend).
- `require("notes").rename(old, new)` — move the file (if it still exists)
  and rewrite all links to it across its vault. Returns the list of rewritten
  files. Safe to call when the file was already moved. This is the hook users
  (or their file manager glue) call.
- Internals are importable for tests: `notes.links` (pure link logic),
  `notes.markdown` (pure list/checkbox logic), `notes.vault` (pure path math).

## 7. Structure

```
plugin/notes.lua            commands + diagnostics autocmds
lua/notes/init.lua          setup, config, command logic, public API
lua/notes/vault.lua         vault resolution, path normalization/relative paths
lua/notes/links.lua         pure: link parse/resolve/rewrite · vim: diagnostics + fix
lua/notes/templates.lua     template variable rendering, template listing
lua/notes/markdown.lua      pure: list continuation, checkbox toggle · vim: keymap handlers
after/ftplugin/markdown.lua buffer keymaps
tests/                      plain-Lua specs (run: nvim --headless -l tests/run.lua)
README.md
```

Pure modules must not touch `vim.*` at load time so the specs run on any Lua.

## 8. Non-goals for v1 (leave room, do not build)

Backlinks, tags, note grep, Zettelkasten IDs, sync/encryption/mobile,
move-tracking outside the `notes.rename` API, completions for `:Note` names,
`oil.nvim`/`nvim-tree` glue shipped in-tree (README snippet only), `:h` tags.

## 9. Known shortcuts (implementation-level)

- `vim.fn.glob` for vault traversal skips hidden directories.
- Templates are listed from `templates.dir` top level only.
- Renaming a file whose path is open in a buffer: the buffer must be
  re-opened (`:edit`) — `:#h` docs note this, no auto-reload.