# shellcheck shell=bash
# The component registry — the single source of truth.
#
# The picker, the dnf transaction, the config deploy, the matugen fragments and
# the DMS bar layout all read from here, so they cannot drift apart. To add a
# component, add one `component` call; nothing else needs to change.
#
#   component <key> <group> <default> <name> <description>
#
# `default` is on | off | base. A `base` component is always installed and is
# shown in the picker greyed out, so the operator can see what they are getting.

declare -A COMPONENT_NAME COMPONENT_DESC COMPONENT_GROUP COMPONENT_DEFAULT
declare -A COMPONENT_PKGS COMPONENT_FLATPAKS COMPONENT_COPR COMPONENT_PLUGIN
declare -A COMPONENT_DETECT
declare -A GROUP_LABEL SELECTED
COMPONENT_ORDER=()
COMPONENT_GROUPS=()

group() { COMPONENT_GROUPS+=("$1"); GROUP_LABEL[$1]=$2; }

component() {
  local key=$1 grp=$2 def=$3 name=$4 desc=$5
  COMPONENT_ORDER+=("$key")
  COMPONENT_GROUP[$key]=$grp
  COMPONENT_DEFAULT[$key]=$def
  COMPONENT_NAME[$key]=$name
  COMPONENT_DESC[$key]=$desc
  [[ $def == off ]] || SELECTED[$key]=1
}

# Attach payloads to the component declared immediately above.
pkgs()     { COMPONENT_PKGS[${COMPONENT_ORDER[-1]}]="$*"; }
flatpaks() { COMPONENT_FLATPAKS[${COMPONENT_ORDER[-1]}]="$*"; }
copr()     { COMPONENT_COPR[${COMPONENT_ORDER[-1]}]="$*"; }
dms_plugin() { COMPONENT_PLUGIN[${COMPONENT_ORDER[-1]}]="$*"; }

# How to tell whether this component is already on the machine. The default is
# "are its rpms installed", which is wrong whenever a component owns no rpms
# (Vesktop comes from a GitHub rpm) or owns them without being usable (zsh
# installed but never made the login shell). The snippet must print
# installed | partial | missing; `all_of` collapses a list of tests for you.
detect() { COMPONENT_DETECT[${COMPONENT_ORDER[-1]}]="$*"; }

# ------------------------------------------------------------- predicates ---
# The checklist works off these lists. A tool other than the installer swaps
# them for its own entries with this, then calls group/component again.
new_list() {
  COMPONENT_ORDER=(); COMPONENT_GROUPS=()
  unset SELECTED COMPONENT_STATE
  declare -gA SELECTED=() COMPONENT_STATE=()
  DETECT_COMPONENTS_READY=1
}

is_selected()      { [[ -n ${SELECTED[$1]:-} ]]; }
component_locked() { [[ ${COMPONENT_DEFAULT[$1]:-} == base ]]; }
select_component()   { SELECTED[$1]=1; }
deselect_component() { unset "SELECTED[$1]"; }
toggle_component() {
  component_locked "$1" && return 0
  if is_selected "$1"; then deselect_component "$1"; else select_component "$1"; fi
}
group_members() {
  local k
  for k in "${COMPONENT_ORDER[@]}"; do
    [[ ${COMPONENT_GROUP[$k]} == "$1" ]] && printf '%s\n' "$k"
  done
  return 0
}
selected_count() {
  local k n=0
  for k in "${COMPONENT_ORDER[@]}"; do
    component_locked "$k" && continue
    is_selected "$k" && (( ++n ))
  done
  printf '%d' "$n"
}

