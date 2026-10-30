-- Markdown link parsing, resolution and rewriting (pure, unit-tested)
-- plus the vim-side diagnostics and fix-suggestion UI.

local vault = require('notes.vault')

local M = {}

local EXTERNAL = '^%a[%w+.-]*:' -- scheme: URLs, mailto:, ...

-- Parse all [label](target) links in one line. Byte-based offsets:
-- lstart/lend span the whole link, 1-based inclusive.
function M.parse_line(line)
  local out = {}
  for lstart, label, target, lend in line:gmatch('()%[([^%]]*)%]%(([^%)]*)%)()') do
    out[#out + 1] = {
      lstart = lstart,
      lend = lend - 1,
      label = label,
      target = target,
    }
  end
  return out
end

-- Split a raw target into { path, frag, title }. Returns nil for targets we
-- should not treat as note links (scheme URLs, empty/fragment-only).
function M.split_target(t)
  t = t:match('^<(.+)>$') or t
  local path, title = t:match('^%s*(%S*)%s*(.*)$')
  if path == '' then return nil end
  local p, frag
  if path:sub(1, 1) == '#' then
    p, frag = '', path:sub(2) -- fragment-only link
  else
    p, frag = path:match('^([^#]+)#(.*)$')
    if not p then
      p, frag = path, ''
    end
  end
  if p == '' then return nil end
  if p:match(EXTERNAL) then return nil end
  -- normalize title to a single leading space so rebuilding is trivial
  title = (title ~= '') and (' ' .. title:gsub('^%s+', '')) or ''
  return { path = p, frag = frag, title = title }
end

-- Resolve a link target to an absolute path of the note it should point at,
-- relative to the reading note. Returns nil for non-note links.
function M.resolve_target(target, note_path)
  local sp = M.split_target(target)
  if not sp then return nil end
  local p = sp.path
  local abs = p:sub(1, 1) == '/' and vault.norm(p) or vault.norm(vault.dirname(note_path) .. '/' .. p)
  if not abs:match('%.[%w]+$') then abs = abs .. '.md' end -- extensionless => .md
  return abs
end

