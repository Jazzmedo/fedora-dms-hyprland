# shellcheck shell=bash
# DankMaterialShell, its plugins, and a settings.json rewritten for this
# machine and this selection.

DMS_CONFIG="$HOME/.config/DankMaterialShell"

# repo|subpath|branch. subpath is "." when the plugin sits at the repo root;
# branch is optional and defaults to whatever the remote HEAD points at.
declare -A DMS_PLUGIN_REPO=(
  [nothingClock]="https://github.com/samgrande/Dank-Nothing-Clock|nothingclock|"
  [dankKDEConnect]="https://github.com/AvengeMedia/dms-plugins|DankKDEConnect|"
)

# Plugins that must not come from the DMS plugin registry, because the registry
# would install upstream over a fork.
declare -A DMS_PLUGIN_PINNED=(
  [cliampDms]=1
  [lyricsOnPanel]=1
)

# Both forks live in private repositories, so a clone on a fresh machine fails
# with an authentication prompt. Their working trees are vendored under
# assets/dms-plugins instead, uncommitted edits and all; see PROVENANCE.txt
# there. Format: directory|subpath, matching DMS_PLUGIN_REPO.
declare -A DMS_PLUGIN_VENDOR=(
  [cliampDms]="cliamp-dms|."
  [lyricsOnPanel]="lyrics-on-panel|dms"
)

stage_dms() {
  ensure_quickshell

  # The shell itself comes from a download that can fail. When it does, the
  # settings and plugins are still worth putting in place: they are files, they
  # need no running shell, and a later ./install.sh --only=dms then has only
  # the download left to do. Taking the whole run down for this cost six later
  # stages -- the login screen among them -- for one unreachable server.
  if install_dms_runtime; then
    verify_dms_shell
    install_dms_plugins
    deploy_dms_settings
  else
    install_dms_plugins
    deploy_dms_settings
    warn "Your settings are in place, but the desktop shell itself is not installed yet"
    info "When the connection is working: ./install.sh --only=dms"
  fi
}

# The unit shipped in this repo hardcodes /usr/bin/dms, which is where the
# captured machine had it. The upstream installer may put it in ~/.local/bin
# instead, and a unit pointing at the wrong path simply restarts forever.
fix_dms_service_path() {
  local unit="$HOME/.config/systemd/user/dms.service"
  [[ -f $unit ]] || return 0
  local dms_path; dms_path=$(command -v dms 2>/dev/null || true)
  if [[ -z $dms_path ]]; then
    soft_fail "Could not find the desktop shell program to point the startup file at" \
              "The dms command is not on your PATH." \
              "./install.sh --only=dms"
    return 0
  fi
  if grep -q "ExecStart=$dms_path " "$unit"; then
    skip "The desktop shell startup file is already correct"
    return 0
  fi
  run sed -i -E "s|^ExecStart=.*/dms run|ExecStart=$dms_path run|" "$unit"
  run systemctl --user daemon-reload
  ok "Pointed the startup file at the desktop shell"
}

# The lowest quickshell this shell's QML is known to run on. Below it the
# parser rejects `//@ pragma AppId`, the shell exits 255 before drawing
# anything, and the supervisor still reports a healthy start.
QUICKSHELL_FLOOR="0.3.1"

# From 1.6 the shell's QML is compiled into the dms binary and
# ~/.config/quickshell/dms is no longer auto-discovered, so a checkout there is
# neither required nor consulted. Below 1.6 it is the shell.
DMS_EMBEDDED_SHELL_FROM="1.6.0"

dms_version() {
  local v
  v=$(dms --version 2>/dev/null || dms version 2>/dev/null) || return 1
  [[ $v =~ ([0-9]+\.[0-9]+\.[0-9]+) ]] || return 1
  printf '%s\n' "${BASH_REMATCH[1]}"
}

dms_embeds_shell() {
  local v; v=$(dms_version) || return 1
  printf '%s\n%s\n' "$DMS_EMBEDDED_SHELL_FROM" "$v" | sort -V -C
}

