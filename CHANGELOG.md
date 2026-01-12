# Changelog
All notable changes to this project will be documented in this file.

## [1.0.1] - 2026-01-08
### Added
- `.luarc.json` for Lua language tooling.
- `.gitignore` entries for macOS artifacts.
### Changed
- Lua namespace to a unique name.
### Fixed
- Log buffers now open in read-only mode.
- Undo history stability when working with Codex buffers.
- Safer handling for empty buffers and selections.
- Full-buffer replacement accuracy and cursor placement.
- Buffer navigation no longer impacts the Codex job (Except early startup).
- README configuration documentation.

## [1.0.0] - 2026-01-04
### Added
- Neovim commands: `:CodexComplete`, `:CodexCompleteBuffer`, `:CodexOpenLog`.
- Integration with the `codex` CLI to replace the selection or buffer with
  output.
- Progress/status virtual line with configurable highlight and update interval.
- Log capture and an action to open the most recent Codex log.
- README demo GIF and setup documentation.
