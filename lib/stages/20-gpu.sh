# shellcheck shell=bash
# GPU detection. lspci proposes, the operator disposes.
detect_gpu() {
  local line
  line=$(lspci -nn 2>/dev/null | grep -Ei 'vga|3d controller|display controller' || true)
  _log_raw "GPU   $line"
  if [[ -z $line ]]; then
    systemd-detect-virt -q && { printf 'vm'; return; }
    printf 'intel'; return
  fi
  # A hybrid laptop lists both an integrated GPU and the NVIDIA card. There the
  # sane default is render offload: the integrated GPU drives the desktop and
  # the NVIDIA card is used on demand, rather than running hot as the primary.
  # A machine with only NVIDIA (a desktop) gets the plain always-on driver.
  if grep -qi nvidia <<<"$line"; then
    grep -qiE 'intel|amd|ati |radeon' <<<"$line" && { printf 'nvidia_offload'; return; }
    printf 'nvidia'; return
  fi
  if grep -qiE 'virtio|qxl|vmware|innotek|cirrus|bochs|red hat' <<<"$line"; then printf 'vm'; return; fi
  if grep -qiE 'amd|ati |radeon' <<<"$line"; then printf 'amd'; return; fi
  if grep -qi intel <<<"$line"; then printf 'intel'; return; fi
  printf 'vm'
}

