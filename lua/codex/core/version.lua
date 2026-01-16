local M = {}

local didCheckCodexVersion = false

local minCodexVersion = "0.45.0"

local function parseVersion(raw)
  if not raw then
    return nil
  end
  return raw:match("(%d+%.%d+%.%d+)")
end

local function compareVersions(a, b)
  local function split(ver)
    local parts = {}
    for part in ver:gmatch("%d+") do
      table.insert(parts, tonumber(part))
    end
    return parts
  end

  local aParts = split(a)
  local bParts = split(b)
  for i = 1, math.max(#aParts, #bParts) do
    local av = aParts[i] or 0
    local bv = bParts[i] or 0
    if av < bv then
      return -1
    elseif av > bv then
      return 1
    end
  end
  return 0
end

local function notifyStaleVersion(version)
  local reported = version or "unknown"
  vim.notify(
    "Codex CLI version " .. reported .. " is stale. Require >= "
      .. minCodexVersion .. "; plugin output may be unexpected.",
    vim.log.levels.ERROR
  )
end

function M.check_codex_version()
  if didCheckCodexVersion then
    return
  end
  didCheckCodexVersion = true

  local output = vim.fn.systemlist({ "codex", "--version" })
  if vim.v.shell_error ~= 0 or not output[1] then
    notifyStaleVersion(nil)
    return
  end

  local detected = parseVersion(output[1])
  if not detected then
    notifyStaleVersion(nil)
    return
  end

  if compareVersions(detected, minCodexVersion) < 0 then
    notifyStaleVersion(detected)
  end
end

return M
