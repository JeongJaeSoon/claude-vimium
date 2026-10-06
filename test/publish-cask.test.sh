#!/bin/sh
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
version=$(sed -n 's/.*"version": "\([^"]*\)".*/\1/p' "$root/plugin/.claude-plugin/plugin.json")
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/stub" "$fixture/payload/Hintvim.app/Contents/MacOS" \
  "$fixture/payload/bin" "$fixture/payload/completions"
printf '#!/bin/sh\necho "hintvim %s"\n' "$version" >"$fixture/payload/Hintvim.app/Contents/MacOS/Hintvim"
printf '#!/bin/sh\nexit 0\n' >"$fixture/payload/bin/hintvim"
printf complete >"$fixture/payload/completions/hintvim.bash"
printf complete >"$fixture/payload/completions/_hintvim"
printf complete >"$fixture/payload/completions/hintvim.fish"
chmod +x "$fixture/payload/Hintvim.app/Contents/MacOS/Hintvim" "$fixture/payload/bin/hintvim"
printf dmg >"$fixture/hintvim.dmg"

cat >"$fixture/stub/codesign" <<'SH'
#!/bin/sh
case "$*" in
  *Hintvim.app*) exit "${TEST_APP_SIGNATURE_STATUS:-0}" ;;
  *) exit "${TEST_DMG_SIGNATURE_STATUS:-0}" ;;
esac
SH
cat >"$fixture/stub/xcrun" <<'SH'
#!/bin/sh
exit "${TEST_STAPLER_STATUS:-0}"
SH
cat >"$fixture/stub/hdiutil" <<'SH'
#!/bin/sh
case $1 in
  attach)
    while [ "$#" -gt 0 ]; do
      if [ "$1" = -mountpoint ]; then shift; mount=$1; break; fi
      shift
    done
    cp -R "$TEST_DMG_PAYLOAD"/. "$mount"/
    ;;
  detach) ;;
  *) exit 1 ;;
esac
SH
chmod +x "$fixture/stub/"*

fail() { echo "FAIL: $*"; exit 1; }
run() {
  DRY_RUN=1 HINTVIM_DMG="$fixture/hintvim.dmg" \
    TEST_DMG_PAYLOAD="$fixture/payload" PATH="$fixture/stub:$PATH" \
    sh "$root/scripts/publish-cask.sh" "v$version"
}

APPLE_TEAM_ID=TESTTEAM01 run >"$fixture/cask.rb"
sha=$(shasum -a 256 "$fixture/hintvim.dmg" | awk '{print $1}')
grep -qF "version \"$version\"" "$fixture/cask.rb" || fail "version not replaced"
grep -qF "sha256 \"$sha\"" "$fixture/cask.rb" || fail "checksum not replaced"
grep -qF 'Run `hintvim uninstall` before' "$fixture/cask.rb" || fail "explicit uninstall instructions missing"
grep -qF 'app "Hintvim.app"' "$fixture/cask.rb" || fail "app artifact missing"
grep -qF 'binary "bin/hintvim"' "$fixture/cask.rb" || fail "CLI artifact missing"

(TEST_DMG_SIGNATURE_STATUS=1 APPLE_TEAM_ID=TESTTEAM01 run) >/dev/null 2>&1 && fail "invalid DMG signature accepted"
(TEST_APP_SIGNATURE_STATUS=1 APPLE_TEAM_ID=TESTTEAM01 run) >/dev/null 2>&1 && fail "invalid app signature accepted"
(TEST_STAPLER_STATUS=1 APPLE_TEAM_ID=TESTTEAM01 run) >/dev/null 2>&1 && fail "missing notarization accepted"
APPLE_TEAM_ID='' run >/dev/null 2>&1 && fail "missing team accepted"
APPLE_TEAM_ID=lowercase1 run >/dev/null 2>&1 && fail "invalid team accepted"
APPLE_TEAM_ID=SHORT run >/dev/null 2>&1 && fail "short team accepted"

rm -rf "$fixture/payload/Hintvim.app"
APPLE_TEAM_ID=TESTTEAM01 run >/dev/null 2>&1 && fail "missing app accepted"

mkdir -p "$fixture/payload/Hintvim.app/Contents/MacOS"
printf '#!/bin/sh\necho "hintvim %s"\n' "$version" >"$fixture/payload/Hintvim.app/Contents/MacOS/Hintvim"
chmod +x "$fixture/payload/Hintvim.app/Contents/MacOS/Hintvim"
rm "$fixture/payload/completions/_hintvim"
APPLE_TEAM_ID=TESTTEAM01 run >/dev/null 2>&1 && fail "missing zsh completion accepted"

printf complete >"$fixture/payload/completions/_hintvim"
rm "$fixture/payload/completions/hintvim.fish"
APPLE_TEAM_ID=TESTTEAM01 run >/dev/null 2>&1 && fail "missing fish completion accepted"

printf complete >"$fixture/payload/completions/hintvim.fish"
cat >"$fixture/stub/gh" <<'SH'
#!/bin/sh
if [ "${4:-}" = .sha ]; then
  echo null
  exit 1
fi
printf '%s\n' "$@" >"$TEST_GH_ARGS"
echo https://example.invalid/commit
SH
chmod +x "$fixture/stub/gh"
DRY_RUN='' GH_TOKEN=test APPLE_TEAM_ID=TESTTEAM01 HINTVIM_DMG="$fixture/hintvim.dmg" \
  TEST_DMG_PAYLOAD="$fixture/payload" TEST_GH_ARGS="$fixture/gh-args" \
  PATH="$fixture/stub:$PATH" sh "$root/scripts/publish-cask.sh" "v$version" >/dev/null
grep -qx "message=hintvim $version" "$fixture/gh-args" || fail "commit message split into multiple arguments"
grep -qx 'repos/JeongJaeSoon/homebrew-tap/contents/Casks/hintvim.rb' "$fixture/gh-args" || fail "tap path argument missing"
echo 'publish-cask OK'
