local M = {}

local config = {
  statusHl = "CodexStatus",
  statusIntervalMs = 200,
}

local function normalizeOptions(opts)
  local normalized = {}
  for key, value in pairs(opts or {}) do
    if key == "status_hl" then
      normalized.statusHl = value
    elseif key == "status_interval_ms" then
      normalized.statusIntervalMs = value
    else
      normalized[key] = value
    end
  end
  return normalized
end

function M.setup(opts)
  local normalized = normalizeOptions(opts)
  config = vim.tbl_extend("force", config, normalized)
end

function M.resolveStatusHl()
  return vim.g.codex_status_hl
    or vim.g.codex_statusHl
    or config.statusHl
end

function M.resolveStatusInterval()
  local interval = vim.g.codex_status_interval_ms
    or vim.g.codex_statusIntervalMs
    or config.statusIntervalMs
  return tonumber(interval) or config.statusIntervalMs
end

return M
