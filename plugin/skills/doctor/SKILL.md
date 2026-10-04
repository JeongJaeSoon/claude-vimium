---
name: doctor
description: Find out why Ctrl+; or /hintvim does nothing and fix it — "hintvim not working", "Ctrl+; does nothing", "check hintvim". Runs hintvim doctor, fixes what it can, and lists the steps it cannot take.
---

# Diagnose hintvim

Run `hintvim doctor`. If the command is missing, use the `setup` skill instead.

For each `FAIL` line:

| Line | Fix |
|---|---|
| `app: not running` | `hintvim start` |
| `login item: not loaded`, `plugin: … not installed`, `mods switch: needed` | `hintvim setup` (idempotent) |
| `accessibility: not allowed` | The user turns it on in System Settings > Privacy & Security > Accessibility. If hintvim is listed and already on, the app was rebuilt or upgraded and the old entry no longer matches: remove it with `-`, then `hintvim stop && hintvim start` to be asked again. |
| `claude CLI: not found` | Claude Desktop installs its own copy the first time its Code tab opens. |

Then run `hintvim doctor` again and report the result.

If every line is `ok` and hints still do not appear:

- The mod reaches the app only in a **new** Code session after setup. Ask the user to open one.
- `Ctrl+;` works only while Claude Desktop is the frontmost app.
- `~/Library/Logs/hintvim/app.log` records each start and the Accessibility state.
