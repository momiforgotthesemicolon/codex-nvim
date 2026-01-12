# Architecture

This plugin is split into small modules by responsibility. Each module should
do one thing well and avoid cross-cutting concerns.

## Directory layout

- lua/Codex.lua
  - Public API only. Wires modules together.
  - Exposes user-facing functions used by commands in `plugin/Codex.lua`.

- lua/codex/core/
  - Cross-cutting core utilities that should not depend on UI or job logic.
  - Config.lua: default config + setup + resolution helpers.
  - Version.lua: codex CLI version check + notifications.
  - Log.lua: append log lines + track last log path.

- lua/codex/prompt/
  - Prompt-related logic only.
  - Acquisition.lua: selection/range detection + buffer text access.
  - Builder.lua: prompt text assembly from ranges and metadata.

- lua/codex/job/
  - Codex execution and its lifecycle.
  - Runner.lua: start job, wire stdout/stderr, timers, exit handling.
  - Status.lua: extmark status line rendering + highlight setup.
  - Output.lua: apply job output to buffer + cursor restoration.

- lua/codex/ui/
  - User-facing UI helpers.
  - LogView.lua: open last log and return mapping.

- plugin/Codex.lua
  - Neovim command registration and lazy-load entry point.

## Dependencies (high level)

- Codex.lua depends on: core, prompt, job, ui.
- prompt modules should not depend on job or ui.
- job modules may depend on core + prompt (for repo root) but not ui.
- ui modules may depend on core, but should not depend on job internals.

## Adding new features

- New prompt logic: add to `lua/codex/prompt/`.
- New job lifecycle behavior: add to `lua/codex/job/`.
- New user-facing views or commands: add to `lua/codex/ui/` and wire
  in `Codex.lua`.
- New cross-cutting shared helpers: add to `lua/codex/core/`.
