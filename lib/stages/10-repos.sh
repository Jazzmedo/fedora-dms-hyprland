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

  if rpm_has dnf-plugins-core; then skip "dnf-plugins-core present"
  else as_root dnf install -y dnf-plugins-core; fi

  local copr
  while read -r copr; do
    [[ -z $copr ]] && continue
    if ls /etc/yum.repos.d/ 2>/dev/null | grep -qi "${copr//\//-}"; then
      skip "COPR $copr already enabled"
    else
      as_root dnf copr enable -y "$copr" || die "could not enable COPR $copr"
      ok "COPR $copr"
    fi
  done < <(selected_coprs)

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
