# shellcheck shell=bash
# DankMaterialShell, its plugins, and a settings.json rewritten for this
# machine and this selection.

DMS_CONFIG="$HOME/.config/DankMaterialShell"

# repo|subpath|branch. subpath is "." when the plugin sits at the repo root;
# branch is optional and defaults to whatever the remote HEAD points at.
declare -A DMS_PLUGIN_REPO=(
  [nothingClock]="https://github.com/samgrande/Dank-Nothing-Clock|nothingclock|"
  [dankKDEConnect]="https://github.com/AvengeMedia/dms-plugins|DankKDEConnect|"
  [cliampDms]="https://github.com/Jazzmedo/cliamp-dms|.|playback-offset"
  [lyricsOnPanel]="https://github.com/Jazzmedo/lyrics-on-panel|dms|niri-enhancments"
)

# Plugins that must come from the repository above rather than from the DMS
# plugin registry, because the registry would install upstream over a fork.
declare -A DMS_PLUGIN_PINNED=(
  [cliampDms]=1
  [lyricsOnPanel]=1
)

stage_dms() {
  step "DankMaterialShell"
  install_dms_runtime
  install_dms_plugins
  deploy_dms_settings
  fix_dms_service_path
}

# The unit shipped in this repo hardcodes /usr/bin/dms, which is where the
# captured machine had it. The upstream installer may put it in ~/.local/bin
# instead, and a unit pointing at the wrong path simply restarts forever.
fix_dms_service_path() {
  local unit="$HOME/.config/systemd/user/dms.service"
  [[ -f $unit ]] || return 0
  local dms_path; dms_path=$(command -v dms 2>/dev/null || true)
  if [[ -z $dms_path ]]; then
    soft_fail "dms is not on PATH, so dms.service was left pointing at /usr/bin/dms"
    return 0
  fi
  if grep -q "ExecStart=$dms_path " "$unit"; then
    skip "dms.service already points at $dms_path"
    return 0
  fi
  run sed -i -E "s|^ExecStart=.*/dms run|ExecStart=$dms_path run|" "$unit"
  run systemctl --user daemon-reload
  ok "dms.service points at $dms_path"
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
  # plugin registry and settings stay consistent. Pinned plugins skip this:
  # the registry would hand back upstream and silently replace a fork.
  if [[ -z ${DMS_PLUGIN_PINNED[$name]:-} ]]; then
    if have dms && dms plugins install "$name" >/dev/null 2>&1; then
      ok "plugin $name (via dms)"
      return 0
    fi
  fi

  local spec=${DMS_PLUGIN_REPO[$name]:-}
  if [[ -z $spec ]]; then
    soft_fail "plugin $name: no known source, skipped"
    return 0
  fi

  local repo sub branch
  IFS='|' read -r repo sub branch <<< "$spec"
  local hash; hash=$(printf '%s' "$repo" | sha256sum | cut -c1-16)
  local dir="$plugins/.repos/$hash"

  if [[ -d $dir/.git ]]; then
    run git -C "$dir" fetch --depth 1 origin "${branch:-HEAD}" || warn "could not fetch $name"
    run git -C "$dir" checkout -q FETCH_HEAD || warn "could not update $name"
  else
    local -a clone=(git clone --depth 1)
    [[ -n $branch ]] && clone+=(--branch "$branch")
    retry 3 "${clone[@]}" "$repo" "$dir" || { soft_fail "plugin $name: clone failed"; return 0; }
  fi

  local target="$dir"
  [[ $sub != "." ]] && target="$dir/$sub"
  [[ -d $target ]] || { soft_fail "plugin $name: $sub missing from $repo"; return 0; }

  # Relative, so the link survives a different \$HOME. The captured config had
  # these pointing at an absolute /home/hanafi.
  backup_path "$plugins/$name"
  run rm -rf "$plugins/$name"
  if [[ $sub == "." ]]; then
    run ln -sfn ".repos/$hash" "$plugins/$name"
  else
    run ln -sfn ".repos/$hash/$sub" "$plugins/$name"
  fi
  (( DRY_RUN )) || printf 'repo=%s\npath=%s\nrepodir=%s\nbranch=%s\n' \
    "$repo" "$sub" "$hash" "${branch:-HEAD}" > "$plugins/$name.meta"
  ok "plugin $name${branch:+ (branch $branch)}"

  plugin_post_install "$name" "$dir"

}

