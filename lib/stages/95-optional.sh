# shellcheck shell=bash
# Optional services. Each one fails soft: an unreachable third-party repo must
# not take the rest of the install down.

stage_optional() {
  local any=0
  for c in tailscale warp niri searxng; do is_selected "$c" && any=1; done
  (( any )) || { skip "No extras were chosen"; return 0; }


  if is_selected tailscale; then
    if rpm_has tailscale; then
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

  if is_selected searxng; then
    install_searxng
  fi
}

install_searxng() {
  have podman-compose || { soft_fail "SearXNG needs podman-compose, which is not installed" \
                        "It runs as a set of containers." \
                        "sudo dnf install podman-compose"; return 0; }
  local dest="$HOME/SelfHosted/searxng"
  if [[ -f $dest/docker-compose.yml ]]; then
    skip "SearXNG is already set up"
    return 0
  fi
  deploy_tree "$REPO_DIR/config/services/searxng" "$dest" || { soft_fail "The SearXNG files are missing from this repository"; return 0; }
  # The secret key must not be the one committed to the repo.
  if [[ -f $dest/.env.example ]] && cp "$dest/.env.example" "$dest/.env"
  [[ -f $dest/.env ]] && ! (( DRY_RUN )); then
    local key; key=$(openssl rand -hex 32)
    sed -i "s|^SEARXNG_SECRET=.*|SEARXNG_SECRET=$key|" "$dest/.env" 2>/dev/null || true
  fi
  ok "SearXNG is ready. Start it with: cd ${dest/#$HOME/\~} && podman-compose up -d"
}
