-- Tiny self-contained test helper: register cases in any order, run at end.
local M = { cases = {} }

function M.t(name, fn)
  M.cases[#M.cases + 1] = { name = name, fn = fn }
end

function M.eq(actual, expected, msg)
  if actual ~= expected then
    error(string.format('%s: expected %q, got %q', msg or 'eq', tostring(expected), tostring(actual)), 2)
  end
end

return M