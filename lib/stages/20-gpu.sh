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

stage_gpu() {
  step "Graphics"
  info "$(lspci -nn 2>/dev/null | grep -Ei 'vga|3d controller' | sed 's/^/    /' | head -3)"
  ok "driver set: ${GPU_VENDOR}"

  case $GPU_VENDOR in
    nvidia)
      warn "NVIDIA: the akmod builds on first boot and can take several minutes"
      if mokutil --sb-state 2>/dev/null | grep -qi enabled; then
        warn "Secure Boot is on. The module will not load until you enrol a MOK:"
        warn "  sudo kmodgenca -a && sudo mokutil --import /etc/pki/akmods/certs/public_key.der"
      fi
      ;;
    vm)
      info "VM detected: Hyprland will be told to render cursors in software"
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
