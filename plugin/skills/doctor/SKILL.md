---
name: doctor
description: Diagnose claude-vimium when Ctrl+; or /vimium does nothing in Claude Desktop — "vimium hints not working", "Ctrl+; does nothing", "check claude-vimium". Runs claude-vimium doctor, fixes what it can, and gives the user the steps it cannot take.
---

# Diagnose claude-vimium

Run `claude-vimium doctor`. If the command is missing, use the `setup` skill instead.

For each `FAIL` line:

| Line | Fix |
|---|---|
| `app: not running` | `claude-vimium start` |
| `login item: not loaded`, `plugin: … not installed`, `mods switch: needed` | `claude-vimium setup` (idempotent) |
| `accessibility: not allowed` | The user turns it on in System Settings > Privacy & Security > Accessibility. If claude-vimium is listed and already on, the app was rebuilt or upgraded and the old entry no longer matches: remove it with `-`, then `claude-vimium stop && claude-vimium start` to be asked again. |
| `claude CLI: not found` | Claude Desktop installs its own copy the first time its Code tab opens. |

Then run `claude-vimium doctor` again and report the result.

If every line is `ok` and hints still do not appear:

- The mod reaches the app only in a **new** Code session after setup. Ask the user to open one.
- `Ctrl+;` works only while Claude Desktop is the frontmost app.
- While an input method is composing (Korean, Japanese), `Ctrl+;` can be swallowed. Press `Esc` first.
- `~/Library/Logs/claude-vimium/app.log` records each start and the Accessibility state.
