local acquisition = require("codex.prompt.acquisition")

local M = {}

local namespace = vim.api.nvim_create_namespace("momiforgotsemicolon_codex_nvim")
local lastLogPath = nil
local activeJobId = nil

local config = {
  status_hl = "CodexStatus",
  status_interval_ms = 200,
}

--- Resolve the highlight group name for Codex status.
---@return string highlight group name
local function resolveStatusHl()
  return vim.g.codex_status_hl
    or config.status_hl
end

--- Resolve the status update interval from globals or config.
---@return integer status interval in milliseconds
local function resolveStatusInterval()
  local interval = vim.g.codex_status_interval_ms
    or config.status_interval_ms
  return tonumber(interval) or config.status_interval_ms
end

--- Ensure the Codex status highlight group is defined with default styling.
local function ensureHighlight()
  vim.api.nvim_set_hl(0, resolveStatusHl(), { fg = "#bfbfbf", default = true })
end

ensureHighlight()

--- Append a line to a log file, ensuring it ends with a newline.
---@param path string|nil path to the log file
---@param line string log line to append
local function appendLog(path, line)
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

--- Determine the row to place the virtual status line for a given selection.
---@param bufnr integer buffer handle
---@param range table selection range with start_row/end_row
---@param cursor table|nil cursor position {row, col}
---@return integer status row (0-based) for the status extmark
local function getStatusRow(bufnr, range, cursor)
  local bufLastLine = vim.api.nvim_buf_line_count(bufnr)
  cursor = cursor or vim.api.nvim_win_get_cursor(0)

  if range.start_row == 1 and range.end_row == bufLastLine then
    return math.max(cursor[1] - 1, 0)
  end

  return math.max(range.end_row - 1, 0)
end

--- Render or update a virtual status line for the given range.
---@param bufnr integer buffer handle
---@param range table selection range with start_row/end_row
---@param message string status message to display
---@param extmarkId integer|nil existing extmark id, if any
---@param cursor table|nil cursor position {row, col}
---@return integer extmark id for the status line
local function setStatus(bufnr, range, message, extmarkId, cursor)
  local statusRow = getStatusRow(bufnr, range, cursor)
  return vim.api.nvim_buf_set_extmark(bufnr, namespace, statusRow, 0, {
    id = extmarkId,
    virt_lines = { { { message, resolveStatusHl() } } },
    virt_lines_above = false,
  })
end

--- Clear the status extmark if present.
---@param bufnr integer buffer handle
---@param extmarkId integer|nil extmark id to clear
local function clearStatus(bufnr, extmarkId)
  if extmarkId then
    pcall(vim.api.nvim_buf_del_extmark, bufnr, namespace, extmarkId)
  end
end

--- Check if a status line is a Codex-formatted progress message.
---@param line string stderr line to inspect
---@return boolean true when the line should be shown as status
local function isLogQualifiedToBeViewed(line)
  return line:match("^%*%*.*%*%*$") ~= nil
end

--- Process stderr output from the Codex job.
---@param data string[]|nil stderr lines
---@param state table job state for status updates and log capture
local function handleJobStderr(data, state)
  if not data then
    return
  end
  for _, line in ipairs(data) do
    if isLogQualifiedToBeViewed(line) then
      local cleaned = vim.trim(line:gsub("^%*%*", ""):gsub("%*%*$", ""))
      state.statusMessage = "Codex: " .. cleaned
      appendLog(state.logPath, state.statusMessage)
      vim.schedule(state.updateStatus)
    else
      appendLog(state.logPath, "stderr: " .. line)
    end
    if line == "codex" or line == "assistant" or line == "final" then
      state.captureStderrOutput = true
    elseif state.captureStderrOutput then
      if line:match("^tokens used") or line == "exec" or line == "thinking"
        or line == "user" or line:match("^mcp startup")
        or line == "--------" then
        state.captureStderrOutput = false
      else
        table.insert(state.stderrOutputLines, line)
      end
    end
  end
end

