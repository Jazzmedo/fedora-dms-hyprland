# shellcheck shell=bash
# zsh and its fragments, starship, Neovim/LazyVim, and the terminal tools that
# the fragments assume are on PATH.

stage_shell() {
  is_selected zsh || is_selected editor || { skip "shell stage not selected"; return 0; }
  step "Shell & editor"
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
    skip "oh-my-zsh present"
  elif retry 2 git clone --depth 1 https://github.com/ohmyzsh/ohmyzsh.git "$omz"; then
    ok "oh-my-zsh installed"
  else
    soft_fail "oh-my-zsh clone failed; the zsh fragments skip it when absent"
  fi

  local custom="$omz/custom/plugins"
  local spec name repo
  for spec in \
    "zsh-autosuggestions|https://github.com/zsh-users/zsh-autosuggestions" \
    "zsh-syntax-highlighting|https://github.com/zsh-users/zsh-syntax-highlighting"
  do
    name=${spec%%|*}; repo=${spec##*|}
    if [[ -d $custom/$name ]]; then
      skip "plugin $name present"
    elif retry 2 git clone --depth 1 "$repo" "$custom/$name"; then
      ok "plugin $name"
    else
      soft_fail "could not clone $name"
    fi
  done

  # The fragments live under XDG config; ~/.zshrc is only a six-line loader.
  # These are deployed whether or not the clones above worked, because the
  # loader and the fragments degrade gracefully on their own.
  deploy_tree "$REPO_DIR/config/shell/zshrc.d" "$HOME/.config/zsh/zshrc.d" \
    || soft_fail "could not deploy the zsh fragments"
  deploy_file "$REPO_DIR/config/shell/zshrc" "$HOME/.zshrc" \
    || soft_fail "could not deploy ~/.zshrc"
  ok "zsh fragments in ~/.config/zsh/zshrc.d/"

  # The syntax-highlighting palette the first fragment sources.
  if [[ -f $HOME/.zsh/catppuccin_mocha-zsh-syntax-highlighting.zsh ]]; then
    skip "syntax-highlighting palette present"
  else
    run mkdir -p "$HOME/.zsh"
    retry 2 curl -fsSL -o "$HOME/.zsh/catppuccin_mocha-zsh-syntax-highlighting.zsh" \
      https://raw.githubusercontent.com/catppuccin/zsh-syntax-highlighting/main/themes/catppuccin_mocha-zsh-syntax-highlighting.zsh \
      || warn "could not fetch the syntax-highlighting palette; the fragment skips it"
  fi

  set_login_shell
}

# chsh refuses a shell that is not listed in /etc/shells, and the message it
# prints when that happens is easy to miss in a long install.
set_login_shell() {
  local zsh_path; zsh_path=$(command -v zsh 2>/dev/null || true)
  if [[ -z $zsh_path ]]; then
    soft_fail "zsh is not installed, so the login shell was left alone"
    return 0
  fi

  local current; current=$(getent passwd "$USER" | cut -d: -f7)
  if [[ $current == "$zsh_path" ]]; then
    skip "zsh is already the login shell"
    return 0
  fi

  grep -qx "$zsh_path" /etc/shells 2>/dev/null \
    || as_root bash -c "printf '%s\n' '$zsh_path' >> /etc/shells"

  if as_root chsh -s "$zsh_path" "$USER"; then
    ok "login shell set to zsh (takes effect at your next login)"
  else
    soft_fail "could not change the login shell; run: chsh -s $zsh_path"
  fi
}

install_neovim() {
  local nvim="$HOME/.config/nvim"
  deploy_tree "$REPO_DIR/config/editor/nvim" "$nvim"
  ok "LazyVim config deployed"

  # lazy-lock.json pins every plugin, so a headless sync reproduces the exact
  # set and the first interactive launch has nothing to install.
  if (( DRY_RUN )); then
    info "would run: nvim --headless +'Lazy! restore' +qa"
  elif have nvim; then
    info "syncing Neovim plugins (first run pulls them all)"
    timeout 300 nvim --headless "+Lazy! restore" +qa >/dev/null 2>&1 \
      || soft_fail "Neovim plugin sync did not finish; open nvim once to complete it"
    ok "Neovim plugins synced"
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
  ok "tool configs deployed"
}

install_runtime_managers() {
  is_selected devtools || return 0

  if [[ -d $HOME/.nvm ]]; then skip "nvm present"
  else
    retry 2 git clone --depth 1 https://github.com/nvm-sh/nvm.git "$HOME/.nvm" \
      && ok "nvm installed" || soft_fail "nvm clone failed"
  fi

  if [[ -d $HOME/.pyenv ]]; then skip "pyenv present"
  else
    retry 2 git clone --depth 1 https://github.com/pyenv/pyenv.git "$HOME/.pyenv" \
      && ok "pyenv installed" || soft_fail "pyenv clone failed"
    [[ -d $HOME/.pyenv ]] && retry 2 git clone --depth 1 \
      https://github.com/pyenv/pyenv-virtualenv.git "$HOME/.pyenv/plugins/pyenv-virtualenv" \
      || true
  fi

  if have rustup || [[ -d $HOME/.cargo ]]; then skip "rust toolchain present"
  elif rpm_has cargo; then skip "cargo from dnf"
  else
    run_visible bash -c 'curl --proto =https --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path' \
      || soft_fail "rustup install failed"
  fi

  run systemctl --user enable --now podman.socket 2>/dev/null || true
  ok "runtime managers ready"
}