quickshell_version() {
  local v
  v=$(quickshell --version 2>/dev/null || qs --version 2>/dev/null) || return 1
  [[ $v =~ ([0-9]+\.[0-9]+\.[0-9]+) ]] || return 1
  printf '%s\n' "${BASH_REMATCH[1]}"
}

# A quickshell from dnf shadows the one the DMS installer would have placed,
# and the installer will not replace what it finds. If the shadowing build is
# too old, it has to go before the installer runs, or the shell never starts.
ensure_quickshell() {
  have quickshell || have qs || return 0

  local v; v=$(quickshell_version) || {
    warn "quickshell is installed but will not say which version it is"
    return 0
  }

  # sort -V -C succeeds when the input is already ascending, so this is true
  # exactly when v is at or above the floor.
  if printf '%s\n%s\n' "$QUICKSHELL_FLOOR" "$v" | sort -V -C; then
    skip "quickshell $v is new enough to draw the desktop"
    return 0
  fi

  warn "quickshell $v is too old to draw this desktop; it needs $QUICKSHELL_FLOOR or newer"

  if ! rpm_has quickshell; then
    soft_fail "A too-old quickshell is in the way and cannot be removed automatically" \
              "It was not installed by Fedora's package manager, so this installer will not delete it." \
              "Remove it by hand, then run ./install.sh again"
    return 0
  fi

  info "Removing the old quickshell so the correct one can be installed"
  if as_root dnf remove -y quickshell; then
    ok "Removed the old quickshell"
  else
    soft_fail "Could not remove the old quickshell $v" \
              "The desktop will not appear while it is in the way." \
              "sudo dnf remove quickshell, then run ./install.sh again"
  fi
  return 0
}

# Upstream's installer is a full-screen program with its own list of optional
# extras, which is the second list of choices you are asked for. If the version
# on the server accepts a flag for running unattended, use it: its defaults are
# already what this installer wants, and dms-greeter in particular must stay
# off, since the login screen here is SDDM.
#
# The flag is looked for in the downloaded script rather than assumed, because
# it is somebody else's program and the name changes between releases.
dank_noninteractive_flag() {
  local script=$1 candidate
  for candidate in --non-interactive --noninteractive --headless --unattended --yes; do
    grep -qF -- "$candidate" "$script" && { printf '%s' "$candidate"; return 0; }
  done
  return 0
}

