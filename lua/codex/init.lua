local acquisition = require("codex.prompt.acquisition")
local builder = require("codex.prompt.builder")
local config = require("codex.core.config")
local runner = require("codex.job.runner")
local status = require("codex.job.status")
local uiLog = require("codex.ui.logView")
local version = require("codex.core.version")

local M = {}

function M.checkCodexVersion()
  version.checkCodexVersion()
end

--- Complete the current selection or full buffer based on cursor context.
function M.completeSelectionOrScope()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  if not acquisition.bufferHasContent(bufnr) then
    vim.notify("Buffer is empty.", vim.log.levels.INFO)
    return
  end
  local visualRange = acquisition.getVisualRange(bufnr)
  local fallbackRange = acquisition.getFallbackRange(bufnr, cursor)
  local range = visualRange or fallbackRange
  local prompt
  if visualRange then
    prompt = builder.buildPrompt(bufnr, range, nil, nil, nil, cursor)
  else
    local scopeRange = acquisition.getScopeRange(bufnr, cursor)
    range = scopeRange or fallbackRange
    local scopeLabel = scopeRange and "Context line" or "Current line"
    prompt = builder.buildPrompt(
      bufnr,
      range,
      scopeLabel,
      "Complete the scope based on the context of the line under the cursor. "
        .. "The scope could be a class, method, function, comment, variable, "
        .. "or other logical block. Update the full buffer accordingly.",
      true,
      cursor
    )
  end
  runner.startJob(bufnr, range, prompt, cursor)
end

function M.completeFullBuffer()
  local bufnr = vim.api.nvim_get_current_buf()
  if not acquisition.bufferHasContent(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, status.getNamespace(), 0, -1)
    vim.notify("Codex: Buffer is empty.", vim.log.levels.INFO)
    return
  end
  local cursor = vim.api.nvim_win_get_cursor(0)
  local range = acquisition.getFullBufferRange(bufnr)
  local prompt = builder.buildPrompt(
    bufnr,
    range,
    "Full buffer",
    "Replace the full buffer with the generated output only in the context of "
      .. "given neovim cursor. Context could be inside a function, lambda, "
      .. "class, method or scope implementation.",
    false,
    cursor
  )
  runner.startJob(bufnr, range, prompt, cursor)
end

function M.openLastLog()
  uiLog.openLastLog()
end

function M.cancelJob()
  runner.cancelJob()
end

function M.setup(opts)
  config.setup(opts)
  status.ensureHighlight()
end

return M