# Every rpm the selection implies, deduplicated.
selected_packages() {
  local k
  for k in "${COMPONENT_ORDER[@]}"; do
    is_selected "$k" || continue
    printf '%s\n' ${COMPONENT_PKGS[$k]:-}
  done | tr ' ' '\n' | grep -v '^$' | sort -u
}
selected_flatpaks() {
  local k
  for k in "${COMPONENT_ORDER[@]}"; do
    is_selected "$k" || continue
    printf '%s\n' ${COMPONENT_FLATPAKS[$k]:-}
  done | tr ' ' '\n' | grep -v '^$' | sort -u
}
# Declaration order matters here, unlike packages: the COPRs are candidates
# tried in preference order, so this deduplicates without sorting.
selected_coprs() {
  local k
  for k in "${COMPONENT_ORDER[@]}"; do
    is_selected "$k" || continue
    printf '%s\n' ${COMPONENT_COPR[$k]:-}
  done | tr ' ' '\n' | grep -v '^$' | awk '!seen[$0]++'
}

# =============================================================== REGISTRY ===

group base  "Base desktop — always installed"

# hyprlock backs the lock screen, hyprpicker the colour picker, cliphist the
# clipboard history, and grim/slurp the region screenshot. DMS drives all four
# over IPC but does not vendor them.
component core        base base "Hyprland + DMS"  "compositor, shell, lock, clipboard, screenshot, picker"
# Hyprland is not in Fedora proper, and no single COPR covers every release:
# solopasha builds for rawhide only, so it is unusable on a stable Fedora.
# These are tried in order and the first one with a chroot for this release
# wins. sdegler is first because it also carries matugen, hyprlock, hypridle,
# hyprpicker, hyprpaper, cliphist and qt6ct.
#
# quickshell is deliberately NOT listed. DankMaterialShell is written against a
# specific quickshell, its installer ships that build, and it skips doing so
# when any quickshell is already present. Letting dnf win that race installs a
# COPR build too old for the shell's QML, and the only symptom is the shell
# exiting 255 on an unrecognized pragma while every command reports success.
copr "sdegler/hyprland ashbuk/Hyprland-Fedora solopasha/hyprland"
pkgs "hyprland hyprland-devel hyprpaper hyprlock hypridle hyprpicker \
      xdg-desktop-portal-hyprland xdg-desktop-portal-gtk xdg-desktop-portal-kde xdg-utils \
      matugen sddm weston accountsservice \
      qt6-qtdeclarative qt6-qt5compat qt6-qtsvg qt6-qtmultimedia \
      polkit-kde qt6ct qt5ct kvantum \
      breeze-icon-theme hicolor-icon-theme adw-gtk3-theme kde-gtk-config \
      cmake meson ninja-build gcc-c++ pkgconf git curl jq \
      ImageMagick brightnessctl playerctl libnotify \
      wl-clipboard cliphist grim slurp wtype satty \
      NetworkManager NetworkManager-wifi nm-connection-editor \
      bluez blueman cargo \
      iwlwifi-dvm-firmware iwlwifi-mvm-firmware iwlwifi-mld-firmware iwlbluetooth-firmware"
# Fedora 44 split linux-firmware per vendor and the thin core package carries
# no radio firmware at all, nor recommends any: without these the Intel combo
# cards come up with no wlan interface and a Bluetooth controller stuck in
# bootloader mode. Harmless in a VM, which has no radio hardware to load them.
detect 'all_of "pkg_installed hyprland" "have quickshell" \
               "have dms" "[[ -f $HOME/.config/hypr/hyprland.lua ]]" \
               "[[ -f /usr/share/wayland-sessions/hyprland.desktop ]]"' 

component audio       base base "PipeWire"        "pipewire, wireplumber, pavucontrol"
pkgs "pipewire pipewire-pulseaudio pipewire-alsa pipewire-utils \
      wireplumber pavucontrol alsa-utils"
detect 'all_of "pkg_installed pipewire" "pkg_installed wireplumber" "pkg_installed pavucontrol"' 

component apps_base   base base "Files & mounts"  "gvfs mounts, thumbnails, secret storage — shared by both file managers"
# gvfs is what lets a file manager open a phone over MTP or a Samba/NFS share,
# and what gives GTK applications a working trash and mount view. tumbler
# generates Thunar's thumbnails; the KDE thumbnailers arrive with Dolphin.
pkgs "gvfs gvfs-mtp gvfs-smb gvfs-nfs gvfs-gphoto2 gvfs-archive gvfs-fuse libsecret zstd tumbler"
detect 'all_of "pkg_installed gvfs" \
               "[[ -f $HOME/.config/mimeapps.list ]]"'

