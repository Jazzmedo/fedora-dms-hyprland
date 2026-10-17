#!/usr/bin/env bash
# Back up or restore the data of your AI coding agents: Claude Code, Codex,
# OpenCode and ZCode. Chats, settings and sign-in credentials can each come
# along, and everything is chosen on screen.
#
# The same shape as browser-backup.sh, for the other half of what a fresh
# install leaves behind: the conversations and logins you would rather not
# lose. Backups go to ~/fedora-nothing-backups/ (or a folder you pick, such as
# a USB drive). They are never written inside a git repository, so one cannot
# be committed by accident.
set -euo pipefail
umask 077   # the archives hold sign-in tokens

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DRY_RUN=0 ASSUME_YES=0 NO_BACKUP=0 PRESET="" LOG_FILE="" MANIFEST_FILE=""

# shellcheck source=lib/common.sh
source "$REPO_DIR/lib/common.sh"
# shellcheck source=lib/progress.sh
source "$REPO_DIR/lib/progress.sh"
# shellcheck source=lib/components.sh
source "$REPO_DIR/lib/components.sh"
# shellcheck source=lib/ui.sh
source "$REPO_DIR/lib/ui.sh"
# shellcheck source=lib/agent-profiles.sh
source "$REPO_DIR/lib/agent-profiles.sh"
set_colors 2>/dev/null || true

[[ -t 0 && -t 1 ]] || die "Run this in a terminal" "Every choice is made on screen."

