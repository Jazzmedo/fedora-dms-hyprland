# shellcheck shell=bash
# One transaction for everything the selection implies, so a failure rolls back
# instead of leaving a half-built desktop.
stage_packages() {

  local -a wanted missing
  mapfile -t wanted < <(selected_packages)
  info "Your choices need ${#wanted[@]} programs in total"

  local p
  for p in "${wanted[@]}"; do rpm_has "$p" || missing+=("$p"); done

  if (( ${#missing[@]} == 0 )); then
    skip "Every program you chose is already installed"
  else
    info "${#missing[@]} still to download. This is the long part; leave it running."
    # Recorded before the transaction, while "absent" is still true of them.
    record_new_pkgs "${missing[@]}"
    if ! as_root dnf install -y --skip-unavailable "${missing[@]}"; then
      die "Installing the programs failed" \
          "Usually the connection dropped partway through, or a download source is temporarily down." \
          "Run ./install.sh again. Already-installed programs are skipped."
    fi
    ok "${#missing[@]} packages installed"
  fi

  # --skip-unavailable keeps one absent package from cancelling ninety, but it
  # also means a COPR that does not actually carry Hyprland fails silently here
  # and confusingly three stages later.
  rpm_has hyprland || die "Hyprland itself did not install" \
     "The community source that was added does not actually carry it for this Fedora version." \
     "Check what is available with: dnf repoquery --available hyprland"

  # Hyprland must have the Lua config backend or none of config/desktop/hypr
  # will load. Fedora does not package Hyprland at all, hence the COPR.
  if have hyprland; then
    local hv; hv=$(hyprland --version 2>/dev/null | grep -oP 'v?\K[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    ok "Hyprland ${hv:-} installed"
    if [[ -n $hv ]] && ! printf '%s\n0.52.0\n' "$hv" | sort -V -C; then
      : # >= 0.52, Lua config is present
    elif [[ -n $hv ]]; then
      warn "Hyprland $hv is too old for this setup, which needs 0.52 or newer; some settings will be ignored"
    fi
  fi

  # kitty.conf uses cursor_trail, added in 0.38.
  if have kitty; then
    local kv; kv=$(kitty --version 2>/dev/null | awk '{print $2}')
    [[ -n $kv ]] && printf '%s\n0.38.0\n' "$kv" | sort -V -C \
      && warn "The kitty terminal is version $kv, so its cursor trail effect will not work"
  fi

  # quickshell is what DankMaterialShell renders with, and this installer does
  # not ask dnf for it: see the note in lib/components.sh. An rpm that arrived
  # some other way still shadows the build DMS wants, so say so here rather
  # than let the shell fail three stages later.
  if rpm_has quickshell; then
    warn "A copy of quickshell was already installed here; the next step checks it is new enough for the desktop shell"
  fi

  local -a fps
  mapfile -t fps < <(selected_flatpaks)
  if (( ${#fps[@]} )) && ! is_selected flatpak; then
    soft_fail "${#fps[@]} app(s) you chose need Flatpak, which is switched off" \
              "Those apps are only distributed as Flatpaks." \
              "Re-run ./install.sh and tick Flatpak in the list"
  elif (( ${#fps[@]} )); then
    local f
    for f in "${fps[@]}"; do
      if flatpak info "$f" >/dev/null 2>&1; then
        skip "$f is already installed"
      else
        run_visible flatpak install -y --noninteractive flathub "$f" \
          && record flatpak "$f" \
          || soft_fail "Could not install $f" \
               "The download from Flathub failed." \
               "./install.sh --only=packages"
      fi
    done
  fi
}
