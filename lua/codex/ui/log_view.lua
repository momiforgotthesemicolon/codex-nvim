local log = require("codex.core.log")

local M = {}

--- Open the most recent Codex log and map "q" to return to the previous buffer.
--- Stores the originating window, buffer, and cursor so the log view can jump
--- back.
function M.open_last_log()
  local lastLogPath = log.get_last_log_path()
  if not lastLogPath then
    vim.notify("No Codex log available yet.", vim.log.levels.INFO)
    return
  end

  local returnWin = vim.api.nvim_get_current_win()
  local returnBuf = vim.api.nvim_get_current_buf()
  local returnCursor = vim.api.nvim_win_get_cursor(returnWin)

  vim.cmd("view " .. vim.fn.fnameescape(lastLogPath))

  local logBuf = vim.api.nvim_get_current_buf()
  pcall(vim.api.nvim_buf_set_var, logBuf, "codex_log_return", {
    win = returnWin,
    buf = returnBuf,
    cursor = returnCursor,
  })

  vim.notify(
    "Press \"q\" to return to your previous view.",
    vim.log.levels.INFO
  )
  vim.keymap.set("n", "q", function()
    local ok, data = pcall(vim.api.nvim_buf_get_var, logBuf, "codex_log_return")
    if ok and data then
      if data.win and vim.api.nvim_win_is_valid(data.win) then
        vim.api.nvim_set_current_win(data.win)
      end
      if data.buf and vim.api.nvim_buf_is_valid(data.buf) then
        vim.api.nvim_set_current_buf(data.buf)
        if data.cursor then
          pcall(vim.api.nvim_win_set_cursor, 0, data.cursor)
        end
        return
      end
    end
    pcall(vim.cmd, "bdelete")
  end, { buffer = logBuf, silent = true, nowait = true })
end

return M
