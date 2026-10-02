#!/bin/sh
# Commits packaging/claude-vimium.rb, with the released tarball's sha256, to the
# Homebrew tap. The tarball must be downloadable, so run it once the repository
# is public. Needs gh signed in with write access to the tap.
#
#   sh scripts/publish-tap.sh v0.3.0
#   DRY_RUN=1 sh scripts/publish-tap.sh v0.3.0    # print the formula instead
set -eu

tag=${1:?usage: publish-tap.sh vX.Y.Z}
repo=JeongJaeSoon/claude-vimium
tap=JeongJaeSoon/homebrew-tap
path=Formula/claude-vimium.rb
formula="$(cd "$(dirname "$0")/.." && pwd)/packaging/claude-vimium.rb"

grep -qF "/tags/$tag.tar.gz\"" "$formula" || { echo "$formula does not point at $tag" >&2; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
tarball=${CLAUDE_VIMIUM_TARBALL:-}
if [ -z "$tarball" ]; then
  tarball="$tmp/src.tar.gz"
  curl -fsSL -o "$tarball" "https://github.com/$repo/archive/refs/tags/$tag.tar.gz"
fi
sha=$(shasum -a 256 "$tarball" | cut -d' ' -f1)
sed "s#^  sha256 .*#  sha256 \"$sha\"#" "$formula" >"$tmp/claude-vimium.rb"

if [ -n "${DRY_RUN:-}" ]; then
  cat "$tmp/claude-vimium.rb"
  exit 0
fi

old=$(gh api "repos/$tap/contents/$path" --jq .sha 2>/dev/null || true)
gh api -X PUT "repos/$tap/contents/$path" \
  -f message="claude-vimium ${tag#v}" \
  -f content="$(base64 <"$tmp/claude-vimium.rb" | tr -d '\n')" \
  ${old:+-f sha="$old"} \
  --jq .commit.html_url