--- Process stdout output from the Codex job.
---@param data string[]|nil stdout lines
---@param stdoutLines string[] accumulator for stdout
---@param logPath string path to the log file
local function handleJobStdout(data, stdoutLines, logPath)
  if not data then
    return
  end

  -- There is a chance that buffer at the end returns the output with the empty
  -- line which is added by codex. We are making sure that we don't introduce
  -- any unnecesary changes here.
  if data[#data] == "" and stdoutLines[#stdoutLines] ~= "" then
    table.remove(data, #data)
  end
  for _, line in ipairs(data) do
    table.insert(stdoutLines, line)
    appendLog(logPath, "stdout: " .. line)
  end
end

--- Replace the full buffer text.
---@param bufnr integer buffer handle
---@param newText string replacement text
local function replaceFullBuffer(bufnr, newText)
  local newLines = {}
  if newText ~= "" then
    newLines = vim.split(newText, "\n", { plain = true })
  end
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, newLines)
end

--- Restore the cursor position after buffer updates.
---@param bufnr integer buffer handle
---@param cursor table|nil cursor position {row, col}
local function restoreCursor(bufnr, cursor)
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

--- Finalize a Codex job and apply its output.
---@param opts table job metadata and buffers
---@param exitCode integer process exit code
local function handleJobExit(opts, exitCode)
  vim.schedule(function()
    local statusTimer = opts.statusTimer
    if statusTimer then
      statusTimer:stop()
      statusTimer:close()
    end
    clearStatus(opts.bufnr, opts.extmarkId)
    activeJobId = nil
    if exitCode ~= 0 then
      vim.notify("Codex failed. See log: " .. opts.logPath, vim.log.levels.ERROR)
      appendLog(opts.logPath, "Exit code: " .. exitCode)
      return
    end
    local output = table.concat(opts.stdoutLines, "\n")
    if output == "" and #opts.stderrOutputLines > 0 then
      output = table.concat(opts.stderrOutputLines, "\n")
    end
    replaceFullBuffer(opts.bufnr, output)
    restoreCursor(opts.bufnr, opts.cursor)
    appendLog(opts.logPath, "Exit code: " .. exitCode)
    appendLog(opts.logPath, "Codex invocation finished.")
  end)
end

--- Start a Codex job for the given range and prompt.
---@param bufnr integer buffer handle
---@param range table selection range
---@param prompt string prompt to send
---@param cursor table|nil cursor position {row, col}
function M.start_job(bufnr, range, prompt, cursor)
  if activeJobId and vim.fn.jobwait({ activeJobId }, 0)[1] == -1 then
    vim.notify("Codex job already running.", vim.log.levels.WARN)
    return
  end

  local bufferPath = vim.api.nvim_buf_get_name(bufnr)
  local bufferDir = bufferPath ~= "" and vim.fn.fnamemodify(bufferPath, ":h") or vim.loop.cwd() or "."
  local repoRoot = acquisition.resolve_repo_root(bufferDir)
  local jobCwd = repoRoot or bufferDir
  local logPath = vim.fn.tempname() .. ".codex.log"
  lastLogPath = logPath

  appendLog(logPath, "Codex invocation started at " .. vim.fn.strftime("%Y-%m-%d %H:%M:%S"))
  appendLog(logPath, "CWD: " .. jobCwd)
  appendLog(logPath, "Buffer: " .. (bufferPath ~= "" and bufferPath or "unknown"))
  appendLog(logPath, "Prompt:")
  appendLog(logPath, prompt)

  local command = { "codex", "exec", "--cd", jobCwd, "-" }

  appendLog(logPath, "Command: " .. table.concat(command, " "))

  local stdoutLines = {}
  local stderrOutputLines = {}
  local extmarkId = nil
  local statusTimer = nil
  local startTime = vim.loop.hrtime()
  local state = {
    statusMessage = "Codex: initializing...",
    captureStderrOutput = false,
    stderrOutputLines = stderrOutputLines,
    logPath = logPath,
    updateStatus = nil,
  }

  --- Format elapsed time since job start.
  ---@return string formatted elapsed time
  local function formatElapsed()
    local elapsedMs = (vim.loop.hrtime() - startTime) / 1e6
    return string.format("%.1fs", elapsedMs / 1000)
  end

  --- Update the virtual status line with the latest message.
  local function updateStatus()
    if not state.statusMessage then
      return
    end
    local message = string.format("%s (%s)", state.statusMessage, formatElapsed())
    extmarkId = setStatus(bufnr, range, message, extmarkId, cursor)
  end

  state.updateStatus = updateStatus

  statusTimer = vim.loop.new_timer()
  statusTimer:start(0, resolveStatusInterval(), function()
    vim.schedule(updateStatus)
  end)

  local jobId = vim.fn.jobstart(command, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      handleJobStdout(data, stdoutLines, logPath)
    end,
    on_stderr = function(_, data)
      handleJobStderr(data, state)
    end,
    on_exit = function(_, exitCode)
      handleJobExit({
        bufnr = bufnr,
        range = range,
        cursor = cursor,
        statusTimer = statusTimer,
        extmarkId = extmarkId,
        logPath = logPath,
        stdoutLines = stdoutLines,
        stderrOutputLines = stderrOutputLines,
      }, exitCode)
    end,
  })
  if jobId <= 0 then
    clearStatus(bufnr, extmarkId)
    vim.notify("Failed to start Codex job", vim.log.levels.ERROR)
    return
  end
  activeJobId = jobId
  vim.fn.chansend(jobId, prompt)
  vim.fn.chanclose(jobId, "stdin")
end

function M.get_last_log_path()
  return lastLogPath
end

function M.get_namespace()
  return namespace
end

function M.setup(opts)
  config = vim.tbl_extend("force", config, opts or {})
  ensureHighlight()
end

return M
