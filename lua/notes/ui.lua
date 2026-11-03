-- UI extension points. Everything the plugin shows through a picker goes
-- through M.select; override it in setup({ ui = { select = ... } }) to plug
-- in snacks.nvim, telescope, or anything else. Default: vim.ui.select.

local M = {}

---@alias notes.SelectFn fun(items: any[], opts: vim.api.keyset.ui_select, on_choice: fun(item?: any, idx?: integer))
---@alias notes.InputFn fun(opts: vim.api.keyset.ui_input, on_confirm: fun(text?: string))

---@class notes.ConfigUi
---UI hooks; each falls back to the stock vim behavior when nil.
---@field select? notes.SelectFn picker used by every selection UI in the plugin
---@field input? notes.InputFn input used for free-text prompts (note names)

---The configured select hook, or vim.ui.select.
---@param items any[]
---@param opts vim.api.keyset.ui_select
---@param on_choice fun(item?: any, idx?: integer)
function M.select(items, opts, on_choice)
  local sel = require('notes').get_config().ui.select
  if sel then return sel(items, opts, on_choice) end
  return vim.ui.select(items, opts, on_choice)
end

---The configured input hook, or vim.ui.input.
---@param opts vim.api.keyset.ui_input
---@param on_confirm fun(text?: string)
function M.input(opts, on_confirm)
  local inp = require('notes').get_config().ui.input
  if inp then return inp(opts, on_confirm) end
  return vim.ui.input(opts, on_confirm)
end

return M