# Whether the GPU renders in hardware. niri, unlike Hyprland, refuses Mesa's
# software renderer, so on a VM without 3D acceleration it starts with no
# screen at all. A virtio GPU reports 3D as feature bit 0 (VIRGL); other
# virtual GPUs are assumed to have none.
gpu_has_3d() {
  local d
  for d in /sys/bus/virtio/devices/*; do
    [[ $(cat "$d/device" 2>/dev/null) == 0x0010 ]] || continue
    [[ $(head -c1 "$d/features" 2>/dev/null) == 1 ]]
    return
  done
  [[ $(detect_gpu) != vm ]]
}

# The RPM Fusion akmod package whose driver branch still supports this card.
# NVIDIA drops old architectures from the mainline driver: the current branch
# is Turing and newer only, 580xx is the last for Maxwell/Pascal/Volta, 470xx
# the last for Kepler, 390xx the last for Fermi. Installing the mainline driver
# on an older card builds a module that loads but refuses the GPU, which is
# exactly how a hybrid laptop ends up with no NVIDIA at all. The codename
# prefix in lspci (GM107, GP104, TU116, ...) names the architecture.
nvidia_akmod_pkg() {
  local chip
  chip=$(lspci 2>/dev/null | grep -Ei 'vga|3d controller|display' | grep -i nvidia \
         | grep -oiE '\b(G[FKMPV]|TU|GA|AD|GB)[0-9]{2,3}' | head -1)
  case ${chip^^} in
    GF*)         printf 'akmod-nvidia-390xx' ;;   # Fermi
    GK*)         printf 'akmod-nvidia-470xx' ;;   # Kepler
    GM*|GP*|GV*) printf 'akmod-nvidia-580xx' ;;   # Maxwell / Pascal / Volta
    *)           printf 'akmod-nvidia'       ;;   # Turing+ and anything unknown
  esac
}

# The full driver package set for a branch. The -cuda subpackage (which pulls
# the libraries prime-run needs) is named after the branch; --skip-unavailable
# in the install swallows a subpackage a given legacy branch happens to lack.
nvidia_driver_pkgs() {
  local akmod suffix
  akmod=$(nvidia_akmod_pkg)
  suffix=${akmod#akmod-nvidia}   # "", "-580xx", "-470xx", "-390xx"
  printf '%s xorg-x11-drv-nvidia%s-cuda libva-nvidia-driver' "$akmod" "$suffix"
}

# Install the chosen NVIDIA driver branch and set the card up for render
# offload: the integrated GPU keeps driving the desktop, the NVIDIA card is
# loaded at boot (nouveau is blacklisted by the akmod package's own scripts)
# so prime-run can reach it. prime-run itself and the Hyprland pin come from
# here and gpu_env_lines; the module finishes building on first reboot.
install_nvidia_offload() {
  local driver_pkgs; driver_pkgs=$(nvidia_driver_pkgs)
  info "NVIDIA on-demand: installing ${driver_pkgs%% *} (the branch that supports this card)"
  if (( DRY_RUN )); then
    info "[dry-run] would install: $driver_pkgs"
    return 0
  fi
  record_new_pkgs $driver_pkgs
  # shellcheck disable=SC2086
  as_root dnf install -y --skip-unavailable $driver_pkgs \
    || { soft_fail "NVIDIA driver install failed; the rest of the desktop is unaffected"; return 0; }

  as_root tee /usr/local/bin/prime-run >/dev/null <<'EOF'
#!/bin/sh
# Run a single program on the NVIDIA GPU (PRIME render offload); everything
# else keeps using the integrated GPU. Usage: prime-run <program> [args...]
exec env __NV_PRIME_RENDER_OFFLOAD=1 __VK_LAYER_NV_optimus=NVIDIA_only \
         __GLX_VENDOR_LIBRARY_NAME=nvidia "$@"
EOF
  as_root chmod 0755 /usr/local/bin/prime-run
  record file /usr/local/bin/prime-run

  # Load the NVIDIA modules at boot so the card is ready for prime-run, and
  # turn on DRM modeset so offloaded Wayland/GBM clients work.
  as_root tee /etc/modules-load.d/nvidia-offload.conf >/dev/null <<'EOF'
nvidia
nvidia_modeset
nvidia_uvm
nvidia_drm
EOF
  as_root tee /etc/modprobe.d/nvidia-offload.conf >/dev/null <<'EOF'
options nvidia-drm modeset=1
options nvidia NVreg_PreserveVideoMemoryAllocations=1
EOF
  record file /etc/modules-load.d/nvidia-offload.conf
  record file /etc/modprobe.d/nvidia-offload.conf

  warn "The NVIDIA module finishes building the first time you reboot, which takes a few minutes"
  info "After reboot: 'nvidia-smi' lists the card, 'prime-run <app>' renders on it"
  if mokutil --sb-state 2>/dev/null | grep -qi enabled; then
    warn "Secure Boot is on, so the NVIDIA driver will not load until you approve it:"
    warn "  sudo kmodgenca -a && sudo mokutil --import /etc/pki/akmods/certs/public_key.der"
  fi
  return 0
}

stage_gpu() {
  local card
  # `|| card=""` is load-bearing. grep exits 1 when it matches nothing, and a
  # VM without lspci matches nothing; pipefail then makes the assignment fail
  # and set -e ends the run on a line that only wanted a label to print.
  card=$(lspci 2>/dev/null | grep -Ei 'vga|3d controller' | head -1 | sed 's/.*: //') || card=""
  [[ -n $card ]] && info "Found: ${card}"
  ok "Graphics card: ${GPU_VENDOR}. The matching driver will be installed."

  case $GPU_VENDOR in
    nvidia)
      warn "The NVIDIA driver finishes building the first time you restart, which takes a few minutes"
      if mokutil --sb-state 2>/dev/null | grep -qi enabled; then
        warn "Secure Boot is on, so the NVIDIA driver will not load until you approve it"
        warn "  Run this, set a password, then reboot and choose Enroll MOK:"; \
        warn "  sudo kmodgenca -a && sudo mokutil --import /etc/pki/akmods/certs/public_key.der"
      fi
      ;;
    nvidia_offload)
      install_nvidia_offload
      ;;
    vm)
      info "This is a virtual machine, so the mouse cursor will be drawn in software"
      ;;
  esac
}

# Written into the Hyprland env module by stage_hyprland.
gpu_env_lines() {
  case $GPU_VENDOR in
    nvidia)
      cat <<'EOF'

-- NVIDIA. Without these, Electron apps fall back to software rendering and
-- hardware video decode is unavailable.
hl.env("LIBVA_DRIVER_NAME", "nvidia")
hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
hl.env("NVD_BACKEND", "direct")
hl.env("GBM_BACKEND", "nvidia-drm")
EOF
      ;;
    vm)
      cat <<'EOF'

-- Virtual GPU: no hardware cursor plane exists, so the pointer would be
-- invisible without this.
hl.env("WLR_NO_HARDWARE_CURSORS", "1")
hl.env("LIBGL_ALWAYS_SOFTWARE", "0")
EOF
      ;;
    amd)
      cat <<'EOF'

hl.env("LIBVA_DRIVER_NAME", "radeonsi")
EOF
      ;;
    intel)
      cat <<'EOF'

hl.env("LIBVA_DRIVER_NAME", "iHD")
EOF
      ;;
    nvidia_offload)
      # The compositor runs on the integrated GPU. aquamarine selects it on its
      # own: a render-offload NVIDIA card is a 3D controller with no display
      # outputs, so it is not a KMS device and is skipped. No AQ_DRM_DEVICES pin
      # -- aquamarine splits that variable on ':', which shreds a PCI by-path
      # name (pci-0000:00:02.0-card) and leaves it with no GPU at all.
      local vaapi=iHD
      lspci 2>/dev/null | grep -Ei 'vga|3d controller|display' | grep -vi nvidia \
        | grep -qiE 'amd|ati |radeon' && vaapi=radeonsi
      printf '\nhl.env("LIBVA_DRIVER_NAME", "%s")\n' "$vaapi"
      ;;
  esac
}
