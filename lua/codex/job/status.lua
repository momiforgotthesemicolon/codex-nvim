local config = require("codex.core.config")

local M = {}

local namespace = vim.api.nvim_create_namespace(
  "momiforgotsemicolon_codex_nvim"
)

--- Ensure the Codex status highlight group is defined with default styling.
function M.ensure_highlight()
  vim.api.nvim_set_hl(0, config.resolve_status_hl(), {
    fg = "#bfbfbf",
    default = true,
  })
end

M.ensure_highlight()

--- Determine the row to place the virtual status line for a given selection.
---@param bufnr integer buffer handle
---@param range table selection range with start_row/end_row
---@param cursor table|nil cursor position {row, col}
---@return integer status row (0-based) for the status extmark
local function get_status_row(bufnr, range, cursor)
  local bufLastLine = vim.api.nvim_buf_line_count(bufnr)
  cursor = cursor or vim.api.nvim_win_get_cursor(0)

  if range.start_row == 1 and range.end_row == bufLastLine then
    return math.max(cursor[1] - 1, 0)
  end

  return math.max(range.end_row - 1, 0)
end

--- Render or update a virtual status line for the given range.
---@param bufnr integer buffer handle
---@param range table selection range with start_row/end_row
---@param message string status message to display
---@param extmarkId integer|nil existing extmark id, if any
---@param cursor table|nil cursor position {row, col}
---@return integer extmark id for the status line
function M.set_status(bufnr, range, message, extmarkId, cursor)
  local statusRow = get_status_row(bufnr, range, cursor)
  return vim.api.nvim_buf_set_extmark(bufnr, namespace, statusRow, 0, {
    id = extmarkId,
    virt_lines = { { { message, config.resolve_status_hl() } } },
    virt_lines_above = false,
  })
end

--- Clear the status extmark if present.
---@param bufnr integer buffer handle
---@param extmarkId integer|nil extmark id to clear
function M.clear_status(bufnr, extmarkId)
  if extmarkId then
    pcall(vim.api.nvim_buf_del_extmark, bufnr, namespace, extmarkId)
  end
end

function M.get_namespace()
  return namespace
end

return M
