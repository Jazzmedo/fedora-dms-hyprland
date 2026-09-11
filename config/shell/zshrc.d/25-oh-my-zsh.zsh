# oh-my-zsh, its plugins, and shell behaviour.
# The syntax-highlighting colour file is shipped alongside this fragment and
# must be sourced before oh-my-zsh loads the highlighter itself.
[[ -f ~/.zsh/catppuccin_mocha-zsh-syntax-highlighting.zsh ]] && \
  source ~/.zsh/catppuccin_mocha-zsh-syntax-highlighting.zsh

# Empty: starship draws the prompt, see 70-prompt.zsh.
ZSH_THEME=""
plugins=(git sudo zsh-autosuggestions zsh-syntax-highlighting)
[[ -f $ZSH/oh-my-zsh.sh ]] && source $ZSH/oh-my-zsh.sh

autoload -Uz compinit && compinit -u
setopt NO_HUP
setopt NO_CHECK_JOBS

# grc colourises the output of ping, dig, df and friends. Fedora installs its
# zsh hook at a different path than Debian does.
for grc_hook in /etc/profile.d/grc.sh /usr/share/grc/grc.zsh /etc/grc.zsh; do
  [[ -f $grc_hook ]] && source "$grc_hook" && break
done
unset grc_hook
