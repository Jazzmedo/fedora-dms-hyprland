# shellcheck shell=bash
# The component picker: a dependency-free checklist for a bare @core Fedora,
# where dialog and whiptail do not exist.
#
# Keys: up/down or k/j move, space toggles, a toggles the whole group,
#       g/G jump to first/last, enter accepts, q or ctrl-c aborts.

UI_ROWS=()        # "group" or "item:<key>"
UI_CURSOR=0
UI_HEADER_H=6
UI_FOOTER_H=4

_tput() { tput "$@" 2>/dev/null || true; }

_ui_banner() {
  printf '%s\n' "$C_RED$C_BOLD"
  cat <<'ART'
  ███  fedora-nothing
ART
  printf '%s' "$C_OFF"
  printf '  %sHyprland · DankMaterialShell · Nothing%s\n\n' "$C_GREY" "$C_OFF"
  printf '  %s↑↓/jk%s move   %sspace%s toggle   %sa%s whole group   %senter%s install   %sq%s abort\n' \
    "$C_BOLD" "$C_OFF" "$C_BOLD" "$C_OFF" "$C_BOLD" "$C_OFF" "$C_BOLD" "$C_OFF" "$C_BOLD" "$C_OFF"
  printf '  %s%s%s\n' "$C_GREY" "$(printf '─%.0s' $(seq 1 "${UI_WIDTH:-72}"))" "$C_OFF"
}

_ui_build_rows() {
  UI_ROWS=()
  local g k
  for g in "${COMPONENT_GROUPS[@]}"; do
    UI_ROWS+=("group:$g")
    for k in $(group_members "$g"); do
      UI_ROWS+=("item:$k")
    done
  done
}

# The first row the cursor may actually land on. Base rows are display-only.
_ui_first_item() {
  local i
  for i in "${!UI_ROWS[@]}"; do
    [[ ${UI_ROWS[i]} == item:* ]] || continue
    component_locked "${UI_ROWS[i]#item:}" && continue
    printf '%s' "$i"; return
  done
  printf '0'
}

# Move the cursor to the next selectable row in direction $1 (-1 or 1).
_ui_move() {
  local dir=$1 n=${#UI_ROWS[@]} i=$UI_CURSOR
  while :; do
    i=$(( i + dir ))
    (( i < 0 || i >= n )) && return
    if [[ ${UI_ROWS[i]} == item:* ]]; then
      local key=${UI_ROWS[i]#item:}
      component_locked "$key" && continue      # base rows are display-only
      UI_CURSOR=$i; return
    fi
  done
}

_ui_render() {
  _tput clear
  _ui_banner
  local i row key
  for i in "${!UI_ROWS[@]}"; do
    row=${UI_ROWS[i]}
    if [[ $row == group:* ]]; then
      printf '\n  %s%s%s\n' "$C_BOLD" "${GROUP_LABEL[${row#group:}]}" "$C_OFF"
      continue
    fi
    key=${row#item:}
    local mark cursor name desc
    name=${COMPONENT_NAME[$key]}
    desc=${COMPONENT_DESC[$key]}
    if component_locked "$key"; then
      mark="${C_GREY}[·]${C_OFF}"
    elif is_selected "$key"; then
      mark="${C_RED}[x]${C_OFF}"
    else
      mark="[ ]"
    fi
    # What the machine already has, so a re-run reads as repair, not reinstall.
    local badge
    case $(component_state "$key") in
      installed) badge="${C_OK}✓${C_OFF}" ;;
      partial)   badge="${C_WARN}~${C_OFF}" ;;
      *)         badge=" " ;;
    esac
    local pad=""
    (( ${#name} < 22 )) && printf -v pad '%*s' $(( 22 - ${#name} )) ''
    if (( i == UI_CURSOR )); then
      printf '  %s❯%s %s %s %s%s%s%s %s%s%s\n' \
        "$C_RED" "$C_OFF" "$mark" "$badge" "$C_BOLD" "$name" "$C_OFF" "$pad" "$C_GREY" "$desc" "$C_OFF"
    else
      printf '    %s %s %s%s %s%s%s\n' "$mark" "$badge" "$name" "$pad" "$C_GREY" "$desc" "$C_OFF"
    fi
  done
  local n; n=$(selected_count)
  printf '\n  %s%s%s\n' "$C_GREY" "$(printf '─%.0s' $(seq 1 "${UI_WIDTH:-72}"))" "$C_OFF"
  printf '  %s%d selected%s   %s✓ already installed   ~ partial   [·] always installed%s\n' \
    "$C_BOLD" "$n" "$C_OFF" "$C_GREY" "$C_OFF"
}

# Read one key, expanding escape sequences to names.
_ui_key() {
  local k rest
  IFS= read -rsn1 k || return 1
  if [[ $k == $'\e' ]]; then
    IFS= read -rsn2 -t 0.01 rest || rest=""
    case $rest in
      '[A') printf 'up';;   '[B') printf 'down';;
      '[C') printf 'right';; '[D') printf 'left';;
      *)    printf 'esc';;
    esac
    return
  fi
  case $k in
    '')  printf 'enter';;
    ' ') printf 'space';;
    *)   printf '%s' "$k";;
  esac
}

