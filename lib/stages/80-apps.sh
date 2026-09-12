# shellcheck shell=bash
# Default applications and the XDG associations that route files to them.

ZEN_INSTALL_DIR=/opt/zen
HELIUM_INSTALL_DIR=/opt/helium

stage_apps() {
  local k="$REPO_DIR/config/terminal/kitty"
  deploy_tree "$k" "$HOME/.config/kitty"
  # kitty.conf includes both of these unconditionally, so they have to exist,
  # but the desktop shell rewrites them on every theme change. Seeded once.
  deploy_seed "$k/seed/dank-theme.conf" "$HOME/.config/kitty/dank-theme.conf"
  deploy_seed "$k/seed/dank-tabs.conf"  "$HOME/.config/kitty/dank-tabs.conf"
  ok "Set up the kitty terminal"

  install_zen
  is_selected helium   && install_helium
  is_selected vesktop  && install_github_rpm Vencord/Vesktop  'vesktop.*\.x86_64\.rpm$' vesktop  Vesktop
  is_selected obsidian && install_github_rpm obsidianmd/obsidian-releases 'obsidian-[0-9.]+\.rpm$' obsidian Obsidian
  install_app_configs
  write_mimeapps
}

# Zen ships a tarball with its own updater. A Flatpak would sandbox it away
# from the matugen-generated userChrome.css.
install_zen() {
  if [[ -x $ZEN_INSTALL_DIR/zen ]]; then
    skip "The Zen browser is already installed"
  else
    local tmp; tmp=$(mktemp -d)
    local url="https://github.com/zen-browser/desktop/releases/latest/download/zen.linux-x86_64.tar.xz"
    if ! retry 3 curl -fL --progress-bar -o "$tmp/zen.tar.xz" "$url"; then
      clean_tmp "$tmp"; soft_fail "Could not download the Zen browser" \
      "The download failed, so you will have no default browser yet." \
      "./install.sh --only=apps"; return 0
    fi
    as_root rm -rf "$ZEN_INSTALL_DIR"
    as_root mkdir -p "$ZEN_INSTALL_DIR"
    # Unpacked as you, not as root. Root-owned files in your own scratch
    # directory cannot be deleted afterwards, and that failure is fatal.
    tar -xf "$tmp/zen.tar.xz" -C "$tmp"
    as_root bash -c "cp -a '$tmp/zen/.' '$ZEN_INSTALL_DIR/'"
    record file "$ZEN_INSTALL_DIR"
    clean_tmp "$tmp"
    ok "Installed the Zen browser"
  fi

  as_root ln -sfn "$ZEN_INSTALL_DIR/zen" /usr/local/bin/zen
  record symlink /usr/local/bin/zen
  record file /usr/share/applications/app.zen_browser.zen.desktop
  as_root tee /usr/share/applications/app.zen_browser.zen.desktop >/dev/null <<EOF
[Desktop Entry]
Name=Zen Browser
GenericName=Web Browser
Exec=$ZEN_INSTALL_DIR/zen %u
Icon=$ZEN_INSTALL_DIR/browser/chrome/icons/default/default128.png
Type=Application
Categories=Network;WebBrowser;
StartupWMClass=zen
StartupNotify=true
MimeType=text/html;text/xml;application/xhtml+xml;x-scheme-handler/http;x-scheme-handler/https;

[Desktop Action new-private-window]
Name=New Private Window
Exec=$ZEN_INSTALL_DIR/zen --private-window %u
EOF
  ok "Zen now appears in the app launcher"
}

install_helium() {
  if [[ -x $HELIUM_INSTALL_DIR/helium ]]; then
    skip "The Helium browser is already installed"; return 0
  fi
  local tmp; tmp=$(mktemp -d)
  local url; url=$(curl -fsSL https://api.github.com/repos/imputnet/helium-linux/releases/latest 2>/dev/null \
    | grep -oP '"browser_download_url":\s*"\K[^"]*x86_64[^"]*\.tar\.xz' | head -1)
  if [[ -z $url ]] || ! retry 3 curl -fL --progress-bar -o "$tmp/helium.tar.xz" "$url"; then
    clean_tmp "$tmp"; soft_fail "Could not download the Helium browser" "The download failed." "./install.sh --only=apps"; return 0
  fi
  as_root mkdir -p "$HELIUM_INSTALL_DIR"
  as_root tar -xf "$tmp/helium.tar.xz" -C "$HELIUM_INSTALL_DIR" --strip-components=1
  as_root ln -sfn "$HELIUM_INSTALL_DIR/helium" /usr/local/bin/helium
  record file "$HELIUM_INSTALL_DIR"
  record symlink /usr/local/bin/helium
  clean_tmp "$tmp"
  ok "Installed the Helium browser"
}

