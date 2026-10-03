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
  # A hybrid laptop lists both; the discrete card is what needs the driver.
  if grep -qi nvidia <<<"$line"; then printf 'nvidia'; return; fi
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
  esac
}
