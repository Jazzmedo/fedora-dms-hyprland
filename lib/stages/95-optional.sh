# shellcheck shell=bash
# Optional services. Each one fails soft: an unreachable third-party repo must
# not take the rest of the install down.

stage_optional() {
  local any=0
  for c in tailscale warp niri; do is_selected "$c" && any=1; done
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

  if is_selected niri; then
    if rpm_has niri; then
      deploy_tree "$REPO_DIR/config/desktop/niri" "$HOME/.config/niri"
      ok "The niri session is set up. Pick it at the login screen if you want it."
    else
      soft_fail "niri did not install, so that session is not available" "" "./install.sh --only=packages,optional"
    fi
  fi
}