# The picker. Returns non-zero if the user aborted.
ui_select_components() {
  UI_WIDTH=$(_tput cols); UI_WIDTH=${UI_WIDTH:-80}; (( UI_WIDTH > 96 )) && UI_WIDTH=96

  if [[ ! -t 0 || ! -t 1 ]]; then
    info "not a terminal, using the default selection"
    return 0
  fi

  _ui_build_rows
  UI_CURSOR=$(_ui_first_item)
  _tput civis
  trap '_tput cnorm; _tput clear' RETURN

  while :; do
    _ui_render
    local key; key=$(_ui_key) || break
    case $key in
      up|k)    _ui_move -1 ;;
      down|j)  _ui_move 1 ;;
      g)       UI_CURSOR=$(_ui_first_item) ;;
      G)       local i; for i in "${!UI_ROWS[@]}"; do
                 [[ ${UI_ROWS[i]} == item:* ]] && ! component_locked "${UI_ROWS[i]#item:}" && UI_CURSOR=$i
               done ;;
      space)   local _k=${UI_ROWS[$UI_CURSOR]#item:}
               if [[ ${COMPONENT_GROUP[$_k]} == gpu ]]; then
                 select_gpu "${_k#gpu_}"
               elif [[ ${COMPONENT_GROUP[$_k]} == layout ]]; then
                 select_layout "${_k#layout_}"
               else
                 toggle_component "$_k"
               fi ;;
      a)       _ui_toggle_group ;;
      enter)   return 0 ;;
      q|esc)   _tput cnorm; _tput clear; die "aborted by the user" ;;
    esac
  done
}

# Toggle every unlocked member of the group the cursor is currently inside.
_ui_toggle_group() {
  local i g=""
  for (( i = UI_CURSOR; i >= 0; i-- )); do
    [[ ${UI_ROWS[i]} == group:* ]] && { g=${UI_ROWS[i]#group:}; break; }
  done
  [[ -z $g || $g == gpu || $g == layout ]] && return
  # If anything in the group is off, turn the whole group on; else turn it off.
  local k want=0
  for k in $(group_members "$g"); do
    component_locked "$k" && continue
    is_selected "$k" || want=1
  done
  for k in $(group_members "$g"); do
    component_locked "$k" && continue
    if (( want )); then select_component "$k"; else deselect_component "$k"; fi
  done
}

# A plain yes/no prompt that honours --yes.
confirm() {
  local prompt=$1 reply
  (( ASSUME_YES )) && return 0
  [[ ! -t 0 ]] && return 0
  printf '  %s?%s %s [Y/n] ' "$C_RED" "$C_OFF" "$prompt"
  read -r reply
  [[ -z $reply || $reply == [yY]* ]]
}

# Print the plan the installer is about to execute.
ui_show_plan() {
  step "Plan"
  printf '  %-14s %s\n' "GPU"     "${GPU_VENDOR}"
  printf '  %-14s %s\n' "Layout"  "${HYPR_LAYOUT}"
  printf '  %-14s %s\n' "Displays" "${OUTPUT_SUMMARY:-detected at install time}"
  printf '  %-14s %s\n' "Stages" "${STAGES_TO_RUN[*]}"
  printf '  %-14s %s\n' "Backups" "$( (( NO_BACKUP )) && echo disabled || echo "~/.fedora-nothing-backup/" )"
  local k names=() fresh=() repair=() satisfied=0
  for k in "${COMPONENT_ORDER[@]}"; do
    [[ ${COMPONENT_GROUP[$k]} == gpu || ${COMPONENT_GROUP[$k]} == layout ]] && continue
    is_selected "$k" || continue
    component_locked "$k" || names+=("${COMPONENT_NAME[$k]}")
    case $(component_state "$k") in
      installed) (( ++satisfied )) ;;
      partial)   repair+=("${COMPONENT_NAME[$k]}") ;;
      *)         fresh+=("${COMPONENT_NAME[$k]}") ;;
    esac
  done
  printf '  %-14s %s\n' "Optional" "${names[*]:-none}"
  printf '  %-14s %s\n' "Already set" "$satisfied component(s), which will be checked and skipped"
  printf '  %-14s %s\n' "To install"  "${fresh[*]:-nothing}"
  printf '  %-14s %s\n' "To repair"   "${repair[*]:-nothing}"
}

# ---------------------------------------------------------------- identity ---
# The owner's fast path. Answering yes installs every component with the
# defaults this repo was captured from and skips the picker entirely.
ui_identity_prompt() {
  (( ASSUME_YES )) && return 0
  [[ -t 0 && -t 1 ]] || return 0

  _tput clear
  _ui_banner
  local reply
  printf '\n  %sAre you Jazzmedo?%s\n\n' "$C_BOLD" "$C_OFF"
  printf '  %syes%s  install everything, exactly as this repo was captured.\n' "$C_RED" "$C_OFF"
  printf '       No questions, no picker.\n\n'
  printf '  %sno%s   choose what to install from a checklist.\n\n' "$C_RED" "$C_OFF"
  printf '  [y/N] '
  read -r reply

  if [[ $reply == [yY]* ]]; then
    OWNER_MODE=1
    apply_preset full
    select_layout scrolling
    printf '\n  %s✓%s welcome back. Installing the full configuration.\n\n' "$C_OK" "$C_OFF"
    sleep 1
    return 0
  fi
  return 1
}