-- Rewrite content so any link resolving to old_abs now resolves to new_abs,
-- relative to reader_dir. Returns the new content, or nil if nothing changed.
-- Label and title are preserved; a #fragment is dropped (the target moved).
function M.rewrite_content(content, old_abs, new_abs, reader_dir)
  if old_abs == new_abs then return nil end
  local out = {}
  local changed = false
  for line in (content .. '\n'):gmatch('(.-)\n') do
    for _, lk in ipairs(M.parse_line(line)) do
      local tstart = lk.lstart + #lk.label + 3 -- first byte of target, 1-based
      local ts = tstart
      if M.resolve_target(lk.target, reader_dir .. '/__reader__.md') == old_abs then
        local sp = M.split_target(lk.target)
        local newpath = vault.relpath(reader_dir, new_abs)
        local nt = sp.title ~= '' and (newpath .. sp.title) or newpath
        line = line:sub(1, ts - 1) .. nt .. line:sub(ts + #lk.target)
        changed = true
      end
    end
    out[#out + 1] = line
  end
  if not changed then return nil end
  return table.concat(out, '\n')
end

-- Rewrite every link to old_abs across all .md files in a vault. Returns the
-- list of files that changed.
function M.rewrite_vault(root, old_abs, new_abs)
  local changed = {}
  for _, f in ipairs(vault.files(root)) do
    local content = table.concat(vim.fn.readfile(f), '\n')
    local nc = M.rewrite_content(content, old_abs, new_abs, vault.dirname(f))
    if nc then
      vim.fn.writefile(vim.split(nc, '\n', { plain = true }), f)
      changed[#changed + 1] = f
    end
  end
  return changed
end

-- ---- vim-side: diagnostics and fix suggestions ----

local ns
local function get_ns()
  ns = ns or vim.api.nvim_create_namespace('notes')
  return ns
end

-- Flag broken links in a buffer (no-op outside vaults).
function M.check_buffer(bufnr)
  local path = vault.canon(vim.api.nvim_buf_get_name(bufnr))
  if path == '' or path == '/' then return end
  local in_vault = false
  for _, v in ipairs(vault.all()) do
    if vault.is_under(v.root, path) then
      in_vault = true
      break
    end
  end
  if not in_vault then return end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local diags = {}
  for i, line in ipairs(lines) do
    for _, lk in ipairs(M.parse_line(line)) do
      local abs = M.resolve_target(lk.target, path)
      if abs and vim.fn.filereadable(abs) ~= 1 then
        diags[#diags + 1] = {
          lnum = i - 1,
          col = vim.str_utfindex(line, lk.lstart - 1),
          end_col = vim.str_utfindex(line, lk.lend - 1) + 1,
          severity = vim.diagnostic.severity.WARN,
          message = 'Broken link: ' .. abs,
        }
      end
    end
  end
  vim.diagnostic.set(get_ns(), bufnr, diags, {})
end

-- Name-similarity score in [0,1]: exact containment counts most, then
-- in-order character matches.
local function similar(target, cand)
  local t, c = target:lower(), cand:lower()
  local contains = c:find(t, 1, true) and 1 or 0
  local idx, hits = 1, 0
  for i = 1, #t do
    local j = c:find(t:sub(i, i), idx, true)
    if j then
      hits = hits + 1
      idx = j + 1
    end
  end
  return contains * 0.6 + (hits / math.max(1, #t)) * 0.4
end

-- Candidate notes for a broken target, best first (top 8).
function M.candidates(root, target)
  local sp = M.split_target(target)
  if not sp then return {} end
  local want = sp.path:match('([^/]+)$') or sp.path
  local out = {}
  for _, f in ipairs(vault.files(root)) do
    local base = f:match('([^/]+)%.md$') or f:match('([^/]+)$')
    local s = similar(want, base)
    if s > 0 then
      out[#out + 1] = {
        rel = vault.relpath(root, f),
        kind = (base == want) and 'moved?' or 'similar',
        score = (base == want) and 100 or s,
      }
    end
  end
  table.sort(out, function(a, b) return a.score > b.score end)
  local top = {}
  for i = 1, math.min(8, #out) do top[#top + 1] = out[i] end
  return top
end

-- :NoteFixLink — replace the broken link under the cursor with a chosen note.
function M.fix_link_at_cursor()
  local buf = vim.api.nvim_get_current_buf()
  local path = vault.canon(vim.api.nvim_buf_get_name(buf))
  local line = vim.api.nvim_get_current_line()
  local row, col = vim.api.nvim_win_get_cursor(0)[1], vim.api.nvim_win_get_cursor(0)[2]

  local target, ts
  for _, lk in ipairs(M.parse_line(line)) do
    local start = lk.lstart + #lk.label + 3
    if col + 1 >= start and col + 1 <= start + #lk.target - 1 then
      target, ts = lk.target, start
      break
    end
  end
  if not target then
    vim.notify('notes: no link under the cursor', vim.log.levels.WARN)
    return
  end

  local abs = M.resolve_target(target, path)
  if abs and vim.fn.filereadable(abs) == 1 then
    vim.notify('notes: link is fine', vim.log.levels.INFO)
    return
  end

  local root
  for _, v in ipairs(vault.all()) do
    if vault.is_under(v.root, path) then
      root = v.root
      break
    end
  end
  if not root then
    vim.notify('notes: buffer is not in a vault', vim.log.levels.WARN)
    return
  end

  local cands = M.candidates(root, target)
  if #cands == 0 then
    vim.notify('notes: no candidate notes for "' .. target .. '"', vim.log.levels.INFO)
    return
  end

  vim.ui.select(cands, {
    prompt = 'Broken link "..' .. target .. '.." — which note?',
    format_item = function(c) return c.rel .. '  (' .. c.kind .. ')' end,
  }, function(choice)
    if not choice then return end
    local newpath = vault.relpath(vault.dirname(path), root .. '/' .. choice.rel)
    vim.api.nvim_buf_set_text(buf, row - 1, ts - 1, row - 1, ts - 1 + #target, { newpath })
  end)
end

return M