# ---------------------------------------------------------------------------
# Tick one or both. With both, the installer asks which is the default:
# SUPER+E opens it, ALT+F the other one, and folders everywhere follow it.
group filemgr "File manager (one or both)"

component filemgr_thunar filemgr on  "Thunar"  "lightweight Xfce file manager; simple and fast, few dependencies"
pkgs "thunar thunar-archive-plugin"
detect 'all_of "pkg_installed thunar"'

component filemgr_dolphin filemgr off "Dolphin" "full-featured KDE file manager; heavier, pulls in KDE libraries"
# kio-extras is Dolphin's MTP/Samba/NFS support; the two thumbnailers render
# previews for images and video inside Dolphin's views.
pkgs "dolphin kf6-kio kf6-kservice kio-extras ffmpegthumbs kdegraphics-thumbnailers"
detect 'all_of "pkg_installed dolphin"'

# The rest of what a DE would install alongside its file manager. These are the
# apps the generated mimeapps.list and the Hyprland window rules already name
# as their fallbacks; without them those lines simply never fire.
component desktop_apps base base "Desktop utilities" "ark, gwenview, okular, kate, kcalc, filelight, satty"
pkgs "ark gwenview okular kate kcalc filelight satty"
detect 'all_of "pkg_installed ark" "pkg_installed gwenview" "pkg_installed okular" \
               "pkg_installed kate" "pkg_installed kcalc" "pkg_installed filelight" \
               "pkg_installed satty"'

# The daemons a desktop environment starts for you and this one would otherwise
# forget. upower feeds the DMS battery widget (and brings udisks2, which mounts
# removable drives); power-profiles-daemon feeds its power-profile OSD;
# firewalld is what Fedora's Standard group normally — but only normally —
# provides; and xdg-user-dirs makes Documents and Downloads exist on an
# install that never had a desktop to create them. dex used to run autostart
# entries here but is retired from Fedora; the one entry that matters, KDE
# Connect's daemon, starts through its own user unit instead.
component de_services base base "Desktop services" "upower, power profiles, firewall, standard folders"
pkgs "upower power-profiles-daemon firewalld xdg-user-dirs"
detect 'all_of "pkg_installed upower" "pkg_installed power-profiles-daemon" \
               "pkg_installed firewalld" \
               "pkg_installed xdg-user-dirs" "[[ -f $HOME/.config/user-dirs.dirs ]]"'

# libsecret is only the client library; without the service behind it, a
# browser that offers to save a password cannot keep it. The PAM half unlocks
# the keyring with the login password; stage_sddm wires that stack.
component keyring base base "Secret service" "gnome-keyring, unlocked at login; seahorse to manage it"
pkgs "gnome-keyring gnome-keyring-pam seahorse"
detect 'all_of "pkg_installed gnome-keyring" "grep -q pam_gnome_keyring /etc/pam.d/sddm"'

component fonts       base base "Nothing fonts"   "Ndot 55/57, NType 82, JetBrainsMono Nerd Font, Arabic faces"
pkgs "fontconfig google-noto-sans-fonts google-noto-emoji-fonts ibm-plex-sans-arabic-fonts"
detect 'all_of "fc-list | grep \"Ndot 57\" >/dev/null" \
               "fc-list | grep \"JetBrainsMono Nerd Font\" >/dev/null" \
               "fc-list | grep \"Kawkab Mono\" >/dev/null" \
               "[[ -f /etc/fonts/local.conf ]] && grep -q \"Kawkab Mono\" /etc/fonts/local.conf"' 

# ---------------------------------------------------------------------------
# Tick one or both. With both, the installer asks which is the default:
# SUPER+Return opens it, SUPER+SHIFT+Return the other one.
group terminal "Terminal (one or both)"

