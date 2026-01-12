if vim.g.loadedCodexNvim == 1 or vim.g.loaded_codex_nvim == 1 then
  return
end
vim.g.loadedCodexNvim = 1

require("Codex").checkCodexVersion()

vim.api.nvim_create_user_command("CodexComplete", function()
  require("Codex").completeSelectionOrScope()
end, {})

vim.api.nvim_create_user_command("CodexCompleteBuffer", function()
  require("Codex").completeFullBuffer()
end, {})

vim.api.nvim_create_user_command("CodexOpenLog", function()
  require("Codex").openLastLog()
end, {})
