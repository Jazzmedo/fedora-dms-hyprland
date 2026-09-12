# shellcheck shell=bash
# zsh and its fragments, starship, Neovim/LazyVim, and the terminal tools that
# the fragments assume are on PATH.

stage_shell() {
  is_selected zsh || is_selected editor || { skip "The terminal and editor setup was not chosen"; return 0; }
  is_selected zsh    && install_zsh
  is_selected editor && install_neovim
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
  elif retry 2 git clone --depth 1 https://github.com/ohmyzsh/ohmyzsh.git "$omz"; then
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
    || as_root bash -c "printf '%s\n' '$zsh_path' >> /etc/shells"

  if as_root chsh -s "$zsh_path" "$USER"; then
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
  is_selected prompt      && deploy_file "$REPO_DIR/config/shell/starship.toml" "$HOME/.config/starship.toml"
  ok "Copied the settings for the smaller tools into place"
}

install_runtime_managers() {
  is_selected devtools || return 0

  if [[ -d $HOME/.nvm ]]; then skip "nvm, the Node version manager, is already installed"
  else
    retry 2 git clone --depth 1 https://github.com/nvm-sh/nvm.git "$HOME/.nvm" \
      && ok "Installed nvm, for managing Node versions" \
      || soft_fail "Could not download nvm" "" "./install.sh --only=shell"
  fi

  if [[ -d $HOME/.pyenv ]]; then skip "pyenv, the Python version manager, is already installed"
  else
    retry 2 git clone --depth 1 https://github.com/pyenv/pyenv.git "$HOME/.pyenv" \
      && ok "Installed pyenv, for managing Python versions" \
      || soft_fail "Could not download pyenv" "" "./install.sh --only=shell"
    [[ -d $HOME/.pyenv ]] && retry 2 git clone --depth 1 \
      https://github.com/pyenv/pyenv-virtualenv.git "$HOME/.pyenv/plugins/pyenv-virtualenv" \
      || true
  fi

  if have rustup || [[ -d $HOME/.cargo ]]; then skip "The Rust toolchain is already installed"
  elif rpm_has cargo; then skip "Rust is already installed through Fedora"
  else
    run_visible bash -c 'curl --proto =https --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path' \
      || soft_fail "Could not install Rust" "The installer script failed to download." "./install.sh --only=shell"
  fi

  run systemctl --user enable --now podman.socket 2>/dev/null || true
  ok "The version managers for Node, Python and Rust are ready"
}
