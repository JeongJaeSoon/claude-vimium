# Security policy

claude-vimium holds the macOS Accessibility permission, which lets it read and press anything in Claude Desktop's window, and its setup edits `~/.claude/settings.json`. Please report anything that could let another process or a web page use that, or that leaks what it reads.

## Reporting

Report privately through [GitHub's private vulnerability reporting](https://github.com/JeongJaeSoon/claude-vimium/security/advisories/new). Please don't open a public issue. Expect a first reply within a week.

## Supported versions

Only the latest release gets fixes.

## What the app does and does not do

- It reads the Accessibility tree of Claude Desktop (bundle id `com.anthropic.claudefordesktop`) only while labels show, when `claude-vimium doctor` asks for a probe, and never for any other app.
- It takes keyboard events only while labels show and Claude is the frontmost app.
- It writes only `~/Library/Logs/claude-vimium/app.log`: start times, the Accessibility state, and element counts. Never element text.
- It makes no network connections. `claude-vimium setup` runs `claude plugin` commands, which fetch the plugin from this repository.
- The `claude-vimium://` URL scheme accepts `start`, `toggle` and `probe` and ignores anything else.
