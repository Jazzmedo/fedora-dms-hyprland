#!/usr/bin/env bash
# Back up or restore your browser extensions and their data: Tampermonkey
# scripts, ShellTint styles, uBlock lists and the rest. Cookies and
# certificates can come along too. Everything is chosen on screen.
#
# Backups go to ~/fedora-nothing-backups/ (or a folder you pick, such as a USB
# drive). They are never written inside a git repository, so one cannot be
# committed by accident.
set -euo pipefail
umask 077   # the archives can hold sign-in data

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
# shellcheck source=lib/browser-profiles.sh
source "$REPO_DIR/lib/browser-profiles.sh"
set_colors 2>/dev/null || true

[[ -t 0 && -t 1 ]] || die "Run this in a terminal" "Every choice is made on screen."

local_need() {
  local c missing=()
  for c in "$@"; do have "$c" || missing+=("$c"); done
  (( ${#missing[@]} == 0 )) && return 0
  die "Missing: ${missing[*]}" "" "sudo dnf install ${missing[*]/secret-tool/libsecret}"
}

# The checklist works off the installer's component lists. Swap them for this
# script's own entries.
new_list() {
  COMPONENT_ORDER=(); COMPONENT_GROUPS=()
  unset SELECTED COMPONENT_STATE
  declare -gA SELECTED=() COMPONENT_STATE=()
  DETECT_COMPONENTS_READY=1
}

picked() { is_selected "$1"; }

# Comma list of the ticked "what" entries.
picked_items() {
  local out=extensions
  picked x_cookies  && out+=,cookies
  picked x_certs    && out+=,certs
  picked x_syscerts && out+=,syscerts
  printf '%s' "$out"
}

inside_git() {   # the nearest existing parent of $1 is in a git work tree
  local d=$1
  while [[ ! -d $d ]]; do d=$(dirname "$d"); done
  git -C "$d" rev-parse --is-inside-work-tree >/dev/null 2>&1
}

backup_flow() {
  local k p found=0
  new_list
  group b "Browsers found on this machine"
  for k in "${BP_BROWSERS[@]}"; do
    p=$(bp_profile "$k") || continue
    component "b_$k" b on "$(bp_name "$k")" "${p/#$HOME/\~}"
    found=1
  done
  (( found )) || die "No browser profiles were found" "Open the browser once so it creates one."
  group what "What to include"
  component x_ext      what base "Extensions + data" "Tampermonkey scripts, ShellTint styles, uBlock lists…"
  component x_cookies  what off  "Cookies"                 "stay logged in to sites; needs encryption"
  component x_certs    what off  "Browser certificates"    "certificates and client keys you imported; needs encryption"
  local nsys; nsys=$(bp_system_cert_count)
  (( nsys )) && component x_syscerts what off "System certificates" "the $nsys you added to this machine"
  group prot "Protection"
  component x_encrypt  prot on   "Encrypt with a passphrase" "recommended; anyone with the files can read them otherwise"

  UI_TITLE="Back up browser extensions" UI_SUBTITLE="tick what to save" UI_ACCEPT="continue"
  UI_LEGEND="[·] always included"
  ui_select_components

  local keys=()
  for k in "${BP_BROWSERS[@]}"; do picked "b_$k" && keys+=("$k"); done
  (( ${#keys[@]} )) || die "No browser was ticked"
  local items; items=$(picked_items)
  if [[ $items == *cookies* || $items == *certs* ]] && ! picked x_encrypt; then
    select_component x_encrypt
    info "Encryption was turned back on: cookies and certificates sign you in, so they are never stored readable"
  fi
  picked x_encrypt && local_need gpg zstd tar || local_need zstd tar
  [[ $items == *cookies* ]] && ! have secret-tool && \
    warn "secret-tool is missing, so the cookie keys of Chromium browsers are not saved (sudo dnf install libsecret)"

  local dest def="$BP_BACKUP_ROOT/browsers-$(date +%Y-%m-%d)"
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

  local ready=()
  for k in "${keys[@]}"; do bp_wait_closed "$k" && ready+=("$k"); done
  (( ${#ready[@]} )) || die "Every browser was skipped; nothing was saved"

  picked x_encrypt && { info "Choose a passphrase. Without it the backup cannot be opened, so keep it safe."; bp_ask_passphrase confirm; }

  printf '# fedora-nothing browser backup, %s, from %s\n' "$(date '+%Y-%m-%d %H:%M')" "$(hostname)" > "$dest/manifest.txt"
  printf 'encrypted\t%s\n' "$( [[ -n $BP_PASS ]] && echo yes || echo no )" >> "$dest/manifest.txt"
  step "Backing up"
  for k in "${ready[@]}"; do bp_backup_one "$k" "$dest" "$items"; done
  bp_backup_shared "$dest" "$items"
  BP_PASS=""
  ok "Saved to ${dest/#$HOME/\~} ($(du -sh "$dest" | cut -f1))"
  info "The list of what is inside is in manifest.txt"
}

restore_flow() {
  local dir; dir=$(bp_pick_backup)
  local k src found=0 count
  new_list
  group t "Restore into"
  for k in "${BP_BROWSERS[@]}"; do
    bp_installed "$k" || continue
    src=$(bp_source_for "$dir" "$k") || continue
    count=$(bp_manifest_extcount "$dir" "$src")
    if [[ $src == "$k" ]]; then
      component "t_$k" t on "$(bp_name "$k")" "$count extensions"
    else
      component "t_$k" t on "$(bp_name "$k")" "$count extensions, from the $(bp_name "$src") backup"
    fi
    found=1
  done
  (( found )) || die "None of the browsers on this machine can use this backup" \
                     "A Firefox-family backup restores into Zen, Firefox or LibreWolf; a Chromium-family one into Brave, Vivaldi or Helium." \
                     "Install a matching browser, then run this again"
  local have_items
  have_items=$(awk -F'\t' '$1 == "browser" || $1 == "shared" {print $NF}' "$dir/manifest.txt" | tr '\n' ,)
  group what "What to restore"
  component x_ext what base "Extensions + data" "reinstalled where needed"
  [[ $have_items == *cookies* ]]  && component x_cookies  what on "Cookies" "sign back in to sites"
  [[ $have_items == *certs* ]]    && component x_certs    what on "Browser certificates" "replaces the browser's own certificate store"
  [[ $have_items == *syscerts* ]] && component x_syscerts what on "System certificates" "added for the whole machine; asks for your password"

  UI_TITLE="Restore browser extensions" UI_SUBTITLE="from ${dir/#$HOME/\~}" UI_ACCEPT="restore"
  UI_LEGEND="[·] always included"
  ui_select_components

  local items; items=$(picked_items)
  bp_is_encrypted "$dir" && { local_need gpg zstd tar; bp_ask_passphrase; } || local_need zstd tar

  step "Restoring"
  for k in "${BP_BROWSERS[@]}"; do
    picked "t_$k" || continue
    bp_wait_closed "$k" || continue
    bp_restore_one "$dir" "$k" "$(bp_source_for "$dir" "$k")" "$items"
  done
  bp_restore_shared "$dir" "$items"
  BP_PASS=""
  info "Open each browser once: extensions reinstall in the background and pick up their data"
  if (( ${#SOFT_FAILURES[@]} )); then
    warn "${#SOFT_FAILURES[@]} part(s) did not finish; see above"
  fi
}

main() {
  printf '\n  %s%s███%s  %sBrowser extensions%s\n' "$C_RED" "$C_BOLD" "$C_OFF" "$C_BOLD" "$C_OFF"
  printf '  %sBack up or restore extensions and their data. Nothing is uploaded.%s\n\n' "$C_GREY" "$C_OFF"
  local reply
  read -rn1 -p "  [B]ack up   [R]estore   [Q]uit " reply; printf '\n\n'
  case $reply in
    [bB]) backup_flow ;;
    [rR]) restore_flow ;;
    *)    exit 0 ;;
  esac
}

main "$@"
