# shellcheck shell=bash
# zsh and its fragments, starship, Neovim/LazyVim, and the terminal tools that
# the fragments assume are on PATH.

stage_shell() {
  if is_selected zsh; then install_zsh; else skip "zsh was not chosen"; fi
  if is_selected editor; then install_neovim; else skip "Neovim was not chosen"; fi
  install_tool_configs
  install_runtime_managers
  return 0
}

install_zsh() {
  # Each piece is independent. A failed oh-my-zsh clone used to return early
  # and take the fragments, .zshrc, starship and the login shell with it.
  local omz="$HOME/.oh-my-zsh"
  if [[ -d $omz ]]; then
    skip "oh-my-zsh is already installed"
  elif retry 2 git clone --depth 1 https://github.com/ohmyzsh/ohmyzsh.git "$omz" && record file "$omz"; then
    ok "Installed oh-my-zsh, which manages your shell add-ons"
  else
    soft_fail "Could not download oh-my-zsh" \
              "Your shell will still work, just with fewer conveniences." \
              "./install.sh --only=shell"
  fi

  local custom="$omz/custom/plugins"
  local spec name repo
  for spec in \
    "zsh-autosuggestions|https://github.com/zsh-users/zsh-autosuggestions" \
    "zsh-syntax-highlighting|https://github.com/zsh-users/zsh-syntax-highlighting"
  do
    name=${spec%%|*}; repo=${spec##*|}
    if [[ -d $custom/$name ]]; then
      skip "The $name shell add-on is already installed"
    elif retry 2 git clone --depth 1 "$repo" "$custom/$name"; then
      ok "Installed the $name shell add-on"
    else
      soft_fail "Could not download the $name shell add-on" "" "./install.sh --only=shell"
    fi
  done

  # The fragments live under XDG config; ~/.zshrc is only a six-line loader.
  # These are deployed whether or not the clones above worked, because the
  # loader and the fragments degrade gracefully on their own.
  deploy_tree "$REPO_DIR/config/shell/zshrc.d" "$HOME/.config/zsh/zshrc.d" \
    || soft_fail "Could not copy the shell settings into place" "" "./install.sh --only=shell"
  deploy_file "$REPO_DIR/config/shell/zshrc" "$HOME/.zshrc" \
    || soft_fail "Could not write your ~/.zshrc" "" "./install.sh --only=shell"
  ok "Your shell settings are in ~/.config/zsh/zshrc.d/, one file per topic"

  # The syntax-highlighting palette the first fragment sources.
  if [[ -f $HOME/.zsh/catppuccin_mocha-zsh-syntax-highlighting.zsh ]]; then
    skip "The shell colour scheme is already installed"
  else
    run mkdir -p "$HOME/.zsh"
    retry 2 curl -fsSL -o "$HOME/.zsh/catppuccin_mocha-zsh-syntax-highlighting.zsh" \
      https://raw.githubusercontent.com/catppuccin/zsh-syntax-highlighting/main/themes/catppuccin_mocha-zsh-syntax-highlighting.zsh \
      || warn "Could not download the shell colour scheme; the shell works without it"
  fi

  set_login_shell
}

# chsh refuses a shell that is not listed in /etc/shells, and the message it
# prints when that happens is easy to miss in a long install.
set_login_shell() {
  local zsh_path; zsh_path=$(command -v zsh 2>/dev/null || true)
  if [[ -z $zsh_path ]]; then
    soft_fail "zsh is not installed, so your login shell was left as it is" \
               "The package did not install earlier." \
               "./install.sh --only=packages,shell"
    return 0
  fi

  local current; current=$(getent passwd "$USER" | cut -d: -f7)
  if [[ $current == "$zsh_path" ]]; then
    skip "zsh is already your login shell"
    return 0
  fi

  grep -qx "$zsh_path" /etc/shells 2>/dev/null \
    || { as_root bash -c "printf '%s\n' '$zsh_path' >> /etc/shells"; record edited /etc/shells; }

  # The old shell goes in the ledger before it is replaced; there is nowhere
  # else to read it from afterwards.
  record shell "$USER" "$current"
  if as_root chsh -s "$zsh_path" "$USER" && [[ $(getent passwd "$USER" | cut -d: -f7) == "$zsh_path" ]]; then
    ok "zsh is now your login shell. This takes effect the next time you log in."
  else
    soft_fail "Could not make zsh your login shell" \
               "The change needs your password and was refused." \
               "chsh -s $zsh_path"
  fi
}

install_neovim() {
  local nvim="$HOME/.config/nvim"
  deploy_tree "$REPO_DIR/config/editor/nvim" "$nvim"
  ok "Copied the Neovim setup into place"

  # lazy-lock.json pins every plugin, so a headless sync reproduces the exact
  # set and the first interactive launch has nothing to install.
  if (( DRY_RUN )); then
    info "Would download the Neovim add-ons"
  elif have nvim; then
    run_quiet "Neovim add-ons downloaded" -- \
      timeout 300 nvim --headless "+Lazy! restore" +qa \
      || soft_fail "The Neovim add-ons did not all download" \
           "It timed out, usually a slow connection." \
           "Open nvim once and it will finish on its own."
  fi
}

install_tool_configs() {
  local t="$REPO_DIR/config/tools"
  if is_selected sysinfo; then
    deploy_tree "$t/btop"      "$HOME/.config/btop"
    deploy_tree "$t/cava"      "$HOME/.config/cava"
    deploy_tree "$t/fastfetch" "$HOME/.config/fastfetch"
  fi
  is_selected filemgr_tui && deploy_tree "$t/yazi" "$HOME/.config/yazi"
  is_selected mux         && deploy_tree "$REPO_DIR/config/shell/tmux" "$HOME/.config/tmux"
  # starship.toml and fastfetch/config.jsonc are matugen targets, so both get
  # rewritten with the live palette the first time the theme changes.
  if is_selected prompt; then
    deploy_file "$REPO_DIR/config/shell/starship.toml" "$HOME/.config/starship.toml"
    ensure_starship
  fi
  ok "Copied the settings for the smaller tools into place"
}

# The prompt comes from the starship rpm, installed with --skip-unavailable
# along with everything else, so a repository that does not carry it drops it
# without a word. The shell then starts with no prompt configured and nothing
# says why. Install it from upstream instead of leaving that hole.
ensure_starship() {
  have starship && return 0
  (( DRY_RUN )) && { info "Would install the starship prompt from starship.rs"; return 0; }

  local tmp; tmp=$(mktemp -d)
  if ! run curl -fsSL -o "$tmp/starship.sh" https://starship.rs/install.sh; then
    clean_tmp "$tmp"
    soft_fail "The prompt could not be installed" \
              "Fedora does not carry the starship package and its own site could not be reached." \
              "./install.sh --only=shell"
    return 0
  fi
  mkdir -p "$HOME/.local/bin"
  if run_quiet "Installing the starship prompt" -- \
       sh "$tmp/starship.sh" --yes --bin-dir "$HOME/.local/bin"; then
    record file "$HOME/.local/bin/starship"
    ok "Installed the starship prompt"
  else
    soft_fail "The prompt could not be installed" "" "./install.sh --only=shell"
  fi
  clean_tmp "$tmp"
  return 0
}

install_runtime_managers() {
  if is_selected mise; then
    if have mise || [[ -x $HOME/.local/bin/mise ]]; then skip "mise is already installed"
    else
      run_visible bash -c 'curl -fsSL https://mise.run | MISE_INSTALL_PATH="$HOME/.local/bin/mise" sh' \
        && record file "$HOME/.local/bin/mise" \
        && ok "Installed mise, for managing tool versions" \
        || soft_fail "Could not install mise" "Its installer could not be downloaded." "./install.sh --only=shell"
    fi
  fi

  # pnpm's own installer edits .zshrc, which is a loader here; the standalone
  # binary from its releases needs nothing else.
  if is_selected pnpm; then
    if have pnpm || [[ -x $HOME/.local/bin/pnpm ]]; then skip "pnpm is already installed"
    else
      local arch=x64; [[ $(uname -m) == aarch64 ]] && arch=arm64
      run mkdir -p "$HOME/.local/bin"
      retry 2 curl -fsSL -o "$HOME/.local/bin/pnpm" \
          "https://github.com/pnpm/pnpm/releases/latest/download/pnpm-linux-$arch" \
        && run chmod +x "$HOME/.local/bin/pnpm" \
        && record file "$HOME/.local/bin/pnpm" \
        && ok "Installed pnpm" \
        || soft_fail "Could not download pnpm" "" "./install.sh --only=shell"
    fi
  fi

  # mise fetches yt-dlp's own standalone build, which updates itself in place
  # with `yt-dlp -U`; sites break old releases quickly. Codex and OpenCode
  # update with `mise up`. mise was installed just above, so it may not be on
  # PATH yet.
  local mise spec key tool
  mise=$(command -v mise || echo "$HOME/.local/bin/mise")
  for spec in ytdlp:yt-dlp codex:codex opencode:opencode; do
    key=${spec%%:*} tool=${spec#*:}
    is_selected "$key" || continue
    if [[ -d $HOME/.local/share/mise/installs/$tool ]]; then skip "$tool is already installed"
    elif [[ -x $mise ]]; then
      run "$mise" use -g "$tool" \
        && ok "Installed $tool through mise" \
        || soft_fail "Could not install $tool" "mise could not download it; GitHub may be rate-limiting this address." \
                     "mise use -g $tool"
    else
      soft_fail "Could not install $tool" "mise is not installed." "./install.sh --only=shell"
    fi
  done

  # Anthropic's own installer, not mise: only that copy updates itself.
  if is_selected claude_code; then
    if [[ -x $HOME/.local/bin/claude ]]; then skip "Claude Code is already installed"
    else
      run bash -c 'curl -fsSL https://claude.ai/install.sh | bash' \
        && ok "Installed Claude Code; run claude to sign in" \
        || soft_fail "Could not install Claude Code" "" "curl -fsSL https://claude.ai/install.sh | bash"
    fi
  fi

  # The GLM Coding Plan is Claude Code pointed at Z.ai. It keeps its own
  # config folder, so it never mixes with a Claude sign-in.
  if is_selected glm; then
    if (( DRY_RUN )); then info "Would write ~/.local/bin/glm"
    else
      mkdir -p "$HOME/.local/bin" "$HOME/.config/glm"
      cat > "$HOME/.local/bin/glm" <<'GLM'
#!/bin/sh
# Claude Code on the Z.ai GLM Coding Plan. Key: https://z.ai/manage-apikey/apikey-list
key_file="$HOME/.config/glm/api-key"
if [ ! -s "$key_file" ]; then
  printf 'Paste your Z.ai API key: ' >&2
  stty -echo 2>/dev/null; read -r key; stty echo 2>/dev/null; printf '\n' >&2
  [ -n "$key" ] || exit 1
  (umask 077; printf '%s\n' "$key" > "$key_file")
fi
ANTHROPIC_BASE_URL=https://api.z.ai/api/anthropic \
ANTHROPIC_AUTH_TOKEN=$(cat "$key_file") \
API_TIMEOUT_MS=3000000 \
CLAUDE_CONFIG_DIR="$HOME/.config/glm/claude" \
  exec claude "$@"
GLM
      chmod 755 "$HOME/.local/bin/glm"
      record file "$HOME/.local/bin/glm"
      ok "Added the glm command; it asks for your Z.ai API key the first time"
    fi
  fi

  if is_selected rust; then
    if have rustup || [[ -d $HOME/.cargo ]]; then skip "The Rust toolchain is already installed"
    elif rpm_has cargo; then skip "Rust is already installed through Fedora"
    else
      run_visible bash -c 'curl --proto =https --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path' \
        && ok "Installed Rust and cargo" \
        || soft_fail "Could not install Rust" "The installer script failed to download." "./install.sh --only=shell"
    fi
  fi

  if is_selected podman; then
    if user_bus_ok; then
      run systemctl --user enable --now podman.socket 2>/dev/null && record unit-user podman.socket || true
    else
      enable_user_unit podman.socket && record unit-user podman.socket || true
    fi
  fi

  # Membership of the docker group takes effect at the next login.
  if is_selected docker && have docker; then
    as_root systemctl enable --now docker && record unit-system docker || true
    if id -nG "$USER" | grep -qw docker; then skip "You are already in the docker group"
    else
      as_root usermod -aG docker "$USER" \
        && ok "Docker is running; log out and back in to use it without sudo" \
        || soft_fail "Could not add you to the docker group" "" "sudo usermod -aG docker $USER"
    fi
  fi
  return 0
}
