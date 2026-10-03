#!/usr/bin/env bash
# Check Catppuccin for new userstyles and rebuild when they changed.
#
# The native host starts this each time the browser connects, detached from
# the messaging channel. Checks are at most one per MATUGENFOX_UPDATE_INTERVAL
# seconds, and a bundle that fails to download, parse or build is thrown away
# so the styles already in use stay in place.
set -u

here="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
cache="$HOME/.cache/matugenfox"
bundle="$cache/catppuccin"
interval="${MATUGENFOX_UPDATE_INTERVAL:-600}"
import_url="https://github.com/catppuccin/userstyles/releases/download/all-userstyles-export/import.json"
std_url="https://userstyles.catppuccin.com/lib/std/v1.less"

mkdir -p "$bundle"
exec 9>"$cache/update.lock"
flock -n 9 || exit 0
exec >>"$cache/build.log" 2>&1

say() { printf '[%s] update: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"; }

stamp="$cache/bundle-checked"
if [ -f "$stamp" ] && [ $(( $(date +%s) - $(stat -c %Y "$stamp") )) -lt "$interval" ]; then
  exit 0
fi

node="$(ls -d "$HOME"/.nvm/versions/node/*/bin/node 2>/dev/null | sort -V | tail -n 1)"
[ -x "$node" ] || node="$(command -v node || true)"
[ -n "$node" ] || { say "node is not installed"; exit 0; }

tmp="$(mktemp -d "$cache/.bundle-XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

if ! curl -fsSL --retry 2 --max-time 120 -o "$tmp/import.json" "$import_url" ||
   ! curl -fsSL --retry 2 --max-time 60 -o "$tmp/std-v1.less" "$std_url"; then
  say "could not reach Catppuccin; keeping the current styles"
  exit 0
fi
touch "$stamp"

if ! "$node" -e '
  const b = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
  process.exit(Array.isArray(b) && b.filter(e => e && typeof e.sourceCode === "string").length >= 50 ? 0 : 1);
' "$tmp/import.json" || ! grep -q '@catppuccin' "$tmp/std-v1.less"; then
  say "the downloaded bundle looks damaged; keeping the current styles"
  exit 0
fi

if cmp -s "$tmp/import.json" "$bundle/import.json" &&
   cmp -s "$tmp/std-v1.less" "$bundle/std-v1.less" &&
   [ -e "$cache/userstyles/current/index.json" ]; then
  exit 0
fi

say "new Catppuccin styles; rebuilding"
{
  # The theme-change hook builds under the same lock.
  if ! flock -w 300 8; then
    say "another build is still running; will check again next launch"
    rm -f "$stamp"
    exit 0
  fi
  if nice -n 10 "$node" "$here/build.mjs" --bundle "$tmp"; then
    mv -f "$tmp/import.json" "$tmp/std-v1.less" "$bundle/"
    (cd "$bundle" && sha256sum import.json std-v1.less > SHA256SUMS)
  else
    say "the new bundle did not build; kept the previous styles"
  fi
} 8>"$cache/userstyles.lock"

# A theme change that arrived while this held the lock was skipped by the hook.
[ -e "$cache/userstyles.dirty" ] && "$here/matugen-hook.sh"
exit 0
