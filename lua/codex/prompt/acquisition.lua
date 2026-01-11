local M = {}

--- Resolve the git repository root for a buffer directory.
--- Returns nil when the directory is not inside a git repository.
---@param bufDir string directory containing the buffer
---@return string|nil path to the root repository folder
function M.resolve_repo_root(bufDir)
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
function M.get_visual_range(bufnr)
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
function M.get_fallback_range(bufnr, cursor)
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
function M.get_scope_range(bufnr, cursor)
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
function M.get_full_buffer_range(bufnr)
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
function M.get_text(bufnr, range)
  return vim.api.nvim_buf_get_text(
    bufnr,
    range.start_row - 1,
    range.start_col,
    range.end_row - 1,
    range.end_col,
    {}
  )
end

--- Check if the buffer has any non-whitespace content.
---@param bufnr integer buffer handle
---@return boolean
function M.buffer_has_content(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for _, line in ipairs(lines) do
    if line:match("[^%s%z]") then
      return true
    end
  end
  return false
end

return M
