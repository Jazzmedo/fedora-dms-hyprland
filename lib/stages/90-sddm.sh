# shellcheck shell=bash
# The Nothing login screen, and the switch from a TTY to a graphical boot.

stage_sddm() {

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

  # A Wayland greeter needs a compositor. The captured config named kwin_wayland,
  # which this install does not have; weston is what Fedora ships for the job.
  local compositor=""
  if ! have weston && ! have kwin_wayland; then
    info "The login screen needs a small compositor to draw on; installing weston"
    record_new_pkgs weston
    as_root dnf install -y weston >/dev/null 2>&1 || true
  fi
  if have weston;      then compositor="weston --shell=fullscreen-shell.so"
  elif have kwin_wayland; then compositor="kwin_wayland --no-lockscreen"
  fi

  if [[ -n $compositor ]]; then
    as_root tee /etc/sddm.conf.d/10-wayland.conf >/dev/null <<EOF
[General]
DisplayServer=wayland
GreeterEnvironment=QT_WAYLAND_SHELL_INTEGRATION=layer-shell,QT_QPA_PLATFORMTHEME=qt6ct

[Wayland]
CompositorCommand=$compositor
EOF
    record file /etc/sddm.conf.d/10-wayland.conf
    ok "The login screen will run in modern graphics mode"
  else
    warn "Falling back to the older graphics mode for the login screen"
    as_root rm -f /etc/sddm.conf.d/10-wayland.conf
  fi

  as_root tee /etc/sddm.conf.d/20-nothing.conf >/dev/null <<'EOF'
[Theme]
Current=nothing
CursorTheme=Afterglow-cursors
CursorSize=24
Font=Ndot 57

[General]
InputMethod=

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

  systemctl is-enabled sddm >/dev/null 2>&1 || record unit-system sddm
  as_root systemctl enable sddm
  # The target as it stands, so uninstall can put it back rather than guess.
  record target "$(systemctl get-default 2>/dev/null)"
  as_root systemctl set-default graphical.target
  ok "The computer will boot straight to the login screen"

  # Read back what SDDM will actually load, rather than trusting that the copy
  # and the config write both landed.
  local active
  active=$(sed -n 's/^Current=//p' /etc/sddm.conf.d/*.conf /etc/sddm.conf 2>/dev/null | tail -1)
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
