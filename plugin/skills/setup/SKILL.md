---
name: setup
description: Install the hintvim app that /hintvim and Ctrl+; need — "set up hintvim", "install hintvim", or /hintvim saying the app was not found. macOS only.
---

# Install the hintvim app

The plugin only forwards `/hintvim`; hint mode itself runs in a small macOS menu bar app,
because it needs the Accessibility API and a global key that no plugin can reach.

1. Check what is there: `command -v hintvim && hintvim doctor`. If every line
   reads `ok`, stop and say so.
2. If `hintvim` is missing and `brew` exists, install it:
   `brew install jeongjaesoon/tap/hintvim`
3. Without Homebrew, build from source (needs the Xcode Command Line Tools,
   `xcode-select --install`):
   ```bash
   git clone https://github.com/JeongJaeSoon/hintvim ~/.hintvim-src
   make -C ~/.hintvim-src app VERSION=source
   ```
   and use `~/.hintvim-src/bin/hintvim` in place of `hintvim` below.
4. Run `hintvim setup`. Tell the user before running it what it changes: it adds this
   plugin's marketplace if needed, may add `CLAUDE_CODE_ENABLE_FUNCTION_HOOKS=1` to
   `~/.claude/settings.json` when Claude Desktop bundles a Claude Code older than 2.1.287,
   and registers a login item. `hintvim uninstall` undoes all of it.
5. The one step you cannot do: the user must turn on hintvim in
   System Settings > Privacy & Security > Accessibility. Say so, then run
   `hintvim doctor` again once they have.
