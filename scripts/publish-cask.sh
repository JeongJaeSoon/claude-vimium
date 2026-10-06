#!/bin/sh
set -eu

tag=${1:?usage: publish-cask.sh vX.Y.Z}
case $tag in v[0-9]*.[0-9]*.[0-9]*) ;; *) echo "invalid version tag: $tag" >&2; exit 2 ;; esac
version=${tag#v}
: "${APPLE_TEAM_ID:?missing APPLE_TEAM_ID}"
case $APPLE_TEAM_ID in *[!A-Z0-9]*) echo "invalid APPLE_TEAM_ID" >&2; exit 2 ;; esac
[ "${#APPLE_TEAM_ID}" -eq 10 ] || { echo "invalid APPLE_TEAM_ID" >&2; exit 2; }

root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
mount="$tmp/mount"
mounted=
cleanup() {
  if [ -n "$mounted" ]; then hdiutil detach "$mount" -quiet >/dev/null 2>&1 || true; fi
  rm -rf "$tmp"
}
trap cleanup EXIT HUP INT TERM

dmg=${HINTVIM_DMG:-$tmp/hintvim.dmg}
if [ -z "${HINTVIM_DMG:-}" ]; then
  curl --fail --location --silent --show-error \
    "https://github.com/JeongJaeSoon/hintvim/releases/download/$tag/hintvim-$version-macos-universal.dmg" \
    --output "$dmg"
fi

requirement="anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = \"$APPLE_TEAM_ID\""
codesign --verify --strict --verbose=2 -R="$requirement" "$dmg"
xcrun stapler validate "$dmg"
mkdir "$mount"
hdiutil attach "$dmg" -quiet -readonly -nobrowse -mountpoint "$mount"
mounted=1
app="$mount/Hintvim.app"
[ -d "$app" ] || { echo "Hintvim.app missing from DMG" >&2; exit 1; }
codesign --verify --deep --strict --verbose=2 -R="$requirement and identifier \"io.github.jeongjaesoon.hintvim\"" "$app"
xcrun stapler validate "$app"
[ "$("$app/Contents/MacOS/Hintvim" --version)" = "hintvim $version" ] || {
  echo "app version does not match $version" >&2
  exit 1
}
[ -x "$mount/bin/hintvim" ] || { echo "bin/hintvim missing from DMG" >&2; exit 1; }
[ -f "$mount/completions/hintvim.bash" ] || { echo "completions missing from DMG" >&2; exit 1; }
[ -f "$mount/completions/_hintvim" ] || { echo "zsh completion missing from DMG" >&2; exit 1; }
[ -f "$mount/completions/hintvim.fish" ] || { echo "fish completion missing from DMG" >&2; exit 1; }
hdiutil detach "$mount" -quiet
mounted=

sha=$(shasum -a 256 "$dmg" | awk '{print $1}')
sed -e "s/version \"[^\"]*\"/version \"$version\"/" \
  -e "s/sha256 \"[0-9a-f]*\"/sha256 \"$sha\"/" \
  "$root/packaging/hintvim-cask.rb" >"$tmp/hintvim.rb"

if [ -n "${DRY_RUN:-}" ]; then
  cat "$tmp/hintvim.rb"
  exit 0
fi

: "${GH_TOKEN:?missing GH_TOKEN}"
tap=${HINTVIM_TAP_REPOSITORY:-JeongJaeSoon/homebrew-tap}
path=Casks/hintvim.rb
if old=$(gh api "repos/$tap/contents/$path" --jq .sha 2>/dev/null); then
  :
else
  old=
fi
if [ -n "$old" ]; then
  current=$(gh api "repos/$tap/contents/$path" --jq .content | base64 --decode)
  current_version=$(printf '%s\n' "$current" | sed -n 's/.*version "\([^"]*\)".*/\1/p')
  newer=$(awk -v old="$current_version" -v new="$version" 'BEGIN {
    split(old, a, "."); split(new, b, ".")
    for (i = 1; i <= 3; i++) {
      if ((a[i] + 0) > (b[i] + 0)) { print "yes"; exit }
      if ((a[i] + 0) < (b[i] + 0)) exit
    }
  }')
  [ "$newer" != yes ] || {
    echo "refusing to replace newer cask version $current_version with $version" >&2
    exit 1
  }
fi

content=$(base64 <"$tmp/hintvim.rb" | tr -d '\n')
set -- api -X PUT "repos/$tap/contents/$path" \
  -f "message=hintvim $version" -f "content=$content"
if [ -n "$old" ]; then set -- "$@" -f "sha=$old"; fi
gh "$@" --jq .commit.html_url
