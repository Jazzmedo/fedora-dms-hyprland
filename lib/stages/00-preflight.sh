# shellcheck shell=bash
# Refuse to run anywhere this installer would do damage, and collect the facts
# every later stage depends on.
stage_preflight() {

  [[ -r /etc/os-release ]] || die "This does not look like a Fedora system." \
       "The file that names the operating system is missing." \
       "Install Fedora first. See the README for which ISO to use."
  # shellcheck disable=SC1091
  . /etc/os-release
  [[ ${ID:-} == fedora ]] || die "This installer only works on Fedora." \
       "This machine is running ${PRETTY_NAME:-something else}." \
       "Install Fedora first. See the README for which ISO to use."
  (( ${VERSION_ID:-0} >= 41 )) || warn "Fedora ${VERSION_ID} is older than this setup expects, so some parts may not be available"
  ok "Running on Fedora ${VERSION_ID}"

  [[ $EUID -ne 0 ]] || die "Do not run this with sudo or as root." \
       "It needs to set up files in your own home folder." \
       "./install.sh"
  id -nG | tr ' ' '\n' | grep -qx wheel || die "Your account is not allowed to install software." \
       "Only accounts in the wheel group can use sudo, and $USER is not one." \
       "From an administrator account: sudo usermod -aG wheel $USER"

  if ! sudo -n true 2>/dev/null; then
    info "Installing software needs your password. You will be asked once."
    sudo -v || die "That password was not accepted." "" "Run ./install.sh again."
  fi
  # Hold the sudo timestamp open for the length of the run.
  ( while kill -0 $$ 2>/dev/null; do sudo -n true 2>/dev/null; sleep 50; done ) &
  SUDO_KEEPALIVE=$!
  trap 'kill $SUDO_KEEPALIVE 2>/dev/null || true' EXIT

  local need=(curl git tar python3 rpm)
  local missing=()
  local t; for t in "${need[@]}"; do have "$t" || missing+=("$t"); done
  if (( ${#missing[@]} )); then
    info "Installing a few tools the installer itself needs"
    as_root dnf install -y "${missing[@]}" || die "Could not install the tools the installer needs: ${missing[*]}" \
         "The download failed, usually because of the network." \
         "Check your connection, then run ./install.sh again."
  fi
  ok "The installer has the tools it needs"

  curl -fsS --max-time 10 -o /dev/null https://mirrors.fedoraproject.org \
    || die "No internet connection." \
         "Almost everything here has to be downloaded." \
         "Connect to a network with: nmtui"
  ok "Internet connection works"

  local free_mb; free_mb=$(df -Pm "$HOME" | awk 'NR==2{print $4}')
  (( free_mb > 8000 )) || die "Not enough free disk space." \
       "This needs about 8 GB free in your home folder, and there is ${free_mb} MB." \
       "Free up some space, then run ./install.sh again."
  ok "Enough free disk space ($(( free_mb / 1024 )) GB)"

  if systemd-detect-virt -q; then
    DETECTED_VIRT=$(systemd-detect-virt)
    info "This is a virtual machine ($DETECTED_VIRT), so some hardware steps are skipped"
  fi
}
