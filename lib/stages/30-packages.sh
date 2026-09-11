# shellcheck shell=bash
# One transaction for everything the selection implies, so a failure rolls back
# instead of leaving a half-built desktop.
stage_packages() {
  step "Packages"

  local -a wanted missing
  mapfile -t wanted < <(selected_packages)
  info "${#wanted[@]} packages implied by the current selection"

  local p
  for p in "${wanted[@]}"; do rpm_has "$p" || missing+=("$p"); done

  if (( ${#missing[@]} == 0 )); then
    skip "all packages already installed"
  else
    info "${#missing[@]} to install"
    if ! as_root dnf install -y --skip-unavailable "${missing[@]}"; then
      die "package installation failed; see ${LOG_FILE:-the output above}"
    fi
    ok "${#missing[@]} packages installed"
  fi

  # --skip-unavailable keeps one absent package from cancelling ninety, but it
  # also means a COPR that does not actually carry Hyprland fails silently here
  # and confusingly three stages later.
  rpm_has hyprland || die "hyprland was not installed.
     The enabled COPR does not provide it for this Fedora release.
     Check: dnf repoquery --available hyprland"

  # Hyprland must have the Lua config backend or none of config/desktop/hypr
  # will load. Fedora does not package Hyprland at all, hence the COPR.
  if have hyprland; then
    local hv; hv=$(hyprland --version 2>/dev/null | grep -oP 'v?\K[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    info "hyprland ${hv:-unknown}"
    if [[ -n $hv ]] && ! printf '%s\n0.52.0\n' "$hv" | sort -V -C; then
      : # >= 0.52, Lua config is present
    elif [[ -n $hv ]]; then
      warn "hyprland $hv predates the Lua config backend; the config in this repo needs >= 0.52"
    fi
  fi

  # kitty.conf uses cursor_trail, added in 0.38.
  if have kitty; then
    local kv; kv=$(kitty --version 2>/dev/null | awk '{print $2}')
    [[ -n $kv ]] && printf '%s\n0.38.0\n' "$kv" | sort -V -C \
      && warn "kitty $kv is older than 0.38; cursor_trail will be ignored"
  fi

  # quickshell is what DankMaterialShell renders with, and this installer does
  # not ask dnf for it: see the note in lib/components.sh. An rpm that arrived
  # some other way still shadows the build DMS wants, so say so here rather
  # than let the shell fail three stages later.
  if rpm_has quickshell; then
    warn "quickshell came from an rpm ($(rpm -q quickshell)); the DMS stage will check it is new enough"
  fi

  local -a fps
  mapfile -t fps < <(selected_flatpaks)
  if (( ${#fps[@]} )) && ! is_selected flatpak; then
    soft_fail "${#fps[@]} flatpak app(s) selected but the Flatpak component is not; skipping them"
  elif (( ${#fps[@]} )); then
    local f
    for f in "${fps[@]}"; do
      if flatpak info "$f" >/dev/null 2>&1; then
        skip "flatpak $f already installed"
      else
        run_visible flatpak install -y --noninteractive flathub "$f" \
          || soft_fail "flatpak $f failed to install"
      fi
    done
  fi
}
