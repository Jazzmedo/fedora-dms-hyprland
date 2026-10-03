# shellcheck shell=bash
# Third-party repositories. Only the ones the selection actually needs.
stage_repos() {

  # dnf's stock settings make a 90-package transaction unpleasantly slow.
  if ! grep -q '^max_parallel_downloads' /etc/dnf/dnf.conf 2>/dev/null; then
    as_root bash -c 'printf "max_parallel_downloads=10\nfastestmirror=True\n" >> /etc/dnf/dnf.conf'
    record edited /etc/dnf/dnf.conf
    ok "Set up Fedora to download several files at once, which is faster"
  else
    skip "Downloads are already set up to run in parallel"
  fi

  local ver; ver=$(rpm -E %fedora)
  if rpm_has rpmfusion-free-release && rpm_has rpmfusion-nonfree-release; then
    skip "RPM Fusion, the extra software source, is already set up"
  else
    record_new_pkgs rpmfusion-free-release rpmfusion-nonfree-release
    as_root dnf install -y \
      "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${ver}.noarch.rpm" \
      "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${ver}.noarch.rpm" \
      || die "Could not add RPM Fusion, an extra source of software." \
            "Fedora does not ship media codecs and some drivers itself, so they come from there." \
            "Check your internet connection, then run ./install.sh again."
    ok "Added RPM Fusion, which provides media codecs and extra drivers"
  fi

  install_copr_plugin

  enable_hyprland_copr

  # Brave and Brave Origin come from the same repository.
  if is_selected brave || is_selected brave_origin; then
    if [[ -f /etc/yum.repos.d/brave-browser.repo ]]; then
      skip "Brave already has a download source"
    else
      as_root dnf config-manager addrepo --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo \
        && record repofile /etc/yum.repos.d/brave-browser.repo \
        || soft_fail "Could not reach Brave's download source" \
              "Their server did not respond." \
              "./install.sh --only=repos,packages"
    fi
  fi

  if is_selected docker; then
    if [[ -f /etc/yum.repos.d/docker-ce.repo ]]; then
      skip "Docker already has a download source"
    else
      as_root dnf config-manager addrepo --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo \
        && record repofile /etc/yum.repos.d/docker-ce.repo \
        || soft_fail "Could not reach Docker's download source" \
              "Their server did not respond." \
              "./install.sh --only=repos,packages"
    fi
  fi

  if is_selected vivaldi; then
    if [[ -f /etc/yum.repos.d/vivaldi-fedora.repo ]]; then
      skip "Vivaldi already has a download source"
    else
      as_root dnf config-manager addrepo --from-repofile=https://repo.vivaldi.com/archive/vivaldi-fedora.repo \
        && record repofile /etc/yum.repos.d/vivaldi-fedora.repo \
        || soft_fail "Could not reach Vivaldi's download source" \
              "Their server did not respond." \
              "./install.sh --only=repos,packages"
    fi
  fi

  if is_selected librewolf; then
    if [[ -f /etc/yum.repos.d/librewolf.repo ]]; then
      skip "LibreWolf already has a download source"
    else
      as_root dnf config-manager addrepo --from-repofile=https://repo.librewolf.net/librewolf.repo \
        && record repofile /etc/yum.repos.d/librewolf.repo \
        || soft_fail "Could not reach LibreWolf's download source" \
              "Their server did not respond." \
              "./install.sh --only=repos,packages"
    fi
  fi

  if is_selected tailscale; then
    [[ -f /etc/yum.repos.d/tailscale.repo ]] && skip "Tailscale already has a download source" || \
      as_root dnf config-manager addrepo --from-repofile="https://pkgs.tailscale.com/stable/fedora/tailscale.repo" \
        && record repofile /etc/yum.repos.d/tailscale.repo \
        || soft_fail "Could not reach Tailscale's download source" \
              "Their server did not respond." \
              "./install.sh --only=repos,optional"
  fi

  if is_selected warp; then
    [[ -f /etc/yum.repos.d/cloudflare-warp.repo ]] && skip "Cloudflare WARP already has a download source" || \
      as_root dnf config-manager addrepo --from-repofile="https://pkg.cloudflareclient.com/cloudflare-warp-ascii.repo" \
        && record repofile /etc/yum.repos.d/cloudflare-warp-ascii.repo \
        || soft_fail "Could not reach Cloudflare WARP's download source" \
              "Their server did not respond." \
              "./install.sh --only=repos,optional"
  fi

  # Flatpak is opt-in: everything else here comes from rpms, which theme and
  # integrate better. Only Gear Lever needs it.
  if is_selected flatpak; then
    have flatpak || { record_new_pkgs flatpak; as_root dnf install -y flatpak; }
    run_visible flatpak remote-add --if-not-exists flathub \
      https://dl.flathub.org/repo/flathub.flatpakrepo || soft_fail "Could not add Flathub, where Flatpak apps come from" \
         "Their server did not respond." \
         "./install.sh --only=repos"
    ok "Added Flathub, where Flatpak apps are downloaded from"
  else
    skip "Flatpak was not chosen, so Flathub is not needed"
  fi
}

