# fastfetch presets. config.jsonc is the matugen-themed default and is rewritten
# on every palette change; the others are hand-maintained alternatives.
alias ff='fastfetch'
alias ffp='fastfetch --config ~/.config/fastfetch/config-pokemon.jsonc'
alias ff2='fastfetch --config ~/.config/fastfetch/config-v2.jsonc'

# The greeting, on a new terminal only.
#
# Guarded, because a fetch that prints where it is not wanted is
# worse than none at all: not without a terminal (scp and rsync both break on
# any output from a login shell), not inside another program's shell (nvim's
# :terminal, a git rebase editor), and once per tmux session rather than once
# per pane. Set FF_IN_TMUX=1 to greet in every pane.
_ff_greeting() {
  [[ -o interactive ]]              || return 0
  [[ -t 1 ]]                        || return 0
  [[ -z $INSIDE_NVIM$NVIM$VIMRUNTIME ]] || return 0
  [[ -z $TMUX ]] || [[ -n $FF_IN_TMUX ]] || return 0
  command -v fastfetch >/dev/null   || return 0
  fastfetch
}
_ff_greeting
unfunction _ff_greeting
