#!/usr/bin/env bash
# Why is the shell not on screen?
#
# `dms restart` reporting "daemon started" only means the supervisor process
# forked. The bar, the keybind overlay and the theme sync all live in the
# quickshell process it launches, and that process can die a second later
# without the supervisor saying so. This collects the evidence that separates
# the three usual causes: quickshell missing or too old, a QML error in the
# shell or in a plugin, and a session the shell cannot attach to.
#
# Run it inside the Hyprland session, in a terminal:  ./doctor.sh
# It writes nothing and changes nothing.

set -uo pipefail
C=$'\033[1;31m'; B=$'\033[1m'; D=$'\033[2m'; O=$'\033[0m'
sec() { printf '\n%s── %s %s%s\n' "$C" "$1" "$(printf '─%.0s' $(seq 1 $(( 60 - ${#1} ))))" "$O"; }
kv()  { printf '  %-26s %s\n' "$1" "${2:-—}"; }

sec "session"
kv "compositor"        "$(hyprctl version 2>/dev/null | head -1)"
kv "WAYLAND_DISPLAY"   "${WAYLAND_DISPLAY:-NOT SET — not inside a Wayland session}"
kv "XDG_RUNTIME_DIR"   "${XDG_RUNTIME_DIR:-NOT SET}"
kv "XDG_CURRENT_DESKTOP" "${XDG_CURRENT_DESKTOP:-}"
kv "QT_QPA_PLATFORMTHEME" "${QT_QPA_PLATFORMTHEME:-}"

sec "binaries"
for b in dms quickshell qs matugen; do
  p=$(command -v "$b" 2>/dev/null)
  kv "$b" "${p:-NOT ON PATH}"
done
kv "dms version"        "$(dms --version 2>/dev/null | head -1)"
# The single most common cause: a distro quickshell older than the QML the
# shell is written against. DMS ships its own build when none is present, and
# skips doing so when an older rpm already is.
kv "quickshell version" "$(quickshell --version 2>/dev/null | head -1 || qs --version 2>/dev/null | head -1)"
kv "quickshell rpm"     "$(rpm -q quickshell 2>/dev/null || echo 'not from rpm')"
# Below 0.3.1 the QML parser rejects `//@ pragma AppId` and the shell exits 255
# before it draws anything, while the supervisor reports a healthy start.
qv=$(quickshell --version 2>/dev/null || qs --version 2>/dev/null)
if [[ $qv =~ ([0-9]+\.[0-9]+\.[0-9]+) ]]; then
  if printf '0.3.1\n%s\n' "${BASH_REMATCH[1]}" | sort -V -C; then
    kv "quickshell verdict" "new enough"
  else
    printf '  %-26s %sTOO OLD for this shell — remove the rpm and re-run the DMS installer%s\n' \
      "quickshell verdict" "$C" "$O"
  fi
fi

sec "is the shell actually up"
# The supervisor forking is not the same as the bar rendering. The only honest
# test is whether the shell answers over its own IPC socket.
kv "dms processes" "$(pgrep -cx dms 2>/dev/null || echo 0)"
if dms ipc call theme list >/dev/null 2>&1; then
  printf '  %sthe shell is running and answering IPC%s\n' "$B" "$O"
else
  printf '  %sthe shell is NOT answering IPC — this is the fault%s\n' "$C" "$O"
fi

# What the supervisor launches. Fetched separately from the binary, so it can
# be absent on a machine where `dms --version` works perfectly.
root="$HOME/.config/quickshell/dms"
entry=""
for c in "$root/quickshell/shell.qml" "$root/shell.qml"; do
  [[ -f $c ]] && { entry=$c; break; }
done
if [[ -n $entry ]]; then
  kv "shell QML" "${entry/#$HOME/\~}"
else
  printf '  %-26s %sMISSING from %s%s\n' "shell QML" "$C" "${root/#$HOME/\~}" "$O"
  printf '  %sthe binary installed but the shell it runs did not%s\n' "$C" "$O"
fi

sec "dms.service"
systemctl --user status dms.service --no-pager -n 0 2>&1 | sed -n '1,6p' | sed 's/^/  /'
kv "ExecStart" "$(systemctl --user show dms.service -p ExecStart --value 2>/dev/null)"

sec "the actual error"
printf '  %sthe last 40 lines the shell printed before it stopped:%s\n\n' "$D" "$O"
journalctl --user -u dms.service -n 40 --no-pager 2>/dev/null | sed 's/^/  /' \
  || printf '  no journal for dms.service\n'

sec "config"
s="$HOME/.config/DankMaterialShell/settings.json"
if [[ -f $s ]]; then
  python3 - "$s" <<'PY' 2>&1 | sed 's/^/  /'
import json, os, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception as e:
    sys.exit(f"settings.json is NOT VALID JSON: {e}")
print(f"theme            {d.get('currentThemeCategory')} / {d.get('currentThemeName')}")
f = d.get("customThemeFile", "")
print(f"custom theme     {f}")
print(f"                 {'exists' if f and os.path.exists(f) else 'MISSING — the shell cannot resolve its palette'}")
print(f"font             {d.get('fontFamily')} / {d.get('monoFontFamily')}")
print(f"matugen monitor  {d.get('matugenTargetMonitor')}")
for bar in d.get("barConfigs") or []:
    print(f"bar monitors     {bar.get('monitors')}")
PY
else
  printf '  settings.json missing\n'
fi

sec "plugins"
p="$HOME/.config/DankMaterialShell/plugins"
if [[ -d $p ]]; then
  for l in "$p"/*; do
    [[ -e $l || -L $l ]] || continue
    n=$(basename "$l"); [[ $n == .* || $n == *.meta ]] && continue
    if [[ -e $l ]]; then
      kv "$n" "ok$([[ -L $l ]] && printf ' → %s' "$(readlink "$l")")"
    else
      printf '  %-26s %sBROKEN SYMLINK → %s%s\n' "$n" "$C" "$(readlink "$l")" "$O"
    fi
  done
  # A plugin enabled in settings but absent on disk is a QML import error at
  # startup, which takes the whole shell down rather than just that widget.
  ps="$HOME/.config/DankMaterialShell/plugin_settings.json"
  [[ -f $ps ]] && python3 - "$ps" "$p" <<'PY' 2>&1 | sed 's/^/  /'
import json, os, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception as e:
    sys.exit(f"plugin_settings.json is NOT VALID JSON: {e}")
missing = [k for k in d if not os.path.exists(os.path.join(sys.argv[2], k))]
print(f"enabled: {len(d)}   without a directory: {missing or 'none'}")
PY
else
  printf '  no plugins directory\n'
fi

sec "theming"
kg="$HOME/.config/kdeglobals"
kv "kdeglobals colour blocks" "$(grep -c '^\[Colors' "$kg" 2>/dev/null || echo 0)  (0 means Dolphin paints Breeze light)"
kv "ColorScheme" "$(sed -n 's/^ColorScheme=//p' "$kg" 2>/dev/null | head -1)"
kv "qt6ct palette" "$([[ -f $HOME/.config/qt6ct/colors/matugen.conf ]] && echo present || echo MISSING)"

sec "next"
cat <<'TXT'
  If the shell is not running, start it in the foreground so its errors land
  in this terminal instead of the journal:

      dms kill 2>/dev/null; dms run

  The first red line it prints is the cause. Send that line and everything
  above it.
TXT
