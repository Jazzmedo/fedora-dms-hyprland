# shellcheck shell=bash
# Default applications and the XDG associations that route files to them.

ZEN_INSTALL_DIR=/opt/zen
MATUGENFOX_DIR="$HOME/.local/share/matugenfox"
MATUGENFOX_XPI_DIR=/usr/local/share/matugenfox
HELIUM_INSTALL_DIR=/opt/helium

stage_apps() {
  if is_selected term_kitty; then
    local k="$REPO_DIR/config/terminal/kitty"
    deploy_tree "$k" "$HOME/.config/kitty"
    # kitty.conf includes both of these unconditionally, so they have to exist,
    # but the desktop shell rewrites them on every theme change. Seeded once.
    deploy_seed "$k/seed/dank-theme.conf" "$HOME/.config/kitty/dank-theme.conf"
    deploy_seed "$k/seed/dank-tabs.conf"  "$HOME/.config/kitty/dank-tabs.conf"
    ok "Set up the kitty terminal"
  fi

  if is_selected term_foot; then
    deploy_tree "$REPO_DIR/config/terminal/foot" "$HOME/.config/foot"
    # foot.ini includes the DMS palette and foot will not start without it;
    # matugen replaces this seed on the first theme change.
    deploy_seed "$REPO_DIR/config/terminal/foot/seed/dms-colors.ini" "$HOME/.config/foot/dms-colors.ini"
    # foot 1.26 renamed [colors] to [colors-dark] and warns on every start
    # about the old name; 1.25 and older reject the new one. Fedora 43 ships
    # 1.24 and Fedora 44 1.26, so follow whichever is installed.
    local fv; fv=$(foot --version 2>/dev/null | awk '{print $3}')
    if [[ -n $fv && $(printf '%s\n' 1.26 "$fv" | sort -V | head -1) == 1.26 ]]; then
      run sed -i 's/^\[colors\]$/[colors-dark]/' \
        "$HOME/.config/matugen/templates/foot-dms.ini" "$HOME/.config/foot/dms-colors.ini"
    fi
    ok "Set up the foot terminal"
  fi

  # A fixed audio buffer: stops crackling when apps pick tiny ones under load.
  deploy_tree "$REPO_DIR/config/apps/pipewire" "$HOME/.config/pipewire"

  is_selected zen      && { install_zen; ensure_zen_profile; }
  is_selected zen      && enable_user_stylesheets
  is_selected zen && is_selected zen_sites && install_zen_site_theming
  is_selected helium   && { install_helium; write_helium_desktop; }
  is_selected vesktop  && install_github_rpm Vencord/Vesktop  'vesktop.*\.x86_64\.rpm$' vesktop  Vesktop
  is_selected obsidian && install_github_rpm obsidianmd/obsidian-releases 'obsidian-[0-9.]+\.rpm$' obsidian Obsidian
  install_app_configs
  is_selected spicetify && install_spicetify_theme
  write_mimeapps
  # Last, so every browser is installed and can be started once if needed.
  [[ -n $BROWSER_BACKUP ]] && bp_restore_for_install "$BROWSER_BACKUP"
  return 0
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

  # Owned by you so Zen's own updater can replace its files: a root-owned
  # /opt/zen never updates. Runs on every pass, so older installs get it too.
  as_root chown -R "$USER:$(id -gn)" "$ZEN_INSTALL_DIR"
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

# The theme stage runs before Zen is installed, so on a first install Zen has
# no profile and the colour generator's config leaves it out. One headless
# start creates the profile; the config is then rebuilt with Zen in it and, if
# the desktop shell is running, the colours are generated straight away.
ensure_zen_profile() {
  (( DRY_RUN )) && return 0
  [[ -d $(detect_zen_profile) ]] && return 0
  info "Starting Zen once in the background to create its profile"
  timeout 25 "$ZEN_INSTALL_DIR/zen" --headless about:blank >/dev/null 2>&1 || true
  if [[ ! -d $(detect_zen_profile) ]]; then
    warn "Zen did not create a profile; open it once, then run ./install.sh --only=themes,apps"
    return 0
  fi
  install_matugen_config
  local mode
  mode=$(dms ipc call theme getMode 2>/dev/null) && [[ $mode == dark || $mode == light ]] \
    && dms ipc call theme "$mode" >/dev/null 2>&1 \
    && ok "Generated Zen's colours from your current theme"
  return 0
}

# Websites in Zen take their colours from the DMS palette. Catppuccin's
# userstyles are rebuilt with the current theme whenever it changes, and a
# patched MatugenFox extension injects them. Zen installs the extension itself
# through an enterprise policy, with website theming already switched on, and
# the extension checks Catppuccin for new styles each time the browser opens.
install_zen_site_theming() {
  local src="$REPO_DIR/assets/matugenfox"
  if (( DRY_RUN )); then
    info "Would colour websites in Zen from your theme"
    return 0
  fi
  if ! have node || ! have npm || ! have zip; then
    soft_fail "Websites in Zen will not follow the theme" \
              "Node.js or zip is missing, and the styles are built with them." \
              "sudo dnf install nodejs npm zip && ./install.sh --only=apps"
    return 0
  fi

  # Copied rather than deployed as a tree: nothing here is a template, and
  # the build dependencies are installed into it afterwards.
  run mkdir -p "$MATUGENFOX_DIR"
  run cp -a "$src/." "$MATUGENFOX_DIR/"
  run chmod +x "$MATUGENFOX_DIR/matugenfox_host.py" "$MATUGENFOX_DIR"/tools/userstyles/*.sh
  record file "$MATUGENFOX_DIR"
  if ! (cd "$MATUGENFOX_DIR/tools/userstyles" && run npm ci --omit=dev --no-audit --no-fund); then
    soft_fail "Could not install the website style builder" "npm could not fetch less and postcss." \
              "./install.sh --only=apps"
    return 0
  fi

  # Only ~/.mozilla. Never create ~/.zen: Zen takes an existing ~/.zen as its
  # profile folder and would open a brand-new empty profile from it. It is
  # written to only when the browser already keeps its profiles there.
  local host_manifest nm
  host_manifest=$(printf '{\n  "name": "matugenfox",\n  "description": "MatugenFox Native Messaging Host",\n  "path": "%s",\n  "type": "stdio",\n  "allowed_extensions": ["matugenfox@ubaid.com"]\n}\n' \
    "$MATUGENFOX_DIR/matugenfox_host.py")
  for nm in "$HOME/.mozilla/native-messaging-hosts" "$HOME/.zen/native-messaging-hosts"; do
    [[ $nm == "$HOME/.zen/"* && ! -d $HOME/.zen ]] && continue
    run mkdir -p "$nm"
    printf '%s' "$host_manifest" > "$nm/matugenfox.json"
    record file "$nm/matugenfox.json"
  done

  # Settings the extension reads through its host, website theming switched on.
  local cfg="$HOME/.config/matugenfox/config.json"
  run mkdir -p "${cfg%/*}"
  [[ -f $cfg ]] || { printf '{}\n' > "$cfg"; record file "$cfg"; }
  json_edit "$cfg" 'data.update(webThemeEnabled=True, browserThemeEnabled=True, ecoMode=False, websitesDir="",
    userstylesDir="~/.cache/matugenfox/userstyles",
    colorsPath=data.get("colorsPath") or "~/.config/matugen/generated/firefox_websites.css")'

  # The extension is built here and not signed by Mozilla, which Zen accepts
  # once signature checks are off. The version is in the file name so a newer
  # build replaces the installed one.
  local version xpi tmp
  version=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$MATUGENFOX_DIR/extension/manifest.json")
  xpi="$MATUGENFOX_XPI_DIR/matugenfox-dms-$version.xpi"
  tmp=$(mktemp -d)
  (cd "$MATUGENFOX_DIR/extension" && zip -q -r -X "$tmp/matugenfox.xpi" .)
  as_root mkdir -p "$MATUGENFOX_XPI_DIR"
  as_root install -m 644 "$tmp/matugenfox.xpi" "$xpi"
  record file "$MATUGENFOX_XPI_DIR"
  clean_tmp "$tmp"

  if [[ -d $ZEN_INSTALL_DIR/defaults/pref ]]; then
    printf '// Added by fedora-nothing: allows the locally built MatugenFox extension.\npref("xpinstall.signatures.required", false);\n' \
      | as_root tee "$ZEN_INSTALL_DIR/defaults/pref/matugenfox.js" >/dev/null
    record file "$ZEN_INSTALL_DIR/defaults/pref/matugenfox.js"
  fi
  # A Zen run from an AppImage cannot be changed in place; its existing profile
  # gets the same preference instead.
  local profile; profile=$(detect_zen_profile)
  if [[ -d $profile ]] && ! grep -qs 'xpinstall.signatures.required' "$profile/user.js"; then
    printf '\n// Added by fedora-nothing: allows the locally built MatugenFox extension.\nuser_pref("xpinstall.signatures.required", false);\n' >> "$profile/user.js"
    record edited "$profile/user.js"
  fi

  merge_policy /etc/zen/policies/policies.json "$(printf '{"policies":{"ExtensionSettings":{"matugenfox@ubaid.com":{"installation_mode":"normal_installed","install_url":"file://%s"}}}}' "$xpi")"
  record file /etc/zen/policies/policies.json
  ok "Zen installs the website theming extension by itself on its next start"

  # First build now; without a theme yet it simply runs again after the first
  # theme change or browser launch.
  MATUGENFOX_UPDATE_INTERVAL=0 run bash "$MATUGENFOX_DIR/tools/userstyles/update.sh" \
    && ok "Built the website styles from your current theme" \
    || warn "The website styles will be built after your first theme change"
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

# Helium's tarball has no launcher entry, so without this it was missing from
# the app launcher and could not be made the default browser.
write_helium_desktop() {
  [[ -x $HELIUM_INSTALL_DIR/helium ]] || return 0
  local icon=$HELIUM_INSTALL_DIR/product_logo_256.png
  [[ -f $icon ]] || icon=web-browser
  record file /usr/share/applications/helium.desktop
  as_root tee /usr/share/applications/helium.desktop >/dev/null <<EOF
[Desktop Entry]
Name=Helium
GenericName=Web Browser
Exec=$HELIUM_INSTALL_DIR/helium %U
Icon=$icon
Type=Application
Categories=Network;WebBrowser;
StartupWMClass=helium
StartupNotify=true
MimeType=text/html;text/xml;application/xhtml+xml;x-scheme-handler/http;x-scheme-handler/https;
Actions=new-window;new-private-window;

[Desktop Action new-window]
Name=New Window
Exec=$HELIUM_INSTALL_DIR/helium

[Desktop Action new-private-window]
Name=New Incognito Window
Exec=$HELIUM_INSTALL_DIR/helium --incognito
EOF
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

  local image=org.kde.dolphin.desktop pdf=$TPL_BROWSER_DESKTOP
  local text=nvim.desktop
  have gwenview && image=org.kde.gwenview.desktop
  have okular   && pdf=okularApplication_pdf.desktop
  [[ -f /usr/share/applications/nvim.desktop ]] || text=org.kde.kwrite.desktop
  [[ -f /usr/share/applications/$text ]] || text=$TPL_BROWSER_DESKTOP

  {
    cat <<EOF
# Generated by fedora-nothing. Rerun the installer after adding an application
# to have it considered here.
[Default Applications]
x-scheme-handler/http=$TPL_BROWSER_DESKTOP
x-scheme-handler/https=$TPL_BROWSER_DESKTOP
x-scheme-handler/about=$TPL_BROWSER_DESKTOP
x-scheme-handler/unknown=$TPL_BROWSER_DESKTOP
text/html=$TPL_BROWSER_DESKTOP
application/xhtml+xml=$TPL_BROWSER_DESKTOP
application/x-extension-htm=$TPL_BROWSER_DESKTOP
application/x-extension-html=$TPL_BROWSER_DESKTOP
application/x-extension-xhtml=$TPL_BROWSER_DESKTOP

inode/directory=org.kde.dolphin.desktop
x-scheme-handler/file=org.kde.dolphin.desktop

x-scheme-handler/terminal=$TPL_TERMINAL.desktop
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
  local browser=${COMPONENT_NAME[${DEFAULT_BROWSER:-zen}]}
  run xdg-settings set default-web-browser "$TPL_BROWSER_DESKTOP" 2>/dev/null \
    || warn "Could not make $browser the default browser automatically; set it in its own settings"
  run xdg-mime default org.kde.dolphin.desktop inode/directory 2>/dev/null
  # Dolphin, Ark and friends read the plasma-prefixed menu, which only exists
  # once kbuildsycoca6 has run against this session's XDG_MENU_PREFIX.
  have kbuildsycoca6 && run kbuildsycoca6 --noincremental 2>/dev/null
  ok "$browser opens links, Dolphin opens folders, $TPL_TERMINAL opens terminals"
}

# The matugen templates write userChrome.css and userContent.css into the
# browser profile, and every Firefox-derived browser ignores both unless this
# preference is on. Nothing in this repository set it, so a fresh install had
# the generated files and no theming at all.
#
# Written the two ways the extension preference above is: into the tarball's
# own defaults, which survive a profile reset, and into an existing profile,
# for an AppImage install that cannot be changed in place.
enable_user_stylesheets() {
  local pref='toolkit.legacyUserProfileCustomizations.stylesheets'

  if (( DRY_RUN )); then
    info "Would let the browser load the generated colours"
    return 0
  fi

  if [[ -d $ZEN_INSTALL_DIR/defaults/pref ]]; then
    printf '// Added by fedora-nothing: load the generated userChrome/userContent styles.\npref("%s", true);\n' "$pref" \
      | as_root tee "$ZEN_INSTALL_DIR/defaults/pref/fedora-nothing-userchrome.js" >/dev/null
    record file "$ZEN_INSTALL_DIR/defaults/pref/fedora-nothing-userchrome.js"
  fi

  # Only an existing profile. Never create one: detect_zen_profile falls back
  # to ~/.zen/default, and making that directory gives Zen a brand-new empty
  # profile to open instead of the real one.
  local profile; profile=$(detect_zen_profile)
  if [[ ! -d $profile ]]; then
    info "The browser has no profile yet; re-run ./install.sh --only=themes,apps after its first start"
    return 0
  fi
  if ! grep -qs "$pref" "$profile/user.js"; then
    backup_path "$profile/user.js"
    printf '\n// Added by fedora-nothing: load the generated userChrome/userContent styles.\nuser_pref("%s", true);\n' \
      "$pref" >> "$profile/user.js"
  fi
  ok "The browser will load the generated colours"
}

# Spotify's colours come from the matugen template; spicetify is what puts
# them into Spotify. Nothing here installs Spotify or spicetify: without them
# this is a no-op, and the matugen fragment is left out of config.toml too.
install_spicetify_theme() {
  spicetify_present || { skip "Spotify colour theming needs spicetify, which is not installed"; return 0; }

  local cfg="$HOME/.config/spicetify/config-xpui.ini"
  [[ -f $cfg ]] || { skip "spicetify has not been set up yet, so Spotify keeps its own colours"; return 0; }

  # The theme directory has to exist before spicetify will accept the name,
  # and matugen has not written a palette yet on a first install. Seeded once
  # with Spotify's own colours; every theme change afterwards rewrites it.
  deploy_seed "$REPO_DIR/config/apps/spicetify/seed/color.ini" \
              "$HOME/.config/spicetify/Themes/dms/color.ini"
  record file "$HOME/.config/spicetify/Themes/dms"

  if grep -qE '^[[:space:]]*current_theme[[:space:]]*=[[:space:]]*dms[[:space:]]*$' "$cfg" \
  && grep -qE '^[[:space:]]*color_scheme[[:space:]]*=[[:space:]]*dms[[:space:]]*$'  "$cfg"; then
    skip "Spotify already follows your desktop colours"
    return 0
  fi

  if (( DRY_RUN )); then
    info "Would point Spotify at your desktop colours"
    return 0
  fi

  backup_path "$cfg"
  if ! run spicetify config current_theme dms color_scheme dms; then
    soft_fail "Could not point Spotify at your colours" \
              "spicetify would not accept the theme name." \
              "spicetify config current_theme dms color_scheme dms && spicetify apply"
    return 0
  fi

  # apply, not refresh, and only this once: the first switch rewrites the files
  # inside Spotify's own installation, which needs the app restarted. Every
  # later theme change is a refresh, which reloads a running Spotify in place.
  if run spicetify apply; then
    ok "Spotify now follows your desktop colours"
  else
    soft_fail "Spotify's own files could not be patched" \
              "Its installation directory stays root-owned until spicetify is allowed to write there." \
              "sudo chmod a+wr /usr/share/spotify && sudo chmod a+wr -R /usr/share/spotify/Apps && spicetify backup apply"
  fi
}
