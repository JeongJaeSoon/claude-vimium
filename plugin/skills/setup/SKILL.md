---
name: setup
description: Install the claude-vimium app that /vimium and Ctrl+; need, when it is missing — "set up claude-vimium", "install vimium hints", or /vimium answering that the app was not found. macOS only.
---

# Install the claude-vimium app

The plugin only forwards `/vimium`; hint mode itself runs in a small macOS menu bar app,
because it needs the Accessibility API and a global key that no plugin can reach.

1. Check what is there: `command -v claude-vimium && claude-vimium doctor`. If every line
   reads `ok`, stop and say so.
2. If `claude-vimium` is missing and `brew` exists, install it:
   `brew install jeongjaesoon/tap/claude-vimium`
3. Without Homebrew, build from source (needs the Xcode Command Line Tools,
   `xcode-select --install`):
   ```bash
   git clone https://github.com/JeongJaeSoon/claude-vimium ~/.claude-vimium-src
   make -C ~/.claude-vimium-src app VERSION=source
   ```
   and use `~/.claude-vimium-src/bin/claude-vimium` in place of `claude-vimium` below.
4. Run `claude-vimium setup`. Tell the user before running it what it changes: it adds this
   plugin's marketplace if needed, may add `CLAUDE_CODE_ENABLE_FUNCTION_HOOKS=1` to
   `~/.claude/settings.json` when Claude Desktop bundles a Claude Code older than 2.1.287,
   and registers a login item. `claude-vimium uninstall` undoes all of it.
5. The one step you cannot do: the user must turn on claude-vimium in
   System Settings > Privacy & Security > Accessibility. Say so, then run
   `claude-vimium doctor` again once they have.
