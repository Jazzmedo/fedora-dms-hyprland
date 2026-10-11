# shellcheck shell=bash
# The services a desktop environment would have started for you. Everything in
# this stage belongs to a base component, so there is nothing to gate on: the
# only question is whether the rpm arrived, which is answered before acting.

stage_desktop() {
  enable_desktop_services
  create_user_dirs
}

# firewalld and power-profiles-daemon are installed with the Desktop services
# component; this turns them on. Both are daemons the shell talks to over D-Bus
# and both quietly degrade to "feature missing" when absent, which is exactly
# the failure mode this stage exists to close.
enable_desktop_services() {
  local unit
  for unit in firewalld power-profiles-daemon; do
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
