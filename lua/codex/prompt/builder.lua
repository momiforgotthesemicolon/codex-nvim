local acquisition = require("codex.prompt.Acquisition")

local M = {}

--- Build the prompt sent to Codex for the given selection or buffer.
---@param bufnr integer buffer handle
---@param range table selection range
---@param scopeLabel string|nil label for the selection header
---@param taskLabel string|nil task description for the prompt
---@param includeFullBuffer boolean|nil whether to include the full buffer
--- contents
---@param cursor table|nil cursor position {row, col}
---@return string prompt text
---@return string|nil repoRoot repository root (if detected)
---@return string bufferDir buffer directory
function M.buildPrompt(
  bufnr,
  range,
  scopeLabel,
  taskLabel,
  includeFullBuffer,
  cursor
)
  local bufferPath = vim.api.nvim_buf_get_name(bufnr)
  local bufferDir = bufferPath ~= ""
      and vim.fn.fnamemodify(bufferPath, ":h")
    or vim.loop.cwd()
    or "."
  local repoRoot = acquisition.resolveRepoRoot(bufferDir) or "unknown"

  cursor = cursor or vim.api.nvim_win_get_cursor(0)
  local filetype = vim.bo[bufnr].filetype
  local selectionLines = acquisition.getText(bufnr, range)
  local bufferLines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local scopeTitle = scopeLabel or "Selection"
  local taskTitle = taskLabel
    or table.concat({
      "Replace the full buffer with the correct output, using the provided ",
      "scope as guidance.",
    })
  local returnLabel = "Return only the full buffer text "
    .. "with your changes applied."
  local shouldIncludeFullBuffer = includeFullBuffer ~= false
  local promptLines = {
    "Task: " .. taskTitle,
    "Buffer path: " .. (bufferPath ~= "" and bufferPath or "unknown"),
    "Repo root: " .. repoRoot,
    "Cursor: line " .. cursor[1] .. ", col " .. cursor[2],
    "Filetype: " .. (filetype ~= "" and filetype or "unknown"),
    "You may inspect repository context if needed.",
    table.concat({
      "Keep in mind that you cannot interact with the user. ",
      "If you face choice, please chose the most probable option",
    }),
    "Please return only the code output",
    table.concat({
      "Make sure that outputs new lines and tabs style matches the ",
      "initial buffer",
    }),
    table.concat({
      "The selection block / Context near cursor is context only; ",
      "do not include it in the output.",
    }),
    table.concat({
      "If you see the comment next to the cursor position, there is a high ",
      "chance that this is a comment directed toward you, not code itself",
    }),
    "Your output must be the full buffer only, with edits applied in place.",
    "If no changes are needed, return the full unchanged buffer.",
    "",
    scopeTitle .. ":",
  }

  vim.list_extend(promptLines, selectionLines)
  if shouldIncludeFullBuffer then
    vim.list_extend(promptLines, {
      "",
      "Full buffer:",
    })
    vim.list_extend(promptLines, bufferLines)
  end
  vim.list_extend(promptLines, {
    "",
    returnLabel,
    table.concat({
      "Do not include markdown, backticks, commentary, or status lines. ",
      "Do not clean from new lines - Its very important",
    }),
  })
  return table.concat(promptLines, "\n"), repoRoot, bufferDir
end

return M
