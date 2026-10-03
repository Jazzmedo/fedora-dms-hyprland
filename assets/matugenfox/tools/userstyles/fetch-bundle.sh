#!/usr/bin/env bash
# Fetch the Catppuccin userstyles bundle and std library into the build cache.
# Files are checked against SHA256SUMS; pass --update to accept new upstream
# versions and record their sums.
set -euo pipefail

dest="${MATUGENFOX_BUNDLE:-$HOME/.cache/matugenfox/catppuccin}"
sums="$(cd "$(dirname "$0")" && pwd)/SHA256SUMS"
update=false
[ "${1:-}" = "--update" ] && update=true

mkdir -p "$dest"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

curl -fsSL --retry 3 -o "$tmp/import.json" \
  https://github.com/catppuccin/userstyles/releases/download/all-userstyles-export/import.json
curl -fsSL --retry 3 -o "$tmp/std-v1.less" \
  https://userstyles.catppuccin.com/lib/std/v1.less

if $update; then
  (cd "$tmp" && sha256sum import.json std-v1.less) > "$sums"
  echo "recorded new sums in $sums"
elif ! (cd "$tmp" && sha256sum --quiet -c "$sums"); then
  echo "upstream changed; review it, then rerun with --update" >&2
  exit 1
fi

mv -f "$tmp/import.json" "$tmp/std-v1.less" "$dest/"
cp -f "$sums" "$dest/SHA256SUMS"
echo "bundle ready in $dest"
