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

  is_selected zen      && install_zen
  is_selected helium   && { install_helium; write_helium_desktop; }
  theme_browsers
  is_selected zen && is_selected zen_sites && install_zen_site_theming
  is_selected vesktop  && install_github_rpm Vencord/Vesktop  'vesktop.*\.x86_64\.rpm$' vesktop  Vesktop
  is_selected obsidian && install_github_rpm obsidianmd/obsidian-releases 'obsidian-[0-9.]+[^"]*\.rpm$' obsidian Obsidian
  is_selected shelltint && install_shelltint
  is_selected nothingwidgets && install_nothing_widgets
  install_app_configs
  is_selected spicetify && install_spicetify_theme
  write_mimeapps
  prefer_kde_app_chooser
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

# Every installed browser's own interface follows the DMS palette, and a theme
# change shows the next time it starts.
#
# Zen, Firefox and LibreWolf load the userChrome.css and userContent.css that
# matugen writes into their profile. The theme stage runs before the browsers
# are installed, so a browser that has never run has no profile for them yet:
# one headless start creates it, and the colour config is rebuilt with it.
#
# Chromium-based browsers cannot load a stylesheet. They are switched to the
# system theme instead, which DMS recolours on every theme change: Qt for Brave
# and Brave Origin, GTK for the others.
theme_browsers() {
  (( DRY_RUN )) && { info "Would theme the browsers from your DMS colours"; return 0; }
  local k new=0 names=()
  for k in "${BP_BROWSERS[@]}"; do
    is_selected "$k" || continue
    if [[ $(bp_engine "$k") == gecko ]]; then
      if ! gecko_profile "$k" >/dev/null; then
        if [[ $k == zen ]]; then
          info "Starting Zen once in the background to create its profile"
          timeout 25 "$ZEN_INSTALL_DIR/zen" --headless about:blank >/dev/null 2>&1 || true
        else
          bp_first_run "$k"
        fi
        if ! gecko_profile "$k" >/dev/null; then
          warn "$(bp_name "$k") did not create a profile; open it once, then run ./install.sh --only=themes,apps"
          continue
        fi
        new=1
      fi
      enable_user_stylesheets "$k"
    else
      chromium_follow_system "$k" || continue
    fi
    names+=("$(bp_name "$k")")
  done
  if (( new )); then
    install_matugen_config
    local mode
    mode=$(dms ipc call theme getMode 2>/dev/null) && [[ $mode == dark || $mode == light ]] \
      && dms ipc call theme "$mode" >/dev/null 2>&1
  fi
  (( ${#names[@]} )) && ok "Following your DMS colours from their next start: $(printf '%s, ' "${names[@]}" | sed 's/, $//')"
  return 0
}

# Zen's profile is found the way the colour config finds it; the others
# through profiles.ini.
gecko_profile() {
  local p
  if [[ $1 == zen ]]; then
    p=$(detect_zen_profile)
    [[ -d $p ]] && printf '%s' "$p"
  else
    bp_profile "$1"
  fi
}

# Chromium keeps the choice in its Preferences file, which it rewrites on exit,
# so this only touches a browser that is closed. system_theme 1 is GTK and 2 is
# Qt; clearing the theme id drops a Web Store theme that would cover it.
chromium_follow_system() {
  local k=$1 p name; name=$(bp_name "$k")
  p=$(bp_profile "$k") || { bp_first_run "$k"; p=$(bp_profile "$k"); } || return 1
  if bp_running "$k"; then
    warn "$name is open, so it was not switched to your DMS colours; close it and run ./install.sh --only=apps"
    return 1
  fi
  local mode=1
  [[ $k == brave || $k == brave_origin ]] && mode=2
  [[ -f $p/Preferences ]] && backup_path "$p/Preferences"
  python3 - "$p/Preferences" "$mode" <<'PY'
import json, sys
f, mode = sys.argv[1], int(sys.argv[2])
try:
    d = json.load(open(f))
except (OSError, ValueError):
    d = {}
d.setdefault('extensions', {}).setdefault('theme', {}).update(id='', system_theme=mode)
d.setdefault('browser', {}).setdefault('theme', {})['follows_system_colors'] = True
json.dump(d, open(f, 'w'))
PY
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
  # `|| true` on purpose: pipefail turns grep's SIGPIPE (head leaves after the
  # first match) or a failed API call into a failed assignment, and set -e
  # would end the stage before the message below could run. Whatever made it
  # through is still captured; empty means the same thing either way.
  local url; url=$(curl -fsSL https://api.github.com/repos/imputnet/helium-linux/releases/latest 2>/dev/null \
    | grep -oP '"browser_download_url":\s*"\K[^"]*x86_64[^"]*\.tar\.xz' | head -1) || true
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
  # `|| true` for the same reason as the Helium download above: pipefail plus
  # head's early exit can fail this assignment on a release with several
  # matching assets, and the message below is the better answer to an empty
  # url than a silent stage death.
  url=$(curl -fsSL --max-time 30 "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null \
        | grep -oiE '"browser_download_url":[[:space:]]*"[^"]+"' \
        | cut -d'"' -f4 \
        | grep -iE "$pattern" \
        | head -1) || true

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

# The ShellTint add-on talks to a native messaging helper; the helper comes
# from the user's own repository. Its installer registers the manifest for
# Firefox-family browsers (~/.mozilla, which Zen reads) and for Chromium
# browsers whose folders already exist, then builds the website styles once.
# The gitea certificate is a home-LAN one the VM has not met, so this one
# clone is pinned to skipping that check.
install_shelltint() {
  local src="$HOME/.local/share/ShellTint"
  if [[ -x $HOME/.local/share/shelltint/host/shelltint_host.py ]] \
     && [[ -f $HOME/.mozilla/native-messaging-hosts/shelltint.json ]]; then
    skip "The ShellTint helper is already installed"
    return 0
  fi

  if [[ -d $src/.git ]]; then
    run git -C "$src" pull --ff-only || true
  elif run git -c http.sslVerify=false clone --depth 1 \
        https://git.home.internal/Jazzmedo/ShellTint.git "$src"; then
    ok "Downloaded the ShellTint helper"
  else
    soft_fail "Could not download the ShellTint helper" \
              "Its repository at git.home.internal could not be reached." \
              "git clone https://git.home.internal/Jazzmedo/ShellTint.git ~/.local/share/ShellTint && ~/.local/share/ShellTint/scripts/install.sh"
    return 0
  fi

  if run_visible bash "$src/scripts/install.sh"; then
    ok "Installed the ShellTint helper — the add-on connects to it on its next start"
  else
    soft_fail "The ShellTint helper did not install" \
              "Its installer needs python3 and node, and the network for the website styles." \
              "$src/scripts/install.sh"
  fi
}

# The Nothing Widgets are five desktop plugins shipped inside this
# repository, so a plain deploy puts each where DMS looks. A running shell
# only picks up new plugins after a restart; on a fresh install they load at
# the first login anyway. The pre-redesign single "nothingWidgets" plugin is
# removed from machines that ran an earlier version of this installer.
install_nothing_widgets() {
  local suite="nothingmedia nothingweather nothingbattery nothingcalendar nothingdatetime"
  local changed=0 p dest

  if [[ -d $HOME/.config/DankMaterialShell/plugins/nothingWidgets ]]; then
    run rm -rf "$HOME/.config/DankMaterialShell/plugins/nothingWidgets"
    record file "$HOME/.config/DankMaterialShell/plugins/nothingWidgets"
  fi

  for p in $suite; do
    dest="$HOME/.config/DankMaterialShell/plugins/$p"
    if [[ -f $dest/plugin.json ]] \
       && diff -rq "$REPO_DIR/config/shell-ui/DankMaterialShell/plugins/$p" "$dest" >/dev/null 2>&1; then
      continue
    fi
    deploy_tree "$REPO_DIR/config/shell-ui/DankMaterialShell/plugins/$p" "$dest"
    changed=1
  done

  if (( changed )); then
    ok "Installed the Nothing Widgets — add them in DMS's desktop widget editor"
    if have dms && pgrep -u "$USER" -x dms >/dev/null 2>&1; then
      run dms restart || true
    fi
  fi
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
  local last="$HOME/.config/fedora-nothing/mimeapps.generated"
  backup_path "$f"
  (( DRY_RUN )) && { info "Would set which app opens which kind of file"; return 0; }
  local gen; gen=$(mktemp)

  local image=$TPL_FILEMANAGER_DESKTOP pdf=$TPL_BROWSER_DESKTOP
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

inode/directory=$TPL_FILEMANAGER_DESKTOP
x-scheme-handler/file=$TPL_FILEMANAGER_DESKTOP

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
  } > "$gen"

  # GTK applications read a per-desktop list such as hyprland-mimeapps.list
  # before mimeapps.list, so one app could follow a choice another never saw.
  # Their entries are folded in, being the ones that were winning, and the
  # files removed: mimeapps.list stays the only answer.
  local desktop_lists=() d
  for d in hyprland niri kde; do
    [[ -f $HOME/.config/$d-mimeapps.list ]] && desktop_lists+=("$HOME/.config/$d-mimeapps.list")
  done

  # Your own choices survive a rerun. An entry is replaced only while it still
  # holds what the installer wrote last time (or is missing); one you changed,
  # in Mimic or in an app's "Open with", is kept.
  mkdir -p "${last%/*}"
  python3 - "$f" "$gen" "$last" "${desktop_lists[@]}" <<'PY'
import os, sys
f, gen, last, *desktop = sys.argv[1:]
def parse(path):
    secs, cur = {}, None
    try:
        lines = open(path).read().splitlines()
    except OSError:
        return secs
    for l in lines:
        l = l.strip()
        if not l or l.startswith('#'):
            continue
        if l.startswith('[') and l.endswith(']'):
            cur = secs.setdefault(l[1:-1], {})
        elif '=' in l and cur is not None:
            k, v = l.split('=', 1)
            cur[k.strip()] = v.strip()
    return secs
current = parse(f)
for p in desktop:
    for sec, kv in parse(p).items():
        current.setdefault(sec, {}).update(kv)
was_ours = os.path.exists(f) and 'Generated by fedora-nothing' in open(f).read(200)
previous = parse(last).get('Default Applications') if os.path.exists(last) else \
    (dict(current.get('Default Applications', {})) if was_ours else {})
defaults = current.setdefault('Default Applications', {})
for k, v in parse(gen)['Default Applications'].items():
    if k not in defaults or defaults[k] == previous.get(k):
        defaults[k] = v
with open(f, 'w') as out:
    out.write('# Written by fedora-nothing, which keeps any entry you change here, in\n'
              '# Mimic, or through an app\'s "Open with" on its next run.\n')
    for sec in ['Default Applications'] + [s for s in current if s != 'Default Applications']:
        out.write('[%s]\n' % sec)
        out.writelines('%s=%s\n' % kv for kv in current[sec].items())
        out.write('\n')
PY
  mv "$gen" "$last"
  for d in "${desktop_lists[@]}"; do backup_path "$d"; rm -f "$d"; done
  ok "Chose which app opens which kind of file, keeping the ones you had changed"

  have update-desktop-database && run update-desktop-database "$HOME/.local/share/applications" 2>/dev/null
  local browser=${COMPONENT_NAME[${DEFAULT_BROWSER:-zen}]}
  # Only when the merge kept the installer's browser: this would overwrite a
  # browser you chose yourself.
  if grep -qx "x-scheme-handler/https=$TPL_BROWSER_DESKTOP" "$f"; then
    run xdg-settings set default-web-browser "$TPL_BROWSER_DESKTOP" 2>/dev/null \
      || warn "Could not make $browser the default browser automatically; set it in its own settings"
  fi
  # Dolphin, Ark and friends read the plasma-prefixed menu, which only exists
  # once kbuildsycoca6 has run against this session's XDG_MENU_PREFIX.
  have kbuildsycoca6 && run kbuildsycoca6 --noincremental 2>/dev/null
  ok "$browser opens links, Dolphin opens folders, $TPL_TERMINAL opens terminals"
}

# Flatpak apps, and others that go through the desktop portal, do not read
# mimeapps.list: they ask the portal to open a file or link, and its "Open with"
# dialog comes from whichever backend answers AppChooser. The Hyprland portal
# has none, so this hands just that one interface to the KDE portal, whose
# dialog is Qt in the DMS colours and lists the same apps Dolphin does.
#
# Each session keeps everything else its own portals.conf says, screen sharing
# and the file picker included: the user copy below starts from the packaged
# one. niri's session calls itself KDE to its applications, so the portal reads
# kde-portals.conf there, and that gets niri's preferences plus this one line.
prefer_kde_app_chooser() {
  (( DRY_RUN )) && { info "Would show the KDE \"Open with\" dialog for portal apps"; return 0; }
  [[ -f /usr/share/xdg-desktop-portal/kde-portals.conf ]] \
    || { warn "The KDE portal is not installed, so portal apps keep the default \"Open with\" dialog"; return 0; }
  local dir="$HOME/.config/xdg-desktop-portal" sys=/usr/share/xdg-desktop-portal
  mkdir -p "$dir"
  _app_chooser_conf "$sys/hyprland-portals.conf" "$dir/hyprland-portals.conf" "hyprland;gtk"
  is_selected niri && _app_chooser_conf "$sys/niri-portals.conf" "$dir/kde-portals.conf" "gnome;gtk"
  systemctl --user try-restart xdg-desktop-portal.service 2>/dev/null || true
  ok "Apps that ask the desktop to open a file get the KDE \"Open with\" dialog"
}

_app_chooser_conf() {   # packaged-conf user-conf fallback-default
  backup_path "$2"
  {
    echo "# Written by fedora-nothing from ${1##*/}, plus the \"Open with\" dialog."
    if [[ -f $1 ]]; then
      grep -v -e '^#' -e 'impl.portal.AppChooser' "$1"
    else
      printf '[preferred]\ndefault=%s\n' "$3"
    fi
    echo "org.freedesktop.impl.portal.AppChooser=kde"
  } > "$2"
  record file "$2"
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
  local k=$1 pref='toolkit.legacyUserProfileCustomizations.stylesheets'

  if [[ $k == zen && -d $ZEN_INSTALL_DIR/defaults/pref ]]; then
    printf '// Added by fedora-nothing: load the generated userChrome/userContent styles.\npref("%s", true);\n' "$pref" \
      | as_root tee "$ZEN_INSTALL_DIR/defaults/pref/fedora-nothing-userchrome.js" >/dev/null
    record file "$ZEN_INSTALL_DIR/defaults/pref/fedora-nothing-userchrome.js"
  fi

  local profile; profile=$(gecko_profile "$k") || return 0
  if ! grep -qs "$pref" "$profile/user.js"; then
    backup_path "$profile/user.js"
    printf '\n// Added by fedora-nothing: load the generated userChrome/userContent styles.\nuser_pref("%s", true);\n' \
      "$pref" >> "$profile/user.js"
  fi
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
