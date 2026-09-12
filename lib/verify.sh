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

# The prompt is drawn by starship or not at all: ~/.zshrc initialises it only
# when the program is on PATH, so a missing rpm shows up as a plain shell with
# no error anywhere.
check_starship() { have starship && [[ -f $HOME/.config/starship.toml ]]; }

check_fastfetch() { have fastfetch && [[ -f $HOME/.config/fastfetch/config.jsonc ]]; }

# The theme SDDM will actually load, which is the last Current= across
# everything in conf.d plus the legacy file.
#
# Each file is checked for existence first. Handing sed a path that is not
# there makes it exit 2, and under `set -euo pipefail` that ends the run: the
# login screen stage did all of its work, moved /etc/sddm.conf aside, and then
# died reading back the file it had just moved.
sddm_configured_theme() {
  local f line out=""
  for f in /etc/sddm.conf.d/*.conf /etc/sddm.conf; do
    [[ -r $f ]] || continue
    while IFS= read -r line; do
      [[ $line == Current=* ]] && out=${line#Current=}
    done <"$f"
  done
  printf '%s' "$out"
}

check_sddm_theme() {
  [[ $(sddm_configured_theme) == nothing ]] \
    && [[ -f /usr/share/sddm/themes/nothing/Main.qml ]]
}

# Whichever unit owns display-manager.service is the one that starts. The theme
# being installed and configured says nothing about that, which is how a
# different greeter ran for a whole session while every check here passed.
active_display_manager() {
  [[ -L /etc/systemd/system/display-manager.service ]] || return 1
  basename "$(readlink -f /etc/systemd/system/display-manager.service)"
}

check_display_manager() { [[ $(active_display_manager) == sddm.service ]]; }

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

# The screen-share source chooser: the portal's config, the wrapper it names and
# the payload that wrapper execs. Missing any one of them and screen sharing
# starts with no window list.
check_share_picker() {
  [[ -f $HOME/.config/hypr/xdph.conf ]] &&
  [[ -x $HOME/.local/bin/dms-share-picker ]] &&
  [[ -x $HOME/.local/bin/quickshell-share-picker ]] &&
  [[ -f $HOME/.local/share/quickshell-share-picker/quickshell/shell.qml ]]
}

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
  _verify "Screen sharing can choose a window" \
          "./install.sh --only=hyprland" check_share_picker
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
  if is_selected prompt; then
    _verify "The starship prompt is installed" \
            "./install.sh --only=shell" check_starship
  fi
  if is_selected sysinfo; then
    _verify "fastfetch greets you in a new terminal" \
            "./install.sh --only=shell" check_fastfetch
  fi

  _verify "The login screen is set to the Nothing theme" \
          "./install.sh --only=sddm" check_sddm_theme
  _verify "SDDM is the login screen that starts" \
          "sudo systemctl enable --force sddm" check_display_manager
  _verify "The computer boots to the login screen" \
          "sudo systemctl set-default graphical.target" check_graphical_target

  printf '\n'
  if (( VERIFY_FAILED )); then
    warn "$VERIFY_FAILED of these did not work. The commands above fix them."
  fi
  return 0
}
