local M = {}

local function getRangeValue(range, camelKey, snakeKey)
  return range[camelKey] or range[snakeKey]
end

--- Resolve the git repository root for a buffer directory.
--- Returns nil when the directory is not inside a git repository.
---@param bufDir string directory containing the buffer
---@return string|nil path to the root repository folder
function M.resolveRepoRoot(bufDir)
  local cmd = { "git", "-C", bufDir, "rev-parse", "--show-toplevel" }
  local output = vim.fn.systemlist(cmd)

  if vim.v.shell_error ~= 0 or not output[1] then
    return nil
  end

  return output[1]
end

function M.resolve_repo_root(bufDir)
  return M.resolveRepoRoot(bufDir)
end

--- Get the current visual selection range, if any.
---@param bufnr integer buffer handle
---@return table|nil selection range with startRow/startCol/endRow/endCol
function M.getVisualRange(bufnr)
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
  local endLine = vim.api.nvim_buf_get_lines(
    bufnr,
    eRow - 1,
    eRow,
    false
  )[1] or ""
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
    startRow = sRow,
    startCol = math.max(sCol, 0),
    endRow = eRow,
    endCol = endCol,
    start_row = sRow,
    start_col = math.max(sCol, 0),
    end_row = eRow,
    end_col = endCol,
  }
end

function M.get_visual_range(bufnr)
  return M.getVisualRange(bufnr)
end

--- Build a range for the current cursor line.
---@param bufnr integer buffer handle
---@param cursor table|nil cursor position {row, col}
---@return table selection range covering the cursor line
function M.getFallbackRange(bufnr, cursor)
  cursor = cursor or vim.api.nvim_win_get_cursor(0)
  local line = vim.api.nvim_buf_get_lines(
    bufnr,
    cursor[1] - 1,
    cursor[1],
    false
  )[1] or ""

  return {
    startRow = cursor[1],
    startCol = 0,
    endRow = cursor[1],
    endCol = #line,
    start_row = cursor[1],
    start_col = 0,
    end_row = cursor[1],
    end_col = #line,
  }
end

function M.get_fallback_range(bufnr, cursor)
  return M.getFallbackRange(bufnr, cursor)
end

--- Determine the smallest relevant scope around the cursor.
---@param bufnr integer buffer handle
---@param cursor table|nil cursor position {row, col}
---@return table|nil selection range covering the detected scope
function M.getScopeRange(bufnr, cursor)
  cursor = cursor or vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1
  local col = cursor[2]
  local ok, node = pcall(
    vim.treesitter.get_node,
    { buf = bufnr, pos = { row, col } }
  )
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
      if priority < bestPriority
        or (priority == bestPriority and size < bestSize)
      then
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
    startRow = srow + 1,
    startCol = scol,
    endRow = erow + 1,
    endCol = ecol,
    start_row = srow + 1,
    start_col = scol,
    end_row = erow + 1,
    end_col = ecol,
  }
end

function M.get_scope_range(bufnr, cursor)
  return M.getScopeRange(bufnr, cursor)
end

--- Build a range that spans the entire buffer.
---@param bufnr integer buffer handle
---@return table selection range covering the full buffer
function M.getFullBufferRange(bufnr)
  local lastLine = vim.api.nvim_buf_line_count(bufnr)
  local line = vim.api.nvim_buf_get_lines(
    bufnr,
    lastLine - 1,
    lastLine,
    false
  )[1] or ""

  return {
    startRow = 1,
    startCol = 0,
    endRow = lastLine,
    endCol = #line,
    start_row = 1,
    start_col = 0,
    end_row = lastLine,
    end_col = #line,
  }
end

function M.get_full_buffer_range(bufnr)
  return M.getFullBufferRange(bufnr)
end

--- Fetch the text within a range.
---@param bufnr integer buffer handle
---@param range table selection range with startRow/startCol/endRow/endCol
---@return string[] lines of text in the range
function M.getText(bufnr, range)
  local startRow = getRangeValue(range, "startRow", "start_row")
  local startCol = getRangeValue(range, "startCol", "start_col")
  local endRow = getRangeValue(range, "endRow", "end_row")
  local endCol = getRangeValue(range, "endCol", "end_col")
  return vim.api.nvim_buf_get_text(
    bufnr,
    startRow - 1,
    startCol,
    endRow - 1,
    endCol,
    {}
  )
end

function M.get_text(bufnr, range)
  return M.getText(bufnr, range)
end

--- Check if the buffer has any non-whitespace content.
---@param bufnr integer buffer handle
---@return boolean
function M.bufferHasContent(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for _, line in ipairs(lines) do
    if line:match("[^%s%z]") then
      return true
    end
  end
  return false
end

function M.buffer_has_content(bufnr)
  return M.bufferHasContent(bufnr)
end

return M
