local acquisition = require("codex.prompt.acquisition")
local config = require("codex.core.config")
local log = require("codex.core.log")
local output = require("codex.job.output")
local status = require("codex.job.status")

local M = {}

local activeJob = nil

--- Reset timers and status markers for a completed or cancelled job.
--- Clears the virtual status line and releases any associated timer.
---@param job table|nil job state table with timers and status metadata
local function cleanupJobState(job)
  if not job then
    return
  end

  -- If the status timer of the job is still alive, send terminate signal to the
  -- process just in case.
  if job.statusTimer then
    pcall(job.statusTimer.stop, job.statusTimer)
    pcall(job.statusTimer.close, job.statusTimer)
    job.statusTimer = nil
  end

  status.clearStatus(job.bufnr, job.extmarkId)
  job.extmarkId = nil
end

--- Check if a status line is a Codex-formatted progress message.
---@param line string stderr line to inspect
---@return boolean true when the line should be shown as status
local function isLogQualifiedToBeViewed(line)
  return line:match("^%*%*.*%*%*$") ~= nil
end

--- Sanitizes log that is qualified to be vieved for user via
--- is_log_qualified_to_be_viewed
---@param line string input from log
---@return string sanitized line
local function sanitizeLogs(line)
  return vim.trim(line:gsub("^%*%*", ""):gsub("%*%*$", ""))
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
      local cleaned = sanitizeLogs(line)
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
    log.append(logPath, "stdout: " .. line)
  end
end

--- Finalize a Codex job and apply its output.
---@param opts table job metadata and buffers
---@param exitCode integer process exit code
local function handleJobExit(opts, exitCode)
  vim.schedule(function()
    cleanupJobState(opts)
    if activeJob and activeJob.id == opts.id then
      activeJob = nil
    end
    if opts.cancelled then
      log.append(opts.logPath, "Codex invocation cancelled.")
      if exitCode ~= 0 then
        log.append(opts.logPath, "Exit code: " .. exitCode)
      end
      return
    end
    if exitCode ~= 0 then
      local message = "Codex failed. See log: " .. opts.logPath
      vim.notify(message, vim.log.levels.ERROR)
      log.append(opts.logPath, "Exit code: " .. exitCode)
      return
    end
    local jobOutput = table.concat(opts.stdoutLines, "\n")
    if jobOutput == "" and #opts.stderrOutputLines > 0 then
      jobOutput = table.concat(opts.stderrOutputLines, "\n")
    end

    -- For convinience we are replacing the whole buffer and hoping that the
    -- codex is not going to change anything but the part we want based on the
    -- promt that we gave him. However this approach is not super reliable and
    -- we should for sure should fix this to be more reliable way.
    output.replaceFullBuffer(opts.bufnr, jobOutput)
    output.restoreCursor(opts.bufnr, opts.cursor)
    log.append(opts.logPath, "Exit code: " .. exitCode)
    log.append(opts.logPath, "Codex invocation finished.")
  end)
end

--- Start a Codex job for the given range and prompt.
---@param bufnr integer buffer handle
---@param range table selection range
---@param prompt string prompt to send
---@param cursor table|nil cursor position {row, col}
function M.startJob(bufnr, range, prompt, cursor)
  if activeJob and vim.fn.jobwait({ activeJob.id }, 0)[1] == -1 then
    vim.notify("Codex job already running.", vim.log.levels.WARN)
    return
  end

  local bufferPath = vim.api.nvim_buf_get_name(bufnr)
  local bufferDir = bufferPath ~= ""
    and vim.fn.fnamemodify(bufferPath, ":h")
    or vim.loop.cwd()
    or "."
  local repoRoot = acquisition.resolveRepoRoot(bufferDir)
  local jobCwd = repoRoot or bufferDir
  local logPath = vim.fn.tempname() .. ".codex.log"
  log.setLastLogPath(logPath)

  log.append(
    logPath,
    "Codex invocation started at " .. vim.fn.strftime("%Y-%m-%d %H:%M:%S")
  )
  log.append(logPath, "CWD: " .. jobCwd)
  log.append(
    logPath,
    "Buffer: " .. (bufferPath ~= "" and bufferPath or "unknown")
  )
  log.append(logPath, "Prompt:")
  log.append(logPath, prompt)

  local command = { "codex", "exec", "--cd", jobCwd, "-" }

  log.append(logPath, "Command: " .. table.concat(command, " "))

  local stdoutLines = {}
  local stderrOutputLines = {}
  local jobState = {
    bufnr = bufnr,
    range = range,
    cursor = cursor,
    extmarkId = nil,
    statusTimer = nil,
    logPath = logPath,
    stdoutLines = {},
    stderrOutputLines = {},
    cancelled = false,
    id = nil,
  }
  local startTime = vim.loop.hrtime()
  local state = {
    statusMessage = "Codex: initializing...",
    captureStderrOutput = false,
    stderrOutputLines = jobState.stderrOutputLines,
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
    local message = string.format(
      "%s (%s)",
      state.statusMessage,
      formatElapsed()
    )
    jobState.extmarkId = status.setStatus(
      bufnr,
      range,
      message,
      jobState.extmarkId,
      cursor
    )
  end

  state.updateStatus = updateStatus

  jobState.statusTimer = vim.loop.new_timer()
  jobState.statusTimer:start(0, config.resolveStatusInterval(), function()
    vim.schedule(updateStatus)
  end)

  local jobId = vim.fn.jobstart(command, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      handleJobStdout(data, jobState.stdoutLines, logPath)
    end,
    on_stderr = function(_, data)
      handleJobStderr(data, state)
    end,
    on_exit = function(_, exitCode)
      handleJobExit(jobState, exitCode)
    end,
  })
  if jobId <= 0 then
    cleanupJobState(jobState)
    vim.notify("Failed to start Codex job", vim.log.levels.ERROR)
    return
  end
  jobState.id = jobId
  activeJob = jobState
  vim.fn.chansend(jobId, prompt)
  vim.fn.chanclose(jobId, "stdin")
end

--- Cancel the active Codex job if one is running.
---@return boolean true when a running job was cancelled
function M.cancelJob()
  -- We will start by checking if there are any active jobs
  if not activeJob or not activeJob.id then
    vim.notify("No active Codex job to cancel.", vim.log.levels.INFO)
    return false
  end

  -- If we have job stored but its not active then we still don't have to cancel
  -- TODO: we most likely should have a way to store many job statuses, when
  -- multiple codex instances are going to be run
  if vim.fn.jobwait({ activeJob.id }, 0)[1] ~= -1 then
    vim.notify("No active Codex job to cancel.", vim.log.levels.INFO)
    return false
  end

  -- Mark job as cancelled
  activeJob.cancelled = true
  log.append(activeJob.logPath, "Cancelling Codex invocation.")

  -- Note here that the Job stop only sends a signal to terminate the job.
  -- We don't wait until the process shuts down!
  -- TODO: it might be neccesary in the future here to track down the ongoing
  -- processes. We don't want to leave zombie processes.
  vim.fn.jobstop(activeJob.id)
  cleanupJobState(activeJob)
  activeJob = nil

  vim.notify("Codex job cancelled.", vim.log.levels.INFO)
  return true
end

function M.start_job(bufnr, range, prompt, cursor)
  return M.startJob(bufnr, range, prompt, cursor)
end

function M.cancel_job()
  return M.cancelJob()
end

return M
