#!/bin/sh
# The mods switch logic of bin/claude-vimium, against a throwaway HOME.
set -eu

cli="$(cd "$(dirname "$0")/.." && pwd)/bin/claude-vimium"
home=$(mktemp -d)
trap 'rm -rf "$home"' EXIT
settings="$home/.claude/settings.json"
desktop="$home/Library/Application Support/Claude/claude-code"
marker="$home/Library/Application Support/claude-vimium/added-mods-switch"

run() { HOME="$home" PATH=/usr/bin:/bin:"$(dirname "$(command -v jq)")" sh "$cli" "$@"; }
fail() { echo "FAIL: $*"; exit 1; }
switch() { jq -r '.["env"] // {} | if has("CLAUDE_CODE_ENABLE_FUNCTION_HOOKS") then .CLAUDE_CODE_ENABLE_FUNCTION_HOOKS | tostring else "unset" end' "$settings"; }

# No Desktop Code tab yet: nothing to switch, settings.json untouched.
run mods | grep -q "not needed" || fail "no Desktop: expected not needed"
[ ! -e "$settings" ] || fail "no Desktop: settings.json was created"

# An old bundled Claude Code: switch on, other settings kept, marker written.
mkdir -p "$desktop/2.1.280" "$home/.claude"
printf '{"model":"opus","env":{"KEEP":"1"}}\n' >"$settings"
run mods | grep -q "turned on" || fail "old Claude Code: expected turned on"
[ "$(switch)" = 1 ] || fail "old Claude Code: switch not set"
[ "$(jq -r '.model + .["env"].KEEP' "$settings")" = opus1 ] || fail "old Claude Code: other settings lost"
[ -f "$marker" ] || fail "old Claude Code: marker missing"
run mods | grep -q "already set" || fail "second run: expected already set"

# Desktop updated past 2.1.287, its old folder left beside the new one: the switch this tool added goes away.
mkdir -p "$desktop/2.1.290"
run mods | grep -q "removed" || fail "new Claude Code: expected removed"
[ "$(switch)" = unset ] || fail "new Claude Code: switch still set"
[ "$(jq -r '.["env"].KEEP' "$settings")" = 1 ] || fail "new Claude Code: other env lost"

# A switch the user set by hand is never removed.
jq '.["env"].CLAUDE_CODE_ENABLE_FUNCTION_HOOKS = "1"' "$settings" >"$settings.tmp" && mv "$settings.tmp" "$settings"
run mods | grep -q "not needed" || fail "user's own switch: expected not needed"
[ "$(switch)" = 1 ] || fail "user's own switch: removed"

# A switch setup added and the user then turned off survives the Desktop update.
rm -r "$desktop/2.1.290"
jq 'del(.["env"].CLAUDE_CODE_ENABLE_FUNCTION_HOOKS)' "$settings" >"$settings.tmp" && mv "$settings.tmp" "$settings"
run mods | grep -q "turned on" || fail "edited switch: expected turned on first"
jq '.["env"].CLAUDE_CODE_ENABLE_FUNCTION_HOOKS = false' "$settings" >"$settings.tmp" && mv "$settings.tmp" "$settings"
mkdir -p "$desktop/2.1.290"
run mods | grep -q "left as it is" || fail "edited switch: expected left as it is"
[ "$(switch)" = false ] || fail "edited switch: removed"
[ ! -f "$marker" ] || fail "edited switch: marker kept"

# A folder that is not a three-part version is ignored.
rm -r "$desktop/2.1.290"
jq 'del(.["env"].CLAUDE_CODE_ENABLE_FUNCTION_HOOKS)' "$settings" >"$settings.tmp" && mv "$settings.tmp" "$settings"
mkdir -p "$desktop/2.1.999.0"
run mods | grep -q "turned on" || fail "four-part folder: counted as newest"
rm -r "$desktop/2.1.999.0" && rm -f "$marker"
mkdir -p "$desktop/2.1.290"
jq '.["env"].CLAUDE_CODE_ENABLE_FUNCTION_HOOKS = "1"' "$settings" >"$settings.tmp" && mv "$settings.tmp" "$settings"

