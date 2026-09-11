# shellcheck shell=bash
# Third-party repositories. Only the ones the selection actually needs.
stage_repos() {
  step "Repositories"

  # dnf's stock settings make a 90-package transaction unpleasantly slow.
  if ! grep -q '^max_parallel_downloads' /etc/dnf/dnf.conf 2>/dev/null; then
    as_root bash -c 'printf "max_parallel_downloads=10\nfastestmirror=True\n" >> /etc/dnf/dnf.conf'
    ok "dnf tuned for parallel downloads"
  else
    skip "dnf already tuned"
  fi

  local ver; ver=$(rpm -E %fedora)
  if rpm_has rpmfusion-free-release && rpm_has rpmfusion-nonfree-release; then
    skip "RPM Fusion already enabled"
  else
    as_root dnf install -y \
      "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${ver}.noarch.rpm" \
      "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${ver}.noarch.rpm" \
      || die "could not enable RPM Fusion"
    ok "RPM Fusion enabled"
  fi

  install_copr_plugin

  enable_hyprland_copr

  if is_selected brave; then
    if [[ -f /etc/yum.repos.d/brave-browser.repo ]]; then
      skip "Brave repo already present"
    else
      as_root dnf config-manager addrepo --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo \
        || soft_fail "Brave repository unavailable; Brave will be skipped"
    fi
  fi

  if is_selected tailscale; then
    [[ -f /etc/yum.repos.d/tailscale.repo ]] && skip "Tailscale repo present" || \
      as_root dnf config-manager addrepo --from-repofile="https://pkgs.tailscale.com/stable/fedora/tailscale.repo" \
        || soft_fail "Tailscale repository unavailable"
  fi

  if is_selected warp; then
    [[ -f /etc/yum.repos.d/cloudflare-warp.repo ]] && skip "WARP repo present" || \
      as_root dnf config-manager addrepo --from-repofile="https://pkg.cloudflareclient.com/cloudflare-warp-ascii.repo" \
        || soft_fail "Cloudflare WARP repository unavailable"
  fi

  if have flatpak; then skip "flatpak present"
  else as_root dnf install -y flatpak; fi
  run_visible flatpak remote-add --if-not-exists flathub \
    https://dl.flathub.org/repo/flathub.flatpakrepo || soft_fail "could not add Flathub"
  ok "Flathub configured"
}

# `dnf copr` lives in a different package depending on which dnf this is.
# Fedora 41 and later default to dnf5, where the command comes from
# dnf5-plugins; installing dnf-plugins-core there gives you the dnf4 plugins
# and `dnf copr` still does not exist.
install_copr_plugin() {
  if dnf copr --help >/dev/null 2>&1; then
    skip "dnf copr available"
    return 0
  fi
  local pkg=dnf-plugins-core
  if dnf --version 2>/dev/null | head -1 | grep -q '^dnf5'; then
    pkg=dnf5-plugins
  fi
  as_root dnf install -y "$pkg" || die "could not install $pkg, which provides 'dnf copr'"
  dnf copr --help >/dev/null 2>&1 || die "'dnf copr' still unavailable after installing $pkg"
  ok "$pkg installed"
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
      skip "COPR $project already enabled"
      return 0
    fi
  done

  for project in "${candidates[@]}"; do
    if ! copr_has_chroot "$project" "$chroot"; then
      info "COPR $project has no $chroot build, trying the next one"
      continue
    fi
    if as_root dnf copr enable -y "$project"; then
      ok "COPR $project ($chroot)"
      return 0
    fi
    warn "COPR $project could not be enabled, trying the next one"
  done

  die "no Hyprland COPR builds for $chroot.
     Tried: ${candidates[*]}
     Hyprland is not in Fedora's own repositories, so one of these must work.
     Check https://copr.fedorainfracloud.org for a project with a $chroot
     chroot and add it to COMPONENT_COPR[core] in lib/components.sh."
}
