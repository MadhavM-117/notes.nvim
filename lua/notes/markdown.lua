-- Markdown list continuation and checkbox toggling. The list/checkbox logic
-- is pure (unit-tested); only the keymap handlers touch vim.

local M = {}

local function parse_list(line)
  local indent, mk, rest = line:match('^([ \t]*)([-*+]%s+)(.*)$')
  local nextmarker
  if not indent then
    indent, mk, rest = line:match('^([ \t]*)(%d+[.)]%s+)(.*)$')
    if indent then
      local num, tail = mk:match('^(%d+)(.*)$')
      nextmarker = string.format('%0' .. #num .. 'd', tonumber(num) + 1) .. tail
    end
  end
  if not indent then return nil end
  local check, rest2 = rest:match('^(%[[ xX]%])%s*(.*)$')
  if check then rest = rest2 end
  return { indent = indent, marker = mk, nextmarker = nextmarker, check = check, rest = rest }
end

-- What <CR> should produce after `line`:
--   string  — next line content (continuation)
--   ''      — empty item: end the list
--   nil     — not a list item: caller falls back to plain <CR>
function M.continuation(line)
  local it = parse_list(line)
  if not it then return nil end
  local body = it.rest:gsub('%s+$', '')
  local s = it.indent .. (it.nextmarker or it.marker)
  if it.check then s = s .. it.check .. ' ' end
  if body == '' then return '' end
  return s
end

-- Flip the first checkbox in a line; returns the line or nil.
function M.toggle_checkbox(line)
  local start, _ = line:find('%[[ xX]%]')
  if not start then return nil end
  local ch = line:sub(start + 1, start + 1)
  local newch = (ch == ' ') and 'x' or ' '
  return line:sub(1, start) .. newch .. line:sub(start + 2)
end

-- ---- keymap handlers ----

function M.cr()
  local s = M.continuation(vim.api.nvim_get_current_line())
  if s == nil then
    return vim.api.nvim_replace_termcodes('<CR>', true, false, true)
  end
  -- Suppress autoindent while we insert, so our marker isn't doubled.
  local buf = vim.api.nvim_get_current_buf()
  local saved = {
    autoindent = vim.bo[buf].autoindent,
    smartindent = vim.bo[buf].smartindent,
    indentexpr = vim.bo[buf].indentexpr,
  }
  vim.bo[buf].autoindent = false
  vim.bo[buf].smartindent = false
  vim.bo[buf].indentexpr = ''
  vim.schedule(function()
    vim.bo[buf].autoindent = saved.autoindent
    vim.bo[buf].smartindent = saved.smartindent
    vim.bo[buf].indentexpr = saved.indentexpr
  end)
  return '\r' .. vim.fn.escape(s, '<')
end

function M.toggle_range(start_line, end_line)
  local buf = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, start_line - 1, end_line, false)
  local new = {}
  for _, l in ipairs(lines) do
    new[#new + 1] = M.toggle_checkbox(l) or l
  end
  vim.api.nvim_buf_set_lines(buf, start_line - 1, end_line, false, new)
end

return M