component term_foot   terminal on "foot"  "fast, minimal Wayland terminal; recoloured live on theme change"
pkgs "foot"
detect 'all_of "pkg_installed foot" "[[ -f $HOME/.config/foot/foot.ini ]]"'
component term_kitty  terminal on "kitty" "GPU terminal with tabs and a cursor trail"
pkgs "kitty"
detect 'all_of "pkg_installed kitty" "[[ -f $HOME/.config/kitty/kitty.conf ]]"'

group shell "Shell & development"

component zsh         shell on  "zsh + oh-my-zsh"  "zsh, oh-my-zsh, autosuggestions, syntax highlighting"
pkgs "zsh util-linux-user"
detect 'all_of "pkg_installed zsh" "[[ -d $HOME/.oh-my-zsh ]]" \
               "[[ -d $HOME/.config/zsh/zshrc.d ]]" \
               "[[ $(getent passwd \"$USER\" | cut -d: -f7) == */zsh ]]"' 

component prompt      shell on  "starship"         "prompt, matugen-themed from the DMS palette"
# Retired from Fedora; mise provides a current build instead.
detect 'all_of "have starship || [[ -d $HOME/.local/share/mise/installs/starship ]]" "[[ -f $HOME/.config/starship.toml ]]"'

component cli         shell on  "modern CLI tools" "eza, bat, ripgrep, fd, fzf, trash-cli, grc"
pkgs "eza bat ripgrep fd-find fzf trash-cli grc tree unzip p7zip p7zip-plugins"

component sysinfo     shell on  "btop · fastfetch · cava" "monitors, matugen-themed"
pkgs "btop fastfetch cava"

component filemgr_tui shell on  "yazi"             "terminal file manager"
# Retired from Fedora; mise provides a current build instead.
detect 'all_of "have yazi || [[ -d $HOME/.local/share/mise/installs/yazi ]]"'

component editor      shell on  "Neovim + LazyVim" "editor, plugins pinned by lazy-lock.json"
pkgs "neovim python3-neovim gcc make gettext"
detect 'all_of "pkg_installed neovim" "[[ -f $HOME/.config/nvim/init.lua ]]" \
               "[[ -d $HOME/.local/share/nvim/lazy ]]"' 

component mux         shell on  "tmux"             "terminal multiplexer, matugen-themed"
pkgs "tmux"
detect 'all_of "pkg_installed tmux" "[[ -d $HOME/.config/tmux ]]"' 

# ---------------------------------------------------------------------------
# Version managers, package managers and containers, one row each.
group dev "Development tools"

component mise        dev on  "mise"           "one version manager for Node, Python, Go, Rust, Java…"
detect 'all_of "have mise || [[ -x $HOME/.local/bin/mise ]]"'

component uv          dev off "uv"             "fast Python package and project manager"
pkgs "uv"

component pipx        dev off "pipx"           "Python command-line apps, each in its own environment"
pkgs "pipx"

component pnpm        dev off "pnpm"           "fast, disk-efficient Node package manager"
detect 'all_of "have pnpm || [[ -x $HOME/.local/bin/pnpm ]]"'

component rust        dev on  "Rust + cargo"   "rustup toolchain manager"
detect 'all_of "have cargo || [[ -x $HOME/.cargo/bin/cargo ]]"'

component golang      dev on  "Go"             "Go toolchain"
pkgs "golang"

component podman      dev on  "Podman"         "rootless containers, podman-compose"
pkgs "podman podman-compose"

component docker      dev off "Docker + Compose" "Docker Engine, docker compose and buildx, from Docker's repo"
pkgs "docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"
detect 'all_of "pkg_installed docker-ce" "pkg_installed docker-compose-plugin"'

component ytdlp       dev on  "yt-dlp"         "video and audio downloader, through mise; yt-dlp -U updates it"
detect 'all_of "[[ -d $HOME/.local/share/mise/installs/yt-dlp ]]"'