# Install an application from the .rpm its own project publishes. Preferred
# over Flatpak: the app then shares the system font and theme, is visible to
# XDG mime handling without portal wiring, and matugen can write into its
# config directly.
#
#   install_github_rpm <owner/repo> <asset regex> <binary> <display name>
install_github_rpm() {
  local repo=$1 pattern=$2 binary=$3 label=$4

  if rpm -q --whatprovides "$binary" >/dev/null 2>&1 || have "$binary"; then
    skip "$label is already installed"
    return 0
  fi
  if (( DRY_RUN )); then
    info "Would install the newest $label"
    return 0
  fi

  local url
  url=$(curl -fsSL --max-time 30 "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null \
        | grep -oiE '"browser_download_url":[[:space:]]*"[^"]+"' \
        | cut -d'"' -f4 \
        | grep -iE "$pattern" \
        | head -1)

  if [[ -z $url ]]; then
    soft_fail "Could not find an installer for $label" \
              "Its newest release does not contain a Fedora package." \
              "Download it yourself from github.com/$repo/releases"
    return 0
  fi

  local tmp; tmp=$(mktemp -d)
  if retry 3 curl -fL --progress-bar -o "$tmp/pkg.rpm" "$url"; then
    record_rpm_file "$tmp/pkg.rpm"
    as_root dnf install -y "$tmp/pkg.rpm" && ok "Installed $label" \
      || soft_fail "Downloaded $label but it would not install" "" "./install.sh --only=apps"
  else
    soft_fail "Could not download $label" "The download from GitHub failed." "./install.sh --only=apps"
  fi
  clean_tmp "$tmp"
}

install_app_configs() {
  local a="$REPO_DIR/config/apps"
  is_selected vesktop     && deploy_tree "$a/vesktop"     "$HOME/.config/vesktop"
  is_selected obs         && deploy_tree "$a/obs-studio"  "$HOME/.config/obs-studio"
  is_selected qbittorrent && deploy_tree "$a/qbittorrent" "$HOME/.config/qBittorrent"
  is_selected easyeffects && deploy_tree "$a/easyeffects" "$HOME/.config/easyeffects"
  is_selected cliamp      && deploy_tree "$REPO_DIR/config/tools/cliamp" "$HOME/.config/cliamp"
  ok "Copied the settings for your apps into place"
}

# Written rather than copied: the captured mimeapps.list points at Gwenview,
# Okular, Kate, Ark, mpv and a userapp-Zen stub, none of which this install has.
write_mimeapps() {
  local f="$HOME/.config/mimeapps.list"
  backup_path "$f"
  (( DRY_RUN )) && { info "Would set which app opens which kind of file"; return 0; }

  local image=org.kde.dolphin.desktop pdf=app.zen_browser.zen.desktop
  local text=nvim.desktop
  have gwenview && image=org.kde.gwenview.desktop
  have okular   && pdf=okularApplication_pdf.desktop
  [[ -f /usr/share/applications/nvim.desktop ]] || text=org.kde.kwrite.desktop
  [[ -f /usr/share/applications/$text ]] || text=app.zen_browser.zen.desktop

  {
    cat <<EOF
# Generated by fedora-nothing. Rerun the installer after adding an application
# to have it considered here.
[Default Applications]
x-scheme-handler/http=app.zen_browser.zen.desktop
x-scheme-handler/https=app.zen_browser.zen.desktop
x-scheme-handler/about=app.zen_browser.zen.desktop
x-scheme-handler/unknown=app.zen_browser.zen.desktop
text/html=app.zen_browser.zen.desktop
application/xhtml+xml=app.zen_browser.zen.desktop
application/x-extension-htm=app.zen_browser.zen.desktop
application/x-extension-html=app.zen_browser.zen.desktop
application/x-extension-xhtml=app.zen_browser.zen.desktop

inode/directory=org.kde.dolphin.desktop
x-scheme-handler/file=org.kde.dolphin.desktop

x-scheme-handler/terminal=kitty.desktop
application/x-shellscript=$text
text/plain=$text
text/markdown=$text

application/pdf=$pdf
image/png=$image
image/jpeg=$image
image/gif=$image
image/webp=$image
image/svg+xml=$image
image/bmp=$image
image/tiff=$image
EOF
    # Video and audio had no handler at all until these two arrived, so a
    # double-clicked film opened in whatever the desktop guessed.
    if is_selected mpv; then
      printf 'video/mp4=mpv.desktop\nvideo/x-matroska=mpv.desktop\nvideo/webm=mpv.desktop\n'
      printf 'video/quicktime=mpv.desktop\nvideo/x-msvideo=mpv.desktop\nvideo/mpeg=mpv.desktop\n'
      printf 'video/x-flv=mpv.desktop\nvideo/ogg=mpv.desktop\n'
    fi
    if is_selected strawberry; then
      local sb=org.strawberrymusicplayer.strawberry.desktop
      printf 'audio/mpeg=%s\naudio/flac=%s\naudio/x-vorbis+ogg=%s\naudio/x-wav=%s\naudio/mp4=%s\naudio/opus=%s\n' \
        "$sb" "$sb" "$sb" "$sb" "$sb" "$sb"
    elif is_selected mpv; then
      printf 'audio/mpeg=mpv.desktop\naudio/flac=mpv.desktop\naudio/x-wav=mpv.desktop\n'
    fi
    is_selected vesktop     && echo "x-scheme-handler/discord=dev.vencord.Vesktop.desktop"
    is_selected qbittorrent && printf 'application/x-bittorrent=org.qbittorrent.qBittorrent.desktop\nx-scheme-handler/magnet=org.qbittorrent.qBittorrent.desktop\n'
    is_selected obsidian    && echo "x-scheme-handler/obsidian=md.obsidian.Obsidian.desktop"
    :
  } > "$f"
  ok "Chose which app opens which kind of file"

  have update-desktop-database && run update-desktop-database "$HOME/.local/share/applications" 2>/dev/null
  run xdg-settings set default-web-browser app.zen_browser.zen.desktop 2>/dev/null \
    || warn "Could not make Zen the default browser automatically; set it in Zen's own settings"
  run xdg-mime default org.kde.dolphin.desktop inode/directory 2>/dev/null
  # Dolphin, Ark and friends read the plasma-prefixed menu, which only exists
  # once kbuildsycoca6 has run against this session's XDG_MENU_PREFIX.
  have kbuildsycoca6 && run kbuildsycoca6 --noincremental 2>/dev/null
  ok "Zen opens links, Dolphin opens folders, kitty opens terminals"
}
