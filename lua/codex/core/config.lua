local M = {}

local config = {
  statusHl = "CodexStatus",
  statusIntervalMs = 200,
}

local function normalizeOptions(opts)
  if not opts then
    return {}
  end

  local normalized = vim.tbl_extend("force", {}, opts)
  if normalized.status_hl ~= nil and normalized.statusHl == nil then
    normalized.statusHl = normalized.status_hl
  end
  if normalized.status_interval_ms ~= nil
      and normalized.statusIntervalMs == nil then
    normalized.statusIntervalMs = normalized.status_interval_ms
  end
  normalized.status_hl = nil
  normalized.status_interval_ms = nil
  return normalized
end

function M.setup(opts)
  config = vim.tbl_extend("force", config, normalizeOptions(opts))
end

function M.resolveStatusHl()
  return vim.g.codexStatusHl or vim.g.codex_status_hl or config.statusHl
end

function M.resolveStatusInterval()
  local interval = vim.g.codexStatusIntervalMs
    or vim.g.codex_status_interval_ms
    or config.statusIntervalMs
  return tonumber(interval) or config.statusIntervalMs
end

function M.resolve_status_hl()
  return M.resolveStatusHl()
end

function M.resolve_status_interval()
  return M.resolveStatusInterval()
end

return M