# ---------------------------------------------------------------------------
group ai "AI coding assistants"

component claude_code ai off "Claude Code"    "Anthropic's coding agent; updates itself"
detect 'all_of "[[ -x $HOME/.local/bin/claude ]]"'

component codex       ai off "Codex"          "OpenAI's coding agent, through mise"
detect 'all_of "[[ -d $HOME/.local/share/mise/installs/codex ]]"'

component opencode    ai off "OpenCode"       "open-source coding agent for any model, through mise"
detect 'all_of "[[ -d $HOME/.local/share/mise/installs/opencode ]]"'

component glm         ai off "GLM (Z.ai)"     "glm command: Claude Code on your Z.ai GLM Coding Plan"
detect 'all_of "[[ -x $HOME/.local/bin/glm ]]"'

# ---------------------------------------------------------------------------
# Tick one or more. With several, the installer asks which is the default: it
# opens links, and SUPER+B starts it.
group browsers "Browsers (one or more)"

component zen          browsers on  "Zen"          "Firefox-based, vertical tabs; tarball in /opt/zen"
detect 'all_of "[[ -x /opt/zen/zen ]]"'
component firefox      browsers off "Firefox"      "from Fedora"
pkgs "firefox"
component librewolf    browsers off "LibreWolf"    "privacy-hardened Firefox, third-party repo"
pkgs "librewolf"
component brave        browsers off "Brave"        "Chromium-based, third-party repo"
pkgs "brave-browser"
component brave_origin browsers on  "Brave Origin" "de-Googled Brave build, third-party repo"
pkgs "brave-origin"
component vivaldi      browsers off "Vivaldi"      "Chromium-based, third-party repo"
pkgs "vivaldi-stable"
component helium       browsers on  "Helium"       "Chromium fork, AppImage-free install to /opt"
detect 'all_of "[[ -x /opt/helium/helium ]]"'
component zen_sites   browsers on  "Zen site theming" "DMS colours on YouTube, GitHub, X and 130 more sites"
detect 'all_of "[[ -f $HOME/.mozilla/native-messaging-hosts/matugenfox.json ]]" \
               "[[ -d $HOME/.local/share/matugenfox/tools/userstyles/node_modules ]]" \
               "[[ -f /etc/zen/policies/policies.json ]] && grep -q matugenfox /etc/zen/policies/policies.json"' 
# node builds the styles; zip packs the extension.
pkgs "nodejs npm python3 zip curl"

# ---------------------------------------------------------------------------
group apps "Applications"

component vesktop     apps on  "Vesktop"      "Discord client, official rpm, matugen-themed"
detect 'all_of "have vesktop" "[[ -d $HOME/.config/vesktop ]]"' 

component qbittorrent apps on  "qBittorrent"  "torrent client"
pkgs "qbittorrent"

component obs         apps on  "OBS Studio"   "screen recording, matugen-themed"
pkgs "obs-studio"

component obsidian    apps on  "Obsidian"     "notes, official rpm, matugen-themed snippet"
detect 'all_of "have obsidian"' 

component cliamp      apps on  "CLIAMP"       "terminal music player + your cliamp-dms bar plugin"
detect 'all_of "have cliamp" "[[ -e $HOME/.config/DankMaterialShell/plugins/cliampDms ]]"' 
# ffprobe ships in ffmpeg-free; gjs and gdbus back the plugin's helper scripts,
# and alsa-lib-devel is what the player links against when Go builds it.
pkgs "curl ffmpeg-free gjs glib2 alsa-lib-devel"
dms_plugin "cliampDms"

component lyrics      apps on  "Lyrics on Panel" "your lyrics-on-panel fork plus its MPRIS backend"
detect 'all_of "[[ -e $HOME/.config/DankMaterialShell/plugins/lyricsOnPanel ]]" \
               "[[ -x $HOME/.local/share/lyrics-on-panel/backend/.venv/bin/python ]]"' 
