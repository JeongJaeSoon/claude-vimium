#!/bin/sh
# Commits packaging/hintvim.rb, with the released tarball's sha256, to the
# Homebrew tap. The tarball must be downloadable, so run it once the repository
# is public. Needs gh signed in with write access to the tap.
#
#   sh scripts/publish-tap.sh v0.3.0
#   DRY_RUN=1 sh scripts/publish-tap.sh v0.3.0    # print the formula instead
set -eu

tag=${1:?usage: publish-tap.sh vX.Y.Z [source|signed]}
mode=${2:-source}
repo=JeongJaeSoon/hintvim
tap=JeongJaeSoon/homebrew-tap
path=Formula/hintvim.rb
root="$(cd "$(dirname "$0")/.." && pwd)"
case $mode in
  source)
    formula="$root/packaging/hintvim.rb"
    archive_url="https://github.com/$repo/archive/refs/tags/$tag.tar.gz"
    ;;
  signed)
    : "${APPLE_TEAM_ID:?APPLE_TEAM_ID is required for signed publication}"
    case $APPLE_TEAM_ID in *[!A-Z0-9]* | '') echo 'Invalid APPLE_TEAM_ID' >&2; exit 1 ;; esac
    formula="$root/packaging/hintvim-signed.rb"
    archive_url="https://github.com/$repo/releases/download/$tag/hintvim-${tag#v}-macos-universal.tar.gz"
    ;;
  *) echo 'Expected source or signed publication mode' >&2; exit 1 ;;
esac

grep -qF "url \"$archive_url\"" "$formula" || { echo "$formula does not point at $tag" >&2; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
tarball=${HINTVIM_TARBALL:-}
if [ -z "$tarball" ]; then
  tarball="$tmp/src.tar.gz"
  curl -fsSL -o "$tarball" "$archive_url"
fi
if [ "$mode" = signed ]; then
  mkdir "$tmp/verify"
  tar -xzf "$tarball" -C "$tmp/verify"
  app="$tmp/verify/Hintvim.app"
  requirement="anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = \"$APPLE_TEAM_ID\" and identifier \"io.github.jeongjaesoon.hintvim\""
  codesign --verify --strict -R="$requirement" "$app"
  xcrun stapler validate "$app"
  "$app/Contents/MacOS/Hintvim" --version | grep -qx "hintvim ${tag#v}"
fi
sha=$(shasum -a 256 "$tarball" | cut -d' ' -f1)
sed "s#^  sha256 .*#  sha256 \"$sha\"#" "$formula" >"$tmp/hintvim.rb"
if [ "$mode" = signed ]; then
  sed "s/@SIGNING_TEAM_ID@/$APPLE_TEAM_ID/g" "$tmp/hintvim.rb" >"$tmp/signed.rb"
  mv "$tmp/signed.rb" "$tmp/hintvim.rb"
fi

if [ -n "${DRY_RUN:-}" ]; then
  cat "$tmp/hintvim.rb"
  exit 0
fi

old=$(gh api "repos/$tap/contents/$path" --jq .sha 2>/dev/null || true)
if [ "$mode" = source ] && [ -n "$old" ]; then
  current=$(gh api "repos/$tap/contents/$path" --jq .content)
  if printf '%s' "$current" | base64 --decode | grep -q '/releases/download/'; then
    echo 'Refusing to replace a signed formula with a source-built app' >&2
    exit 1
  fi
fi
gh api -X PUT "repos/$tap/contents/$path" \
  -f message="hintvim ${tag#v}" \
  -f content="$(base64 <"$tmp/hintvim.rb" | tr -d '\n')" \
  ${old:+-f sha="$old"} \
  --jq .commit.html_url