# Run it attached to the terminal. run_visible would put it behind a pipe to
# tee, and a full-screen program drawing into a pipe is what turned that screen
# into overlapping text.
dank_run_installer() {
  local script=$1; shift
  _log_raw "RUN   sh $script $*"
  if (( $# == 0 )); then
    printf '\n  %s→%s The next screen belongs to the desktop shell'"'"'s own installer,\n' "$C_CYAN" "$C_OFF"
    printf '    not to this one. Its defaults already match what you chose.\n'
    printf '    %sPress Enter to continue.%s\n\n' "$C_BOLD" "$C_OFF"
    sleep 2
  fi

  # Give it a clean screen to start on and take the terminal back afterwards.
  # It draws its own frames and can leave the cursor hidden, the colours set,
  # or half a line of its last screen behind.
  # Screen only, not the scrollback: `tput clear` on the console also throws
  # away everything the earlier stages printed.
  local rc=0
  printf '\033[H\033[2J'
  sh "$script" "$@" || rc=$?
  printf '\033[0m\033[?25h\033[H\033[2J'
  return "$rc"
}

# Upstream's installer knows which quickshell revision it needs; reproducing
# that here would rot. Run it, then layer our config on top.
install_dms_runtime() {
  # `dms` being present is not enough: the installer also places quickshell and
  # the shell QML, and a run that got as far as the binary may have stopped
  # before either. Re-run it unless all three are there; it is idempotent.
  if have dms && ( have quickshell || have qs ) \
     && { dms_embeds_shell || shell_qml_path >/dev/null; }; then
    local _v; _v=$(dms --version 2>/dev/null | head -1)
    skip "The desktop shell is already installed${_v:+ ($_v)}"
    return 0
  fi
  info "Downloading and installing the desktop shell. This takes a few minutes."
  if (( DRY_RUN )); then
    info '$ curl -fsSL https://install.danklinux.com | sh'
    return 0
  fi
  local tmp; tmp=$(mktemp -d)
  local script="$tmp/danklinux.sh"

  # Fetched to a file rather than piped into sh, so a failed download is told
  # apart from a failed install, and so the installer can be handed arguments.
  local attempt got=0
  for attempt in 1 2 3; do
    if run curl -fsSL -o "$script" https://install.danklinux.com; then got=1; break; fi
    (( attempt < 3 )) && {
      warn "could not reach the download server, trying again ($attempt of 3)"
      sleep $(( attempt * 5 ))
    }
  done
  if (( ! got )); then
    rm -rf "$tmp"
    soft_fail "The desktop shell could not be downloaded" \
        "Its download server could not be reached. Everything else on this machine is unaffected." \
        "When the connection is working: ./install.sh --only=dms"
    return 1
  fi

  local -a args=()
  local flag
  flag=$(dank_noninteractive_flag "$script")
  [[ -n $flag ]] && args=("$flag")

  local ok_run=0
  for attempt in 1 2 3; do
    if dank_run_installer "$script" ${args[@]+"${args[@]}"}; then ok_run=1; break; fi
    (( attempt < 3 )) && {
      warn "the desktop shell installer did not finish, trying again ($attempt of 3)"
      sleep $(( attempt * 5 ))
    }
  done
  rm -rf "$tmp"

  if (( ! ok_run )) || ! have dms; then
    soft_fail "The desktop shell could not be downloaded" \
        "Its installer could not reach GitHub to find out which version to fetch. Everything else on this machine is unaffected." \
        "When the connection is working: ./install.sh --only=dms"
    return 1
  fi
  # The upstream installer decides its own paths, so what it left is read back
  # rather than assumed.
  local dms_bin; dms_bin=$(command -v dms 2>/dev/null)
  [[ -n $dms_bin ]] && record file "$dms_bin"
  local qs_bin; qs_bin=$(command -v quickshell 2>/dev/null)
  [[ -n $qs_bin ]] && record file "$qs_bin"
  record note "the desktop shell came from https://install.danklinux.com"
  ok "Installed the desktop shell"
}

# The `dms` binary is only a supervisor. What draws the bar is a quickshell
# process it launches against the shell's QML, and that QML is fetched
# separately by the upstream installer. When the fetch fails -- which it does
# on a connection that intercepts plain HTTP -- the binary still installs and
# still reports "daemon started", but nothing ever appears on screen. Checking
# for the entry point turns that silence into a message.
shell_qml_path() {
  local root="$HOME/.config/quickshell/dms" entry
  for entry in "$root/quickshell/shell.qml" "$root/shell.qml"; do
    [[ -f $entry ]] && { printf '%s\n' "$entry"; return 0; }
  done
  return 1
}

verify_dms_shell() {
  local root="$HOME/.config/quickshell/dms"
  local entry

  if dms_embeds_shell; then
    skip "This version of the desktop shell carries everything it needs internally"
    return 0
  fi

  if entry=$(shell_qml_path); then
    ok "The desktop shell has the files it draws from"
    return 0
  fi

  (( DRY_RUN )) && { info "Would check the desktop shell files are present"; return 0; }

  soft_fail "The desktop shell program is installed but the files it draws from are missing" \
            "Those files download separately, and the download failed. This is why the bar never appears even though the shell reports that it started." \
            "curl -fsSL https://install.danklinux.com | sh"
  return 0
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

  if [[ -e $plugins/$name && -z ${DMS_PLUGIN_VENDOR[$name]:-} ]]; then
    skip "The $name add-on is already installed"
    return 0
  fi

  # Anything DMS knows about is best installed through DMS itself, so the
  # plugin registry and settings stay consistent. Pinned plugins skip this:
  # the registry would hand back upstream and silently replace a fork.
  if [[ -z ${DMS_PLUGIN_PINNED[$name]:-} ]]; then
    if have dms && dms plugins install "$name" >/dev/null 2>&1; then
      ok "Installed the $name add-on"
      return 0
    fi
  fi

  local repo sub branch source dir hash

  if [[ -n ${DMS_PLUGIN_VENDOR[$name]:-} ]]; then
    local vdir
    IFS='|' read -r vdir sub <<< "${DMS_PLUGIN_VENDOR[$name]}"
    source="$REPO_DIR/assets/dms-plugins/$vdir"
    [[ -d $source ]] || { soft_fail "The $name add-on is missing from this repository" \
         "It should be in assets/dms-plugins/$vdir." \
         "git pull, then ./install.sh --only=dms"; return 0; }
    hash=$(printf 'vendor:%s' "$vdir" | sha256sum | cut -c1-16)
    dir="$plugins/.repos/$hash"
    run rm -rf "$dir"
    run mkdir -p "$dir"
    run cp -a "$source/." "$dir/"
    repo="vendored from assets/dms-plugins/$vdir"
    branch=""
  else
    local spec=${DMS_PLUGIN_REPO[$name]:-}
    if [[ -z $spec ]]; then
      soft_fail "Do not know where to get the $name add-on, so it was skipped"
      return 0
    fi
    IFS='|' read -r repo sub branch <<< "$spec"
    hash=$(printf '%s' "$repo" | sha256sum | cut -c1-16)
    dir="$plugins/.repos/$hash"

    if [[ -d $dir/.git ]]; then
      run git -C "$dir" fetch --depth 1 origin "${branch:-HEAD}" || warn "Could not download an update for the $name add-on"
      run git -C "$dir" checkout -q FETCH_HEAD || warn "Could not update the $name add-on"
    else
      local -a clone=(git clone --depth 1)
      [[ -n $branch ]] && clone+=(--branch "$branch")
      retry 3 "${clone[@]}" "$repo" "$dir" || { soft_fail "Could not download the $name add-on" \
           "The download from $repo failed." \
           "./install.sh --only=dms"; return 0; }
    fi
  fi

  local target="$dir"
  [[ $sub != "." ]] && target="$dir/$sub"
  [[ -d $target ]] || { soft_fail "The $name add-on downloaded but does not contain what was expected"; return 0; }

  # Relative, so the link survives a different \$HOME. The captured config had
  # these pointing at an absolute /home/hanafi.
  backup_path "$plugins/$name"
  run rm -rf "$plugins/$name"
  if [[ $sub == "." ]]; then
    run ln -sfn ".repos/$hash" "$plugins/$name"
  else
    run ln -sfn ".repos/$hash/$sub" "$plugins/$name"
  fi
  record file "$plugins/$name"
  record file "$dir"
  record file "$plugins/$name.meta"
  (( DRY_RUN )) || printf 'repo=%s\npath=%s\nrepodir=%s\nbranch=%s\n' \
    "$repo" "$sub" "$hash" "${branch:-HEAD}" > "$plugins/$name.meta"
  ok "Installed the $name add-on"

  plugin_post_install "$name" "$dir"

}

# Plugins that need more than their QML copied into place.
plugin_post_install() {
  local name=$1 repo_dir=$2
  case $name in
    quickCapture)
      # A Rust screenshot backend that has to be compiled.
      [[ -x $repo_dir/scripts/install-backend.sh ]] || return 0
      have cargo || { soft_fail "The $name add-on needs the Rust toolchain, which is not installed" \
                            "Part of it has to be compiled." \
                            "Re-run ./install.sh and tick language runtimes"; return 0; }
      run_visible "$repo_dir/scripts/install-backend.sh" || soft_fail "The $name add-on did not finish building" "" "./install.sh --only=dms"
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
    skip "The CLIAMP music player is already installed"
  else
    # The project publishes a prebuilt binary and a one-line installer for it.
    # Compiling from source was the fallback and is now only that: it needs the
    # Go toolchain, takes minutes, and fails on any machine without it.
    # Downloaded to a file and then run, never `curl ... | sh`: pipefail does
    # not apply inside the new shell, so a failed download feeds an empty
    # script to sh, which exits 0 and reports the install as a success.
    local tmp; tmp=$(mktemp -d)
    local got=0
    run curl -fsSL -o "$tmp/cliamp-install.sh" https://cliamp.stream/install.sh && got=1
    if (( got )) && run_quiet "Installing the CLIAMP music player" -- sh "$tmp/cliamp-install.sh"; then
      rm -rf "$tmp"
      have cliamp && record file "$(command -v cliamp)"
    elif rm -rf "$tmp"; have go; then
      warn "the download failed, building it from source instead"
      run_quiet "Building the CLIAMP music player" -- \
        env GOBIN="$HOME/.local/bin" go install github.com/bjarneo/cliamp@latest \
        || soft_fail "The CLIAMP music player did not build" "" "./install.sh --only=dms"
    else
      soft_fail "The CLIAMP music player could not be downloaded" \
                "Its download server could not be reached, and there is no Go toolchain here to build it from source." \
                "curl -fsSL https://cliamp.stream/install.sh | sh"
    fi
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
    # CLIAMP refuses to load a Lua plugin it has not been told to trust, and
    # says so only in its own startup output. Copying the file is not enough.
    if have cliamp; then
      if run cliamp plugins trust cliamp-dms-bridge; then
        ok "CLIAMP radio support is ready. Turn it on from the Radio tab in the widget."
      else
        soft_fail "Could not mark the CLIAMP radio add-on as trusted" \
                  "CLIAMP will refuse to load it until it is." \
                  "cliamp plugins trust cliamp-dms-bridge"
      fi
    else
      info "CLIAMP radio support is in place. Once CLIAMP is installed: cliamp plugins trust cliamp-dms-bridge"
    fi
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

  [[ -d $repo_dir/backend ]] || { soft_fail "The lyrics add-on is missing the part that fetches the words"; return 0; }

  # The sources are refreshed every run, since the vendored copy is what
  # changes; only the virtualenv is expensive enough to reuse.
  run mkdir -p "$dest"
  record file "$dest"
  run rsync -a --exclude='.venv' "$repo_dir/backend/" "$dest/backend/" \
    || run cp -a "$repo_dir/backend/." "$dest/backend/"

  if [[ -x $dest/backend/.venv/bin/python ]]; then
    skip "The lyrics helper is already built"
  else
    # dbus-python has no wheel and compiles against dbus-devel and glib2-devel,
    # so this is a real build and not a download.
    run_quiet "Building the lyrics helper" -- \
      bash -c 'python3 -m venv "$1/.venv" \
        && "$1/.venv/bin/pip" install --upgrade pip \
        && "$1/.venv/bin/pip" install -r "$1/requirements.txt"' _ "$dest/backend" \
      || { soft_fail "The lyrics helper did not finish building" \
           "It compiles small Python pieces that need development headers." \
           "sudo dnf install dbus-devel glib2-devel, then ./install.sh --only=dms"; return 0; }
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
  run systemctl --user enable "$unit" && record unit-user "$unit" || soft_fail "Could not set the lyrics helper to start automatically" "" "systemctl --user enable $unit"
  ok "The lyrics helper will start when you log in"
}

# settings.json and plugin_settings.json, rewritten for this install.
deploy_dms_settings() {
  local src="$REPO_DIR/config/shell-ui/DankMaterialShell"
  run mkdir -p "$DMS_CONFIG/themes"
  deploy_tree "$src/themes" "$DMS_CONFIG/themes"
  ok "Installed $(count_files "$src/themes" -maxdepth 1) colour themes"

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
  info "Sized the desktop clock for a ${width}x${height} screen"

  (( DRY_RUN )) && { info "Would write the desktop shell settings"; return 0; }

  KEEP_PLUGINS="$keep" DEAD_PLUGINS="$dead" \
  OUTPUT_NAME="$TPL_MONITOR" SCREEN_W="$width" SCREEN_H="$height" \
  python3 "$REPO_DIR/lib/dms_settings.py" \
    "$DMS_CONFIG/settings.json" "$DMS_CONFIG/plugin_settings.json" \
    || die "Could not write the desktop shell settings" \
         "The settings file could not be read or written." \
         "./install.sh --only=dms"
  ok "Set the Nothing Matrix theme, the desktop clock and $(wc -w <<<"${keep//,/ }") add-ons"
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
