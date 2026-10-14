# shellcheck shell=bash
# The Nothing login screen, and the switch from a TTY to a graphical boot.

# Enabling SDDM is not the same as making it the login screen. Whichever
# display manager owns /etc/systemd/system/display-manager.service is the one
# that starts, and `systemctl enable sddm` will not take that symlink from
# another unit: it leaves the existing one alone.
#
# The desktop shell'"'"'s own installer offers a greeter, dms-greeter, and its
# description says plainly that it replaces the current display manager. When
# that happens, the Nothing theme is installed, configured and never seen.
make_sddm_the_login_screen() {
  local current=""
  [[ -L /etc/systemd/system/display-manager.service ]] && \
    current=$(basename "$(readlink -f /etc/systemd/system/display-manager.service)")

  if [[ $current == sddm.service ]]; then
    skip "SDDM is already the login screen"
    return 0
  fi

  if [[ -n $current ]]; then
    warn "${current%.service} is currently the login screen; switching to SDDM"
    record dm "$current"
    as_root systemctl disable "$current" || \
      warn "could not switch ${current%.service} off; SDDM is being forced in anyway"
  fi

  systemctl is-enabled sddm >/dev/null 2>&1 || record unit-system sddm
  # --force is what replaces the symlink; without it this is a no-op whenever
  # anything else already claimed the name.
  as_root systemctl enable --force sddm \
    || soft_fail "Could not make SDDM the login screen" \
                 "systemctl refused to hand it display-manager.service." \
                 "sudo systemctl enable --force sddm"
  return 0
}

# A keyring nobody unlocks is a keyring you type a separate password into on
# every login. The greeter hands the login password to pam_gnome_keyring, and
# the session's gnome-keyring-daemon picks the unlocked keyring up from there.
# Fedora's sddm PAM ships the kwallet lines but not these, so they are added:
# after the first auth line that pulls in the system stack, and after the last
# session line. Both are `optional`, so a stack that grows later is unaffected.
configure_keyring_pam() {
  if ! rpm_has gnome-keyring-pam; then
    soft_fail "The keyring package did not install, so logins cannot unlock it" \
              "Saved passwords would ask for a separate unlock on every login." \
              "sudo dnf install gnome-keyring-pam && ./install.sh --only=sddm"
    return 0
  fi

  local stack file tmp
  for stack in sddm sddm-autologin sddm-greeter; do
    file=/etc/pam.d/$stack
    [[ -f $file ]] || continue
    if grep -q pam_gnome_keyring "$file"; then
      skip "The $stack login already unlocks the keyring"
      continue
    fi
    backup_path "$file"
    (( DRY_RUN )) && { info "Would make the $stack login unlock the keyring"; continue; }
    tmp=$(mktemp)
    awk '
      { lines[++n] = $0 }
      /^auth[ \t]/ && !done_auth && /(substack|include)/ { auth_at = n; done_auth = 1 }
      /^session[ \t]/ { last = n }
      END {
        for (i = 1; i <= n; i++) {
          print lines[i]
          if (i == auth_at) print "auth        optional       pam_gnome_keyring.so"
          if (i == last) print "session     optional       pam_gnome_keyring.so auto_start"
        }
        if (!done_auth) print "auth        optional       pam_gnome_keyring.so"
        if (!last) print "session     optional       pam_gnome_keyring.so auto_start"
      }
    ' "$file" > "$tmp"
    as_root cp "$tmp" "$file"
    rm -f "$tmp"
    record edited "$file"
    ok "The $stack login will unlock the keyring"
  done
  return 0
}

# Num Lock on the text consoles as well as the login screen. SDDM handles its
# own greeter with Numlock=on above; the consoles have no such setting, so a
# one-shot service does it once the terminals exist.
enable_console_numlock() {
  local unit=numlock-on.service
  local src="$REPO_DIR/config/system/systemd/$unit"
  [[ -f $src ]] || return 0

  if ! have setleds; then
    record_new_pkgs kbd
    as_root dnf install -y kbd >/dev/null 2>&1 || true
  fi
  have setleds || { warn "Num Lock cannot be set on the text consoles: setleds is not installed"; return 0; }

  as_root cp "$src" "/etc/systemd/system/$unit"
  record file "/etc/systemd/system/$unit"
  systemctl is-enabled "$unit" >/dev/null 2>&1 || record unit-system "$unit"
  as_root systemctl daemon-reload
  as_root systemctl enable --now "$unit" >/dev/null 2>&1 \
    && ok "Num Lock will be on at the login screen and on the text consoles" \
    || warn "Could not switch Num Lock on for the text consoles"
  return 0
}

