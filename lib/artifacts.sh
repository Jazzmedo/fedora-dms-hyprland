# shellcheck shell=bash
# Everywhere this installer, or an installer it runs, can leave something.
#
# The manifest records what a run changed, but it only covers runs made after
# the manifest existed, and it cannot cover what somebody else's installer did
# on our behalf: the desktop shell arrives through install.danklinux.com, the
# music player through cliamp.stream, the Rust toolchain through rustup. Those
# write where they please and tell nobody.
#
# So this is the swept list: every path, unit and package this project can be
# responsible for. uninstall.sh walks it and acts only on what is actually
# there. Derived from the repository where it can be, so it stays in step.

# Directories and files under $HOME. A directory here is removed whole.
artifact_home_paths() {
  local -a p=(
    # the desktop shell, and what its own installer leaves
    "$HOME/.config/DankMaterialShell"
    "$HOME/.config/quickshell"
    "$HOME/.local/share/DankMaterialShell"
    "$HOME/.local/state/DankMaterialShell"
    "$HOME/.cache/quickshell"
    "$HOME/.local/share/dank"
    "$HOME/.local/bin/dms"
    "$HOME/.local/bin/quickshell"
    "$HOME/.local/bin/qs"
    "$HOME/.local/bin/dankinstall"

    # window managers and the session
    "$HOME/.config/hypr"
    "$HOME/.config/niri"
    "$HOME/.config/uwsm"

    # look and feel
    "$HOME/.config/matugen"
    "$HOME/.config/gtk-3.0"
    "$HOME/.config/gtk-4.0"
    "$HOME/.config/qt5ct"
    "$HOME/.config/qt6ct"
    "$HOME/.config/kdeglobals"
    "$HOME/.config/dolphinrc"
    "$HOME/.gtkrc-2.0"
    "$HOME/.local/share/color-schemes"
    "$HOME/.local/share/icons/Afterglow-cursors"
    "$HOME/.local/share/icons/Cawnonical Mono-Glyph Icon Suite (White)"
    "$HOME/Pictures/Wallpapers/theme-collections"

    # terminal, shell and editor
    "$HOME/.zshrc"
    "$HOME/.config/zsh"
    "$HOME/.zsh"
    "$HOME/.oh-my-zsh"
    "$HOME/.config/starship.toml"
    "$HOME/.config/kitty"
    "$HOME/.config/tmux"
    "$HOME/.config/yazi"
    "$HOME/.config/btop"
    "$HOME/.config/cava"
    "$HOME/.config/fastfetch"
    "$HOME/.config/nvim"
    "$HOME/.local/share/nvim"
    "$HOME/.local/state/nvim"
    "$HOME/.cache/nvim"

    # applications and their helpers
    "$HOME/.config/cliamp"
    "$HOME/.local/bin/cliamp"
    "$HOME/.local/share/applications/cliamp.desktop"
    "$HOME/.local/share/icons/hicolor/512x512/apps/cliamp.png"
    "$HOME/.local/share/lyrics-on-panel"
    "$HOME/.config/vesktop"
    "$HOME/.config/obs-studio"
    "$HOME/.config/qBittorrent"
    "$HOME/.config/easyeffects"
    "$HOME/SelfHosted/searxng"

    # language toolchains, each installed by its own upstream script
    "$HOME/.nvm"
    "$HOME/.pyenv"
    "$HOME/.cargo"
    "$HOME/.rustup"

    # this installer's own state
    "$HOME/.config/fedora-nothing"
    "$HOME/.cache/fedora-nothing"
  )

  # The helper scripts, taken from the repository rather than listed again.
  local f
  for f in "$REPO_DIR"/bin/*; do
    [[ -e $f ]] && p+=("$HOME/.local/bin/$(basename "$f")")
  done
  for f in "$REPO_DIR"/assets/dms-plugins/cliamp-dms/scripts/cliamp-dms-*; do
    [[ -e $f ]] && p+=("$HOME/.local/bin/$(basename "$f")")
  done

  printf '%s\n' "${p[@]}"
}

# Paths outside $HOME. Every one of these is also inside the prefixes
# uninstall.sh is willing to touch; anything else it would refuse anyway.
artifact_system_paths() {
  printf '%s\n' \
    /usr/share/sddm/themes/nothing \
    /etc/sddm.conf.d/10-wayland.conf \
    /etc/sddm.conf.d/20-nothing.conf \
    /usr/share/fonts/nothing \
    /usr/share/fonts/jetbrains-nerd \
    /etc/fonts/local.conf \
    /usr/share/wayland-sessions/hyprland.desktop \
    /usr/share/applications/app.zen_browser.zen.desktop \
    /usr/local/bin/zen \
    /usr/local/bin/helium \
    /usr/local/bin/dms \
    /usr/local/bin/quickshell \
    /opt/zen \
    /opt/helium \
    /etc/sysctl.d/99-usb-copy-fix.conf \
    /etc/systemd/system/numlock-on.service \
    /usr/share/plymouth/themes/nothing \
    /etc/dracut.conf.d/99-fedora-nothing-splash.conf \
    /etc/zen/policies/policies.json \
    /etc/firefox/policies/policies.json \
    /etc/librewolf/policies.json \
    /opt/zen/distribution/policies.json \
    /etc/chromium/policies/managed/searxng_policy.json \
    /etc/brave/policies/managed/searxng_policy.json \
    /etc/opt/chrome/policies/managed/searxng_policy.json \
    /etc/helium/policies/managed/searxng_policy.json
}

# Services started when you log in. Read from the repository, plus the ones
# other installers add.
artifact_user_units() {
  local f
  for f in "$REPO_DIR"/config/desktop/systemd-user/*; do
    [[ -e $f ]] && printf '%s\n' "$(basename "$f")"
  done
  printf '%s\n' Universal-Mpris-LyricServer.service dms-greeter.service
}

# System services. sddm is deliberately absent: which login screen runs is
# restored from the manifest, and switching it off blind would leave a machine
# with no way to log in graphically.
artifact_system_units() {
  printf '%s\n' tailscaled warp-svc avahi-daemon numlock-on.service
}

# Every package any component can install, whether or not it was ticked.
artifact_packages() {
  local k
  for k in "${COMPONENT_ORDER[@]}"; do
    printf '%s\n' ${COMPONENT_PKGS[$k]:-}
  done
  # Installed by name rather than by a component: the shell's own installer
  # pulls this one in, and dnf is the only thing that can take it out again.
  printf '%s\n' quickshell
}

artifact_flatpaks() {
  local k
  for k in "${COMPONENT_ORDER[@]}"; do
    printf '%s\n' ${COMPONENT_FLATPAKS[$k]:-}
  done
}

# Community sources, from the same declarations the installer enables them by.
artifact_coprs() {
  local k
  for k in "${COMPONENT_ORDER[@]}"; do
    printf '%s\n' ${COMPONENT_COPR[$k]:-}
  done
}

artifact_repofiles() {
  printf '%s\n' \
    /etc/yum.repos.d/brave-browser.repo \
    /etc/yum.repos.d/tailscale.repo \
    /etc/yum.repos.d/cloudflare-warp-ascii.repo
}
