# nvm, pyenv and mise. Each is skipped when absent; mise comes last so the
# versions it pins win over the other two.
export NVM_DIR="$HOME/.nvm"
[[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"
[[ -s "$NVM_DIR/bash_completion" ]] && source "$NVM_DIR/bash_completion"

export PYENV_ROOT="$HOME/.pyenv"
if [[ -d $PYENV_ROOT/bin ]]; then
  path=("$PYENV_ROOT/bin" $path)
  eval "$(pyenv init -)"
  eval "$(pyenv virtualenv-init -)" 2>/dev/null
fi

(( $+commands[mise] )) && eval "$(mise activate zsh)"
