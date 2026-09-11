# PATH, most specific first. Duplicate entries are harmless but pointless, so
# each is added only when its directory actually exists.
typeset -U path
for dir in \
  "$HOME/bin" \
  "$HOME/.local/bin" \
  "$HOME/.cargo/bin" \
  "$HOME/go/bin" \
  "$HOME/.spicetify" \
  "/usr/local/bin"
do
  [[ -d $dir ]] && path=("$dir" $path)
done
unset dir

export PNPM_HOME="$HOME/.local/share/pnpm"
[[ -d $PNPM_HOME ]] && path=("$PNPM_HOME" $path)
