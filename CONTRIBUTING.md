# Contributing

Thanks for helping. Bug reports, compatibility reports after a Claude Desktop update, and pull requests are all welcome.

## Before you open a pull request

```bash
make test                       # Node, shell and Swift unit tests
make app                        # builds build/ClaudeVimium.app
claude plugin validate plugin
claude plugin test plugin       # run from an empty directory
```

CI runs the same commands, builds the Homebrew formula from your branch, and installs it on a clean macOS runner.

## Changes to the app

The drawing, the key handling and the Accessibility walk have no automated tests, so a pull request that touches `app/main.swift` needs these checked by hand on a real Claude Desktop. Say in the pull request which ones you ran, and on which macOS and Claude Desktop versions.

- `Ctrl+;` with Claude frontmost shows labels over the sidebar, the title bar and the conversation; the window's close, minimize and full-screen buttons have none.
- Typing a label presses the element, or focuses a text field.
- `j` / `k` / `d` / `u` scroll and relabel; `Esc` and `Delete` on an empty label leave.
- Nothing you type while labels show reaches the prompt box, with a Korean or Japanese input source too.
- `Cmd+Tab` leaves hint mode and still switches apps; clicking another app leaves hint mode.
- Moving or resizing the window while labels show moves them with it.
- `claude-vimium doctor` prints only `ok` lines.

Every build is a new app to macOS, so allow Accessibility again after each rebuild (remove the old entry with `−`).

## Changes to `bin/claude-vimium`

It edits `~/.claude/settings.json`. Add a case to `test/cli.test.sh` for any new edit, and keep these rules: never drop a key the user has, write through symlinks, and remove only what setup added.

## Style

- Match the code around you. Comments say what the code can't.
- Small commits with plain messages (`fix: …`, `feat: …`, `docs: …`).
- Add a line to the `Unreleased` section of [CHANGELOG.md](CHANGELOG.md) for anything a user would notice.

## Releasing (maintainers)

1. Move the `Unreleased` notes under a new version in `CHANGELOG.md`, and set the same version in `plugin/.claude-plugin/plugin.json` and in the `url` of `packaging/claude-vimium.rb`.
2. Merge, then push a tag `vX.Y.Z` on `main`. The release workflow checks the versions, publishes the GitHub release, and attaches the formula with the tarball's sha256. With the `TAP_TOKEN` secret set, it also commits the formula to `JeongJaeSoon/homebrew-tap`.
