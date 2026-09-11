# starship draws the prompt and must initialise after oh-my-zsh has finished.
command -v starship >/dev/null && eval "$(starship init zsh)"
