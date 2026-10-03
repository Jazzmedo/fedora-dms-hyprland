#!/usr/bin/env bash
# fedora-nothing — turn a barebones Fedora into the Nothing-styled Hyprland
# desktop: Hyprland, DankMaterialShell and its plugins, the Nothing login
# theme, Ndot 57 as the system font, and foot or kitty/Zen/Dolphin as the defaults.
#
#   ./install.sh                    pick components interactively, then install
#   ./install.sh --yes              install the defaults, no prompts
#   ./install.sh --preset=full      every optional component
#   ./install.sh --dry-run          print every command without running one
#   ./install.sh --only=themes,dms  re-run just those stages
#
# Safe to re-run: every step checks before acting and anything it replaces is
# copied to ~/.fedora-nothing-backup/<timestamp>/ first.

set -euo pipefail

REPO_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly REPO_DIR

# ------------------------------------------------------------------ options ---
DRY_RUN=0
ASSUME_YES=0
NO_BACKUP=0
OWNER_MODE=0
PRESET=""
GPU_VENDOR=""
GPU_VENDOR_FLAG=""
HYPR_LAYOUT="scrolling"
LAYOUT_FLAG=""
DEFAULT_TERMINAL=""
TERMINAL_FLAG=""
DEFAULT_BROWSER=""
BROWSER_FLAG=""
BROWSER_BACKUP=""
RESET_SELECTION=0
ONLY=""
SKIP=""
SHOW_STATUS=0

# Order matters in one place beyond the obvious. The desktop shell comes from
# somebody else's installer, which sets up a desktop of its own and writes into
# the same directories this repository does. It therefore runs BEFORE any
# configuration is deployed, so that what it writes is overwritten by these
# settings rather than the other way round.
ALL_STAGES=(preflight repos gpu packages fonts dms hyprland themes apps shell tweaks sddm optional)
STAGES_TO_RUN=()

usage() {
  cat <<'EOF'
fedora-nothing — turns a barebones Fedora into the Nothing desktop: the
Hyprland window manager, the DankMaterialShell bar and widgets, the Nothing
login screen and typefaces, and your choice of terminal, browser and Dolphin.

  ./install.sh                    choose what to install, then install it
  ./install.sh --yes              install the usual set, ask nothing
  ./install.sh --dry-run          show what would happen, change nothing
  ./install.sh --only=themes,dms  redo just those parts

Safe to run again. Every step checks before it acts, and anything it replaces
is copied to ~/.fedora-nothing-backup/ first.

Options:
  --yes, -y             accept the default selection, ask nothing
  --preset=NAME         minimal | standard | full
  --gpu=VENDOR          amd | intel | nvidia | vm   (default: detected)
  --layout=NAME         scrolling | dwindle          (default: scrolling)
  --terminal=NAME       foot | kitty: the default when both are ticked
  --browser=NAME        zen | firefox | librewolf | brave | brave_origin | vivaldi | helium:
                        the default when several are ticked
  --only=A,B            run only these stages
  --skip=A,B            run everything except these stages
  --dry-run             print what would happen, change nothing
  --no-backup           do not copy replaced files aside
  --status              report what is already installed, then exit
  --reset-selection     forget the remembered choices and start from all-ticked
  --color=WHEN          auto | always | never   (always keeps colour in a pipe)
  --list-stages         print the stage names and exit
  --help, -h            this text
EOF
}

for arg in "$@"; do
  case $arg in
    -y|--yes)        ASSUME_YES=1 ;;
    --dry-run)       DRY_RUN=1 ;;
    --no-backup)     NO_BACKUP=1 ;;
    --owner)         OWNER_MODE=1; ASSUME_YES=1; PRESET=full ;;
    --preset=*)      PRESET=${arg#*=} ;;
    --gpu=*)         GPU_VENDOR=${arg#*=}; GPU_VENDOR_FLAG=1 ;;
    --layout=*)      HYPR_LAYOUT=${arg#*=}; LAYOUT_FLAG=1 ;;
    --terminal=*)    DEFAULT_TERMINAL=${arg#*=}; TERMINAL_FLAG=1 ;;
    --browser=*)     DEFAULT_BROWSER=${arg#*=}; BROWSER_FLAG=1 ;;
    --only=*)        ONLY=${arg#*=} ;;
    --skip=*)        SKIP=${arg#*=} ;;
    --list-stages)   printf '%s\n' "${ALL_STAGES[@]}"; exit 0 ;;
    --status)        SHOW_STATUS=1 ;;
    --reset-selection) RESET_SELECTION=1 ;;
    --color=*)       COLOR_MODE=${arg#*=}; COLOR_MODE_EXPLICIT=1 ;;
    --no-color)      COLOR_MODE=never; COLOR_MODE_EXPLICIT=1 ;;
    -h|--help)       usage; exit 0 ;;
    *)               printf 'unknown option: %s\n\n' "$arg" >&2; usage; exit 2 ;;
  esac
