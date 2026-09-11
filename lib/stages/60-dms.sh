# shellcheck shell=bash
# DankMaterialShell, its plugins, and a settings.json rewritten for this
# machine and this selection.

DMS_CONFIG="$HOME/.config/DankMaterialShell"

declare -A DMS_PLUGIN_REPO=(
  [nothingClock]="https://github.com/samgrande/Dank-Nothing-Clock|nothingclock"
  [dankKDEConnect]="https://github.com/AvengeMedia/dms-plugins|DankKDEConnect"
)

stage_dms() {
  step "DankMaterialShell"
  install_dms_runtime
  install_dms_plugins
  deploy_dms_settings
}

# Upstream's installer knows which quickshell revision it needs; reproducing
# that here would rot. Run it, then layer our config on top.
install_dms_runtime() {
  if have dms; then
    local _v; _v=$(dms --version 2>/dev/null | head -1)
    skip "dms already installed${_v:+ ($_v)}"
    return 0
  fi
  info "running the DankMaterialShell installer"
  if (( DRY_RUN )); then
    info '$ curl -fsSL https://install.danklinux.com | sh'
    return 0
  fi
  if ! curl -fsSL https://install.danklinux.com | sh; then
    die "the DankMaterialShell installer failed; see https://github.com/AvengeMedia/DankMaterialShell"
  fi
  have dms || die "the DMS installer completed but dms is not on PATH"
  ok "dms installed"
}

# Plugins live in plugins/.repos/<hash>/ with a symlink in plugins/. The backup
# committed absolute symlinks into /home/hanafi; these are relative.
install_dms_plugins() {
  local plugins="$DMS_CONFIG/plugins"
  run mkdir -p "$plugins/.repos"

  local name
  while read -r name; do
    [[ -z $name ]] && continue
    install_one_plugin "$name"
  done < <(selected_dms_plugins)
}

install_one_plugin() {
  local name=$1
  local plugins="$DMS_CONFIG/plugins"

  if [[ -e $plugins/$name ]]; then
    skip "plugin $name present"
    return 0
  fi

  # Anything DMS knows about is best installed through DMS itself, so the
  # plugin registry and settings stay consistent.
  if have dms && dms plugins install "$name" >/dev/null 2>&1; then
    ok "plugin $name (via dms)"
    return 0
  fi

  local spec=${DMS_PLUGIN_REPO[$name]:-}
  if [[ -z $spec ]]; then
    soft_fail "plugin $name: no known source, skipped"
    return 0
  fi

  local repo=${spec%%|*} sub=${spec##*|}
  local hash; hash=$(printf '%s' "$repo" | sha256sum | cut -c1-16)
  local dir="$plugins/.repos/$hash"

  if [[ -d $dir/.git ]]; then
    run git -C "$dir" pull --ff-only || warn "could not update $name"
  else
    retry 3 git clone --depth 1 "$repo" "$dir" || { soft_fail "plugin $name: clone failed"; return 0; }
  fi

  [[ -d $dir/$sub ]] || { soft_fail "plugin $name: $sub missing from $repo"; return 0; }
  run ln -sfn "../plugins/.repos/$hash/$sub" "$plugins/$name" 2>/dev/null || \
    run ln -sfn ".repos/$hash/$sub" "$plugins/$name"
  (( DRY_RUN )) || printf 'repo=%s\npath=%s\nrepodir=%s\n' "$repo" "$sub" "$hash" > "$plugins/$name.meta"
  ok "plugin $name"

  # quickCapture ships a Rust screenshot backend that has to be compiled.
  if [[ -x $plugins/$name/scripts/install-backend.sh ]]; then
    have cargo || { soft_fail "$name needs cargo to build its backend"; return 0; }
    run_visible "$plugins/$name/scripts/install-backend.sh" || soft_fail "$name backend build failed"
  fi
}

# settings.json and plugin_settings.json, rewritten for this install.
deploy_dms_settings() {
  local src="$REPO_DIR/config/shell-ui/DankMaterialShell"
  run mkdir -p "$DMS_CONFIG/themes"
  deploy_tree "$src/themes" "$DMS_CONFIG/themes"
  ok "$(ls "$src/themes" | wc -l) themes installed"

  backup_path "$DMS_CONFIG/settings.json"
  backup_path "$DMS_CONFIG/plugin_settings.json"
  deploy_file "$src/settings.json"        "$DMS_CONFIG/settings.json"
  deploy_file "$src/plugin_settings.json" "$DMS_CONFIG/plugin_settings.json"

  local keep dead
  keep=$(selected_dms_plugins | paste -sd, -)
  dead=$(printf '%s,' "${DMS_DEAD_PLUGINS[@]}")

  local width height
  read -r width height < <(detect_resolution)
  info "clock geometry computed for ${width}x${height}"

  (( DRY_RUN )) && { info "would rewrite settings.json"; return 0; }

  KEEP_PLUGINS="$keep" DEAD_PLUGINS="$dead" \
  OUTPUT_NAME="$TPL_MONITOR" SCREEN_W="$width" SCREEN_H="$height" \
  python3 "$REPO_DIR/lib/dms_settings.py" \
    "$DMS_CONFIG/settings.json" "$DMS_CONFIG/plugin_settings.json" \
    || die "could not rewrite the DMS settings"
  ok "settings.json rewritten: nothingMatrix theme, Nothing Clock, $(wc -w <<<"${keep//,/ }") plugins"
}

# The preferred mode of the output the session will actually use. Reading the
# first `modes` file found picks whichever connector the kernel enumerated
# first, which on a laptop with a dock is rarely the panel.
detect_resolution() {
  local m dir name first
  for m in /sys/class/drm/card*-*/modes; do
    [[ -r $m ]] || continue
    dir=$(dirname "$m")
    [[ $(cat "$dir/status" 2>/dev/null) == connected ]] || continue
    name=$(basename "$dir"); name=${name#card*-}
    [[ -n ${TPL_MONITOR:-} && $name != "$TPL_MONITOR" ]] && continue
    read -r first < "$m" 2>/dev/null || continue
    if [[ $first =~ ^([0-9]+)x([0-9]+) ]]; then
      printf '%s %s' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"; return
    fi
  done
  printf '1920 1080'
}
