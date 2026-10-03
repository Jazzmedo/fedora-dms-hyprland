#!/usr/bin/env bash
# matugen post_hook: rebuild the DMS-coloured userstyles after a theme change.
# Returns immediately so matugen is never held up; the build runs detached.
# Bursts of theme changes collapse into one more build via the .dirty flag.
set -u

here="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
cache="$HOME/.cache/matugenfox"
build="$here/build.mjs"
node="$(ls -d "$HOME"/.nvm/versions/node/*/bin/node 2>/dev/null | sort -V | tail -n 1)"
[ -x "$node" ] || node="$(command -v node || true)"
[ -n "$node" ] && [ -f "$build" ] || exit 0

mkdir -p "$cache"
touch "$cache/userstyles.dirty"

setsid -f bash -c '
  cache=$1 node=$2 build=$3
  log="$cache/build.log"
  while :; do
    {
      flock -n 9 || exit 0
      while [ -e "$cache/userstyles.dirty" ]; do
        rm -f "$cache/userstyles.dirty"
        [ -f "$log" ] && [ "$(stat -c %s "$log")" -gt 1048576 ] && mv -f "$log" "$log.1"
        nice -n 10 "$node" "$build" >>"$log" 2>&1
      done
    } 9>"$cache/userstyles.lock"
    # A change may have landed after the last check but before the lock was released.
    [ -e "$cache/userstyles.dirty" ] || exit 0
  done
' _ "$cache" "$node" "$build" </dev/null >/dev/null 2>&1
