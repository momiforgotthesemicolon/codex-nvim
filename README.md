# codex-nvim

Neovim integration for the `codex` CLI. It sends the current selection or buffer
to Codex and replaces it with the returned output.

## Requirements
- `codex` available on your `$PATH`
- Neovim 0.8+

## Install (lazy.nvim)
```lua
{
  "momiforgotthesemicolon/codex-nvim",
  config = function()
    require("codex").setup()
    vim.keymap.set({ "n", "x" }, "<leader>i", function()
      require("codex").completeSelectionOrScope()
    end, { desc = "Codex: complete selection or buffer" })
    vim.keymap.set("n", "<leader><leader>i", function()
      require("codex").openLastLog()
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
require("codex").setup({
  status_hl = "CodexStatus",
  status_interval_ms = 200,
})
```

You can also override these via globals:
- `vim.g.codex_status_hl`
- `vim.g.codex_status_interval_ms`

Legacy globals from the original config are still respected:
- `vim.g.animator_codex_status_hl`
- `vim.g.animator_codex_status_interval`
