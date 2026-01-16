local config = require("codex.core.config")

local M = {}

local namespace = vim.api.nvim_create_namespace(
  "momiforgotsemicolon_codex_nvim"
)

--- Ensure the Codex status highlight group is defined with default styling.
<<<<<<< HEAD
function M.ensureHighlight()
  vim.api.nvim_set_hl(0, config.resolveStatusHl(), {
=======
function M.ensure_highlight()
  vim.api.nvim_set_hl(0, config.resolve_status_hl(), {
>>>>>>> main
    fg = "#bfbfbf",
    default = true,
  })
end

function M.ensure_highlight()
  M.ensureHighlight()
end

M.ensureHighlight()

--- Determine the row to place the virtual status line for a given selection.
---@param bufnr integer buffer handle
---@param range table selection range with startRow/endRow
---@param cursor table|nil cursor position {row, col}
---@return integer status row (0-based) for the status extmark
local function getStatusRow(bufnr, range, cursor)
  local bufLastLine = vim.api.nvim_buf_line_count(bufnr)
  cursor = cursor or vim.api.nvim_win_get_cursor(0)
  local startRow = range.startRow or range.start_row
  local endRow = range.endRow or range.end_row

  if startRow == 1 and endRow == bufLastLine then
    return math.max(cursor[1] - 1, 0)
  end

  return math.max(endRow - 1, 0)
end

--- Render or update a virtual status line for the given range.
---@param bufnr integer buffer handle
---@param range table selection range with startRow/endRow
---@param message string status message to display
---@param extmarkId integer|nil existing extmark id, if any
---@param cursor table|nil cursor position {row, col}
---@return integer extmark id for the status line
function M.set_status(bufnr, range, message, extmarkId, cursor)
  return M.setStatus(bufnr, range, message, extmarkId, cursor)
end

--- Render or update a virtual status line for the given range.
---@param bufnr integer buffer handle
---@param range table selection range with startRow/endRow
---@param message string status message to display
---@param extmarkId integer|nil existing extmark id, if any
---@param cursor table|nil cursor position {row, col}
---@return integer extmark id for the status line
function M.setStatus(bufnr, range, message, extmarkId, cursor)
  local statusRow = getStatusRow(bufnr, range, cursor)
  return vim.api.nvim_buf_set_extmark(bufnr, namespace, statusRow, 0, {
    id = extmarkId,
    virt_lines = { { { message, config.resolveStatusHl() } } },
    virt_lines_above = false,
  })
end

--- Clear the status extmark if present.
---@param bufnr integer buffer handle
---@param extmarkId integer|nil extmark id to clear
function M.clear_status(bufnr, extmarkId)
  return M.clearStatus(bufnr, extmarkId)
end

--- Clear the status extmark if present.
---@param bufnr integer buffer handle
---@param extmarkId integer|nil extmark id to clear
function M.clearStatus(bufnr, extmarkId)
  if extmarkId then
    pcall(vim.api.nvim_buf_del_extmark, bufnr, namespace, extmarkId)
  end
end

function M.getNamespace()
  return namespace
end

function M.get_namespace()
  return M.getNamespace()
end

return M
