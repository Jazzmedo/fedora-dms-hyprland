# shellcheck shell=bash
# What is already on this machine.
#
# Every component reports one of three states:
#   installed  everything it provides is present
#   partial    some of it is present, so a re-run repairs the rest
#   missing    none of it is here
#
# Package membership alone lies in both directions: a component can own no rpms
# at all (Vesktop comes from a GitHub rpm) or own them and still be unusable
# (zsh installed but never made the login shell). So a component may declare a
# `detector` and the fallback is the ratio of its rpms that are installed.

declare -A INSTALLED_RPMS INSTALLED_FLATPAKS COMPONENT_STATE
DETECT_READY=0

# One rpm -qa and one flatpak list, rather than a subprocess per package.
detect_snapshot() {
  (( DETECT_READY )) && return 0
  INSTALLED_RPMS=(); INSTALLED_FLATPAKS=()

  local name
  if have rpm; then
    while read -r name; do INSTALLED_RPMS[$name]=1; done \
      < <(rpm -qa --qf '%{NAME}\n' 2>/dev/null)
  fi
  if have flatpak; then
    while read -r name; do INSTALLED_FLATPAKS[$name]=1; done \
      < <(flatpak list --app --columns=application 2>/dev/null)
  fi
  DETECT_READY=1
}

pkg_installed()     { [[ -n ${INSTALLED_RPMS[$1]:-} ]]; }
flatpak_installed() { [[ -n ${INSTALLED_FLATPAKS[$1]:-} ]]; }

# Collapse a list of yes/no facts into one state.
# Usage: state_from <present count> <total count>
state_from() {
  local have=$1 total=$2
  (( total == 0 ))    && { printf 'missing';   return; }
  (( have == 0 ))     && { printf 'missing';   return; }
  (( have == total )) && { printf 'installed'; return; }
  printf 'partial'
}

component_state() {
  local key=$1
  [[ -n ${COMPONENT_STATE[$key]:-} ]] && { printf '%s' "${COMPONENT_STATE[$key]}"; return; }
  detect_snapshot

  local state
  if [[ -n ${COMPONENT_DETECT[$key]:-} ]]; then
    state=$(eval "${COMPONENT_DETECT[$key]}")
  else
    local have=0 total=0 p
    for p in ${COMPONENT_PKGS[$key]:-};     do (( ++total )); pkg_installed "$p"     && (( ++have )); done
    for p in ${COMPONENT_FLATPAKS[$key]:-}; do (( ++total )); flatpak_installed "$p" && (( ++have )); done
    state=$(state_from "$have" "$total")
  fi
  COMPONENT_STATE[$key]=$state
  printf '%s' "$state"
}

# Count how many of the given tests pass, then collapse. Each argument is a
# shell expression; this is what the detectors in components.sh are built from.
all_of() {
  local have=0 total=0 test
  for test in "$@"; do
    (( ++total ))
    eval "$test" >/dev/null 2>&1 && (( ++have ))
  done
  state_from "$have" "$total"
}

# ------------------------------------------------------------ system facts ---
# Things that belong to a stage rather than to a component, shown by --status.
system_checks() {
  local theme; theme=$(awk -F= '/^Current=/{print $2}' /etc/sddm.conf.d/*.conf 2>/dev/null | tail -1)
  printf '%s\t%s\n' "SDDM theme"      "${theme:-not set}"
  printf '%s\t%s\n' "SDDM theme files" \
    "$( [[ -f /usr/share/sddm/themes/nothing/Main.qml ]] && echo present || echo missing )"
  printf '%s\t%s\n' "Qt5Compat (theme needs it)" \
    "$( pkg_installed qt6-qt5compat && echo present || echo MISSING )"
  printf '%s\t%s\n' "default target" "$(systemctl get-default 2>/dev/null)"
  printf '%s\t%s\n' "login shell"    "$(getent passwd "$USER" 2>/dev/null | cut -d: -f7 || echo unknown)"
  printf '%s\t%s\n' "dms.service"    "$(systemctl --user is-active dms.service 2>/dev/null || echo inactive)"
  printf '%s\t%s\n' "dms binary"     "$(command -v dms 2>/dev/null || echo 'not on PATH')"
  printf '%s\t%s\n' "hyprland config" \
    "$( [[ -f $HOME/.config/hypr/hyprland.lua ]] && echo deployed || echo missing )"
  printf '%s\t%s\n' "default browser" "$(xdg-settings get default-web-browser 2>/dev/null || echo unset)"
  local plugins=0
  [[ -d $HOME/.config/DankMaterialShell/plugins ]] && \
    plugins=$(find "$HOME/.config/DankMaterialShell/plugins" -maxdepth 1 -mindepth 1 \
              \( -type d -o -type l \) ! -name '.*' 2>/dev/null | wc -l)
  printf '%s\t%s\n' "DMS plugins"    "$plugins installed"
  return 0
}

# ------------------------------------------------------------------ report ---
show_status() {
  detect_snapshot
  step "Already on this machine"

  local group key state mark label
  for group in "${COMPONENT_GROUPS[@]}"; do
    [[ $group == gpu || $group == layout ]] && continue
    printf '\n  %s%s%s\n' "$C_BOLD" "${GROUP_LABEL[$group]}" "$C_OFF"
    for key in $(group_members "$group"); do
      state=$(component_state "$key")
      case $state in
        installed) mark="${C_OK}installed${C_OFF}" ;;
        partial)   mark="${C_WARN}partial${C_OFF}" ;;
        *)         mark="${C_GREY}missing${C_OFF}" ;;
      esac
      label=${COMPONENT_NAME[$key]}
      local pad=""; (( ${#label} < 24 )) && printf -v pad '%*s' $(( 24 - ${#label} )) ''
      printf '    %s%s  %s\n' "$label" "$pad" "$mark"
    done
  done

  printf '\n  %sSystem%s\n' "$C_BOLD" "$C_OFF"
  local name value
  while IFS=$'\t' read -r name value; do
    local pad=""; (( ${#name} < 24 )) && printf -v pad '%*s' $(( 24 - ${#name} )) ''
    printf '    %s%s  %s%s%s\n' "$name" "$pad" "$C_GREY" "$value" "$C_OFF"
  done < <(system_checks)
  echo
  return 0
}
