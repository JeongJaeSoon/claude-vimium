#!/bin/sh
# Turns Claude Code mods on for every session that reads ~/.claude/settings.json,
# the Claude Desktop Code tab included. Only Claude Code older than 2.1.287 needs
# it: mods are on by default from 2.1.287, which ignores the variable, and the
# docs ask you to remove it then (--off).
#
#   sh scripts/enable-mods.sh          # turn on
#   sh scripts/enable-mods.sh --off    # turn off
set -eu

settings="${SETTINGS_FILE:-$HOME/.claude/settings.json}"
key=CLAUDE_CODE_ENABLE_FUNCTION_HOOKS

command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }
[ -f "$settings" ] || echo '{}' >"$settings"

backup="$settings.bak.$(date +%Y%m%d%H%M%S)"
cp "$settings" "$backup"

tmp=$(mktemp)
if [ "${1:-}" = "--off" ]; then
  jq --arg k "$key" 'if has("env") then .["env"] |= del(.[$k]) else . end' "$settings" >"$tmp"
else
  jq --arg k "$key" '.["env"] = ((.["env"] // {}) + {($k): "1"})' "$settings" >"$tmp"
fi
mv "$tmp" "$settings"

echo "backup: $backup"
echo "$key = $(jq -r --arg k "$key" '.["env"][$k] // "unset"' "$settings")"
echo "Start a new Code session in Claude Desktop for it to take effect."
