# shellcheck shell=bash
# What the run looks like while it happens: the stage header, the progress bar,
# and a spinner for the steps that would otherwise sit in silence.
#
# Sourced after common.sh, which owns the colours and the log file.

# ------------------------------------------------------------------ layout ---
# One width for the whole program. lib/ui.sh used to compute this inside the
# picker only, so a --yes run drew its rules at a different width from an
# interactive one.
ui_width() {
  local w
  w=$(tput cols 2>/dev/null) || w=""
  [[ $w =~ ^[0-9]+$ ]] || w=${COLUMNS:-80}
  (( w > 96 )) && w=96
  (( w < 40 )) && w=40
  printf '%s' "$w"
}

UI_WIDTH=$(ui_width)

# Parameter expansion, not `tr`: tr substitutes byte by byte and would shred a
# three-byte box-drawing character into mojibake.
rule() {
  local n=${1:-$UI_WIDTH} ch=${2:-─} pad
  (( n > 0 )) || return 0
  printf -v pad '%*s' "$n" ''
  printf '%s' "${pad// /$ch}"
}

# --------------------------------------------------------------- the stages ---
# What each stage is called in plain words, and one sentence on what it does.
# Keyed by the internal names in ALL_STAGES.
declare -A STAGE_TITLE=(
  [preflight]="Checks"
  [repos]="Software sources"
  [gpu]="Graphics"
  [packages]="Programs"
  [fonts]="Fonts"
  [hyprland]="Window manager"
  [dms]="Desktop shell"
  [themes]="Colours and wallpapers"
  [apps]="Everyday apps"
  [shell]="Terminal and editor"
  [tweaks]="System settings"
  [sddm]="Login screen"
  [optional]="Extras"
)

declare -A STAGE_BLURB=(
  [preflight]="Makes sure this machine can run the installer at all."
  [repos]="Tells Fedora where to get software it does not ship itself."
  [gpu]="Installs the driver for your graphics card."
  [packages]="Downloads and installs everything you chose. The longest step."
  [fonts]="Installs the Nothing typefaces and makes them the system default."
  [hyprland]="Sets up the window manager and works out your screen layout."
  [dms]="Installs the bar, the launcher and the widgets you see on screen."
  [themes]="Puts the colour schemes and wallpapers in place, and links them up."
  [apps]="Installs your browser and file manager, and makes them the defaults."
  [shell]="Sets up zsh, the prompt and Neovim, and makes zsh your login shell."
  [tweaks]="Small system fixes, such as faster copying to USB drives."
  [sddm]="Installs the Nothing login screen and boots straight into it."
  [optional]="Anything extra you ticked, such as Tailscale or the niri session."
)

# ------------------------------------------------------------------ header ---
PROGRESS_TOTAL=0
PROGRESS_INDEX=0
PROGRESS_START=0

progress_init() {
  PROGRESS_TOTAL=$1
  PROGRESS_INDEX=0
  PROGRESS_START=$SECONDS
}

# m:ss for anything under an hour, which is every realistic run.
elapsed_since() {
  local s=$(( SECONDS - PROGRESS_START ))
  printf '%dm %02ds' $(( s / 60 )) $(( s % 60 ))
}

