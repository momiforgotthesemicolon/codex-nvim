# Architecture

This plugin is split into small modules by responsibility. Each module should do one thing well and avoid cross-cutting concerns.

## Directory layout

- lua/codex/init.lua
  - Public API only. Wires modules together.
  - Exposes user-facing functions used by commands in `plugin/codex.lua`.

- lua/codex/core/
  - Cross-cutting core utilities that should not depend on UI or job logic.
  - config.lua: default config + setup + resolution helpers.
  - version.lua: codex CLI version check + notifications.
  - log.lua: append log lines + track last log path.

- lua/codex/prompt/
  - Prompt-related logic only.
  - acquisition.lua: selection/range detection + buffer text access.
  - builder.lua: prompt text assembly from ranges and metadata.

- lua/codex/job/
  - Codex execution and its lifecycle.
  - runner.lua: start job, wire stdout/stderr, timers, exit handling.
  - status.lua: extmark status line rendering + highlight setup.
  - output.lua: apply job output to buffer + cursor restoration.

- lua/codex/ui/
  - User-facing UI helpers.
  - log_view.lua: open last log and return mapping.

- plugin/codex.lua
  - Neovim command registration and lazy-load entry point.

## Dependencies (high level)

- init.lua depends on: core, prompt, job, ui.
- prompt modules should not depend on job or ui.
- job modules may depend on core + prompt (for repo root) but not ui.
- ui modules may depend on core, but should not depend on job internals.

## Adding new features

- New prompt logic: add to `lua/codex/prompt/`.
- New job lifecycle behavior: add to `lua/codex/job/`.
- New user-facing views or commands: add to `lua/codex/ui/` and wire in `init.lua`.
- New cross-cutting shared helpers: add to `lua/codex/core/`.
