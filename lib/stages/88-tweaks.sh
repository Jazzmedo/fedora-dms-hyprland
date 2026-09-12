# shellcheck shell=bash
# System-level tweaks that are not part of the desktop itself: browser search
# policy, name resolution, and writeback tuning.

stage_tweaks() {
  is_selected tweaks || { skip "System settings were not chosen"; return 0; }
  install_browser_policies
  configure_nsswitch
  install_sysctl
}

# Enterprise policy files, which is the only way to set a default search engine
# that survives a profile reset. Firefox-family and Chromium-family each have
# their own format and their own search path.
install_browser_policies() {
  local ff="$REPO_DIR/config/system/policies/firefox-policies.json"
  local cr="$REPO_DIR/config/system/policies/chromium-searxng.json"

  local dir
  for dir in /etc/zen/policies /opt/zen/distribution /etc/firefox/policies /etc/librewolf; do
    [[ -d ${dir%/*} || $dir == /etc/* ]] || continue
    as_root mkdir -p "$dir"
    as_root cp "$ff" "$dir/policies.json"
  done
  ok "Set your custom search engine in Zen and Firefox"

  for dir in /etc/chromium/policies/managed /etc/brave/policies/managed \
             /etc/opt/chrome/policies/managed /etc/helium/policies/managed; do
    as_root mkdir -p "$dir"
    as_root cp "$cr" "$dir/searxng_policy.json"
  done
  ok "Set your custom search engine in Chromium, Brave, Chrome and Helium"
}

# mdns4_minimal resolves .local names from Avahi, which is what the SearXNG
# host in the policies above relies on. mymachines resolves podman containers.
configure_nsswitch() {
  local want='hosts:          files dns mdns4_minimal mymachines'
  if grep -qx "$want" /etc/nsswitch.conf 2>/dev/null; then
    skip "Local network name lookup is already set up"
    return 0
  fi
  as_root cp /etc/nsswitch.conf /etc/nsswitch.conf.fedora-nothing.bak
  as_root sed -i "s|^hosts:.*|$want|" /etc/nsswitch.conf
  grep -q '^hosts:' /etc/nsswitch.conf || as_root bash -c "printf '%s\n' '$want' >> /etc/nsswitch.conf"
  ok "Set up name lookup so devices on your network resolve by name"

  if ! rpm_has nss-mdns; then
    as_root dnf install -y nss-mdns avahi || soft_fail "Could not install the local name lookup service" \
         "Addresses ending in .local will not work." \
         "sudo dnf install nss-mdns avahi"
    as_root systemctl enable --now avahi-daemon || true
  fi
}

install_sysctl() {
  local f=/etc/sysctl.d/99-usb-copy-fix.conf
  if [[ -f $f ]] && cmp -s "$REPO_DIR/config/system/sysctl/99-usb-copy-fix.conf" "$f"; then
    skip "The USB copying fix is already applied"
    return 0
  fi
  as_root cp "$REPO_DIR/config/system/sysctl/99-usb-copy-fix.conf" "$f"
  as_root sysctl --system >/dev/null
  ok "Copying to USB drives will no longer make the system freeze"
}
