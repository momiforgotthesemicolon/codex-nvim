if vim.g.loaded_codex_nvim == 1 then
  return
end
vim.g.loaded_codex_nvim = 1

require("codex").checkCodexVersion()

vim.api.nvim_create_user_command("CodexComplete", function()
  require("codex").completeSelectionOrScope()
end, {})

vim.api.nvim_create_user_command("CodexCompleteBuffer", function()
  require("codex").completeFullBuffer()
end, {})

vim.api.nvim_create_user_command("CodexOpenLog", function()
  require("codex").openLastLog()
end, {})
