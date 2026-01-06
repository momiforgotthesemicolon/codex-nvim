local M = {}

local namespace = vim.api.nvim_create_namespace("codex_nvim")
local lastLogPath = nil

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

--- Resolve the git repository root for a buffer directory.
--- Returns nil when the directory is not inside a git repository.
---@param bufDir string directory containing the buffer
---@return string|nil path to the root repository folder
local function resolveRepoRoot(bufDir)
  local cmd = { "git", "-C", bufDir, "rev-parse", "--show-toplevel" }
  local output = vim.fn.systemlist(cmd)

  if vim.v.shell_error ~= 0 or not output[1] then
    return nil
  end

  return output[1]
end

--- Get the current visual selection range, if any.
---@param bufnr integer buffer handle
---@return table|nil selection range with start_row/start_col/end_row/end_col
local function getVisualRange(bufnr)
  local currentMode = vim.fn.mode()

  if currentMode ~= "v" and currentMode ~= "V" and currentMode ~= "\22" then
    return nil
  end

  local startPos = vim.api.nvim_buf_get_mark(bufnr, "<")
  local endPos = vim.api.nvim_buf_get_mark(bufnr, ">")

  if startPos[1] == 0 or endPos[1] == 0 then
    return nil
  end

  local sRow, sCol = startPos[1], startPos[2]
  local eRow, eCol = endPos[1], endPos[2]

  if sRow > eRow or (sRow == eRow and sCol > eCol) then
    sRow, eRow = eRow, sRow
    sCol, eCol = eCol, sCol
  end

  local mode = vim.fn.visualmode()
  local endLine = vim.api.nvim_buf_get_lines(bufnr, eRow - 1, eRow, false)[1] or ""
  local endCol

  if mode == "V" then
    endCol = #endLine
  else
    endCol = eCol + 1
  end

  if endCol > #endLine then
    endCol = #endLine
  end

  if endCol < 0 then
    endCol = 0
  end

  return {
    start_row = sRow,
    start_col = math.max(sCol, 0),
    end_row = eRow,
    end_col = endCol,
  }
end

--- Build a range for the current cursor line.
---@param bufnr integer buffer handle
---@param cursor table|nil cursor position {row, col}
---@return table selection range covering the cursor line
local function getFallbackRange(bufnr, cursor)
  cursor = cursor or vim.api.nvim_win_get_cursor(0)
  local line = vim.api.nvim_buf_get_lines(bufnr, cursor[1] - 1, cursor[1], false)[1] or ""

  return {
    start_row = cursor[1],
    start_col = 0,
    end_row = cursor[1],
    end_col = #line,
  }
end

--- Determine the smallest relevant scope around the cursor.
---@param bufnr integer buffer handle
---@param cursor table|nil cursor position {row, col}
---@return table|nil selection range covering the detected scope
local function getScopeRange(bufnr, cursor)
  cursor = cursor or vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1
  local col = cursor[2]
  local ok, node = pcall(vim.treesitter.get_node, { buf = bufnr, pos = { row, col } })
  if not ok or not node then
    local ok_parser, parser = pcall(vim.treesitter.get_parser, bufnr)
    if ok_parser and parser then
      local tree = parser:parse()[1]
      if tree then
        node = tree:root():named_descendant_for_range(row, col, row, col)
      end
    end
  end
  if not node then
    return nil
  end

  local scopePriorities = {
    comment = 1,
    function_declaration = 2,
    function_definition = 2,
    method_declaration = 2,
    method_definition = 2,
    class_declaration = 2,
    class_definition = 2,
    interface_declaration = 2,
    struct_specifier = 2,
    enum_specifier = 2,
    module = 2,
    local_function = 2,
    local_variable_declaration = 3,
    variable_declaration = 3,
    assignment_statement = 3,
    lexical_declaration = 3,
    declaration = 3,
    property_declaration = 3,
    field_definition = 3,
    if_statement = 4,
    for_statement = 4,
    while_statement = 4,
    repeat_statement = 4,
    do_statement = 4,
    switch_statement = 4,
    case_statement = 4,
    block = 5,
  }

  ---@type TSNode?
  local bestNode = nil
  local bestPriority = math.huge
  local bestSize = math.huge

  ---@type TSNode?
  local current = node
  while current do
    local nodeType = current:type()
    local priority = scopePriorities[nodeType]
    if priority then
      local srow, scol, erow, ecol = current:range()
      local size = (erow - srow) * 10000 + (ecol - scol)
      if priority < bestPriority or (priority == bestPriority and size < bestSize) then
        bestNode = current
        bestPriority = priority
        bestSize = size
      end
    end
    current = current:parent()
  end

  if not bestNode then
    return nil
  end

  local srow, scol, erow, ecol = bestNode:range()
  if erow == srow and ecol == scol then
    return nil
  end

  return {
    start_row = srow + 1,
    start_col = scol,
    end_row = erow + 1,
    end_col = ecol,
  }
end

--- Build a range that spans the entire buffer.
---@param bufnr integer buffer handle
---@return table selection range covering the full buffer
local function getFullBufferRange(bufnr)
  local lastLine = vim.api.nvim_buf_line_count(bufnr)
  local line = vim.api.nvim_buf_get_lines(bufnr, lastLine - 1, lastLine, false)[1] or ""

  return {
    start_row = 1,
    start_col = 0,
    end_row = lastLine,
    end_col = #line,
  }
end

