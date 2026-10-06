#!/bin/sh
set -eu
root="$(cd "$(dirname "$0")/.." && pwd)"
version=$(sed -n 's/.*"version": "\([^"]*\)".*/\1/p' "$root/plugin/.claude-plugin/plugin.json")
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/stub" "$fixture/Hintvim.app/Contents/MacOS"
printf '#!/bin/sh\necho "hintvim %s"\n' "$version" >"$fixture/Hintvim.app/Contents/MacOS/Hintvim"
chmod +x "$fixture/Hintvim.app/Contents/MacOS/Hintvim"
tar -czf "$fixture/archive.tar.gz" -C "$fixture" Hintvim.app
printf '#!/bin/sh\nexit "${TEST_CODESIGN_STATUS:-0}"\n' >"$fixture/stub/codesign"
printf '#!/bin/sh\nexit "${TEST_STAPLER_STATUS:-0}"\n' >"$fixture/stub/xcrun"
chmod +x "$fixture/stub/"*
fail() { echo "FAIL: $*"; exit 1; }
run() {
  DRY_RUN=1 HINTVIM_TARBALL="$fixture/archive.tar.gz" PATH="$fixture/stub:$PATH" \
    sh "$root/scripts/publish-tap.sh" "v$version" "$@"
}
run >"$fixture/formula.rb"
grep -qF "/tags/v$version.tar.gz" "$fixture/formula.rb" || fail "source URL changed"
sha=$(shasum -a 256 "$fixture/archive.tar.gz" | cut -d' ' -f1)
grep -qF "sha256 \"$sha\"" "$fixture/formula.rb" || fail "checksum not replaced"

APPLE_TEAM_ID=TESTTEAM01 run signed >"$fixture/formula.rb"
grep -qF "/releases/download/v$version/hintvim-$version-macos-universal.tar.gz" "$fixture/formula.rb" || fail "signed URL missing"
grep -q 'prefix.install "Hintvim.app"' "$fixture/formula.rb" || fail "signed app not installed intact"
grep -q 'SIGNING_TEAM_ID = "TESTTEAM01"' "$fixture/formula.rb" || fail "signing team not pinned"
grep -q 'system "make"' "$fixture/formula.rb" && fail "signed formula rebuilds the app"

TEST_CODESIGN_STATUS=1 APPLE_TEAM_ID=TESTTEAM01 run signed >/dev/null 2>&1 && fail "invalid signature accepted"
TEST_STAPLER_STATUS=1 APPLE_TEAM_ID=TESTTEAM01 run signed >/dev/null 2>&1 && fail "missing notarization accepted"
APPLE_TEAM_ID='' run signed >/dev/null 2>&1 && fail "missing team accepted"
run bogus >/dev/null 2>&1 && fail "invalid mode accepted"
cat >"$fixture/stub/gh" <<'SH'
#!/bin/sh
case "$*" in
  *'--jq .sha') echo 'existing-sha' ;;
  *'--jq .content') printf 'url "https://github.com/example/releases/download/v1/app.tar.gz"\n' | base64 ;;
  *'-X PUT'*) touch "$TEST_WRITE_MARKER" ;;
  *) exit 1 ;;
esac
SH
chmod +x "$fixture/stub/gh"
DRY_RUN='' HINTVIM_TARBALL="$fixture/archive.tar.gz" TEST_WRITE_MARKER="$fixture/written" \
  PATH="$fixture/stub:$PATH" sh "$root/scripts/publish-tap.sh" "v$version" >/dev/null 2>&1 && fail "signed distribution downgraded"
[ ! -e "$fixture/written" ] || fail "tap written during downgrade"
echo 'publish-tap OK'