# The backend is a Python service that reads MPRIS over D-Bus; dbus-devel and
# the compiler are needed because dbus-python builds from source.
pkgs "python3 python3-devel dbus-devel glib2-devel pkgconf gcc"
dms_plugin "lyricsOnPanel"

component shelltint   apps on  "ShellTint helper" "connects the ShellTint browser add-on to your desktop colours"
# The helper comes from the user's own ShellTint repository; the apps stage
# clones it and runs its installer, which registers native messaging for the
# Firefox-family browsers and, when their folders exist, Chromium ones too.
# node and npm usually arrive with the Zen site theming; listed here so the
# helper never depends on another component being ticked.
pkgs "nodejs npm"
detect 'all_of "[[ -x $HOME/.local/share/shelltint/host/shelltint_host.py ]]" \
               "[[ -f $HOME/.mozilla/native-messaging-hosts/shelltint.json ]]"'

component mpv         apps on  "mpv"          "video player; becomes the default for video files"
pkgs "mpv"

component strawberry  apps on  "Strawberry"   "music player for a local library, with a Qt interface"
pkgs "strawberry"

component easyeffects apps on  "EasyEffects"  "audio effects, Handfree/Normal presets"
pkgs "easyeffects"
detect 'all_of "pkg_installed easyeffects" "[[ -f $HOME/.config/easyeffects/output/Normal.json ]]"' 

# Theming only. This repository never installs Spotify or spicetify; it
# detects one. On a machine without spicetify the matugen fragment is left out
# of config.toml, the stage that switches Spotify over skips itself, and the
# refresh hook returns at its first guard -- so the component owes nothing,
# and its detector says so rather than reporting "missing" for ever.
component spicetify   apps on  "Spotify colours" "recolours Spotify from your theme, if you already use spicetify"
detect 'if spicetify_present; then all_of "[[ -f $HOME/.config/spicetify/Themes/dms/color.ini ]]" "grep -qE \"^[[:space:]]*current_theme[[:space:]]*=[[:space:]]*dms\" \"$HOME/.config/spicetify/config-xpui.ini\""; else printf installed; fi'

# Packaging preference is rpm first, then an upstream tarball or AppImage.
# Flatpak is only used where nothing else exists, so it is opt-in and the two
# apps that used to be flatpaks now come from their projects' own rpms.
component flatpak     apps off "Flatpak"      "Flathub support; only Gear Lever needs it"
pkgs "flatpak"

component gearlever   apps off "Gear Lever"   "manage AppImages as normal apps; requires Flatpak"
flatpaks "it.mijorus.gearlever"
detect 'all_of "flatpak_installed it.mijorus.gearlever"' 

component mimic       apps off "Mimic"        "change which app opens each file and link type; requires Flatpak"
flatpaks "io.github.arijanj.Mimic"
detect 'all_of "flatpak_installed io.github.arijanj.Mimic"'

# ---------------------------------------------------------------------------
group services "Services & sessions"

component tailscale   services off "Tailscale"      "mesh VPN, enables the dankscale bar plugin"
pkgs "tailscale"
detect 'all_of "pkg_installed tailscale" "systemctl is-enabled tailscaled"' 
dms_plugin "dankscale"

component warp        services off "Cloudflare WARP" "enables the warpToggle bar plugin"
pkgs "cloudflare-warp"
detect 'all_of "pkg_installed cloudflare-warp" "systemctl is-enabled warp-svc"'
dms_plugin "warpToggle"

# The daemon autostarts through its dms-kdeconnect.service user unit (Fedora
# retired dex, which used to run autostart entries), and the optional stage
# opens its firewall ports so pairing just works.
component kdeconnect  services off "KDE Connect" "pair your phone: notifications, clipboard, files; enables the Phone Connect plugin"
# Fedora renamed the package: the daemon now ships as kdeconnectd alone.
pkgs "kdeconnectd"
detect 'all_of "pkg_installed kdeconnectd"'
dms_plugin "dankKDEConnect"

