# codex-nvim

Neovim integration for the `codex` CLI. It sends the current selection or buffer
to Codex and replaces it with the returned output.
Modular Lua architecture; see `ARCHITECTURE.md` for module layout.

## Demo
![Demo](.github/Demo.gif)

## Requirements
- `codex` 0.45.0+ available on your `$PATH`
- Neovim 0.8+

## Install (lazy.nvim)
```lua
{
  "momiforgotthesemicolon/codex-nvim",
  config = function()
    require("Codex").setup()
    vim.keymap.set({ "n", "x" }, "<leader>i", function()
      require("Codex").completeSelectionOrScope()
    end, { desc = "Codex: complete selection or buffer" })
    vim.keymap.set({ "n", "x" }, "<leader>ic", function()
      require("Codex").cancelJob()
    end, { desc = "Codex: cancel running job" })
    vim.keymap.set("n", "<leader><leader>i", function()
      require("Codex").openLastLog()
    end, { desc = "Codex: open last log" })
  end,
}
```

## Commands
- `:CodexComplete` - complete the current selection or the full buffer.
- `:CodexCompleteBuffer` - always run against the full buffer.
- `:CodexOpenLog` - open the most recent Codex log.

## Configuration
```lua
require("Codex").setup({
  statusHl = "CodexStatus",
  statusIntervalMs = 200,
})
```
Settings:
- `statusHl` - highlight group used for the inline status line while
  Codex runs.
- `statusIntervalMs` - how often (ms) the status line updates.
- `cancelJob()` - public API to stop the active Codex job.

You can also override these via globals:
- `vim.g.codex_statusHl` or `vim.g.codex_status_hl`
- `vim.g.codex_statusIntervalMs` or `vim.g.codex_status_interval_ms`

## Architecture
See `ARCHITECTURE.md` for module responsibilities and layout.
