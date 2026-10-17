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

# The outcome checks are defined once, in lib/verify.sh, and used both here and
# at the end of an install.
DOCTOR_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/verify.sh
[[ -r $DOCTOR_DIR/lib/verify.sh ]] && source "$DOCTOR_DIR/lib/verify.sh"
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
dmsv=$(dms --version 2>/dev/null | head -1); [[ -n $dmsv ]] || dmsv=$(dms version 2>/dev/null | head -1)
kv "dms version"        "$dmsv"
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

# From 1.6 the QML is compiled into the binary and ~/.config/quickshell/dms is
# no longer auto-discovered. Before that it was fetched separately and could be
# absent on a machine where `dms --version` works perfectly.
root="$HOME/.config/quickshell/dms"
entry=""
for c in "$root/quickshell/shell.qml" "$root/shell.qml"; do
  [[ -f $c ]] && { entry=$c; break; }
done
if [[ $dmsv =~ ([0-9]+\.[0-9]+\.[0-9]+) ]] && printf '1.6.0\n%s\n' "${BASH_REMATCH[1]}" | sort -V -C; then
  kv "shell QML" "carried inside the dms binary"
  [[ -n $entry ]] && kv "stale checkout" "${root/#$HOME/\~} is present but ignored"
elif [[ -n $entry ]]; then
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
# 1.6 keeps only non-default values in settings.json and moved machine-specific
# state to session.json, so a file written for 1.5 may be half-ignored.
kv "session.json" "$([[ -f $HOME/.config/DankMaterialShell/session.json ]] && echo present || echo 'absent (pre-1.6 layout)')"

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

# The daemons a desktop environment would have started, which the shell's
# widgets depend on quietly: no upower means no battery widget, no
# power-profiles-daemon means no power-profile OSD, no secret service means
# saved passwords go nowhere.
sec "desktop services"
kv "upower"        "$(systemctl is-active upower 2>/dev/null || echo INACTIVE — battery widget is dead)"
kv "power-profiles" "$(systemctl is-active power-profiles-daemon 2>/dev/null || echo INACTIVE — power OSD is dead)"
kv "firewalld"     "$(systemctl is-active firewalld 2>/dev/null || echo INACTIVE)"
kv "secret service" "$(busctl --user list 2>/dev/null | grep -q org.freedesktop.secrets && echo present || echo MISSING — saved passwords have nowhere to go)"
kv "keyring PAM"   "$(grep -q pam_gnome_keyring /etc/pam.d/sddm 2>/dev/null && echo unlocks at login || echo 'not wired into the login screen')"
kv "hyprlock PAM"  "$([[ -f /etc/pam.d/hyprlock ]] && echo present || echo 'MISSING — the lock screen may not accept the password')"
kv "kdeconnect daemon" "$(systemctl --user is-enabled dms-kdeconnect.service >/dev/null 2>&1 && echo enabled || echo 'not enabled — your phone will not connect')"
kv "user dirs"     "$([[ -f $HOME/.config/user-dirs.dirs ]] && echo present || echo MISSING — no Documents/Downloads)"
# The optional pieces report only when installed, so a machine that declined
# printing does not show red for it.
rpm -q cups >/dev/null 2>&1 && kv "cups" "$(systemctl is-active cups 2>/dev/null || echo INACTIVE)"
rpm -q fwupd >/dev/null 2>&1 && kv "fwupd timer" "$(systemctl is-active fwupd-refresh.timer 2>/dev/null || echo INACTIVE)"

sec "shell"
login=$(getent passwd "$USER" | cut -d: -f7) || login=""
zsh=$(command -v zsh 2>/dev/null)
if [[ -n $zsh && $login == "$zsh" ]]; then
  kv "login shell" "$login"
else
  printf '  %-26s %s%s%s\n' "login shell" "$C" "${login:-unknown} — not zsh" "$O"
  [[ -z $zsh ]] && printf '  %-26s %sNOT INSTALLED%s\n' "zsh" "$C" "$O"
fi
# chsh refuses a shell that is not listed here, and says so quietly.
kv "zsh in /etc/shells" "$( [[ -n $zsh ]] && grep -qx "$zsh" /etc/shells 2>/dev/null && echo yes || echo NO )"
kv "oh-my-zsh"   "$([[ -d $HOME/.oh-my-zsh ]] && echo present || echo MISSING)"
kv "starship"    "$(command -v starship >/dev/null 2>&1 && echo present || echo MISSING)"
kv ".zshrc"      "$([[ -f $HOME/.zshrc ]] && echo "$(wc -l < "$HOME/.zshrc") lines" || echo MISSING)"
kv "zshrc.d"     "$(ls "${XDG_CONFIG_HOME:-$HOME/.config}/zsh/zshrc.d"/*.zsh 2>/dev/null | wc -l) fragment(s)"

sec "login screen"
kv "configured theme" "$(sddm_configured_theme)"
kv "theme installed"  "$([[ -f /usr/share/sddm/themes/nothing/Main.qml ]] && echo yes || echo NO)"
kv "starts at boot"   "$(active_display_manager || echo "none enabled")"
kv "default target"   "$(systemctl get-default 2>/dev/null)"
# A QML import the greeter cannot resolve makes SDDM fall back to its own
# default silently, which looks exactly like the theme never being set.
qmlroot=$(qtpaths6 --query QT_INSTALL_QML 2>/dev/null || qmake6 -query QT_INSTALL_QML 2>/dev/null)
for m in Qt5Compat/GraphicalEffects Qt/labs/folderlistmodel QtQuick SddmComponents; do
  hit=""
  for r in "$qmlroot" /usr/lib64/qt6/qml /usr/lib/qt6/qml; do
    [[ -n $r && -d $r/$m ]] && { hit=$r; break; }
  done
  if [[ -n $hit ]]; then kv "imports $m" "present"
  else printf '  %-26s %sMISSING — greeter falls back to default%s\n' "imports $m" "$C" "$O"; fi
done

sec "wallpaper follows theme"
kv "watcher" "$(systemctl --user is-active dms-theme-wallpapers.path 2>/dev/null)"
kv "last theme applied" "$(cat "${XDG_STATE_HOME:-$HOME/.local/state}/dms-theme-wallpapers/last-applied" 2>/dev/null)"
journalctl --user -u dms-theme-wallpapers.service -n 5 --no-pager -o cat 2>/dev/null | sed 's/^/  /'

sec "next"
cat <<'TXT'
  If the shell is not running, start it in the foreground so its errors land
  in this terminal instead of the journal:

      dms kill 2>/dev/null; dms run

  The first red line it prints is the cause. Send that line and everything
  above it.
TXT
