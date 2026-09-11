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

# ------------------------------------------------------------- predicates ---
is_selected()      { [[ -n ${SELECTED[$1]:-} ]]; }
component_locked() { [[ ${COMPONENT_DEFAULT[$1]:-} == base ]]; }
select_component()   { SELECTED[$1]=1; }
deselect_component() { unset "SELECTED[$1]"; }
toggle_component() {
  component_locked "$1" && return 0
  is_selected "$1" && deselect_component "$1" || select_component "$1"
}
group_members() {
  local k
  for k in "${COMPONENT_ORDER[@]}"; do
    [[ ${COMPONENT_GROUP[$k]} == "$1" ]] && printf '%s\n' "$k"
  done
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
copr "sdegler/hyprland ashbuk/Hyprland-Fedora solopasha/hyprland"
pkgs "hyprland hyprland-devel hyprpaper hyprlock hypridle hyprpicker \
      xdg-desktop-portal-hyprland xdg-desktop-portal-gtk xdg-utils \
      quickshell matugen sddm qt6-qtvirtualkeyboard \
      qt6-qtdeclarative qt6-qt5compat qt6-qtsvg qt6-qtmultimedia \
      polkit-kde qt6ct qt5ct kvantum \
      cmake meson ninja-build gcc-c++ pkgconf git curl jq \
      ImageMagick brightnessctl playerctl libnotify \
      wl-clipboard cliphist grim slurp wtype \
      NetworkManager NetworkManager-wifi nm-connection-editor \
      bluez blueman kdeconnectd cargo"

component audio       base base "PipeWire"        "pipewire, wireplumber, pavucontrol"
pkgs "pipewire pipewire-pulseaudio pipewire-alsa pipewire-utils \
      wireplumber pavucontrol alsa-utils"

component apps_base   base base "kitty · Zen · Dolphin" "default terminal, browser, file manager"
pkgs "kitty dolphin kf6-kio kf6-kservice ffmpegthumbs kdegraphics-thumbnailers"

component fonts       base base "Nothing fonts"   "Ndot 55/57, NType 82, JetBrainsMono Nerd Font"
pkgs "fontconfig google-noto-sans-fonts google-noto-emoji-fonts"

# ---------------------------------------------------------------------------
group shell "Shell & development"

component zsh         shell on  "zsh + oh-my-zsh"  "zsh, oh-my-zsh, autosuggestions, syntax highlighting"
pkgs "zsh util-linux-user"

component prompt      shell on  "starship"         "prompt, matugen-themed from the DMS palette"
pkgs "starship"

component cli         shell on  "modern CLI tools" "eza, bat, ripgrep, fd, fzf, trash-cli, grc"
pkgs "eza bat ripgrep fd-find fzf trash-cli grc tree unzip p7zip p7zip-plugins"

component sysinfo     shell on  "btop · fastfetch · cava" "monitors, matugen-themed"
pkgs "btop fastfetch cava"

component filemgr_tui shell on  "yazi"             "terminal file manager"
pkgs "yazi"

component editor      shell on  "Neovim + LazyVim" "editor, plugins pinned by lazy-lock.json"
pkgs "neovim python3-neovim gcc make gettext"

component mux         shell on  "tmux"             "terminal multiplexer, matugen-themed"
pkgs "tmux"

component devtools    shell on  "language runtimes" "podman, pyenv, nvm, rustup, go, yt-dlp"
pkgs "podman podman-compose golang yt-dlp python3-pip \
      openssl-devel readline-devel zlib-devel bzip2-devel libffi-devel \
      sqlite-devel xz-devel tk-devel"

# ---------------------------------------------------------------------------
group browsers "Browsers (Zen is in the base group)"

component helium      browsers on  "Helium"      "Chromium fork, AppImage-free install to /opt"
component brave       browsers on  "Brave Origin" "de-Googled Brave build, third-party repo"
pkgs "brave-browser"

# ---------------------------------------------------------------------------
group apps "Applications"

component vesktop     apps on  "Vesktop"      "Discord client, official rpm, matugen-themed"

component qbittorrent apps on  "qBittorrent"  "torrent client"
pkgs "qbittorrent"

component obs         apps on  "OBS Studio"   "screen recording, matugen-themed"
pkgs "obs-studio"

component obsidian    apps on  "Obsidian"     "notes, official rpm, matugen-themed snippet"

component cliamp      apps on  "CLIAMP"       "terminal music player + your cliamp-dms bar plugin"
# ffprobe ships in ffmpeg-free; gjs and gdbus back the plugin's helper scripts,
# and alsa-lib-devel is what the player links against when Go builds it.
pkgs "curl ffmpeg-free gjs glib2 alsa-lib-devel"
dms_plugin "cliampDms"

component lyrics      apps on  "Lyrics on Panel" "your lyrics-on-panel fork plus its MPRIS backend"
# The backend is a Python service that reads MPRIS over D-Bus; dbus-devel and
# the compiler are needed because dbus-python builds from source.
pkgs "python3 python3-devel dbus-devel glib2-devel pkgconf gcc"
dms_plugin "lyricsOnPanel"

component easyeffects apps on  "EasyEffects"  "audio effects, Handfree/Normal presets"
pkgs "easyeffects"

# Packaging preference is rpm first, then an upstream tarball or AppImage.
# Flatpak is only used where nothing else exists, so it is opt-in and the two
# apps that used to be flatpaks now come from their projects' own rpms.
component flatpak     apps off "Flatpak"      "Flathub support; only Gear Lever needs it"
pkgs "flatpak"

component gearlever   apps off "Gear Lever"   "manage AppImages as normal apps; requires Flatpak"
flatpaks "it.mijorus.gearlever"

# ---------------------------------------------------------------------------
group services "Services & sessions"

component tailscale   services off "Tailscale"      "mesh VPN, enables the dankscale bar plugin"
pkgs "tailscale"
dms_plugin "dankscale"

component warp        services off "Cloudflare WARP" "enables the warpToggle bar plugin"
pkgs "cloudflare-warp"
dms_plugin "warpToggle"

component niri        services off "niri session"    "second Wayland session at the login screen"
pkgs "niri"

component searxng     services off "SearXNG"         "self-hosted search via podman-compose"

component tweaks      services off "System tweaks"   "SearXNG search policy, mDNS resolution, writeback cap"

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
component gpu_vm      gpu off "VM"     "virtio/llvmpipe + guest agent"
pkgs "mesa-dri-drivers qemu-guest-agent spice-vdagent"

# The GPU group is a radio, not a checklist.
select_gpu() {
  local pick=$1 k
  for k in gpu_amd gpu_intel gpu_nvidia gpu_vm; do deselect_component "$k"; done
  select_component "gpu_$pick"
  GPU_VENDOR=$pick
}

# DMS plugins that are always installed, regardless of selection.
DMS_BASE_PLUGINS=(
  dmsThemeSync nothingClock wallpaperCarousel emojiLauncher quickCapture
  dankKDEConnect extendedNetworkToggle aiOverviewControl
)
# Present in the backup's settings.json but with no plugin directory. Removed
# from plugin_settings.json and from the bar so DMS does not log for them.
DMS_DEAD_PLUGINS=(
  ocrScanner todoLauncher audioPortSwitcher gpuMonitor
  screenRecorder screenRecorderLH screenRecorderX wifiHotspot
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
