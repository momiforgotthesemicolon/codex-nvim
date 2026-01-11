local acquisition = require("codex.prompt.acquisition")
local builder = require("codex.prompt.builder")
local config = require("codex.core.config")
local runner = require("codex.job.runner")
local status = require("codex.job.status")
local ui_log = require("codex.ui.log_view")
local version = require("codex.core.version")

local M = {}

function M.checkCodexVersion()
  version.check_codex_version()
end

--- Complete the current selection or full buffer based on cursor context.
function M.completeSelectionOrScope()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  if not acquisition.buffer_has_content(bufnr) then
    vim.notify("Buffer is empty.", vim.log.levels.INFO)
    return
  end
  local visualRange = acquisition.get_visual_range(bufnr)
  local fallbackRange = acquisition.get_fallback_range(bufnr, cursor)
  local range = visualRange or fallbackRange
  local prompt
  if visualRange then
    prompt = builder.build_prompt(bufnr, range, nil, nil, nil, cursor)
  else
    local scopeRange = acquisition.get_scope_range(bufnr, cursor)
    range = scopeRange or fallbackRange
    local scopeLabel = scopeRange and "Context line" or "Current line"
    prompt = builder.build_prompt(
      bufnr,
      range,
      scopeLabel,
      "Complete the scope based on the context of the line under the cursor. The scope could be a class, method, function, comment, variable, or other logical block. Update the full buffer accordingly.",
      true,
      cursor
    )
  end
  runner.start_job(bufnr, range, prompt, cursor)
end

function M.completeFullBuffer()
  local bufnr = vim.api.nvim_get_current_buf()
  if not acquisition.buffer_has_content(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, status.get_namespace(), 0, -1)
    vim.notify("Codex: Buffer is empty.", vim.log.levels.INFO)
    return
  end
  local cursor = vim.api.nvim_win_get_cursor(0)
  local range = acquisition.get_full_buffer_range(bufnr)
  local prompt = builder.build_prompt(
    bufnr,
    range,
    "Full buffer",
    "Replace the full buffer with the generated output only in the context of given neovim cursor. Context could be inside a function, lambda, class, method or scope implementation.",
    false,
    cursor
  )
  runner.start_job(bufnr, range, prompt, cursor)
end

function M.openLastLog()
  ui_log.open_last_log()
end

function M.setup(opts)
  config.setup(opts)
  status.ensure_highlight()
end

return M