component niri        services off "niri session"    "second Wayland session at the login screen"
pkgs "niri"
detect 'all_of "pkg_installed niri" "[[ -f $HOME/.config/niri/config.kdl ]]"' 

component splash      services on  "Boot splash"     "Nothing-styled loading screen instead of the boot text"
pkgs "plymouth plymouth-scripts plymouth-plugin-script"
detect 'all_of "[[ -f /usr/share/plymouth/themes/nothing/nothing.script ]]" \
               "[[ $(plymouth-set-default-theme 2>/dev/null) == nothing ]]"'

component tweaks      services off "System tweaks"   "search engine policy, mDNS resolution, writeback cap, Egyptian regional formats"
detect 'all_of "[[ -f /etc/sysctl.d/99-usb-copy-fix.conf ]]" \
               "grep -q mdns4_minimal /etc/nsswitch.conf" \
               "[[ -f /etc/zen/policies/policies.json ]]"'

component printing    services off "Printing & scanning" "cups, the KDE printer settings, skanpage"
pkgs "cups cups-filters system-config-printer sane-backends-drivers-scanners skanpage"
detect 'all_of "pkg_installed cups" "systemctl is-enabled cups"'

component firmware    services off "Firmware updates" "fwupd, with its refresh timer enabled"
pkgs "fwupd"
detect 'all_of "pkg_installed fwupd" "systemctl is-enabled fwupd-refresh.timer"'

component office      services off "Office"          "LibreOffice with the Arabic language pack"
pkgs "libreoffice libreoffice-langpack-ar"

component backups     services off "System snapshots" "timeshift: restore points for the whole disk"
pkgs "timeshift"

# The tool behind the SUPER+ALT+D draw-on-screen bind. No dnf package exists;
# the project publishes an rpm of its own, which install_github_rpm fetches.
component draw        services off "Draw on screen"  "wayscriber: annotate over anything on screen (SUPER+ALT+X)"
detect 'all_of "have wayscriber"'

# A screen driven at limited RGB range looks washed out, and Hyprland offers no
# way to change it: the range is a DRM connector property its backend leaves at
# the driver's automatic choice, and setting it from outside does not stick,
# because the compositor rewrites connector state on its next commit. So this
# builds a patched aquamarine from source and runs it through a second login
# entry. Off by default: it compiles a library, and most screens are fine.
#
# Only the link dependencies are listed. The compiler, cmake, ninja and git all
# arrive with `core`, which is always installed. The versionlock plugin is here
# rather than in `core` so that a machine which never picks this component is
# never in a position to hold packages back.
#
# See docs/aquamarine-rgb-full.md.
component aquamarine  services off "Full RGB colour fix" "rebuilds Hyprland's display backend so an external screen is not washed out"
pkgs "libdrm-devel mesa-libgbm-devel mesa-libEGL-devel libseat-devel libinput-devel \
      libdisplay-info-devel hwdata-devel wayland-devel pixman-devel \
      hyprutils-devel hyprwayland-scanner python3-dnf-plugin-versionlock"
# The third test names the staged library after the *installed* aquamarine, so
# an update that moves the package reports partial -- "built, but needs
# rebuilding" -- instead of a misleading installed.
detect 'all_of "[[ -x /usr/local/bin/hyprland-rgb-full ]]" \
               "[[ -f /usr/share/wayland-sessions/hyprland-rgb-full.desktop ]]" \
               "[[ -e /opt/aquamarine-rgb-full/lib64/libaquamarine.so.$(rpm -q --qf %{VERSION} aquamarine 2>/dev/null) \
                || -e /opt/aquamarine-rgb-full/lib/libaquamarine.so.$(rpm -q --qf %{VERSION} aquamarine 2>/dev/null) ]]"'

# ---------------------------------------------------------------------------
group layout "Tiling layout (pick one)"

component layout_scrolling layout on  "Scrolling"  "windows on an endless tape, Niri-style; what this config was built around"
component layout_dwindle   layout off "Dwindle"    "stock Hyprland binary split"