# A switch the user turned off is not turned on.
rm -r "$desktop/2.1.290"
jq '.["env"].CLAUDE_CODE_ENABLE_FUNCTION_HOOKS = false' "$settings" >"$settings.tmp" && mv "$settings.tmp" "$settings"
run mods | grep -q "already set" || fail "user's false: expected already set"
[ "$(jq -r '.["env"].CLAUDE_CODE_ENABLE_FUNCTION_HOOKS' "$settings")" = false ] || fail "user's false: overwritten"

# A symlinked settings.json stays a symlink.
rm -r "$desktop/2.1.280" && mkdir -p "$desktop/2.1.284"
jq 'del(.["env"].CLAUDE_CODE_ENABLE_FUNCTION_HOOKS)' "$settings" >"$home/shared.json"
rm "$settings" && ln -s "$home/shared.json" "$settings"
run mods >/dev/null
[ -L "$settings" ] || fail "symlink replaced by a file"
[ "$(switch)" = 1 ] || fail "symlink: switch not written through"

# Version ordering is numeric, not lexical: 2.1.1000 is newer than 2.1.287.
rm -r "$desktop/2.1.284" && mkdir -p "$desktop/2.1.1000"
run mods | grep -q "removed" || fail "2.1.1000: expected removed"

# setup --app-only leaves the plugin out: the login item then never touches the switch.
stub="$home/stub" && mkdir -p "$stub" && printf '#!/bin/sh\n' >"$stub/open" && chmod +x "$stub/open"
login() { HOME="$home" PATH="$stub":/usr/bin:/bin:"$(dirname "$(command -v jq)")" sh "$cli" login; }
rm "$settings" && printf '{}\n' >"$settings" && rm -f "$marker" && rm -r "$desktop/2.1.1000" && mkdir -p "$desktop/2.1.280"
touch "$home/Library/Application Support/claude-vimium/app-only"
login
[ "$(switch)" = unset ] || fail "app-only login: switch added"
run doctor 2>/dev/null | grep -q "skipped by setup --app-only" || fail "app-only doctor: plugin not reported as skipped"
rm "$home/Library/Application Support/claude-vimium/app-only"
login
[ "$(switch)" = 1 ] || fail "login: switch not added"
run setup --bogus 2>/dev/null && fail "setup with an unknown option should fail"

# setup --app-only after a full setup takes back the switch that setup added. A copy of the
# command with a stand-in app, and stubs for the system tools, keep the real login item untouched.
mkdir -p "$home/repo/bin" "$home/repo/build/ClaudeVimium.app"
cp "$cli" "$home/repo/bin/claude-vimium"
for t in pkill launchctl; do printf '#!/bin/sh\n' >"$stub/$t" && chmod +x "$stub/$t"; done
setup() { HOME="$home" PATH="$stub":/usr/bin:/bin:"$(dirname "$(command -v jq)")" sh "$home/repo/bin/claude-vimium" setup "$@"; }
[ "$(switch)" = 1 ] && [ -f "$marker" ] || fail "app-only setup: fixture lacks the added switch"
setup --app-only --bogus 2>/dev/null && fail "setup with an extra operand should fail"
[ ! -e "$home/Library/Application Support/claude-vimium/app-only" ] || fail "rejected setup changed state"
setup --app-only | grep -q "mods switch: removed" || fail "app-only setup: expected the switch removed"
[ "$(switch)" = unset ] || fail "app-only setup: switch still set"
[ -f "$home/Library/Application Support/claude-vimium/app-only" ] || fail "app-only setup: marker missing"

# A switch the user changed after setup added it stays, and setup no longer claims it.
setup >/dev/null && [ "$(switch)" = 1 ] || fail "full setup: switch not added"
jq '.["env"].CLAUDE_CODE_ENABLE_FUNCTION_HOOKS = false' "$settings" >"$settings.tmp" && cat "$settings.tmp" >"$settings"
setup --app-only >/dev/null
[ "$(switch)" = false ] || fail "app-only setup: user's change overwritten"
[ ! -e "$marker" ] || fail "app-only setup: stale ownership marker"

run version | grep -q "claude-vimium dev" || fail "version"
run bogus 2>/dev/null && fail "unknown command should fail"

echo "cli OK"