# Which display server the greeter itself runs on.
#
# Wayland where the hardware can draw it, X11 in a virtual machine. There the
# graphics are software-rendered through llvmpipe, and a Qt greeter on a
# layer-shell compositor on top of that is the combination that hangs with a
# black screen and no way in.
configure_greeter_display_server() {
  if [[ ${GPU_VENDOR:-} == vm ]]; then
    info "This is a virtual machine, so the login screen uses the older graphics mode, which is reliable here"
    as_root rm -f /etc/sddm.conf.d/10-wayland.conf
    ensure_x11_greeter
    return 0
  fi

  # The captured config named kwin_wayland, which this install does not have;
  # weston is what Fedora ships for the job.
  if ! have weston && ! have kwin_wayland; then
    info "The login screen needs a small compositor to draw on; installing weston"
    record_new_pkgs weston
    as_root dnf install -y weston >/dev/null 2>&1 || true
  fi

  local compositor=""
  if have weston;         then compositor="weston --shell=fullscreen-shell.so"
  elif have kwin_wayland; then compositor="kwin_wayland --no-lockscreen"
  fi

  if [[ -z $compositor ]]; then
    warn "No compositor for the login screen, so it falls back to the older graphics mode"
    as_root rm -f /etc/sddm.conf.d/10-wayland.conf
    ensure_x11_greeter
    return 0
  fi

  as_root tee /etc/sddm.conf.d/10-wayland.conf >/dev/null <<EOF
[General]
DisplayServer=wayland
GreeterEnvironment=QT_WAYLAND_SHELL_INTEGRATION=layer-shell,QT_QPA_PLATFORMTHEME=qt6ct

[Wayland]
CompositorCommand=$compositor
EOF
  record file /etc/sddm.conf.d/10-wayland.conf
  ok "The login screen will run in modern graphics mode"
  return 0
}

# X11 mode needs an X server, which a @core Fedora does not necessarily have.
# Without it SDDM starts, finds nothing to draw on, and retries forever.
ensure_x11_greeter() {
  have Xorg && return 0
  record_new_pkgs xorg-x11-server-Xorg
  as_root dnf install -y xorg-x11-server-Xorg >/dev/null 2>&1 || true
  have Xorg || soft_fail "The login screen has no display server to draw on" \
      "Neither a Wayland compositor nor Xorg is installed." \
      "sudo dnf install xorg-x11-server-Xorg"
  return 0
}

# Which entry the greeter highlights before you have ever logged in: the full
# RGB session leads when the colour fix is installed. After the first manual
# login SDDM remembers the session you picked, which is the way it should be.
install_default_session() {
  local session=hyprland
  [[ -f /usr/share/wayland-sessions/hyprland-rgb-full.desktop ]] && session=hyprland-rgb-full
  local conf=/etc/sddm.conf.d/zz-fedora-nothing-session.conf
  as_root tee "$conf" >/dev/null <<EOF
[General]
Session=$session
EOF
  record file "$conf"
  ok "The login screen starts with \"$session\" selected"
}

