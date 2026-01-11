local acquisition = require("codex.prompt.acquisition")
local creation = require("codex.prompt.creation")
local request = require("codex.prompt.request")

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
    "Codex CLI version " .. reported .. " is stale. Require >= " .. minCodexVersion
      .. "; plugin output may be unexpected.",
    vim.log.levels.ERROR
  )
end

function M.checkCodexVersion()
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
    prompt = creation.build_prompt(bufnr, range, nil, nil, nil, cursor)
  else
    local scopeRange = acquisition.get_scope_range(bufnr, cursor)
    range = scopeRange or fallbackRange
    local scopeLabel = scopeRange and "Context line" or "Current line"
    prompt = creation.build_prompt(
      bufnr,
      range,
      scopeLabel,
      "Complete the scope based on the context of the line under the cursor. The scope could be a class, method, function, comment, variable, or other logical block. Update the full buffer accordingly.",
      true,
      cursor
    )
  end
  request.start_job(bufnr, range, prompt, cursor)
end

function M.completeFullBuffer()
  local bufnr = vim.api.nvim_get_current_buf()
  if not acquisition.buffer_has_content(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, request.get_namespace(), 0, -1)
    vim.notify("Codex: Buffer is empty.", vim.log.levels.INFO)
    return
  end
  local cursor = vim.api.nvim_win_get_cursor(0)
  local range = acquisition.get_full_buffer_range(bufnr)
  local prompt = creation.build_prompt(
    bufnr,
    range,
    "Full buffer",
    "Replace the full buffer with the generated output only in the context of given neovim cursor. Context could be inside a function, lambda, class, method or scope implementation.",
    false,
    cursor
  )
  request.start_job(bufnr, range, prompt, cursor)
end

--- Open the most recent Codex log and map "q" to return to the previous buffer.
--- Stores the originating window, buffer, and cursor so the log view can jump back.
function M.openLastLog()
  local lastLogPath = request.get_last_log_path()
  if not lastLogPath then
    vim.notify("No Codex log available yet.", vim.log.levels.INFO)
    return
  end

  local returnWin = vim.api.nvim_get_current_win()
  local returnBuf = vim.api.nvim_get_current_buf()
  local returnCursor = vim.api.nvim_win_get_cursor(returnWin)

  vim.cmd("view " .. vim.fn.fnameescape(lastLogPath))

  local logBuf = vim.api.nvim_get_current_buf()
  pcall(vim.api.nvim_buf_set_var, logBuf, "codex_log_return", {
    win = returnWin,
    buf = returnBuf,
    cursor = returnCursor,
  })

  vim.notify("Press \"q\" to return to your previous view.", vim.log.levels.INFO)
  vim.keymap.set("n", "q", function()
    local ok, data = pcall(vim.api.nvim_buf_get_var, logBuf, "codex_log_return")
    if ok and data then
      if data.win and vim.api.nvim_win_is_valid(data.win) then
        vim.api.nvim_set_current_win(data.win)
      end
      if data.buf and vim.api.nvim_buf_is_valid(data.buf) then
        vim.api.nvim_set_current_buf(data.buf)
        if data.cursor then
          pcall(vim.api.nvim_win_set_cursor, 0, data.cursor)
        end
        return
      end
    end
    pcall(vim.cmd, "bdelete")
  end, { buffer = logBuf, silent = true, nowait = true })
end

function M.setup(opts)
  request.setup(opts)
end

return M
