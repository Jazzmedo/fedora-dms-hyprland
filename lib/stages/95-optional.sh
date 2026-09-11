# shellcheck shell=bash
# Optional services. Each one fails soft: an unreachable third-party repo must
# not take the rest of the install down.

stage_optional() {
  local any=0
  for c in tailscale warp niri searxng; do is_selected "$c" && any=1; done
  (( any )) || { skip "no optional services selected"; return 0; }

  step "Optional services"

  if is_selected tailscale; then
    if rpm_has tailscale; then
      as_root systemctl enable --now tailscaled && ok "tailscaled running" \
        || soft_fail "could not start tailscaled"
      info "authenticate with: sudo tailscale up"
    else
      soft_fail "tailscale is not installed; the dankscale plugin will be inert"
    fi
  fi

  if is_selected warp; then
    if rpm_has cloudflare-warp; then
      as_root systemctl enable --now warp-svc && ok "warp-svc running" \
        || soft_fail "could not start warp-svc"
      info "register with: warp-cli registration new"
    else
      soft_fail "cloudflare-warp is not installed; the warpToggle plugin will be inert"
    fi
  fi

  if is_selected niri; then
    if rpm_has niri; then
      deploy_tree "$REPO_DIR/config/desktop/niri" "$HOME/.config/niri"
      ok "niri session configured; pick it at the login screen"
    else
      soft_fail "niri is not installed"
    fi
  fi

  if is_selected searxng; then
    install_searxng
  fi
}

install_searxng() {
  have podman-compose || { soft_fail "podman-compose missing; SearXNG skipped"; return 0; }
  local dest="$HOME/SelfHosted/searxng"
  if [[ -f $dest/docker-compose.yml ]]; then
    skip "SearXNG already set up in ${dest/#$HOME/\~}"
    return 0
  fi
  deploy_tree "$REPO_DIR/config/services/searxng" "$dest" || { soft_fail "SearXNG files missing"; return 0; }
  # The secret key must not be the one committed to the repo.
  if [[ -f $dest/.env.example ]] && cp "$dest/.env.example" "$dest/.env"
  [[ -f $dest/.env ]] && ! (( DRY_RUN )); then
    local key; key=$(openssl rand -hex 32)
    sed -i "s|^SEARXNG_SECRET=.*|SEARXNG_SECRET=$key|" "$dest/.env" 2>/dev/null || true
  fi
  ok "SearXNG staged in ${dest/#$HOME/\~}; start it with: cd $dest && podman-compose up -d"
}