# Radio, like the graphics group. HYPR_LAYOUT is what the installer writes into
# quattro-state.lua; SUPER+SHIFT+L still toggles a single workspace either way.
select_layout() {
  local pick=$1
  deselect_component layout_scrolling; deselect_component layout_dwindle
  select_component "layout_$pick"
  HYPR_LAYOUT=$pick
}

# ---------------------------------------------------------------------------
group gpu "Graphics driver (detected, pick one)"

component gpu_amd     gpu off "AMD"    "mesa + RADV"
pkgs "mesa-dri-drivers mesa-vulkan-drivers libva-utils vulkan-tools"
component gpu_intel   gpu off "Intel"  "mesa + ANV"
pkgs "mesa-dri-drivers mesa-vulkan-drivers intel-media-driver libva-utils vulkan-tools"
component gpu_nvidia  gpu off "NVIDIA" "akmod-nvidia from RPM Fusion"
pkgs "akmod-nvidia xorg-x11-drv-nvidia-cuda nvidia-vaapi-driver libva-utils vulkan-tools"
# On-demand (PRIME render offload) for a hybrid laptop: the integrated GPU
# drives the desktop and the NVIDIA card renders only apps started with
# prime-run. The driver branch is picked to match the card (see stage_gpu), so
# the mesa stack for the integrated GPU is what this component carries; the
# NVIDIA packages are chosen and installed by the graphics stage.
component gpu_nvidia_offload gpu off "NVIDIA (on-demand)" "iGPU desktop, NVIDIA via prime-run"
pkgs "mesa-dri-drivers mesa-vulkan-drivers intel-media-driver libva-utils vulkan-tools"
component gpu_vm      gpu off "VM"     "virtio/llvmpipe + guest agent"
pkgs "mesa-dri-drivers qemu-guest-agent spice-vdagent"

# The GPU group is a radio, not a checklist.
select_gpu() {
  local pick=$1 k
  for k in gpu_amd gpu_intel gpu_nvidia gpu_nvidia_offload gpu_vm; do deselect_component "$k"; done
  select_component "gpu_$pick"
  GPU_VENDOR=$pick
}

# DMS plugins that are always installed, regardless of selection. The Phone
# Connect plugin is not here: it rides with the kdeconnect component through
# its dms_plugin line, because a plugin for a daemon that is not installed
# only fills the log with errors.
DMS_BASE_PLUGINS=(
  dmsThemeSync nothingClock wallpaperCarousel emojiLauncher quickCapture
)
# Removed from plugin_settings.json and from the bar so DMS does not log for
# them: either present in the backup's settings.json with no plugin directory
# at all, or deliberately dropped.
DMS_DEAD_PLUGINS=(
  ocrScanner todoLauncher audioPortSwitcher gpuMonitor
  screenRecorder screenRecorderLH screenRecorderX wifiHotspot
  extendedNetworkToggle aiOverviewControl
)

selected_dms_plugins() {
  printf '%s\n' "${DMS_BASE_PLUGINS[@]}"
  local k
  for k in "${COMPONENT_ORDER[@]}"; do
    is_selected "$k" || continue
    [[ -n ${COMPONENT_PLUGIN[$k]:-} ]] && printf '%s\n' "${COMPONENT_PLUGIN[$k]}"
  done
  return 0
}

# ------------------------------------------------------------------ presets ---
apply_preset() {
  local preset=$1 k
  case $preset in
    minimal) for k in "${COMPONENT_ORDER[@]}"; do
               component_locked "$k" || deselect_component "$k"; done
             select_layout scrolling ;;
    standard) : ;;   # the declared defaults
    full)    for k in "${COMPONENT_ORDER[@]}"; do
               [[ ${COMPONENT_GROUP[$k]} == gpu || ${COMPONENT_GROUP[$k]} == layout ]] && continue
               select_component "$k"; done
             select_layout scrolling ;;
    *)       die "unknown preset: $preset (minimal|standard|full)" ;;
  esac
}
