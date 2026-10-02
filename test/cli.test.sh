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
switch() { jq -r '.["env"].CLAUDE_CODE_ENABLE_FUNCTION_HOOKS // "unset"' "$settings"; }

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

run version | grep -q "claude-vimium dev" || fail "version"
run bogus 2>/dev/null && fail "unknown command should fail"

echo "cli OK"