done

# ------------------------------------------------------------------ library ---
# shellcheck source=lib/common.sh
source "$REPO_DIR/lib/common.sh"
# shellcheck source=lib/progress.sh
source "$REPO_DIR/lib/progress.sh"
# shellcheck source=lib/components.sh
source "$REPO_DIR/lib/components.sh"
# shellcheck source=lib/detect.sh
source "$REPO_DIR/lib/detect.sh"
# shellcheck source=lib/verify.sh
source "$REPO_DIR/lib/verify.sh"
# shellcheck source=lib/ui.sh
source "$REPO_DIR/lib/ui.sh"
# shellcheck source=lib/browser-profiles.sh
source "$REPO_DIR/lib/browser-profiles.sh"
for f in "$REPO_DIR"/lib/stages/*.sh; do
  # shellcheck source=/dev/null
  source "$f"
done

# Both files live in the repository, next to the installer that wrote them, so
# they are where you already are when something goes wrong and they survive a
# cache clear. If the repository is not writable -- a read-only clone, or run
# from a different user -- they fall back to the cache directory.
RUN_STAMP=$(date +%Y%m%d-%H%M%S)
LOG_DIR="$REPO_DIR/logs"
mkdir -p "$LOG_DIR" 2>/dev/null || true
[[ -w $LOG_DIR ]] || { LOG_DIR="$HOME/.cache/fedora-nothing"; mkdir -p "$LOG_DIR"; }

LOG_FILE="$LOG_DIR/install-$RUN_STAMP.log"
MANIFEST_FILE="$LOG_DIR/install-$RUN_STAMP.manifest"
: > "$LOG_FILE"
: > "$MANIFEST_FILE"
# A stable name for the newest of each, which is what uninstall.sh reads and
# what report.sh attaches.
ln -sfn "install-$RUN_STAMP.log"      "$LOG_DIR/latest.log"      2>/dev/null || true
ln -sfn "install-$RUN_STAMP.manifest" "$LOG_DIR/latest.manifest" 2>/dev/null || true

trap 'install_exit_trap "$?"' EXIT
trap 'spin_cleanup; printf "\n"; exit 130' INT

# ------------------------------------------------------------------- stages ---
resolve_stages() {
  local -a wanted=("${ALL_STAGES[@]}")
  if [[ -n $ONLY ]]; then
    IFS=',' read -ra wanted <<< "$ONLY"
    # preflight is never optional: later stages rely on what it establishes.
    [[ ${wanted[0]} == preflight ]] || wanted=(preflight "${wanted[@]}")
  fi
  local s skip_list=",$SKIP,"
  for s in "${wanted[@]}"; do
    [[ $s == preflight ]] || [[ $skip_list != *",$s,"* ]] || continue
    printf '%s\n' " ${ALL_STAGES[*]} " | grep -q " $s " \
      || die "There is no step called \"$s\"" "" "./install.sh --list-stages shows the names"
    STAGES_TO_RUN+=("$s")
  done
}

run_stage() {
  local name=$1
  CURRENT_STAGE=$name
  progress_stage_begin "$name"
  "stage_${name}"
}

# ---------------------------------------------------------------- selection ---
SELECTION_FILE="$HOME/.config/fedora-nothing/selection.conf"

# Pre-ticks for the picker, nothing more. This used to double as a reason to
# skip the picker entirely, so a single run that left zsh unticked disabled the
# whole shell stage on every run after it, invisibly and permanently.
load_selection() {
  [[ -f $SELECTION_FILE ]] || return 1
  (( RESET_SELECTION )) && return 1

  local k
  for k in "${COMPONENT_ORDER[@]}"; do
    component_locked "$k" || deselect_component "$k"
  done
  while read -r k; do
    [[ -z $k || $k == \#* ]] && continue
    # A flag given on the command line has to win over a remembered value.
    [[ $k == gpu=* ]]    && { [[ -z $GPU_VENDOR_FLAG ]] && GPU_VENDOR=${k#gpu=}; continue; }
    [[ $k == layout=* ]] && { [[ -z $LAYOUT_FLAG ]] && HYPR_LAYOUT=${k#layout=}; continue; }
    [[ $k == terminal=* ]] && { [[ -z $TERMINAL_FLAG ]] && DEFAULT_TERMINAL=${k#terminal=}; continue; }
    [[ $k == browser=* ]]  && { [[ -z $BROWSER_FLAG ]] && DEFAULT_BROWSER=${k#browser=}; continue; }
    # "devtools" was one row before each tool got its own.
    [[ $k == devtools ]] && { for k in mise nvm pyenv rust golang podman ytdlp; do select_component "$k"; done; continue; }
    [[ -n ${COMPONENT_NAME[$k]:-} ]] && select_component "$k"
  done < "$SELECTION_FILE"
  return 0
}

save_selection() {
  (( DRY_RUN )) && return 0
  mkdir -p "$(dirname "$SELECTION_FILE")"
  {
    echo "# Written by fedora-nothing. Re-running the installer reuses this."
    echo "gpu=$GPU_VENDOR"
    echo "layout=$HYPR_LAYOUT"
    echo "terminal=$DEFAULT_TERMINAL"
    echo "browser=$DEFAULT_BROWSER"
    local k
    for k in "${COMPONENT_ORDER[@]}"; do
      component_locked "$k" && continue
      is_selected "$k" && printf '%s\n' "$k"
    done
  } > "$SELECTION_FILE"
}

choose_components() {
  local detected; detected=$(detect_gpu)
  # Show the picker with the detected driver already ticked, so the radio has
  # a sane answer whether or not the operator touches that group.
  select_gpu "${GPU_VENDOR:-$detected}"
  select_layout "$HYPR_LAYOUT"

  if [[ -n $PRESET ]]; then
    apply_preset "$PRESET"
    info "Installing the \"$PRESET\" set of components"
  else
    # Everything ticked to start with, then last run's choices on top of that.
    apply_preset full
    load_selection && info "Your choices from last time are already ticked"
    # One rpm -qa and one flatpak list for the whole run. Without this every
    # caller below forks a pair of them per component.
    printf '  %sChecking what is already installed%s\n' "$C_GREY" "$C_OFF"
    detect_all_components
    # Anything already on the machine stays ticked, so a re-run verifies it
    # instead of silently leaving it out.
    reselect_installed
    ui_select_components
  fi

  # An explicit flag wins over the saved value, which wins over the picker.
  select_gpu "${GPU_VENDOR:-$detected}"
  [[ $HYPR_LAYOUT == scrolling || $HYPR_LAYOUT == dwindle ]] \
    || die "\"$HYPR_LAYOUT\" is not a window layout this installer knows" "" "Use --layout=scrolling or --layout=dwindle"
  select_layout "$HYPR_LAYOUT"

  # Gear Lever is only distributed as a Flatpak, so picking it turns Flatpak on
  # rather than failing later with an app that cannot be installed.
  if is_selected gearlever && ! is_selected flatpak; then
    select_component flatpak
    info "Gear Lever only comes as a Flatpak, so Flatpak was switched on too"
  fi

  choose_default_terminal
  choose_default_browser
  choose_browser_backup

  # Summarise the displays for the plan; the hyprland stage re-reads them.
  detect_outputs
  local i parts=()
  for i in "${!OUTPUT_NAMES[@]}"; do
    parts+=("${OUTPUT_NAMES[i]} ${OUTPUT_MODES[i]} ${OUTPUT_ORIENT[i]}")
  done
  OUTPUT_SUMMARY=$(printf '%s, ' "${parts[@]}"); OUTPUT_SUMMARY=${OUTPUT_SUMMARY%, }
}

# At least one terminal is installed. With both, one is the default: it is
# what SUPER+Return, the niri bind and "open a terminal" requests launch.
choose_default_terminal() {
  if ! is_selected term_foot && ! is_selected term_kitty; then
    select_component term_foot
    info "No terminal was ticked, so foot will be installed"
  fi
  if is_selected term_foot && is_selected term_kitty; then
    if [[ $DEFAULT_TERMINAL != foot && $DEFAULT_TERMINAL != kitty ]]; then
      DEFAULT_TERMINAL=foot
      if [[ -t 0 ]] && ! (( ASSUME_YES )) && [[ -z $PRESET ]]; then
        local reply
        printf '  %s?%s Both terminals are ticked. Which should be the default? [F]oot / [k]itty ' "$C_RED" "$C_OFF"
        read -r reply
        [[ $reply == [kK]* ]] && DEFAULT_TERMINAL=kitty
      fi
    fi
  elif is_selected term_kitty; then
    DEFAULT_TERMINAL=kitty
  else
    DEFAULT_TERMINAL=foot
  fi
  TPL_TERMINAL=$DEFAULT_TERMINAL
  TPL_ALT_TERMINAL=$DEFAULT_TERMINAL
  if is_selected term_foot && is_selected term_kitty; then
    [[ $DEFAULT_TERMINAL == foot ]] && TPL_ALT_TERMINAL=kitty || TPL_ALT_TERMINAL=foot
  fi
}

# At least one browser is installed. With several, one is the default: it
# opens links and SUPER+B starts it. A flag or last run's answer is kept when
# that browser is still ticked; otherwise the first ticked one is offered.
choose_default_browser() {
  local k ticked=()
  for k in $(group_members browsers); do
    [[ $k == zen_sites ]] && continue
    is_selected "$k" && ticked+=("$k")
  done
  if (( ${#ticked[@]} == 0 )); then
    select_component zen; ticked=(zen)
    info "No browser was ticked, so Zen will be installed"
  fi
  if [[ -n $DEFAULT_BROWSER && $BROWSER_FLAG ]] && ! is_selected "$DEFAULT_BROWSER"; then
    die "\"$DEFAULT_BROWSER\" is not one of the browsers being installed" "" \
        "Tick it in the list, or use --browser=$(_join "${ticked[@]}")"
  fi
  is_selected "${DEFAULT_BROWSER:-none}" 2>/dev/null || DEFAULT_BROWSER=${ticked[0]}
  if (( ${#ticked[@]} > 1 )) && [[ -t 0 ]] && ! (( ASSUME_YES )) && [[ -z $PRESET && -z $BROWSER_FLAG ]]; then
    local i reply def=1
    printf '  %s?%s Several browsers are ticked. Which should open links?\n' "$C_RED" "$C_OFF"
    for i in "${!ticked[@]}"; do
      [[ ${ticked[i]} == "$DEFAULT_BROWSER" ]] && def=$(( i + 1 ))
      printf '      %d) %s\n' $(( i + 1 )) "${COMPONENT_NAME[${ticked[i]}]}"
    done
    printf '    Number [%d]: ' "$def"
    read -r reply
    [[ $reply =~ ^[0-9]+$ ]] && (( reply >= 1 && reply <= ${#ticked[@]} )) || reply=$def
    DEFAULT_BROWSER=${ticked[reply - 1]}
  fi
  set_browser_templates "$DEFAULT_BROWSER"
}

# Extensions and their data from ./browser-backup.sh, restored at the end of
# the apps stage. Asked only interactively; the passphrase is asked here too,
# so the long install steps run unattended.
choose_browser_backup() {
  [[ -t 0 ]] && ! (( ASSUME_YES )) && [[ -z $PRESET ]] || return 0
  local reply
  printf '  %s?%s Restore browser extensions from a backup? [y/N] ' "$C_RED" "$C_OFF"
  read -r reply
  [[ $reply == [yY]* ]] || return 0
  BROWSER_BACKUP=$(bp_pick_backup)
  bp_is_encrypted "$BROWSER_BACKUP" || return 0
  local probe; probe=$(ls -S "$BROWSER_BACKUP"/*.gpg | tail -1)   # the smallest
  while :; do
    read -rsp "  Backup passphrase (empty skips the restore): " BP_PASS; printf '\n'
    [[ -z $BP_PASS ]] && { BROWSER_BACKUP=""; return 0; }
    bp_decrypt "$probe" >/dev/null 2>&1 && return 0
    warn "That passphrase does not open the backup"
  done
}

# A component that is already installed stays selected even if it is absent
# from the saved selection, because deselecting it would not remove it anyway;
# it would only stop the installer from checking it.
reselect_installed() {
  local k n=0
  for k in "${COMPONENT_ORDER[@]}"; do
    [[ ${COMPONENT_GROUP[$k]} == gpu || ${COMPONENT_GROUP[$k]} == layout ]] && continue
    is_selected "$k" && continue
    [[ $(component_state "$k") == installed ]] || continue
    select_component "$k"; (( ++n ))
  done
  (( n )) && info "$n thing(s) you already have were re-ticked, so they get checked"
  return 0
}

# The picker clears the screen and draws its own banner, so a run that skips
# the picker used to show no title at all.
install_banner() {
  printf '\n  %s%s███%s  %sfedora-nothing%s\n' "$C_RED" "$C_BOLD" "$C_OFF" "$C_BOLD" "$C_OFF"
  printf '  %sTurns this Fedora into the Nothing desktop.%s\n' "$C_GREY" "$C_OFF"
  printf '  %s%s%s\n' "$C_GREY" "$(rule)" "$C_OFF"
}

# -------------------------------------------------------------------- main ---
main() {
  if (( SHOW_STATUS )); then
    show_status
    INSTALL_COMPLETED=1
    exit 0
  fi
  resolve_stages
  install_banner
  choose_components
  ui_show_plan

  (( DRY_RUN )) && warn "This is a dry run. Nothing on this machine will be changed."
  save_selection
  sudo_begin

  # Both the shell settings and the window manager settings template the
  # monitor name in, and either stage can now be the first to need it.
  detect_outputs
  TPL_MONITOR=${OUTPUT_NAMES[0]:-}

  local start=$SECONDS
  progress_init "${#STAGES_TO_RUN[@]}"
  local s
  for s in "${STAGES_TO_RUN[@]}"; do
    run_stage "$s"
  done

  INSTALL_COMPLETED=1
  (( DRY_RUN )) || verify_install
  summary $(( SECONDS - start ))
}

summary() {
  local secs=$1

  printf '\n%s%s%s\n' "$C_RED" "$(rule)" "$C_OFF"
  if (( ${#SOFT_FAILURES[@]} )); then
    printf '  %s%s Finished in %dm %02ds, with %d thing(s) to look at%s\n' \
      "$C_WARN" "$C_BOLD" $(( secs / 60 )) $(( secs % 60 )) "${#SOFT_FAILURES[@]}" "$C_OFF"
  else
    printf '  %s%s✓ All done, in %dm %02ds%s\n' \
      "$C_OK" "$C_BOLD" $(( secs / 60 )) $(( secs % 60 )) "$C_OFF"
  fi
  printf '%s%s%s\n' "$C_RED" "$(rule)" "$C_OFF"

  # Cause and command reprinted together, rather than the flattened one-line
  # list this used to show.
  if (( ${#SOFT_FAILURES[@]} )); then
    printf '\n  %sThese parts did not finish. The rest of your desktop is fine.%s\n\n' \
      "$C_BOLD" "$C_OFF"
    local i
    for i in "${!SOFT_FAILURES[@]}"; do
      printf '   %s%d.%s %s\n' "$C_WARN" $(( i + 1 )) "$C_OFF" "${SOFT_FAILURES[i]}"
      [[ -n ${SOFT_WHY[i]} ]] && printf '      %sWhy:%s  %s\n' "$C_GREY" "$C_OFF" "${SOFT_WHY[i]}"
      [[ -n ${SOFT_FIX[i]} ]] && printf '      %sFix:%s  %s%s%s\n' \
        "$C_GREY" "$C_OFF" "$C_BOLD" "${SOFT_FIX[i]}" "$C_OFF"
      printf '\n'
    done
  fi

  printf '  %sFull log%s        %s\n' "$C_GREY" "$C_OFF" "${LOG_FILE/#$HOME/\~}"
  if [[ -n ${MANIFEST_FILE:-} && -s $MANIFEST_FILE ]]; then
    printf '  %sWhat changed%s    %s  %s(./uninstall.sh reverses it)%s\n' \
      "$C_GREY" "$C_OFF" "${MANIFEST_FILE/#$HOME/\~}" "$C_GREY" "$C_OFF"
  fi
  [[ -n $BACKUP_DIR ]] && \
    printf '  %sReplaced files%s  %s\n' "$C_GREY" "$C_OFF" "${BACKUP_DIR/#$HOME/\~}"

  (( DRY_RUN )) && {
    printf '\n  %sThat was a dry run. Nothing on this machine changed.%s\n\n' "$C_CYAN" "$C_OFF"
    return 0
  }

  printf '\n  %sWhat happens next%s\n' "$C_BOLD" "$C_OFF"
  printf '   %s1.%s Restart the computer.\n' "$C_RED" "$C_OFF"
  printf '   %s2.%s At the login screen, pick %sHyprland%s as the session, then log in.\n' \
    "$C_RED" "$C_OFF" "$C_BOLD" "$C_OFF"
  printf '   %s3.%s Press %sSuper + Return%s for a terminal, %sSuper + /%s for every shortcut.\n' \
    "$C_RED" "$C_OFF" "$C_BOLD" "$C_OFF" "$C_BOLD" "$C_OFF"
  printf '\n  %sIf the desktop looks empty after logging in, run ./doctor.sh — it says why.%s\n\n' \
    "$C_GREY" "$C_OFF"

  if [[ -t 0 ]] && ! (( ASSUME_YES )); then
    confirm "Restart now?" && as_root systemctl reboot
  else
    printf '  %sRestart when you are ready:%s sudo systemctl reboot\n\n' "$C_GREY" "$C_OFF"
  fi
}

main "$@"
