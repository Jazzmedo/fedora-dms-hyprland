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
  printf '  %sCustomisable installation%s  everything is ticked; untick what you do not want\n\n' \
    "$C_BOLD" "$C_OFF"
  printf '  %s↑↓/jk%s move   %sspace%s tick   %sa%s whole group   %senter%s install   %sq%s cancel\n' \
    "$C_BOLD" "$C_OFF" "$C_BOLD" "$C_OFF" "$C_BOLD" "$C_OFF" "$C_BOLD" "$C_OFF" "$C_BOLD" "$C_OFF"
  printf '  %s%s%s\n' "$C_GREY" "$(printf '─%.0s' $(seq 1 "$UI_WIDTH"))" "$C_OFF"
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
  printf '\n  %s%s%s\n' "$C_GREY" "$(printf '─%.0s' $(seq 1 "$UI_WIDTH"))" "$C_OFF"
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
  [[ ! -t 0 ]] && return 1
  printf '  %s?%s %s [Y/n] ' "$C_RED" "$C_OFF" "$prompt"
  read -r reply
  [[ -z $reply || $reply == [yY]* ]]
}

# Print the plan the installer is about to execute.
# Wrap a long value under a fixed-width label, so a list of twenty components
# does not run off the side of a narrow terminal.
#
# Items are comma-separated, not space-separated: component names contain
# spaces ("Nothing fonts", "zsh + oh-my-zsh"), so wrapping on whitespace ran
# them into each other and there was no telling where one ended.
_plan_row() {
  local label=$1 value=$2 colour=${3:-}
  local indent=18
  local width=$(( UI_WIDTH - indent ))
  (( width < 24 )) && width=24

  local -a items=()
  local IFS=,
  read -ra items <<< "$value"
  unset IFS

  local first=1 line="" item
  _emit() {
    if (( first )); then
      printf '  %s%-14s%s  %s%s%s\n' "$C_GREY" "$label" "$C_OFF" "$colour" "$1" "${colour:+$C_OFF}"
      first=0
    else
      printf '%*s%s%s%s\n' "$indent" '' "$colour" "$1" "${colour:+$C_OFF}"
    fi
  }

  for item in "${items[@]}"; do
    item=${item#"${item%%[![:space:]]*}"}          # strip the leading space
    [[ -n $item ]] || continue
    if [[ -n $line ]] && (( ${#line} + ${#item} + 2 > width )); then
      _emit "$line,"
      line=$item
    else
      line="${line:+$line, }$item"
    fi
  done
  _emit "${line:-none}"
  unset -f _emit
}

# Join the arguments with ", " for _plan_row.
_join() { local IFS=,; printf '%s' "$*"; }

ui_show_plan() {
  printf '\n  %sHere is what will happen%s\n\n' "$C_BOLD" "$C_OFF"
  _plan_row "Graphics"  "${GPU_VENDOR}"
  _plan_row "Windows"   "arranged the ${HYPR_LAYOUT} way"
  _plan_row "Screens"   "${OUTPUT_SUMMARY:-worked out while installing}"
  _plan_row "Steps"     "${#STAGES_TO_RUN[@]} of them, about 15-40 minutes"
  _plan_row "Backups"   "$( (( NO_BACKUP )) && echo "off" || echo "replaced files go to ~/.fedora-nothing-backup/" )"
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
  printf '\n'
  _plan_row "Already there" "$satisfied thing(s), which will be checked and left alone" "$C_GREY"
  _plan_row "To install"    "$(_join ${fresh[@]+"${fresh[@]}"})"   "$C_OK"
  _plan_row "To repair"     "$(_join ${repair[@]+"${repair[@]}"})" "$C_WARN"
}
