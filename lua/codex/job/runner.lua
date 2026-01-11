local acquisition = require("codex.prompt.acquisition")
local config = require("codex.core.config")
local log = require("codex.core.log")
local output = require("codex.job.output")
local status = require("codex.job.status")

local M = {}

local activeJobId = nil

--- Check if a status line is a Codex-formatted progress message.
---@param line string stderr line to inspect
---@return boolean true when the line should be shown as status
local function is_log_qualified_to_be_viewed(line)
  return line:match("^%*%*.*%*%*$") ~= nil
end

--- Process stderr output from the Codex job.
---@param data string[]|nil stderr lines
---@param state table job state for status updates and log capture
local function handle_job_stderr(data, state)
  if not data then
    return
  end
  for _, line in ipairs(data) do
    if is_log_qualified_to_be_viewed(line) then
      local cleaned = vim.trim(line:gsub("^%*%*", ""):gsub("%*%*$", ""))
      state.statusMessage = "Codex: " .. cleaned
      log.append(state.logPath, state.statusMessage)
      vim.schedule(state.updateStatus)
    else
      log.append(state.logPath, "stderr: " .. line)
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
local function handle_job_stdout(data, stdoutLines, logPath)
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
    log.append(logPath, "stdout: " .. line)
  end
end

--- Finalize a Codex job and apply its output.
---@param opts table job metadata and buffers
---@param exitCode integer process exit code
local function handle_job_exit(opts, exitCode)
  vim.schedule(function()
    local statusTimer = opts.statusTimer
    if statusTimer then
      statusTimer:stop()
      statusTimer:close()
    end
    status.clear_status(opts.bufnr, opts.extmarkId)
    activeJobId = nil
    if exitCode ~= 0 then
      vim.notify("Codex failed. See log: " .. opts.logPath, vim.log.levels.ERROR)
      log.append(opts.logPath, "Exit code: " .. exitCode)
      return
    end
    local jobOutput = table.concat(opts.stdoutLines, "\n")
    if jobOutput == "" and #opts.stderrOutputLines > 0 then
      jobOutput = table.concat(opts.stderrOutputLines, "\n")
    end
    output.replace_full_buffer(opts.bufnr, jobOutput)
    output.restore_cursor(opts.bufnr, opts.cursor)
    log.append(opts.logPath, "Exit code: " .. exitCode)
    log.append(opts.logPath, "Codex invocation finished.")
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
  log.set_last_log_path(logPath)

  log.append(logPath, "Codex invocation started at " .. vim.fn.strftime("%Y-%m-%d %H:%M:%S"))
  log.append(logPath, "CWD: " .. jobCwd)
  log.append(logPath, "Buffer: " .. (bufferPath ~= "" and bufferPath or "unknown"))
  log.append(logPath, "Prompt:")
  log.append(logPath, prompt)

  local command = { "codex", "exec", "--cd", jobCwd, "-" }

  log.append(logPath, "Command: " .. table.concat(command, " "))

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
    extmarkId = status.set_status(bufnr, range, message, extmarkId, cursor)
  end

  state.updateStatus = updateStatus

  statusTimer = vim.loop.new_timer()
  statusTimer:start(0, config.resolve_status_interval(), function()
    vim.schedule(updateStatus)
  end)

  local jobId = vim.fn.jobstart(command, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      handle_job_stdout(data, stdoutLines, logPath)
    end,
    on_stderr = function(_, data)
      handle_job_stderr(data, state)
    end,
    on_exit = function(_, exitCode)
      handle_job_exit({
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
    status.clear_status(bufnr, extmarkId)
    vim.notify("Failed to start Codex job", vim.log.levels.ERROR)
    return
  end
  activeJobId = jobId
  vim.fn.chansend(jobId, prompt)
  vim.fn.chanclose(jobId, "stdin")
end

return M