--- Fetch the text within a range.
---@param bufnr integer buffer handle
---@param range table selection range with start_row/start_col/end_row/end_col
---@return string[] lines of text in the range
local function getText(bufnr, range)
  return vim.api.nvim_buf_get_text(
    bufnr,
    range.start_row - 1,
    range.start_col,
    range.end_row - 1,
    range.end_col,
    {}
  )
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
  for _, line in ipairs(data) do
    table.insert(stdoutLines, line)
    appendLog(logPath, "stdout: " .. line)
  end
end

--- Build the prompt sent to Codex for the given selection or buffer.
---@param bufnr integer buffer handle
---@param range table selection range
---@param scopeLabel string|nil label for the selection header
---@param taskLabel string|nil task description for the prompt
---@param includeFullBuffer boolean|nil whether to include the full buffer contents
---@param cursor table|nil cursor position {row, col}
---@return string prompt text
---@return string|nil repoRoot repository root (if detected)
---@return string bufferDir buffer directory
local function buildPrompt(bufnr, range, scopeLabel, taskLabel, includeFullBuffer, cursor)
  local bufferPath = vim.api.nvim_buf_get_name(bufnr)
  local bufferDir = bufferPath ~= "" and vim.fn.fnamemodify(bufferPath, ":h") or vim.loop.cwd() or "."
  local repoRoot = resolveRepoRoot(bufferDir) or "unknown"

  cursor = cursor or vim.api.nvim_win_get_cursor(0)
  local filetype = vim.bo[bufnr].filetype
  local selectionLines = getText(bufnr, range)
  local bufferLines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local scopeTitle = scopeLabel or "Selection"
  local taskTitle = taskLabel
      or "Replace the full buffer with the correct output, using the provided scope as guidance."
  local returnLabel = "Return only the full buffer text with your changes applied."
  local shouldIncludeFullBuffer = includeFullBuffer ~= false
  local promptLines = {
    "Task: " .. taskTitle,
    "Buffer path: " .. (bufferPath ~= "" and bufferPath or "unknown"),
    "Repo root: " .. repoRoot,
    "Cursor: line " .. cursor[1] .. ", col " .. cursor[2],
    "Filetype: " .. (filetype ~= "" and filetype or "unknown"),
    "You may inspect repository context if needed.",
    "Keep in mind that you cannot interact with the user. If you face choice, please chose the most probable option",
    "Please return only the code output",
    "Make sure that outputs new lines and tabs style matches the initial buffer",
    "The selection block is context only; do not include it in the output.",
    "Your output must be the full buffer only, with edits applied in place.",
    "",
    scopeTitle .. ":",
  }

  vim.list_extend(promptLines, selectionLines)
  if shouldIncludeFullBuffer then
    vim.list_extend(promptLines, {
      "",
      "Full buffer:",
    })
    vim.list_extend(promptLines, bufferLines)
  end
  vim.list_extend(promptLines, {
    "",
    returnLabel,
    "Do not include markdown, backticks, commentary, or status lines. Do not clean from new lines - Its very important",
  })
  return table.concat(promptLines, "\n"), repoRoot, bufferDir
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
local function startJob(bufnr, range, prompt, cursor)
  local bufferPath = vim.api.nvim_buf_get_name(bufnr)
  local bufferDir = bufferPath ~= "" and vim.fn.fnamemodify(bufferPath, ":h") or vim.loop.cwd() or "."
  local repoRoot = resolveRepoRoot(bufferDir)
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
  vim.fn.chansend(jobId, prompt)
  vim.fn.chanclose(jobId, "stdin")
end

--- Check if the buffer has any non-whitespace content.
---@param bufnr integer buffer handle
---@return boolean
local function bufferHasContent(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for _, line in ipairs(lines) do
    if line:match("%S") then
      return true
    end
  end
  return false
end


--- Complete the current selection or full buffer based on cursor context.
function M.completeSelectionOrScope()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  if not bufferHasContent(bufnr) then
    vim.notify("Buffer is empty.", vim.log.levels.INFO)
    return
  end
  local visualRange = getVisualRange(bufnr)
  local fallbackRange = getFallbackRange(bufnr, cursor)
  local range = visualRange or fallbackRange
  local prompt
  if visualRange then
    prompt = buildPrompt(bufnr, range, nil, nil, nil, cursor)
  else
    local scopeRange = getScopeRange(bufnr, cursor)
    range = scopeRange or fallbackRange
    local scopeLabel = scopeRange and "Context line" or "Current line"
    prompt = buildPrompt(
      bufnr,
      range,
      scopeLabel,
      "Complete the scope based on the context of the line under the cursor. The scope could be a class, method, function, comment, variable, or other logical block. Update the full buffer accordingly.",
      true,
      cursor
    )
  end
  startJob(bufnr, range, prompt, cursor)
end

--- Complete the entire buffer based on cursor context.
function M.completeFullBuffer()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  if not bufferHasContent(bufnr) then
    vim.notify("Buffer is empty.", vim.log.levels.INFO)
    return
  end
  -- Instead of giving only vague description of the cursor and context, we should also git the text around the cursor so its easier for codex to determine the change that the user wants
  local range = getFullBufferRange(bufnr)
  local prompt = buildPrompt(
    bufnr,
    range,
    "Full buffer",
    "Replace the full buffer with the generated output only in the context of given neovim cursor. Context could be inside a function, lambda, class, method or scope implementation.",
    false,
    cursor
  )
  startJob(bufnr, range, prompt, cursor)
end

function M.openLastLog()
  if not lastLogPath then
    vim.notify("No Codex log available yet.", vim.log.levels.INFO)
    return
  end
  vim.cmd("edit " .. vim.fn.fnameescape(lastLogPath))
end

function M.setup(opts)
  config = vim.tbl_extend("force", config, opts or {})
  ensureHighlight()
end

return M
