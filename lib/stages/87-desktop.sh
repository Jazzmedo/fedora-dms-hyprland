# shellcheck shell=bash
# The services a desktop environment would have started for you. Everything in
# this stage belongs to a base component, so there is nothing to gate on: the
# only question is whether the rpm arrived, which is answered before acting.

stage_desktop() {
  enable_desktop_services
  create_user_dirs
}

# ufw and power-profiles-daemon are installed with the Desktop services
# component; this turns them on. Fedora installs firewalld enabled by
# default, and two enabled firewalls both writing nftables rules is worse
# than either alone — so firewalld gets turned off on ufw's way in.
enable_desktop_services() {
  if rpm_has firewalld && systemctl is-enabled firewalld >/dev/null 2>&1; then
    as_root systemctl disable --now firewalld \
      && ok "firewalld is off — ufw owns the firewall" \
      || soft_fail "Could not turn firewalld off" \
                   "ufw and firewalld will both write firewall rules." \
                   "sudo systemctl disable --now firewalld"
  fi
  local unit
  for unit in ufw power-profiles-daemon; do
    if ! rpm_has "${unit}"; then
      soft_fail "$unit did not install, so its part of the desktop stays dark" \
                "The package was not available in the sources this run used." \
                "sudo dnf install $unit && sudo systemctl enable --now $unit"
      continue
    fi
    if systemctl is-active "$unit" >/dev/null 2>&1; then
      skip "$unit is already running"
      continue
    fi
    systemctl is-enabled "$unit" >/dev/null 2>&1 || record unit-system "$unit"
    as_root systemctl enable --now "$unit" \
      && ok "$unit is running" \
      || soft_fail "Could not start $unit" \
                   "The package is installed but the service refused to start." \
                   "sudo systemctl status $unit"
  done
  # The ufw service running is not the same as the ruleset enforced: the
  # package ships with ENABLED=no in /etc/ufw/ufw.conf and a bare service
  # start loads nothing. `ufw enable` flips the config and loads the rules,
  # and is idempotent on a machine where the user already did it by hand.
  if rpm_has ufw; then
    as_root ufw enable \
      && ok "ufw is active and denies incoming traffic by default" \
      || soft_fail "Could not enable ufw's ruleset" \
                   "The service runs, but no rules are enforced." \
                   "sudo ufw enable"
  fi
}

# Documents, Downloads, Pictures and friends. An install that never had a
# desktop has none of them, and applications behave oddly when the XDG folders
# they expect are missing. --force is what makes an existing set follow the
# active locale; without it the update only fills in what is missing.
create_user_dirs() {
  rpm_has xdg-user-dirs || { soft_fail "xdg-user-dirs did not install, so the standard folders were not created" "" "sudo dnf install xdg-user-dirs"; return 0; }
  if (( DRY_RUN )); then
    info "Would create the standard folders (Documents, Downloads, …)"
    return 0
  fi
  run xdg-user-dirs-update --force
  ok "The standard folders exist in $HOME"
}
