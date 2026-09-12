# shellcheck shell=bash
# What actually happened, checked at the end of the run.
#
# Every stage reports on the command it issued, which is not the same as the
# outcome. `chsh` can succeed while the login shell stays put; `cp` of a
# greeter theme succeeds whether or not SDDM will load it. These checks read
# the finished state instead, so a run cannot claim success for something that
# did not take.
#
# Also sourced by doctor.sh, so the two never drift apart.

VERIFY_FAILED=0

# verify <label> <fix> <test...>
_verify() {
  local label=$1 fix=$2; shift 2
  if "$@"; then
    printf '  %s✓%s %s\n' "$C_OK" "$C_OFF" "$label"
  else
    printf '  %s✗%s %s\n' "$C_WARN$C_BOLD" "$C_OFF" "$label"
    [[ -n $fix ]] && printf '      %sFix:%s  %s%s%s\n' "$C_GREY" "$C_OFF" "$C_BOLD" "$fix" "$C_OFF"
    VERIFY_FAILED=$(( VERIFY_FAILED + 1 ))
  fi
}

# --------------------------------------------------------------- the checks ---
check_login_shell() {
  local zsh; zsh=$(command -v zsh 2>/dev/null) || return 1
  [[ -n $zsh ]] || return 1
  [[ $(getent passwd "$USER" | cut -d: -f7) == "$zsh" ]]
}

check_zshrc() { [[ -s $HOME/.zshrc ]]; }

# The theme SDDM will actually load, which is the last Current= across
# everything in conf.d plus the legacy file.
sddm_configured_theme() {
  sed -n 's/^Current=//p' /etc/sddm.conf.d/*.conf /etc/sddm.conf 2>/dev/null | tail -1
}

check_sddm_theme() {
  [[ $(sddm_configured_theme) == nothing ]] \
    && [[ -f /usr/share/sddm/themes/nothing/Main.qml ]]
}

check_graphical_target() {
  [[ $(systemctl get-default 2>/dev/null) == graphical.target ]]
}

# No pipe into grep -q: grep exits on the first match, fc-list takes SIGPIPE,
# and pipefail then reports the whole check as a failure.
check_nothing_font() {
  local families; families=$(fc-list : family 2>/dev/null) || return 1
  [[ $families == *[Nn]dot* ]]
}

check_session_entry() { [[ -f /usr/share/wayland-sessions/hyprland.desktop ]]; }

check_wallpapers() {
  local d="$HOME/Pictures/Wallpapers/theme-collections"
  [[ -d $d ]] && [[ -n $(find "$d" -type f -print -quit 2>/dev/null) ]]
}

check_hypr_config() { [[ -f $HOME/.config/hypr/hyprland.lua ]]; }

check_dms_binary() { command -v dms >/dev/null 2>&1; }

# ---------------------------------------------------------------- the pass ---
# Only the things that have quietly failed before, or that you would not notice
# until the next reboot.
verify_install() {
  VERIFY_FAILED=0
  printf '\n  %sChecking it actually worked%s\n\n' "$C_BOLD" "$C_OFF"

  _verify "Hyprland settings are in place" \
          "./install.sh --only=hyprland" check_hypr_config
  _verify "Hyprland is offered at the login screen" \
          "./install.sh --only=hyprland" check_session_entry
  _verify "The desktop shell is installed" \
          "./install.sh --only=dms" check_dms_binary
  _verify "The Nothing typefaces are installed" \
          "./install.sh --only=fonts" check_nothing_font
  _verify "The wallpapers are on disk" \
          "./install.sh --only=themes" check_wallpapers

  if is_selected zsh; then
    _verify "zsh is your login shell" \
            "chsh -s $(command -v zsh 2>/dev/null || echo /usr/bin/zsh)" check_login_shell
    _verify "Your ~/.zshrc is written" \
            "./install.sh --only=shell" check_zshrc
  fi

  _verify "The login screen is set to the Nothing theme" \
          "./install.sh --only=sddm" check_sddm_theme
  _verify "The computer boots to the login screen" \
          "sudo systemctl set-default graphical.target" check_graphical_target

  printf '\n'
  if (( VERIFY_FAILED )); then
    warn "$VERIFY_FAILED of these did not work. The commands above fix them."
  fi
  return 0
}