# One row of the header box. The text is padded by CHARACTER count, not by
# printf's %-*s, which pads by bytes and so loses a column for every multibyte
# glyph in the string.
_box_row() {
  local text=$1 colour=${2:-} inner=$(( UI_WIDTH - 4 ))
  local pad=$(( inner - ${#text} ))
  (( pad < 0 )) && { text=${text:0:$inner}; pad=0; }
  printf '%s│%s  %s%s%s%*s%s│%s\n' \
    "$C_RED" "$C_OFF" "$colour" "$text" "${colour:+$C_OFF}" "$pad" '' "$C_RED" "$C_OFF"
}

# Printed once as each stage starts. Deliberately not redrawn: a header that
# repaints would fight with the sudo prompt and with dnf drawing its own
# output, and those matter more than a live counter.
progress_stage_begin() {
  local name=$1
  PROGRESS_INDEX=$(( PROGRESS_INDEX + 1 ))

  local title=${STAGE_TITLE[$name]:-$name}
  local blurb=${STAGE_BLURB[$name]:-}
  local total=$(( PROGRESS_TOTAL > 0 ? PROGRESS_TOTAL : 1 ))
  local pct=$(( (PROGRESS_INDEX - 1) * 100 / total ))

  if ! (( COLOR_ON )); then
    printf '\n== Step %d of %d: %s ==\n%s\n\n' \
      "$PROGRESS_INDEX" "$PROGRESS_TOTAL" "$title" "$blurb"
    _log_raw "STAGE $PROGRESS_INDEX/$PROGRESS_TOTAL $name"
    return 0
  fi

  local inner=$(( UI_WIDTH - 4 ))
  # The bar shares the row with "  100%   59m 59s", 16 characters.
  local barw=$(( inner - 16 ))
  (( barw < 8 )) && barw=8
  local filled=$(( (PROGRESS_INDEX - 1) * barw / total ))
  local tail; printf -v tail '%5s%%  %8s' "$pct" "$(elapsed_since)"

  printf '\n%s╭%s╮%s\n' "$C_RED" "$(rule $(( inner + 2 )))" "$C_OFF"
  _box_row "Step $PROGRESS_INDEX of $PROGRESS_TOTAL  ·  $title" "$C_BOLD"
  [[ -n $blurb ]] && _box_row "$blurb" "$C_GREY"
  # Built by hand rather than through _box_row, because the bar carries its own
  # colours in the middle of the row.
  printf '%s│%s  %s%s%s%s%s%s%s%*s%s│%s\n' \
    "$C_RED" "$C_OFF" \
    "$C_RED" "$(rule "$filled" '█')" "$C_GREY" "$(rule $(( barw - filled )) '░')" "$C_OFF" \
    "$C_GREY" "$tail" $(( inner - barw - 16 )) '' "$C_RED" "$C_OFF"
  printf '%s╰%s╯%s\n\n' "$C_RED" "$(rule $(( inner + 2 )))" "$C_OFF"

  _log_raw "STAGE $PROGRESS_INDEX/$PROGRESS_TOTAL $name"
}

# ----------------------------------------------------------------- spinner ---
# run() sends everything to the log, so a slow command shows nothing at all.
# Neovim's plugin sync can sit silent for five minutes that way. The spinner
# is what turns that into visible progress.
#
# It only ever wraps run(). Never run_visible or as_root: a sudo password
# prompt or dnf's own progress must have the terminal to itself.
SPIN_PID=""
SPIN_MSG=""

_spin_loop() {
  local msg=$1 start=$SECONDS i=0
  local frames='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
  while :; do
    local f=${frames:$(( i % 10 )):1}
    local s=$(( SECONDS - start ))
    printf '\r  %s%s%s %s %s%ds%s\033[K' \
      "$C_CYAN" "$f" "$C_OFF" "$msg" "$C_GREY" "$s" "$C_OFF"
    i=$(( i + 1 ))
    sleep 0.1
  done
}

spin_start() {
  SPIN_MSG=$1
  if ! (( COLOR_ON )) || (( DRY_RUN )); then
    info "$1"
    return 0
  fi
  printf '\033[?25l'                       # hide the cursor while it spins
  _spin_loop "$1" &
  SPIN_PID=$!
  disown "$SPIN_PID" 2>/dev/null || true
}

# spin_stop <ok|fail|skip> [message] — clears the spinner line and prints the
# outcome in its place, so one line becomes one result.
spin_stop() {
  local result=${1:-ok} msg=${2:-$SPIN_MSG}
  if [[ -n $SPIN_PID ]]; then
    kill "$SPIN_PID" 2>/dev/null || true
    wait "$SPIN_PID" 2>/dev/null || true
    SPIN_PID=""
    printf '\r\033[K\033[?25h'
  fi
  (( DRY_RUN )) && return 0
  case $result in
    ok)   ok   "$msg" ;;
    skip) skip "$msg" ;;
    *)    return 0 ;;   # the caller reports its own failure, with a fix
  esac
}

# Killed from the exit trap so ctrl-c never leaves an orphan or a hidden cursor.
spin_cleanup() {
  [[ -n $SPIN_PID ]] || return 0
  kill "$SPIN_PID" 2>/dev/null || true
  SPIN_PID=""
  printf '\r\033[K\033[?25h'
  return 0
}

# run_quiet <message> -- <command...>
# The command's output goes to the log, as with run(); the spinner is what the
# user sees. Returns the command's own status so callers can still branch.
run_quiet() {
  local msg=$1; shift
  [[ ${1:-} == -- ]] && shift
  spin_start "$msg"
  local rc=0
  run "$@" || rc=$?
  if (( rc == 0 )); then
    spin_stop ok "$msg"
  else
    spin_stop none
  fi
  return "$rc"
}