# Plugins that need more than their QML copied into place.
plugin_post_install() {
  local name=$1 repo_dir=$2
  case $name in
    quickCapture)
      # A Rust screenshot backend that has to be compiled.
      [[ -x $repo_dir/scripts/install-backend.sh ]] || return 0
      have cargo || { soft_fail "$name needs cargo to build its backend"; return 0; }
      run_visible "$repo_dir/scripts/install-backend.sh" || soft_fail "$name backend build failed"
      ;;
    cliampDms)  install_cliamp "$repo_dir" ;;
    lyricsOnPanel) install_lyrics_backend "$repo_dir" ;;
  esac
}

# The player the plugin drives. CLIAMP is a Go program with no Fedora package,
# and `go install` is more dependable than guessing release asset names.
install_cliamp() {
  local repo_dir=$1
  if have cliamp; then
    skip "cliamp already installed"
  elif ! have go; then
    soft_fail "cliamp needs Go to build; select the language runtimes component"
  else
    info "building CLIAMP with go install"
    run_visible env GOBIN="$HOME/.local/bin" go install github.com/bjarneo/cliamp@latest \
      || soft_fail "could not build cliamp"
    have cliamp && ok "cliamp installed"
  fi

  # Helper scripts the widget shells out to, and the optional Lua bridge that
  # gives it radio playback and queue jumping.
  local f
  for f in "$repo_dir"/scripts/cliamp-dms-*; do
    [[ -f $f ]] || continue
    deploy_file "$f" "$HOME/.local/bin/$(basename "$f")" 755
  done
  if [[ -f $repo_dir/cliamp/cliamp-dms-bridge.lua ]]; then
    deploy_file "$repo_dir/cliamp/cliamp-dms-bridge.lua" \
      "$HOME/.config/cliamp/plugins/cliamp-dms-bridge.lua"
    info "CLIAMP bridge staged; trust it from the plugin's Radio tab, then restart cliamp"
  fi
}

# The widget reads lyrics from a local websocket server that watches MPRIS.
# The upstream scripts/install-backend.sh is Arch-only (it calls pacman) and
# clones upstream over the fork, so the equivalent is done here against dnf and
# against the checkout we already have.
install_lyrics_backend() {
  local repo_dir=$1
  local dest="$HOME/.local/share/lyrics-on-panel"
  local unit="Universal-Mpris-LyricServer.service"

  [[ -d $repo_dir/backend ]] || { soft_fail "lyrics backend missing from the checkout"; return 0; }

  if [[ -x $dest/backend/.venv/bin/python ]]; then
    skip "lyrics backend already built"
  else
    run mkdir -p "$dest"
    run cp -a "$repo_dir/backend" "$dest/"
    (( DRY_RUN )) || {
      # dbus-python has no wheel and compiles against dbus-devel and glib2-devel.
      python3 -m venv "$dest/backend/.venv" \
        && "$dest/backend/.venv/bin/pip" install --quiet --upgrade pip \
        && "$dest/backend/.venv/bin/pip" install --quiet \
             -r "$dest/backend/requirements.txt" \
        || { soft_fail "lyrics backend dependencies failed to build"; return 0; }
    }
    ok "lyrics backend built in ${dest/#$HOME/\~}"
  fi

  (( DRY_RUN )) || cat > "$dest/backend/run.sh" <<EOF
#!/bin/bash
cd "\$(dirname "\$0")"
source .venv/bin/activate
exec python src/server.py
EOF
  run chmod +x "$dest/backend/run.sh"

  (( DRY_RUN )) || cat > "$HOME/.config/systemd/user/$unit" <<EOF
[Unit]
Description=Lyrics-on-Panel MPRIS2 backend
After=graphical-session.target

[Service]
Type=simple
ExecStart=$dest/backend/run.sh
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF
  run systemctl --user daemon-reload
  run systemctl --user enable "$unit" || soft_fail "could not enable $unit"
  ok "lyrics backend service enabled (ws://127.0.0.1:23560)"
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
  # `read` returns non-zero at EOF without a trailing newline, which under
  # `set -e` aborted the whole installer here. Hence the newline in
  # detect_resolution, and the guard.
  read -r width height < <(detect_resolution) || true
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
      printf '%s %s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"; return
    fi
  done
  printf '1920 1080\n'
}
