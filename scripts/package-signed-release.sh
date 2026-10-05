#!/bin/sh
# Builds, signs, notarizes, staples, and packages the macOS release artifact.
set -eu

version=${1:?usage: package-signed-release.sh VERSION [OUTPUT_DIR]}
output_dir=${2:-dist}

: "${APPLE_SIGNING_CERTIFICATE_P12_BASE64:?missing APPLE_SIGNING_CERTIFICATE_P12_BASE64}"
: "${APPLE_SIGNING_CERTIFICATE_PASSWORD:?missing APPLE_SIGNING_CERTIFICATE_PASSWORD}"
: "${APPLE_SIGNING_IDENTITY:?missing APPLE_SIGNING_IDENTITY}"
: "${APPLE_TEAM_ID:?missing APPLE_TEAM_ID}"
: "${APPLE_NOTARIZATION_APPLE_ID:?missing APPLE_NOTARIZATION_APPLE_ID}"
: "${APPLE_NOTARIZATION_APP_PASSWORD:?missing APPLE_NOTARIZATION_APP_PASSWORD}"

case $version in v*) version=${version#v} ;; esac

root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
keychain="$tmp/signing.keychain-db"
keychain_password=$(uuidgen)

cleanup() {
  security delete-keychain "$keychain" >/dev/null 2>&1 || true
  rm -rf "$tmp"
}
trap cleanup EXIT HUP INT TERM

printf '%s' "$APPLE_SIGNING_CERTIFICATE_P12_BASE64" | /usr/bin/base64 -D >"$tmp/certificate.p12"
security create-keychain -p "$keychain_password" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"
security import "$tmp/certificate.p12" -k "$keychain" \
  -P "$APPLE_SIGNING_CERTIFICATE_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security
security set-key-partition-list -S apple-tool:,apple:,codesign: \
  -s -k "$keychain_password" "$keychain" >/dev/null

identities=$(security find-identity -v -p codesigning "$keychain")
printf '%s\n' "$identities" | grep -Fq "\"$APPLE_SIGNING_IDENTITY\"" || {
  echo "signing identity not found in imported certificate: $APPLE_SIGNING_IDENTITY" >&2
  exit 1
}
case $APPLE_SIGNING_IDENTITY in
  "Developer ID Application: "*" ($APPLE_TEAM_ID)") ;;
  *) echo "signing identity is not a Developer ID Application identity for team $APPLE_TEAM_ID" >&2; exit 1 ;;
esac

cd "$root"
make app VERSION="$version"
app=build/Hintvim.app
lipo -archs "$app/Contents/MacOS/Hintvim" | grep -q 'arm64 x86_64\|x86_64 arm64'
test "$("$app/Contents/MacOS/Hintvim" --version)" = "hintvim $version"
codesign --force --options runtime --timestamp --sign "$APPLE_SIGNING_IDENTITY" \
  --keychain "$keychain" "$app"
requirement="anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = \"$APPLE_TEAM_ID\" and identifier \"io.github.jeongjaesoon.hintvim\""
codesign --verify --deep --strict --verbose=2 -R="$requirement" "$app"
team=$(codesign -dv --verbose=4 "$app" 2>&1 | sed -n 's/^TeamIdentifier=//p')
[ "$team" = "$APPLE_TEAM_ID" ] || {
  echo "signed app team mismatch: expected $APPLE_TEAM_ID, got ${team:-none}" >&2
  exit 1
}

ditto -c -k --keepParent "$app" "$tmp/Hintvim-notarization.zip"
xcrun notarytool submit "$tmp/Hintvim-notarization.zip" --wait --output-format json \
  --apple-id "$APPLE_NOTARIZATION_APPLE_ID" --team-id "$APPLE_TEAM_ID" \
  --password "$APPLE_NOTARIZATION_APP_PASSWORD" >"$tmp/notarization.json"
jq -e '.status == "Accepted"' "$tmp/notarization.json" >/dev/null
xcrun stapler staple "$app"
xcrun stapler validate "$app"

stage="$tmp/package"
mkdir -p "$stage/bin" "$stage/completions" "$output_dir"
ditto "$app" "$stage/Hintvim.app"
cp bin/hintvim "$stage/bin/hintvim"
cp completions/* "$stage/completions/"
cp LICENSE "$stage/LICENSE"

artifact="$output_dir/hintvim-$version-macos-universal.tar.gz"
COPYFILE_DISABLE=1 tar -C "$stage" -czf "$artifact" Hintvim.app bin/hintvim completions LICENSE
echo "$artifact"