local_need() {
  local c missing=()
  for c in "$@"; do have "$c" || missing+=("$c"); done
  (( ${#missing[@]} == 0 )) && return 0
  die "Missing: ${missing[*]}" "" "$(ap_install_hint "${missing[@]}")"
}

picked() { is_selected "$1"; }

# Comma list of the ticked "what" entries.
picked_items() {
  local out=chats
  picked x_settings && out+=,settings
  picked x_auth     && out+=,auth
  printf '%s' "$out"
}

inside_git() {   # the nearest existing parent of $1 is in a git work tree
  local d=$1
  while [[ ! -d $d ]]; do d=$(dirname "$d"); done
  git -C "$d" rev-parse --is-inside-work-tree >/dev/null 2>&1
}

backup_flow() {
  local k root found=0
  new_list
  group a "Agents found on this machine"
  for k in "${AP_AGENTS[@]}"; do
    ap_present "$k" || continue
    root=$(ap_root "$k")
    component "a_$k" a on "$(ap_name "$k")" "${root/#$HOME/\~}"
    found=1
  done
  (( found )) || die "No agent data was found" "Run the agent once so it creates its folder."
  group what "What to include"
  component x_chats    what base "Chats + history"  "conversations, prompts, session logs"
  component x_settings what on   "Settings"         "config, skills, rules, plugins, model choices"
  # Auth defaults on: the point of moving a backup between machines is arriving
  # still signed in. Anything that can sign you in forces encryption on a few
  # lines below, so the convenience has its guard rail built in.
  component x_auth     what on   "Sign-in (auth)"   "credentials and tokens; needs encryption"
  group prot "Protection"
  component x_encrypt  prot on   "Encrypt with a passphrase" "recommended; anyone with the files can read them otherwise"

  UI_TITLE="Back up AI agent data" UI_SUBTITLE="tick what to save" UI_ACCEPT="continue"
  UI_LEGEND="[·] always included"
  ui_select_components

  local keys=()
  for k in "${AP_AGENTS[@]}"; do picked "a_$k" && keys+=("$k"); done
  (( ${#keys[@]} )) || die "No agent was ticked"
  local items; items=$(picked_items)
  if [[ $items == *auth* ]] && ! picked x_encrypt; then
    select_component x_encrypt
    info "Encryption was turned back on: sign-in tokens would otherwise be stored readable"
  fi
  picked x_encrypt && local_need gpg zstd tar || local_need zstd tar

  local dest def="$AP_BACKUP_ROOT/agents-$(date +%Y-%m-%d)"
  while :; do
    read -rep "  Save to: " -i "${def/#$HOME/\~}" dest
    dest=${dest/#\~/$HOME}
    [[ -n $dest ]] || continue
    if inside_git "$dest"; then
      warn "That folder is inside a git repository; pick one outside it so the backup cannot be committed"
      continue
    fi
    if [[ -f $dest/manifest.txt ]]; then
      local yn; read -rp "  A backup is already there. Replace it? [y/N] " yn
      [[ $yn == [yY]* ]] || continue
      rm -f "$dest"/*.tar.zst "$dest"/*.tar.zst.gpg "$dest/manifest.txt"
    fi
    break
  done
  mkdir -p "$dest"
  chmod 700 "$dest"

  picked x_encrypt && { info "Choose a passphrase. Without it the backup cannot be opened, so keep it safe."; ap_ask_passphrase confirm; }

  printf '# fedora-nothing agent backup, %s, from %s\n' "$(date '+%Y-%m-%d %H:%M')" "$(hostname)" > "$dest/manifest.txt"
  printf 'encrypted\t%s\n' "$( [[ -n $AP_PASS ]] && echo yes || echo no )" >> "$dest/manifest.txt"
  step "Backing up"
  for k in "${keys[@]}"; do ap_backup_one "$k" "$dest" "$items"; done
  AP_PASS=""
  ok "Saved to ${dest/#$HOME/\~} ($(du -sh "$dest" | cut -f1))"
  info "The list of what is inside is in manifest.txt"
}

restore_flow() {
  local dir; dir=$(ap_pick_backup)
  local k src found=0 count
  new_list
  group t "Restore into"
  for k in "${AP_AGENTS[@]}"; do
    src=$(ap_source_for "$dir" "$k") || continue
    count=$(ap_manifest_count "$dir" "$src")
    component "t_$k" t on "$(ap_name "$k")" "$count item(s)"
    found=1
  done
  (( found )) || die "This backup holds no agent data" \
                     "An agent backup from ./agent-backup.sh lists agents under \"agent\" in manifest.txt." \
                     "Pick the folder agent-backup.sh wrote, then run this again"
  local have_items
  have_items=$(awk -F'\t' '$1 == "agent" {print $3}' "$dir/manifest.txt" | tr '\n' ,)
  group what "What to restore"
  component x_chats what base "Chats + history" "conversations and session logs"
  [[ $have_items == *settings* ]] && component x_settings what on "Settings" "config, skills, rules, plugins"
  [[ $have_items == *auth* ]]     && component x_auth     what on "Sign-in (auth)" "credentials and tokens"

  UI_TITLE="Restore AI agent data" UI_SUBTITLE="from ${dir/#$HOME/\~}" UI_ACCEPT="restore"
  UI_LEGEND="[·] always included"
  ui_select_components

  local items; items=$(picked_items)
  ap_is_encrypted "$dir" && { local_need gpg zstd tar; ap_ask_passphrase; } || local_need zstd tar

  step "Restoring"
  for k in "${AP_AGENTS[@]}"; do
    picked "t_$k" || continue
    ap_restore_one "$dir" "$k" "$items"
  done
  AP_PASS=""
  info "Open each agent once: it picks up its conversations and stays signed in"
  if (( ${#SOFT_FAILURES[@]} )); then
    warn "${#SOFT_FAILURES[@]} part(s) did not finish; see above"
  fi
}

main() {
  printf '\n  %s%s███%s  %sAI agent data%s\n' "$C_RED" "$C_BOLD" "$C_OFF" "$C_BOLD" "$C_OFF"
  printf '  %sBack up or restore your coding agents. Nothing is uploaded.%s\n\n' "$C_GREY" "$C_OFF"
  local reply
  read -rn1 -p "  [B]ack up   [R]estore   [Q]uit " reply; printf '\n\n'
  case $reply in
    [bB]) backup_flow ;;
    [rR]) restore_flow ;;
    *)    exit 0 ;;
  esac
}

main "$@"
