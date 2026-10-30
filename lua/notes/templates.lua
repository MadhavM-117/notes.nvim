-- One small template engine shared by note and daily templates.
-- Pure render() is unit-testable; file ops use vim lazily.

local M = {}

-- Accept both strftime (%Y) and human (YYYY) formats for {{date:...}}.
local TOKENS = { YYYY = '%Y', MM = '%m', DD = '%d', HH = '%H', mm = '%M', SS = '%S' }
local function to_strftime(fmt)
  if fmt:find('%%') then return fmt end
  return (fmt:gsub('[YMDHms]+', function(tok) return TOKENS[tok] or tok end))
end

-- Expand {{name}} and {{date:FORMAT}}; unknown variables become ''.
function M.render(text, vars)
  return (text:gsub('%{{([^}]+)}}', function(key)
    local name, fmt = key:match('^([%w_]+):?(.-)$')
    if name == 'date' and fmt ~= '' then
      return os.date(to_strftime(fmt))
    end
    return vars[name] or ''
  end))
end

function M.read(path)
  return vim.fn.readfile(path)
end

-- Top-level .md files in a directory (absolute paths).
function M.list(dir)
  return vim.fn.glob(dir .. '/*.md', false, true)
end

return M