# shellcheck shell=bash
# System-level tweaks that are not part of the desktop itself: browser search
# policy, name resolution, and writeback tuning.

stage_tweaks() {
  is_selected tweaks || { skip "System settings were not chosen"; return 0; }
  install_browser_policies
  configure_nsswitch
  configure_locale
  install_sysctl
}

# Enterprise policy files, which is the only way to set a default search engine
# that survives a profile reset. Firefox-family and Chromium-family each have
# their own format and their own search path.
install_browser_policies() {
  local ff="$REPO_DIR/config/system/policies/firefox-policies.json"
  local cr="$REPO_DIR/config/system/policies/chromium-searxng.json"

  # Only the browsers being installed get a policy directory.
  local dir gecko=() chromium=()
  is_selected zen       && gecko+=(/etc/zen/policies /opt/zen/distribution)
  is_selected firefox   && gecko+=(/etc/firefox/policies)
  is_selected librewolf && gecko+=(/etc/librewolf)
  # Brave Origin reads Brave's policy directory.
  { is_selected brave || is_selected brave_origin; } && chromium+=(/etc/brave/policies/managed)
  is_selected vivaldi   && chromium+=(/etc/opt/vivaldi/policies/managed)
  is_selected helium    && chromium+=(/etc/helium/policies/managed)

  for dir in "${gecko[@]}"; do
    [[ -d ${dir%/*} || $dir == /etc/* ]] || continue
    # Merged, not copied: the apps stage adds Zen's site-theming extension here.
    merge_policy "$dir/policies.json" "$(cat "$ff")"
    record file "$dir/policies.json"
  done
  (( ${#gecko[@]} )) && ok "Set your custom search engine in the Firefox-based browsers"

  for dir in "${chromium[@]}"; do
    as_root mkdir -p "$dir"
    as_root cp "$cr" "$dir/searxng_policy.json"
    record file "$dir/searxng_policy.json"
  done
  (( ${#chromium[@]} )) && ok "Set your custom search engine in the Chromium-based browsers"
  return 0
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
  record edited /etc/nsswitch.conf
  as_root sed -i "s|^hosts:.*|$want|" /etc/nsswitch.conf
  grep -q '^hosts:' /etc/nsswitch.conf || as_root bash -c "printf '%s\n' '$want' >> /etc/nsswitch.conf"
  ok "Set up name lookup so devices on your network resolve by name"

  if ! rpm_has nss-mdns; then
    record_new_pkgs nss-mdns avahi
    as_root dnf install -y nss-mdns avahi || soft_fail "Could not install the local name lookup service" \
         "Addresses ending in .local will not work." \
         "sudo dnf install nss-mdns avahi"
    as_root systemctl enable --now avahi-daemon && record unit-system avahi-daemon || true
  fi
}

# English interface; Egyptian formats for paper size, names, addresses and
# phone numbers.
configure_locale() {
  if ! locale -a 2>/dev/null | grep -qi '^ar_EG'; then
    record_new_pkgs glibc-langpack-ar
    as_root dnf install -y glibc-langpack-ar || { soft_fail "Could not install the Arabic locale" \
         "Paper size, address and phone formats stay English." \
         "sudo dnf install glibc-langpack-ar"; return 0; }
  fi
  local want=(LANG=en_US.UTF-8 LC_PAPER=ar_EG.UTF-8 LC_NAME=ar_EG.UTF-8
              LC_ADDRESS=ar_EG.UTF-8 LC_TELEPHONE=ar_EG.UTF-8
              LC_IDENTIFICATION=ar_EG.UTF-8)
  if [[ $(grep -v '^#' /etc/locale.conf 2>/dev/null | sort) == "$(printf '%s\n' "${want[@]}" | sort)" ]]; then
    skip "The language and regional formats are already set"
    return 0
  fi
  [[ -f /etc/locale.conf ]] && as_root cp /etc/locale.conf /etc/locale.conf.fedora-nothing.bak
  record edited /etc/locale.conf
  as_root localectl set-locale "${want[@]}"
  ok "Set English with Egyptian regional formats (takes effect at next login)"
}

install_sysctl() {
  local f=/etc/sysctl.d/99-usb-copy-fix.conf
  if [[ -f $f ]] && cmp -s "$REPO_DIR/config/system/sysctl/99-usb-copy-fix.conf" "$f"; then
    skip "The USB copying fix is already applied"
    return 0
  fi
  as_root cp "$REPO_DIR/config/system/sysctl/99-usb-copy-fix.conf" "$f"
  record file "$f"
  as_root sysctl --system >/dev/null
  ok "Copying to USB drives will no longer make the system freeze"
}
