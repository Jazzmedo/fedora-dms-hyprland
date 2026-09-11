#!/usr/bin/env bash
# fedora-nothing — turn a barebones Fedora into the Nothing-styled Hyprland
# desktop: Hyprland, DankMaterialShell and its plugins, the Nothing login
# theme, Ndot 57 as the system font, and kitty/Zen/Dolphin as the defaults.
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
HYPR_LAYOUT="scrolling"
ONLY=""
SKIP=""

ALL_STAGES=(preflight repos gpu packages fonts hyprland dms themes apps shell tweaks sddm optional)
STAGES_TO_RUN=()

usage() {
  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
  cat <<'EOF'

Options:
  --yes, -y             accept the default selection, ask nothing
  --preset=NAME         minimal | standard | full
  --gpu=VENDOR          amd | intel | nvidia | vm   (default: detected)
  --layout=NAME         scrolling | dwindle          (default: scrolling)
  --only=A,B            run only these stages
  --skip=A,B            run everything except these stages
  --dry-run             print what would happen, change nothing
  --no-backup           do not copy replaced files aside
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
    --gpu=*)         GPU_VENDOR=${arg#*=} ;;
    --layout=*)      HYPR_LAYOUT=${arg#*=} ;;
    --only=*)        ONLY=${arg#*=} ;;
    --skip=*)        SKIP=${arg#*=} ;;
    --list-stages)   printf '%s\n' "${ALL_STAGES[@]}"; exit 0 ;;
    -h|--help)       usage; exit 0 ;;
    *)               printf 'unknown option: %s\n\n' "$arg" >&2; usage; exit 2 ;;
  esac
done

# ------------------------------------------------------------------ library ---
# shellcheck source=lib/common.sh
source "$REPO_DIR/lib/common.sh"
# shellcheck source=lib/components.sh
source "$REPO_DIR/lib/components.sh"
# shellcheck source=lib/ui.sh
source "$REPO_DIR/lib/ui.sh"
for f in "$REPO_DIR"/lib/stages/*.sh; do
  # shellcheck source=/dev/null
  source "$f"
done

LOG_FILE="$HOME/.cache/fedora-nothing/install-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$(dirname "$LOG_FILE")"
: > "$LOG_FILE"

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
      || die "unknown stage: $s (see --list-stages)"
    STAGES_TO_RUN+=("$s")
  done
}

run_stage() {
  local name=$1
  printf '%s\n' " ${STAGES_TO_RUN[*]} " | grep -q " $name " || return 0
  "stage_${name}"
}

# ---------------------------------------------------------------- selection ---
SELECTION_FILE="$HOME/.config/fedora-nothing/selection.conf"

load_selection() {
  [[ -f $SELECTION_FILE ]] || return 1
  local k
  for k in "${COMPONENT_ORDER[@]}"; do
    component_locked "$k" || deselect_component "$k"
  done
  while read -r k; do
    [[ -z $k || $k == \#* ]] && continue
    [[ $k == gpu=* ]]    && { GPU_VENDOR=${k#gpu=}; continue; }
    [[ $k == layout=* ]] && { HYPR_LAYOUT=${k#layout=}; continue; }
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
    info "preset: $PRESET"
  elif load_selection; then
    info "reusing the selection from ${SELECTION_FILE/#$HOME/\~}"
  elif ui_identity_prompt; then
    : # owner mode already applied the full preset
  else
    ui_select_components
  fi

  # An explicit flag wins over the saved value, which wins over the picker.
  select_gpu "${GPU_VENDOR:-$detected}"
  [[ $HYPR_LAYOUT == scrolling || $HYPR_LAYOUT == dwindle ]] \
    || die "unknown layout: $HYPR_LAYOUT (scrolling|dwindle)"
  select_layout "$HYPR_LAYOUT"

  # Summarise the displays for the plan; the hyprland stage re-reads them.
  detect_outputs
  local i parts=()
  for i in "${!OUTPUT_NAMES[@]}"; do
    parts+=("${OUTPUT_NAMES[i]} ${OUTPUT_MODES[i]} ${OUTPUT_ORIENT[i]}")
  done
  OUTPUT_SUMMARY=$(printf '%s, ' "${parts[@]}"); OUTPUT_SUMMARY=${OUTPUT_SUMMARY%, }
}

# -------------------------------------------------------------------- main ---
main() {
  resolve_stages
  choose_components
  ui_show_plan

  (( DRY_RUN )) && warn "dry run: nothing will be changed"
  if ! (( ASSUME_YES )) && ! confirm "Proceed?"; then
    die "cancelled"
  fi
  save_selection

  local start=$SECONDS
  run_stage preflight
  run_stage repos
  run_stage gpu
  run_stage packages
  run_stage fonts
  run_stage hyprland
  run_stage dms
  run_stage themes
  run_stage apps
  run_stage shell
  run_stage tweaks
  run_stage sddm
  run_stage optional

  summary $(( SECONDS - start ))
}

summary() {
  local secs=$1
  step "Done in $(( secs / 60 ))m $(( secs % 60 ))s"

  if (( ${#SOFT_FAILURES[@]} )); then
    printf '\n  %s%d step(s) did not complete:%s\n' "$C_WARN" "${#SOFT_FAILURES[@]}" "$C_OFF"
    printf '    · %s\n' "${SOFT_FAILURES[@]}"
  fi

  [[ -n $BACKUP_DIR ]] && info "replaced files are in ${BACKUP_DIR/#$HOME/\~}"
  info "full log: ${LOG_FILE/#$HOME/\~}"

  (( DRY_RUN )) && return 0

  cat <<EOF

  ${C_BOLD}Next:${C_OFF}
    1. reboot
    2. log in through the Nothing greeter, choosing the Hyprland session
    3. SUPER + Return opens kitty, SUPER + / lists every keybinding

  ${C_GREY}If the shell does not appear, check: systemctl --user status dms.service${C_OFF}
EOF
  confirm "Reboot now?" && as_root systemctl reboot
}

main "$@"
