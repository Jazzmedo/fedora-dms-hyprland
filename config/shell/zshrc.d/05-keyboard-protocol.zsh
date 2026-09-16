# Pop any terminal keyboard-protocol mode a TUI left enabled.
#
# Editors and full-screen tools -- nvim, lazygit, yazi, btop, Claude Code --
# ask the terminal for the "progressive enhancement" keyboard protocol, where
# every key arrives as an escape sequence like ESC [ 8 ; 6 u instead of a plain
# byte. They pop it again when they exit, unless they are killed, crash, or are
# left behind in a dead ssh or tmux session.
#
# ZLE does not speak that protocol. It swallows the ESC [ while waiting for a
# key sequence it recognises and inserts the remainder as literal text, so a
# keypress turns into "8;6u" on the command line and a paste comes out mangled.
#
# CSI < u pops an entry off the terminal's keyboard-mode stack. Emitting it
# before every prompt makes the shell self-healing: the worst a crashed TUI can
# cost is the keys pressed before the next prompt. It is a no-op when the stack
# is empty, and a terminal that does not implement the protocol ignores it.
if [[ -o interactive ]]; then
  autoload -Uz add-zsh-hook
  _reset_keyboard_protocol() { [[ -t 1 ]] && printf '\e[<u'; }
  add-zsh-hook precmd _reset_keyboard_protocol
fi
