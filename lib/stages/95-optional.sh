# shellcheck shell=bash
# Optional services. Each one fails soft: an unreachable third-party repo must
# not take the rest of the install down.

stage_optional() {
  local any=0
  for c in tailscale warp niri splash; do is_selected "$c" && any=1; done
  (( any )) || { skip "No extras were chosen"; return 0; }


  if is_selected tailscale; then
    if rpm_has tailscale; then
      systemctl is-enabled tailscaled >/dev/null 2>&1 || record unit-system tailscaled
      as_root systemctl enable --now tailscaled && ok "Tailscale is running" \
        || soft_fail "Could not start Tailscale" "" "sudo systemctl enable --now tailscaled"
      info "To sign in to Tailscale, run: sudo tailscale up"
    else
      soft_fail "Tailscale did not install, so its widget will do nothing" \
                "Its download source could not be reached earlier." \
                "./install.sh --only=repos,packages,optional"
    fi
  fi

  if is_selected warp; then
    if rpm_has cloudflare-warp; then
      systemctl is-enabled warp-svc >/dev/null 2>&1 || record unit-system warp-svc
      as_root systemctl enable --now warp-svc && ok "Cloudflare WARP is running" \
        || soft_fail "Could not start Cloudflare WARP" "" "sudo systemctl enable --now warp-svc"
      info "To set up Cloudflare WARP, run: warp-cli registration new"
    else
      soft_fail "Cloudflare WARP did not install, so its widget will do nothing" \
                "Its download source could not be reached earlier." \
                "./install.sh --only=repos,packages,optional"
    fi
  fi

  if is_selected splash; then
    install_boot_splash
  fi

  if is_selected niri; then
    if rpm_has niri; then
      deploy_tree "$REPO_DIR/config/desktop/niri" "$HOME/.config/niri"
      ok "The niri session is set up. Pick it at the login screen if you want it."
    else
      soft_fail "niri did not install, so that session is not available" "" "./install.sh --only=packages,optional"
    fi
  fi
}

# The Plymouth theme: what the machine shows between the firmware and the login
# screen, in place of a wall of service messages.
#
# Two things here are easy to get wrong and expensive to discover at the next
# boot. The theme has to be inside the initrd, which means rebuilding it, and
# on an encrypted disk the theme is also what asks for the passphrase, so a
# theme without a password prompt is a machine that cannot boot.
install_boot_splash() {
  have plymouth-set-default-theme || {
    soft_fail "The boot splash needs Plymouth, which is not installed" \
              "Its packages did not install earlier." \
              "./install.sh --only=packages,optional"; return 0; }

  local dest=/usr/share/plymouth/themes/nothing
  as_root mkdir -p "$dest"
  as_root cp "$REPO_DIR"/assets/plymouth/nothing/* "$dest/"
  record file "$dest"

  # The splash draws its text in Ndot, which lives in /usr/share/fonts and is
  # not in the initrd by default. Without this it silently falls back.
  local dracut_conf=/etc/dracut.conf.d/99-fedora-nothing-splash.conf
  if [[ -d /usr/share/fonts/nothing ]]; then
    as_root tee "$dracut_conf" >/dev/null <<'CONF'
# Written by fedora-nothing: put the splash typeface inside the initrd, so the
# boot screen uses it rather than falling back to whatever else is in there.
install_items+=" /usr/share/fonts/nothing/Ndot57-Regular.otf "
CONF
    record file "$dracut_conf"
  fi

  # The theme in use now, so uninstall can put it back rather than guess.
  local previous; previous=$(plymouth-set-default-theme 2>/dev/null) || previous=""
  [[ -n $previous && $previous != nothing ]] && record plymouth "$previous"

  # -R rebuilds the initrd, which is the slow part and the part that matters:
  # without it the theme is on disk and never seen.
  if run_quiet "Building the boot splash into the startup image" -- \
       sudo plymouth-set-default-theme -R nothing; then
    ok "The boot splash is set. You will see it at the next restart."
  else
    soft_fail "Could not set the boot splash" \
              "Plymouth accepted the theme but rebuilding the startup image failed." \
              "sudo plymouth-set-default-theme -R nothing"
    return 0
  fi

  # A splash only appears if the kernel was asked for one. Fedora usually has
  # both of these already; a minimal install often has neither.
  if have grubby && ! grep -q 'rhgb' /proc/cmdline; then
    as_root grubby --update-kernel=ALL --args="rhgb quiet" >/dev/null 2>&1 \
      && info "Told the boot loader to show the splash instead of the startup text" \
      || warn "Could not tell the boot loader to show the splash; add rhgb quiet to the kernel line yourself"
  fi
  return 0
}
