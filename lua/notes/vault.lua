-- Vault discovery and path math. No vim.* at load time; pure functions are
-- unit-tested under plain Lua.

local M = {}

-- Lexically normalize an absolute path: collapse '.', '..', repeated slashes.
function M.norm(p)
  local parts = {}
  for seg in p:gmatch('[^/]+') do
    if seg == '..' then
      if #parts > 0 then parts[#parts] = nil end
    elseif seg ~= '.' then
      parts[#parts + 1] = seg
    end
  end
  if #parts == 0 then return '/' end
  return '/' .. table.concat(parts, '/')
end

-- Canonicalize for comparison: expand ~, absolutize, and resolve symlinks in
-- the (existing) directory part — so /var/... matches /private/var/... on macOS.
function M.canon(p)
  p = vim.fn.expand(p)
  local dir, name = p:match('^(.*)/([^/]*)$')
  if not dir or dir == '' then return vim.fn.resolve(p) end
  return vim.fn.resolve(vim.fn.fnamemodify(dir, ':p')) .. '/' .. name
end

-- Directory part of a path.
function M.dirname(p)
  return p:match('^(.*)/[^/]*$') or '.'
end

-- Relative path from directory `from` to target `to` (both absolute).
function M.relpath(from, to)
  local a, b = M.norm(from), M.norm(to)
  if a == b then return '' end
  local pa, pb = {}, {}
  for s in a:gmatch('[^/]+') do pa[#pa + 1] = s end
  for s in b:gmatch('[^/]+') do pb[#pb + 1] = s end
  local i = 1
  while pa[i] and pb[i] and pa[i] == pb[i] do i = i + 1 end
  local out = {}
  for _ = i, #pa do out[#out + 1] = '..' end
  for j = i, #pb do out[#out + 1] = pb[j] end
  return table.concat(out, '/')
end

-- Vault config lives in notes.init; resolve lazily so setup() can override.
local cfg = function()
  return require('notes').get_config()
end

local function expand(p)
  return vim.fn.expand(p)
end

-- Ordered list of { name, root } — default vault first, then named vaults.
function M.all()
  local c = cfg()
  local out = { { name = 'default', root = expand(c.default_vault) } }
  for name, root in pairs(c.vaults) do
    out[#out + 1] = { name = name, root = expand(root) }
  end
  return out
end

function M.is_under(root, path)
  root = M.norm(M.canon(expand(root)))
  path = M.norm(M.canon(path))
  return path == root or path:sub(1, #root + 1) == root .. '/'
end

-- Resolve the vault for a command call: explicit @name wins, else the vault
-- containing cwd, else the default vault.
function M.resolve(prefix)
  local all = M.all()
  if prefix and prefix ~= '' then
    for _, v in ipairs(all) do
      if v.name == prefix then return v end
    end
    error("notes: no vault named '" .. prefix .. "'", 0)
  end
  local cwd = vim.fn.getcwd()
  for _, v in ipairs(all) do
    if M.is_under(v.root, cwd) then return v end
  end
  return all[1]
end

-- All markdown files under a root.
-- shortcut: glob skips hidden directories, fine for note vaults.
function M.files(root)
  local r = M.canon(expand(root))
  return vim.fn.glob(r .. '/**/*.md', false, true)
end

return M