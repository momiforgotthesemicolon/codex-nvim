# Style

This plugin enforces a maximum line length of 80 characters.

- Keep lines at or under 80 characters in Lua, Markdown, and workflows.
- CI checks line length for all tracked files.
- Use camelCase naming throughout code and docs:
  - Variables start with a lowercase letter.
  - Classes and objects start with a capital letter.
  - Functions and methods start with a lowercase letter.
- Do not rename internal plugin commands (for example `:CodexCancelJob`);
  keep existing command names unchanged to preserve compatibility.
