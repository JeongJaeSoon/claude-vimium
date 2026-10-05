#!/bin/sh
set -eu

cli="$(cd "$(dirname "$0")/.." && pwd)/bin/hintvim"
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/repo/bin" "$fixture/repo/build/Hintvim.app" "$fixture/stub" \
  "$fixture/Library/Logs/hintvim" "$fixture/Library/Application Support/hintvim"
cp "$cli" "$fixture/repo/bin/hintvim"
touch "$fixture/Library/Application Support/hintvim/app-only"
for tool in pgrep launchctl sleep; do
  printf '#!/bin/sh\nexit 0\n' >"$fixture/stub/$tool"
done
cat >"$fixture/stub/open" <<'SH'
#!/bin/sh
case $DOCTOR_SCENARIO in
  denied) echo 'now probe: accessibility trusted=false' >>"$HOME/Library/Logs/hintvim/app.log" ;;
  allowed)
    echo 'now probe: accessibility trusted=true' >>"$HOME/Library/Logs/hintvim/app.log"
    echo 'now probe: 3 targets in a window' >>"$HOME/Library/Logs/hintvim/app.log"
    ;;
  silent) ;;
  failure) exit 1 ;;
esac
SH
chmod +x "$fixture/stub/"*

fail() { echo "FAIL: $*"; exit 1; }
doctor() {
  status=0
  output=$(HOME="$fixture" PATH="$fixture/stub:/usr/bin:/bin" DOCTOR_SCENARIO="$1" \
    sh "$fixture/repo/bin/hintvim" doctor) || status=$?
}

echo 'old started accessibility trusted=true' >"$fixture/Library/Logs/hintvim/app.log"
doctor denied
[ "$status" = 1 ] || fail "revoked permission should fail"
echo "$output" | grep -q 'FAIL  accessibility: not allowed' || fail "revoked permission reported as allowed"
echo "$output" | grep -q 'hint targets:' && fail "targets checked without permission"

echo 'old started accessibility trusted=false' >"$fixture/Library/Logs/hintvim/app.log"
doctor allowed
[ "$status" = 0 ] || fail "newly granted permission should pass"
echo "$output" | grep -q 'ok    accessibility: allowed' || fail "new grant not recognized"
echo "$output" | grep -q 'ok    hint targets: 3 targets' || fail "fresh targets not recognized"

doctor silent
[ "$status" = 1 ] || fail "stale successful probe should not pass"
echo "$output" | grep -q 'FAIL  accessibility: could not verify' || fail "missing response not reported"

rm "$fixture/Library/Logs/hintvim/app.log"
doctor allowed
[ "$status" = 0 ] || fail "first probe without an existing log should pass"

doctor failure
[ "$status" = 1 ] || fail "failed URL dispatch should fail"
echo "$output" | grep -q 'FAIL  accessibility: could not verify' || fail "dispatch failure not reported"

echo 'doctor OK'
