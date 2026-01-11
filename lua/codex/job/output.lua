local M = {}

--- Replace the full buffer text.
---@param bufnr integer buffer handle
---@param newText string replacement text
function M.replace_full_buffer(bufnr, newText)
  local newLines = {}
  if newText ~= "" then
    newLines = vim.split(newText, "\n", { plain = true })
  end
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, newLines)
end

--- Restore the cursor position after buffer updates.
---@param bufnr integer buffer handle
---@param cursor table|nil cursor position {row, col}
function M.restore_cursor(bufnr, cursor)
  if not cursor then
    return
  end
  local lineCount = vim.api.nvim_buf_line_count(bufnr)
  if lineCount < 1 then
    return
  end
  local row = math.max(1, math.min(cursor[1], lineCount))
  local line = vim.api.nvim_buf_get_lines(bufnr, row - 1, row, false)[1] or ""
  local col = math.max(0, math.min(cursor[2], #line))
  vim.api.nvim_win_set_cursor(0, { row, col })
end

return M
