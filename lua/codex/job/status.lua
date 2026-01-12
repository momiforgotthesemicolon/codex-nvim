local config = require("codex.core.Config")

local M = {}

local namespace = vim.api.nvim_create_namespace(
  "momiforgotsemicolon_codex_nvim"
)

--- Ensure the Codex status highlight group is defined with default styling.
function M.ensureHighlight()
  vim.api.nvim_set_hl(0, config.resolveStatusHl(), {
    fg = "#bfbfbf",
    default = true,
  })
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

  if range.startRow == 1 and range.endRow == bufLastLine then
    return math.max(cursor[1] - 1, 0)
  end

  return math.max(range.endRow - 1, 0)
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
function M.clearStatus(bufnr, extmarkId)
  if extmarkId then
    pcall(vim.api.nvim_buf_del_extmark, bufnr, namespace, extmarkId)
  end
end

function M.getNamespace()
  return namespace
end

return M
