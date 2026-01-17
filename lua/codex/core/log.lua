local M = {}

local lastLogPath = nil

--- Append a line to a log file, ensuring it ends with a newline.
---@param path string|nil path to the log file
---@param line string log line to append
function M.append(path, line)
  if not path then
    return
  end

  local file = io.open(path, "a")
  if not file then
    return
  end

  file:write(line)
  if not line:match("\n$") then
    file:write("\n")
  end

  file:close()
end

function M.setLastLogPath(path)
  lastLogPath = path
end

function M.getLastLogPath()
  return lastLogPath
end

function M.set_last_log_path(path)
  M.setLastLogPath(path)
end

function M.get_last_log_path()
  return M.getLastLogPath()
end

return M
