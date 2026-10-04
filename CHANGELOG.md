# Changelog

## [Unreleased]

## [1.0.0] - 2026-10-04

### Changed

- Renamed from claude-vimium to **hintvim**: the repository, the `hintvim` command and formula, `Hintvim.app`, the `hintvim` plugin with `/hintvim` and `/hintvim-palette`, and the `hintvim://` URL scheme. `brew upgrade` moves an existing install over, and `hintvim setup` removes what claude-vimium left: its login item, plugin, state and Accessibility entry.
- The menu bar item uses the icon's motif as a template image instead of the generic keyboard symbol, so it follows light and dark menu bars.

### Added

- An app icon, shown in Finder, Spotlight and System Settings, including in the app Homebrew builds from source.
- A README header with the icon, and a social preview image at `docs/assets/social-preview.png`.
- Shell completions for zsh, bash and fish, installed by the formula.

## [0.3.1] - 2026-10-04

### Added

- `hintvim setup --app-only` sets up the app and its login item without the Claude plugin or the mods switch. `Ctrl+;` needs only the app.
- A demo GIF at the top of the README, and a README section on why hintvim is an app and not a Claude Code mod.

### Changed

- `hintvim doctor` reports the plugin as skipped after `setup --app-only` instead of failing.
- When Claude Desktop has no window open, `hintvim doctor` says to click Claude in the Dock.
- The README describes hintvim as an app first, the plugin as optional, and lists two more fixes: a closed Claude window, and a tap that `brew untap` refuses to remove.

## [0.3.0] - 2026-10-03

First public release.

### Added

- `Hintvim.app`, a menu bar app that labels the whole Claude Desktop window through the macOS Accessibility API: `Ctrl+;`, label letters, `j` `k` `d` `u` to scroll, `Esc`.
- Homebrew formula that builds the app from source: `brew install jeongjaesoon/tap/hintvim`.
- `hintvim` command: `setup`, `doctor`, `uninstall`, `toggle`, `start`, `stop`, `mods`.
- The `hintvim` Claude plugin (marketplace `hintvim`): `/hintvim`, `/hintvim-palette`, and the `setup` and `doctor` skills.
- A login item that starts the app and keeps the mods switch in step with Claude Desktop's bundled Claude Code.

### Changed

- The plugin no longer builds a helper at session start; it talks to the installed app through the `hintvim://` URL scheme.
- Hint mode ends when Claude loses focus, skips the window's close, minimize and full-screen buttons, and follows the window when it moves or resizes.

## [0.2.1] - 2026-10-02

Unreleased preview: the plugin built and started an Accessibility helper on each session start.

## [0.1.0] - 2026-08-17

DevTools snippet (`src/hintvim.js`) with hint mode over the web page, settings and help panels.

[Unreleased]: https://github.com/JeongJaeSoon/hintvim/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/JeongJaeSoon/hintvim/compare/v0.3.1...v1.0.0
[0.3.1]: https://github.com/JeongJaeSoon/hintvim/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/JeongJaeSoon/hintvim/releases/tag/v0.3.0
