# shellcheck shell=bash
# The Nothing login screen, and the switch from a TTY to a graphical boot.

stage_sddm() {
  step "Login screen"

  local dest=/usr/share/sddm/themes/nothing
  if [[ -f $dest/Main.qml ]]; then
    skip "Nothing theme already installed"
  else
    as_root mkdir -p /usr/share/sddm/themes
    as_root cp -r "$REPO_DIR/assets/sddm/nothing" "$dest"
    ok "Nothing SDDM theme installed (MIT, Darkkal44)"
  fi

  # The greeter runs before any user session, so it needs its own copy of the
  # fonts rather than the ones in the user's home.
  as_root mkdir -p "$dest/font"
  as_root cp "$REPO_DIR/assets/fonts/nothing/Ndot57-Regular.otf" "$dest/font/" 2>/dev/null || true

  # A Wayland greeter needs a compositor. The captured config named kwin_wayland,
  # which this install does not have; weston is what Fedora ships for the job.
  local compositor=""
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
    ok "Wayland greeter via ${compositor%% *}"
  else
    warn "no Wayland compositor for the greeter; falling back to X11"
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
  ok "theme set to nothing"

  # Fedora's own /etc/sddm.conf, if present, overrides conf.d on some builds.
  [[ -f /etc/sddm.conf ]] && as_root mv /etc/sddm.conf /etc/sddm.conf.fedora-nothing.bak && \
    info "moved /etc/sddm.conf aside so conf.d wins"

  as_root systemctl enable sddm
  as_root systemctl set-default graphical.target
  ok "graphical boot enabled"
}
