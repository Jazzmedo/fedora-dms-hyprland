# shellcheck shell=bash
# Refuse to run anywhere this installer would do damage, and collect the facts
# every later stage depends on.
stage_preflight() {
  step "Preflight"

  [[ -r /etc/os-release ]] || die "no /etc/os-release; this is not a Fedora system"
  # shellcheck disable=SC1091
  . /etc/os-release
  [[ ${ID:-} == fedora ]] || die "this installer targets Fedora, found: ${PRETTY_NAME:-unknown}"
  (( ${VERSION_ID:-0} >= 41 )) || warn "Fedora ${VERSION_ID}: Hyprland's Lua config needs a recent COPR build"
  ok "Fedora ${VERSION_ID} (${VARIANT_ID:-custom})"

  [[ $EUID -ne 0 ]] || die "run this as your normal user, not root; it will call sudo when it needs to"
  id -nG | tr ' ' '\n' | grep -qx wheel || die "$USER is not in the wheel group, so sudo will not work"

  if ! sudo -n true 2>/dev/null; then
    info "sudo password needed for package installation"
    sudo -v || die "sudo authentication failed"
  fi
  # Hold the sudo timestamp open for the length of the run.
  ( while kill -0 $$ 2>/dev/null; do sudo -n true 2>/dev/null; sleep 50; done ) &
  SUDO_KEEPALIVE=$!
  trap 'kill $SUDO_KEEPALIVE 2>/dev/null || true' EXIT

  local need=(curl git tar python3 rpm)
  local missing=()
  local t; for t in "${need[@]}"; do have "$t" || missing+=("$t"); done
  if (( ${#missing[@]} )); then
    info "installing bootstrap tools: ${missing[*]}"
    as_root dnf install -y "${missing[@]}" || die "could not install ${missing[*]}"
  fi
  ok "bootstrap tools present"

  curl -fsS --max-time 10 -o /dev/null https://mirrors.fedoraproject.org \
    || die "no network. Connect first: nmtui"
  ok "network reachable"

  local free_mb; free_mb=$(df -Pm "$HOME" | awk 'NR==2{print $4}')
  (( free_mb > 8000 )) || die "need at least 8 GB free in $HOME, found ${free_mb} MB"
  ok "${free_mb} MB free in $HOME"

  if systemd-detect-virt -q; then
    DETECTED_VIRT=$(systemd-detect-virt)
    info "running under $DETECTED_VIRT"
  fi
}
