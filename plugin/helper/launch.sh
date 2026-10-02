#!/bin/sh
# Builds ClaudeVimium.app when its source changed, then runs it.
#   launch.sh          build if stale, start if not running
#   launch.sh toggle   enter (or leave) hint mode, once the helper is running
#   launch.sh stop     quit the helper
set -eu

here=$(cd "$(dirname "$0")" && pwd)
home_dir="$HOME/Library/Application Support/claude-vimium"
app="$home_dir/ClaudeVimium.app"
bin="$app/Contents/MacOS/ClaudeVimium"

case "${1:-start}" in
  stop)
    pkill -x ClaudeVimium || true
    exit 0
    ;;
esac

# Rebuilding changes the ad-hoc signature, and macOS then asks for the
# Accessibility grant again, so build only when the source hash moved.
hash=$(shasum -a 256 "$here/ClaudeVimium.swift" | cut -d' ' -f1)
if [ ! -x "$bin" ] || [ "$(cat "$home_dir/source.sha256" 2>/dev/null)" != "$hash" ]; then
  pkill -x ClaudeVimium || true
  mkdir -p "$app/Contents/MacOS"
  cat >"$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>dev.claude-vimium.helper</string>
  <key>CFBundleName</key><string>ClaudeVimium</string>
  <key>CFBundleExecutable</key><string>ClaudeVimium</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
  swiftc -O "$here/ClaudeVimium.swift" -o "$bin"
  codesign --force --sign - "$app"
  echo "$hash" >"$home_dir/source.sha256"
  echo "built $app"
fi

if ! pgrep -x ClaudeVimium >/dev/null; then
  open -g "$app"
  # SIGUSR1 kills a helper that has not installed its handler yet, so a
  # helper started just now is left alone: Ctrl+; then shows the labels.
  echo "started"
  exit 0
fi

if [ "${1:-start}" = toggle ]; then
  pkill -USR1 -x ClaudeVimium
fi
echo "running"
