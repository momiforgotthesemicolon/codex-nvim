local M = {}

local config = {
  status_hl = "CodexStatus",
  status_interval_ms = 200,
}

function M.setup(opts)
  config = vim.tbl_extend("force", config, opts or {})
end

function M.resolve_status_hl()
  return vim.g.codex_status_hl or config.status_hl
end

function M.resolve_status_interval()
  local interval = vim.g.codex_status_interval_ms or config.status_interval_ms
  return tonumber(interval) or config.status_interval_ms
end

return M
