-- Test runner: nvim --headless -l tests/run.lua  (also runs under plain Lua,
-- the pure modules never touch vim at load time).
package.path = './?.lua;./lua/?.lua;./lua/?/init.lua;' .. package.path

local helper = require('tests.helper')

local specs = { 'tests/links_spec.lua', 'tests/markdown_spec.lua', 'tests/templates_spec.lua', 'tests/vault_spec.lua' }
for _, f in ipairs(specs) do
  local ok, err = pcall(dofile, f)
  if not ok then
    print('LOAD FAIL: ' .. f)
    print(err)
    os.exit(1)
  end
end

local fails = 0
for _, c in ipairs(helper.cases) do
  local ok, err = pcall(c.fn)
  if ok then
    print('ok   ' .. c.name)
  else
    fails = fails + 1
    print('FAIL ' .. c.name .. '\n  ' .. tostring(err))
  end
end
print(string.format('%d passed, %d failed', #helper.cases - fails, fails))
os.exit(fails == 0 and 0 or 1)