# `dnf copr` lives in a different package depending on which dnf this is.
# Fedora 41 and later default to dnf5, where the command comes from
# dnf5-plugins; installing dnf-plugins-core there gives you the dnf4 plugins
# and `dnf copr` still does not exist.
install_copr_plugin() {
  if dnf copr --help >/dev/null 2>&1; then
    skip "Fedora can already add community software sources"
    return 0
  fi
  local pkg=dnf-plugins-core
  if dnf --version 2>/dev/null | head -1 | grep -q '^dnf5'; then
    pkg=dnf5-plugins
  fi
  record_new_pkgs "$pkg"
  as_root dnf install -y "$pkg" || die "Could not install $pkg." \
       "It is what lets Fedora add community software sources, and Hyprland comes from one." \
       "Check your internet connection, then run ./install.sh again."
  dnf copr --help >/dev/null 2>&1 || die "Fedora still cannot add community software sources." \
       "$pkg installed but did not provide the command it should have." \
       "Try: sudo dnf reinstall $pkg"
  ok "Fedora can now add community software sources"
}

# True when the named COPR has a build chroot for this Fedora release and
# architecture. Asking first turns an opaque `dnf copr enable` failure into a
# clear statement about which repositories can serve this machine.
copr_has_chroot() {
  local project=$1 chroot=$2
  local owner=${project%%/*} name=${project##*/}
  curl -fsSL --max-time 20 \
    "https://copr.fedorainfracloud.org/api_3/project?ownername=${owner}&projectname=${name}" 2>/dev/null \
  | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(2)
sys.exit(0 if '$chroot' in (data.get('chroot_repos') or {}) else 1)
"
}

# Hyprland is not packaged in Fedora, so exactly one COPR has to work. Try the
# candidates in order and stop at the first that builds for this release.
enable_hyprland_copr() {
  local -a candidates
  mapfile -t candidates < <(selected_coprs)
  (( ${#candidates[@]} )) || return 0

  local release arch chroot
  release=$(rpm -E %fedora)
  arch=$(rpm -E %_arch)
  chroot="fedora-${release}-${arch}"

  local project
  for project in "${candidates[@]}"; do
    if ls /etc/yum.repos.d/ 2>/dev/null | grep -qi "${project//\//-}"; then
      skip "The community source that provides Hyprland is already set up"
      return 0
    fi
  done

  for project in "${candidates[@]}"; do
    if ! copr_has_chroot "$project" "$chroot"; then
      info "One source has no build for this Fedora version, trying another"
      continue
    fi
    if as_root dnf copr enable -y "$project" && record copr "$project"; then
      ok "Added the community source that provides Hyprland"
      return 0
    fi
    warn "That source could not be added, trying another"
  done

  die "Could not find a source that provides Hyprland for this Fedora version" \
      "Fedora does not package Hyprland itself, so it comes from a community build, and none of the ones this installer knows about has a build for $chroot yet." \
      "Wait a few days and try again, or look for a project with a $chroot build at copr.fedorainfracloud.org and add it to lib/components.sh"
}
