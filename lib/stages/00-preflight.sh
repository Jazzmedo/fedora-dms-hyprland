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


  # Said once here rather than four times later as a failure per service.
  if user_bus_ok; then
    ok "Your login session can manage its own background services"
  else
    warn "This session has no service manager of its own, so services cannot be started from here"
    _detail "systemctl --user cannot reach a bus. It happens when a terminal was opened with su, or over a connection that did not create a full login session." \
            "Nothing is lost: the services are still set up, and they start the next time you log in normally."
  fi

  local need=(curl git tar python3 rpm)
  local missing=()
  local t; for t in "${need[@]}"; do have "$t" || missing+=("$t"); done
  if (( ${#missing[@]} )); then
    info "Installing a few tools the installer itself needs"
    record_new_pkgs "${missing[@]}"
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