stage_sddm() {

  install_default_session

  local dest=/usr/share/sddm/themes/nothing

  # Copied every run rather than skipped when Main.qml exists, so an edit to
  # the theme in this repo actually reaches an installed machine.
  as_root mkdir -p /usr/share/sddm/themes /etc/sddm.conf.d
  as_root rm -rf "$dest"
  as_root cp -r "$REPO_DIR/assets/sddm/nothing" "$dest"
  record file "$dest"
  # SDDM reads theme.conf.user as an override on top of theme.conf, so shipping
  # both means the override silently wins over anything edited in the base.
  as_root rm -f "$dest/theme.conf.user"
  ok "Installed the Nothing login screen"

  # The theme carries its own NDot55 and NType82 and loads them with a
  # FontLoader, because the greeter runs before any user session and cannot
  # read fonts from a home directory.

  verify_sddm_theme

  configure_greeter_display_server

  as_root tee /etc/sddm.conf.d/20-nothing.conf >/dev/null <<'EOF'
[Theme]
Current=nothing
CursorTheme=Afterglow-cursors
CursorSize=24
Font=Ndot 57

[General]
InputMethod=
Numlock=on

[Users]
MaximumUid=60000
MinimumUid=1000
EOF
  record file /etc/sddm.conf.d/20-nothing.conf
  ok "The Nothing theme is now the login screen"

  # Fedora's own /etc/sddm.conf, if present, overrides conf.d on some builds.
  [[ -f /etc/sddm.conf ]] && as_root mv /etc/sddm.conf /etc/sddm.conf.fedora-nothing.bak && \
    record moved /etc/sddm.conf /etc/sddm.conf.fedora-nothing.bak && \
    info "Moved an old login screen config aside so these settings take effect"

  enable_console_numlock

  configure_keyring_pam

  make_sddm_the_login_screen
  # The target as it stands, so uninstall can put it back rather than guess.
  record target "$(systemctl get-default 2>/dev/null)"
  as_root systemctl set-default graphical.target
  ok "The computer will boot straight to the login screen"

  # Read back what SDDM will actually load, rather than trusting that the copy
  # and the config write both landed.
  local dm=""
  [[ -L /etc/systemd/system/display-manager.service ]] && \
    dm=$(basename "$(readlink -f /etc/systemd/system/display-manager.service)")
  if [[ $dm == sddm.service ]]; then
    ok "Confirmed: SDDM is the login screen this machine will start"
  else
    soft_fail "The login screen that will actually start is ${dm:-none}, not SDDM" \
              "Another display manager owns display-manager.service." \
              "sudo systemctl disable ${dm:-greetd} && sudo systemctl enable --force sddm"
  fi

  local active
  active=$(sddm_configured_theme)
  if [[ $active == nothing ]]; then
    ok "Confirmed: the login screen is set to the Nothing theme"
  else
    soft_fail "The login screen is set to \"${active:-nothing at all}\", not the Nothing theme" \
              "Another file in /etc/sddm.conf.d is overriding this one." \
              "grep -r Current= /etc/sddm.conf.d /etc/sddm.conf"
  fi
}

# A QML theme whose imports cannot be resolved does not fail loudly: SDDM logs
# the error and silently presents its own default greeter, which looks exactly
# like the theme never having been set. Every import in Main.qml is checked
# against what is installed, before the reboot rather than after it.
verify_sddm_theme() {
  # QtQuick.Window is folded into the QtQuick module in Qt 6 and has no
  # directory of its own, so QtQuick is what gets checked for it.
  local -A provider=(
    [Qt5Compat/GraphicalEffects]=qt6-qt5compat
    [Qt/labs/folderlistmodel]=qt6-qtdeclarative
    [QtQuick]=qt6-qtdeclarative
    [SddmComponents]=sddm
  )

  # Ask Qt where its QML modules live rather than guessing a libdir.
  local -a roots=()
  local q
  q=$(qtpaths6 --query QT_INSTALL_QML 2>/dev/null \
      || qmake6 -query QT_INSTALL_QML 2>/dev/null) && [[ -n $q ]] && roots+=("$q")
  roots+=(/usr/lib64/qt6/qml /usr/lib/qt6/qml)

  local module missing=()

  for module in "${!provider[@]}"; do
    local found=0 root
    for root in "${roots[@]}"; do
      [[ -d $root/$module ]] && { found=1; break; }
    done
    (( found )) || missing+=("$module (from ${provider[$module]})")
  done

  if (( ${#missing[@]} == 0 )); then
    ok "Everything the login screen needs to draw itself is installed"
    return 0
  fi

  local m
  for m in "${missing[@]}"; do
    soft_fail "The login screen needs $m, which is missing" \
               "Without it the screen cannot draw and Fedora shows its plain one instead." \
               "sudo dnf install ${provider[$m]}"
  done
  soft_fail "Until those are installed you will see Fedora's plain login screen" \
            "The Nothing theme is installed but cannot load." \
            "Install the packages listed above, then restart."
  return 0
}
