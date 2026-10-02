# Changelog

## [Unreleased]

## [0.3.0] - 2026-10-03

First public release.

### Added

- `ClaudeVimium.app`, a menu bar app that labels the whole Claude Desktop window through the macOS Accessibility API: `Ctrl+;`, label letters, `j` `k` `d` `u` to scroll, `Esc`.
- Homebrew formula that builds the app from source: `brew install jeongjaesoon/tap/claude-vimium`.
- `claude-vimium` command: `setup`, `doctor`, `uninstall`, `toggle`, `start`, `stop`, `mods`.
- The `vimium-hints` Claude plugin (marketplace `claude-vimium`): `/vimium`, `/vimium-palette`, and the `setup` and `doctor` skills.
- A login item that starts the app and keeps the mods switch in step with Claude Desktop's bundled Claude Code.

### Changed

- The plugin no longer builds a helper at session start; it talks to the installed app through the `claude-vimium://` URL scheme.
- Hint mode ends when Claude loses focus, skips the window's close, minimize and full-screen buttons, and follows the window when it moves or resizes.

## [0.2.1] - 2026-10-02

Unreleased preview: the plugin built and started an Accessibility helper on each session start.

## [0.1.0] - 2026-08-17

DevTools snippet (`src/claude-vimium.js`) with hint mode over the web page, settings and help panels.

[Unreleased]: https://github.com/JeongJaeSoon/claude-vimium/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/JeongJaeSoon/claude-vimium/releases/tag/v0.3.0
