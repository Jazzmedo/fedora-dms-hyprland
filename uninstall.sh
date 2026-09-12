#!/usr/bin/env bash
# Undo what install.sh did on this machine.
#
# Reads the ledger every install writes to logs/*.manifest, and reverses it:
# services it enabled, files it created, packages it installed, sources it
# added. Anything absent from the ledger is left alone, which is the whole
# point -- a package that was already on the machine before the installer ran
# was never ours to remove.
#
# For an install that predates the ledger there is --from-log, which infers the
# same list from the prose log. It is less certain, and it says so.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DRY_RUN=0
ASSUME_YES=0
NO_BACKUP=0
COLOR_MODE=${COLOR_MODE:-auto}
KEEP_PACKAGES=0
KEEP_FILES=0
SWEEP=1
RESTORE=1
MANIFESTS=()
FROM_LOGS=()

# shellcheck source=lib/common.sh
source "$REPO_DIR/lib/common.sh"
# shellcheck source=lib/progress.sh
source "$REPO_DIR/lib/progress.sh"
# shellcheck source=lib/components.sh
source "$REPO_DIR/lib/components.sh"
# shellcheck source=lib/detect.sh
source "$REPO_DIR/lib/detect.sh"
# shellcheck source=lib/artifacts.sh
source "$REPO_DIR/lib/artifacts.sh"

LOG_FILE="$REPO_DIR/logs/uninstall-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || LOG_FILE=""
[[ -n $LOG_FILE ]] && : > "$LOG_FILE"

usage() {
  cat <<'EOF'
  ./uninstall.sh — remove what ./install.sh installed

  Options
    --dry-run            show what would happen, change nothing
    --yes                do not ask for confirmation
    --manifest FILE      undo this record only (default: every run, newest first)
    --from-log FILE      work an old install log out instead, for runs made
                         before the installer kept records
    --keep-packages      leave installed programs alone, remove only settings
    --keep-files         remove programs and services, leave settings in place
    --recorded-only      undo only what the records list, and sweep nothing.
                         Without this, everywhere this installer or the
                         installers it runs can leave something is swept too
    --no-restore         do not put replaced files back from the backup
    --list               show the records available and exit
    -h, --help           this
EOF
}

# ------------------------------------------------------------------ input ---
while (( $# )); do
  case $1 in
    --dry-run)       DRY_RUN=1 ;;
    --yes|-y)        ASSUME_YES=1 ;;
    --manifest)      MANIFESTS+=("$2"); shift ;;
    --manifest=*)    MANIFESTS+=("${1#*=}") ;;
    --from-log)      FROM_LOGS+=("$2"); shift ;;
    --from-log=*)    FROM_LOGS+=("${1#*=}") ;;
    --keep-packages) KEEP_PACKAGES=1 ;;
    --keep-files)    KEEP_FILES=1 ;;
    --no-restore)    RESTORE=0 ;;
    --recorded-only) SWEEP=0 ;;
    --color=*)       COLOR_MODE=${1#*=}; set_colors ;;
    --list)          LIST_ONLY=1 ;;
    -h|--help)       usage; exit 0 ;;
    *)               die "I do not understand \"$1\"" "" "./uninstall.sh --help" ;;
  esac
  shift
done
LIST_ONLY=${LIST_ONLY:-0}

# --------------------------------------------------------------- the input ---
list_records() {
  local f found=0
  printf '\n  %sInstall records in %s%s\n\n' "$C_BOLD" "${REPO_DIR/#$HOME/\~}/logs" "$C_OFF"
  for f in "$REPO_DIR"/logs/*.manifest; do
    [[ -e $f && ! -L $f ]] || continue
    found=1
    printf '    %-44s %s%s entries%s\n' "$(basename "$f")" "$C_GREY" "$(wc -l <"$f")" "$C_OFF"
  done
  (( found )) || printf '    %snone yet%s\n' "$C_GREY" "$C_OFF"
  printf '\n'
}

# Entries in the order they were made, so they can be undone backwards.
ENTRY_KIND=()
ENTRY_A=()
ENTRY_B=()
INFERRED=0
SWEPT=0

load_entries() {
  local -a files=()
  if (( ${#MANIFESTS[@]} )); then
    files=("${MANIFESTS[@]}")
  elif (( ${#FROM_LOGS[@]} == 0 )); then
    # Every run, oldest first: undoing walks the whole list backwards.
    local f
    for f in "$REPO_DIR"/logs/*.manifest; do
      [[ -e $f && ! -L $f ]] && files+=("$f")
    done
  fi

  local file kind a b
  for file in ${files[@]+"${files[@]}"}; do
    [[ -r $file ]] || die "Cannot read $file"
    while IFS=$'\t' read -r kind a b; do
      [[ -n ${kind:-} ]] || continue
      ENTRY_KIND+=("$kind"); ENTRY_A+=("${a:-}"); ENTRY_B+=("${b:-}")
    done <"$file"
  done

  (( SWEEP )) && sweep_artifacts

  for file in ${FROM_LOGS[@]+"${FROM_LOGS[@]}"}; do
    [[ -r $file ]] || die "Cannot read $file"
    INFERRED=1
    while IFS=$'\t' read -r kind a b; do
      [[ -n ${kind:-} ]] || continue
      ENTRY_KIND+=("$kind"); ENTRY_A+=("${a:-}"); ENTRY_B+=("${b:-}")
    done < <(python3 "$REPO_DIR/lib/manifest_from_log.py" "$file")
  done
}


# Everything the inventory names that is actually on this machine.
#
# The records cannot cover a run made before they existed, nor anything another
# installer did on our behalf: the desktop shell, the music player and the Rust
# toolchain all arrive through somebody else's script and write where they
# please. This walks the known locations instead of the history.
sweep_artifacts() {
  local x
  while read -r x; do
    [[ -n $x ]] || continue
    [[ -e $x || -L $x ]] && { ENTRY_KIND+=(file); ENTRY_A+=("$x"); ENTRY_B+=(""); }
  done < <(artifact_home_paths; artifact_system_paths)

  while read -r x; do
    [[ -n $x ]] || continue
    systemctl --user list-unit-files "$x" >/dev/null 2>&1 || continue
    ENTRY_KIND+=(unit-user); ENTRY_A+=("$x"); ENTRY_B+=("")
  done < <(artifact_user_units)

  while read -r x; do
    [[ -n $x ]] || continue
    systemctl is-enabled "$x" >/dev/null 2>&1 || continue
    ENTRY_KIND+=(unit-system); ENTRY_A+=("$x"); ENTRY_B+=("")
  done < <(artifact_system_units)

  # One rpm -qa, not ninety rpm -q.
  detect_snapshot
  while read -r x; do
    [[ -n $x ]] || continue
    pkg_installed "$x" || continue
    ENTRY_KIND+=(pkg); ENTRY_A+=("$x"); ENTRY_B+=("")
  done < <(artifact_packages)

  if have flatpak; then
    while read -r x; do
      [[ -n $x ]] || continue
      flatpak_installed "$x" || continue
      ENTRY_KIND+=(flatpak); ENTRY_A+=("$x"); ENTRY_B+=("")
    done < <(artifact_flatpaks)
  fi

  # A copr writes a repo file named after itself. No file, never enabled, and
  # asking dnf to disable it would only produce noise.
  while read -r x; do
    [[ -n $x ]] || continue
    local slug=${x//\//:}
    compgen -G "/etc/yum.repos.d/*${slug}*.repo" >/dev/null 2>&1 || continue
    ENTRY_KIND+=(copr); ENTRY_A+=("$x"); ENTRY_B+=("")
  done < <(artifact_coprs)

  while read -r x; do
    [[ -n $x ]] || continue
    [[ -f $x ]] && { ENTRY_KIND+=(repofile); ENTRY_A+=("$x"); ENTRY_B+=(""); }
  done < <(artifact_repofiles)

  SWEPT=1
}

# Collect the values of one kind, newest occurrence first, without repeats.
collect() {
  local want=$1 i seen_key
  local -A seen=()
  for (( i = ${#ENTRY_KIND[@]} - 1; i >= 0; i-- )); do
    [[ ${ENTRY_KIND[i]} == "$want" ]] || continue
    seen_key="${ENTRY_A[i]}"
    [[ -n ${seen[$seen_key]:-} ]] && continue
    seen[$seen_key]=1
    printf '%s\t%s\n' "${ENTRY_A[i]}" "${ENTRY_B[i]}"
  done
}

# ----------------------------------------------------------------- safety ---
# A path is only removable if this installer is known to own that location.
# Nothing else is touched, however the ledger got its contents.
SYSTEM_PREFIXES=(
  /usr/share/sddm/themes/nothing
  /usr/share/fonts/nothing
  /usr/share/fonts/jetbrains-nerd
  /usr/share/wayland-sessions/
  /usr/share/applications/
  /usr/local/bin/
  /etc/sddm.conf.d/
  /etc/fonts/local.conf
  /etc/sysctl.d/
  /etc/yum.repos.d/
  /etc/zen/
  /etc/firefox/
  /etc/librewolf
  /etc/chromium/
  /etc/brave/
  /etc/opt/chrome/
  /etc/helium/
  /opt/zen
  /opt/helium
)

# Directories in $HOME that hold the user's own documents. A ledger entry
# should never name one, and if one ever does, it is a bug that must not cost
# somebody their files.
HOME_PROTECTED=(Documents Downloads Desktop Music Videos Public Templates .ssh .gnupg .mozilla)

SKIPPED_PATHS=()

path_removable() {
  local p=$1 d
  [[ -n $p ]]                       || return 1
  [[ $p != *".."* ]]                || return 1
  [[ $p == /* ]]                    || return 1
  [[ $p != "/" && $p != "$HOME" ]]  || return 1
  # Never anything inside the repository itself.
  [[ $p != "$REPO_DIR"* ]]          || return 1

  if [[ $p == "$HOME"/* ]]; then
    local rel=${p#"$HOME"/}
    local top=${rel%%/*}
    [[ -n $top ]] || return 1
    for d in "${HOME_PROTECTED[@]}"; do
      [[ $top == "$d" ]] && return 1
    done
    # Pictures itself is the user's; only the collection we made is ours.
    if [[ $top == Pictures ]]; then
      [[ $p == "$HOME/Pictures/Wallpapers/theme-collections"* ]] || return 1
    fi
    return 0
  fi

  for d in "${SYSTEM_PREFIXES[@]}"; do
    [[ $p == "$d"* ]] && return 0
  done
  return 1
}

# Returns 0 only when something was actually removed, so the count is honest.
remove_path() {
  local p=$1
  if ! path_removable "$p"; then
    SKIPPED_PATHS+=("$p")
    return 1
  fi
  [[ -e $p || -L $p ]] || return 1
  if [[ $p == "$HOME"/* ]]; then
    run rm -rf -- "$p"
  else
    as_root rm -rf -- "$p"
  fi
}

# ------------------------------------------------------------------- plan ---
declare -a IGNORED_PATHS=()
declare -a P_FILES=() P_PKGS=() P_FLATPAKS=() P_COPRS=() P_REPOFILES=()
declare -a P_UNITS_USER=() P_UNITS_SYSTEM=() P_MOVED=() P_EDITED=() P_BACKUPS=()
P_SHELL_USER=""; P_SHELL_WAS=""; P_TARGET=""; P_DM=""; P_PLYMOUTH=""

# Packages whose removal would break the machine rather than the desktop.
CRITICAL_PKGS=" kernel kernel-core dnf dnf5 rpm systemd systemd-libs systemd-udev \
glibc bash coreutils util-linux filesystem setup dbus dbus-broker polkit sudo \
NetworkManager selinux-policy grub2-common shim dracut openssh-server "

build_plan() {
  local a b
  while IFS=$'\t' read -r a b; do [[ -n $a ]] && P_FILES+=("$a"); done < <(collect file; collect symlink)
  while IFS=$'\t' read -r a b; do
    [[ -n $a ]] || continue
    [[ $CRITICAL_PKGS == *" $a "* ]] && continue
    rpm -q "$a" >/dev/null 2>&1 && P_PKGS+=("$a")
  done < <(collect pkg)
  while IFS=$'\t' read -r a b; do [[ -n $a ]] && P_FLATPAKS+=("$a"); done < <(collect flatpak)
  while IFS=$'\t' read -r a b; do [[ -n $a ]] && P_COPRS+=("$a"); done < <(collect copr)
  while IFS=$'\t' read -r a b; do [[ -n $a ]] && P_REPOFILES+=("$a"); done < <(collect repofile)
  while IFS=$'\t' read -r a b; do [[ -n $a ]] && P_UNITS_USER+=("$a"); done < <(collect unit-user)
  while IFS=$'\t' read -r a b; do [[ -n $a ]] && P_UNITS_SYSTEM+=("$a"); done < <(collect unit-system)
  while IFS=$'\t' read -r a b; do [[ -n $a ]] && P_MOVED+=("$a"$'\t'"$b"); done < <(collect moved)
  while IFS=$'\t' read -r a b; do [[ -n $a ]] && P_EDITED+=("$a"); done < <(collect edited)
  while IFS=$'\t' read -r a b; do [[ -d $a ]] && P_BACKUPS+=("$a"); done < <(collect backup)

  # Removing SDDM with nothing recorded to fall back on would leave the machine
  # booting to a graphical target with no way to log in graphically.
  if (( SWEPT )) && [[ -z $P_TARGET ]]; then
    local p
    for p in ${P_PKGS[@]+"${P_PKGS[@]}"}; do
      [[ $p == sddm ]] && { P_TARGET=multi-user.target; break; }
    done
  fi

  local first
  first=$(collect shell | head -1)
  P_SHELL_USER=${first%%$'\t'*}; P_SHELL_WAS=${first#*$'\t'}
  P_TARGET=$(collect target | head -1); P_TARGET=${P_TARGET%%$'\t'*}
  P_DM=$(collect dm | head -1); P_DM=${P_DM%%$'\t'*}
  P_PLYMOUTH=$(collect plymouth | head -1); P_PLYMOUTH=${P_PLYMOUTH%%$'\t'*}
  # A swept removal takes the theme's files, which leaves the boot pointing at
  # a theme that is gone. Fedora's own is the safe landing place.
  if (( SWEPT )) && [[ -z $P_PLYMOUTH ]] && [[ -d /usr/share/plymouth/themes/nothing ]]; then
    P_PLYMOUTH=bgrt
  fi
}

count_line() {
  local n=$1 label=$2
  (( n )) || return 0
  printf '    %s%4d%s  %s\n' "$C_BOLD" "$n" "$C_OFF" "$label"
}

show_plan() {
  printf '\n%s╭%s╮%s\n' "$C_RED" "$(rule $(( UI_WIDTH - 2 )))" "$C_OFF"
  local title="Removing the fedora-nothing desktop"
  printf '%s│%s  %s%s%s%*s%s│%s\n' \
    "$C_RED" "$C_OFF" "$C_BOLD" "$title" "$C_OFF" $(( UI_WIDTH - 4 - ${#title} )) '' "$C_RED" "$C_OFF"
  printf '%s╰%s╯%s\n\n' "$C_RED" "$(rule $(( UI_WIDTH - 2 )))" "$C_OFF"

  local f removable=0
  IGNORED_PATHS=()
  for f in ${P_FILES[@]+"${P_FILES[@]}"}; do
    if path_removable "$f"; then (( ++removable )); else IGNORED_PATHS+=("$f"); fi
  done
  (( KEEP_FILES ))    || count_line "$removable"             "files and folders the installer created"
  (( KEEP_PACKAGES )) || count_line "${#P_PKGS[@]}"          "programs it installed"
  (( KEEP_PACKAGES )) || count_line "${#P_FLATPAKS[@]}"      "Flatpak apps it installed"
  (( KEEP_PACKAGES )) || count_line "${#P_COPRS[@]}"         "community software sources it enabled"
  (( KEEP_PACKAGES )) || count_line "${#P_REPOFILES[@]}"     "download sources it added"
  count_line "${#P_UNITS_USER[@]}"   "services it starts when you log in"
  count_line "${#P_UNITS_SYSTEM[@]}" "system services it switched on"
  [[ -n $P_SHELL_WAS ]] && printf '    %s   ·%s  your login shell goes back to %s\n' \
    "$C_BOLD" "$C_OFF" "$P_SHELL_WAS"
  [[ -n $P_TARGET ]] && printf '    %s   ·%s  the computer boots to %s again\n' \
    "$C_BOLD" "$C_OFF" "$P_TARGET"
  [[ -n $P_DM ]] && printf '    %s   ·%s  %s becomes the login screen again\n' \
    "$C_BOLD" "$C_OFF" "${P_DM%.service}"
  [[ -n $P_PLYMOUTH ]] && printf '    %s   ·%s  the boot splash goes back to %s\n' \
    "$C_BOLD" "$C_OFF" "$P_PLYMOUTH"
  (( RESTORE )) && count_line "${#P_BACKUPS[@]}" "backups to put back afterwards"

  if (( ${#P_EDITED[@]} )); then
    printf '\n  %sLeft as they are%s  %d file(s) the installer changed rather than created.\n' \
      "$C_GREY" "$C_OFF" "${#P_EDITED[@]}"
    printf '  %sIf a backup exists it is restored over them.%s\n' "$C_GREY" "$C_OFF"
  fi

  if (( ${#IGNORED_PATHS[@]} )); then
    printf '\n  %sNot touched%s  %d path(s) in the record are outside anywhere this installer\n' \
      "$C_WARN" "$C_OFF" "${#IGNORED_PATHS[@]}"
    printf '               owns, so they stay:\n'
    for f in "${IGNORED_PATHS[@]}"; do printf '    %s\n' "${f/#$HOME/\~}"; done
  fi

  if (( SWEPT )); then
    printf '\n  %s▲ This is a full removal.%s Everywhere this installer, and the installers\n' \
      "$C_WARN" "$C_OFF"
    printf '    it runs, can leave something has been swept, not just what the records\n'
    printf '    list. A program above may predate your first install: the records know\n'
    printf '    the difference, a sweep cannot. %s--recorded-only%s undoes only the records.\n' \
      "$C_BOLD" "$C_OFF"
  fi

  if (( INFERRED )); then
    printf '\n  %s▲ This list was worked out from a log, not from a record of the run.%s\n' \
      "$C_WARN" "$C_OFF"
    printf '    %sA log cannot say what was already installed beforehand. Read the list.%s\n' \
      "$C_GREY" "$C_OFF"
  fi
  printf '\n'
}

show_detail() {
  local x
  if (( ${#P_PKGS[@]} && ! KEEP_PACKAGES )); then
    printf '  %sPrograms to remove%s\n    %s\n\n' "$C_BOLD" "$C_OFF" "${P_PKGS[*]}"
  fi
  if (( ${#P_FILES[@]} && ! KEEP_FILES )); then
    printf '  %sFiles and folders to remove%s\n' "$C_BOLD" "$C_OFF"
    for x in "${P_FILES[@]}"; do
      path_removable "$x" && printf '    %s\n' "${x/#$HOME/\~}"
    done
    printf '\n'
  fi
}

# ------------------------------------------------------------------- doing ---
undo_services() {
  local u
  for u in ${P_UNITS_USER[@]+"${P_UNITS_USER[@]}"}; do
    systemctl --user list-unit-files "$u" >/dev/null 2>&1 || continue
    run systemctl --user disable --now "$u" || true
  done
  (( ${#P_UNITS_USER[@]} )) && ok "Stopped the services that started at login"

  for u in ${P_UNITS_SYSTEM[@]+"${P_UNITS_SYSTEM[@]}"}; do
    as_root systemctl disable --now "$u" || true
  done
  (( ${#P_UNITS_SYSTEM[@]} )) && ok "Switched off the system services it turned on"
  return 0
}

undo_boot_splash() {
  [[ -n $P_PLYMOUTH ]] || return 0
  have plymouth-set-default-theme || return 0
  [[ -d /usr/share/plymouth/themes/$P_PLYMOUTH ]] || return 0
  # -R rebuilds the startup image; without it the boot still looks for ours.
  as_root plymouth-set-default-theme -R "$P_PLYMOUTH" \
    && ok "The boot splash is back to $P_PLYMOUTH"
  return 0
}

undo_display_manager() {
  [[ -n $P_DM ]] || return 0
  systemctl list-unit-files "$P_DM" >/dev/null 2>&1 || return 0
  as_root systemctl enable --force "$P_DM" \
    && ok "${P_DM%.service} is the login screen again"
  return 0
}

undo_boot_target() {
  [[ -n $P_TARGET ]] || return 0
  [[ $P_TARGET == graphical.target ]] && { skip "The computer already booted to a login screen before"; return 0; }
  as_root systemctl set-default "$P_TARGET" && ok "The computer will boot to $P_TARGET again"
  return 0
}

undo_login_shell() {
  # A log records that chsh ran, never what the shell was before it. Guessing
  # would be worse than saying so.
  if [[ -z $P_SHELL_WAS && -n $P_SHELL_USER ]]; then
    warn "Cannot tell what your login shell was before, so it is left as it is"
    info "To change it yourself: chsh -s /bin/bash"
    return 0
  fi
  [[ -n $P_SHELL_WAS ]] || return 0
  [[ -x $P_SHELL_WAS ]] || { warn "Cannot restore the login shell: $P_SHELL_WAS is not there any more"; return 0; }
  as_root chsh -s "$P_SHELL_WAS" "${P_SHELL_USER:-$USER}" \
    && ok "Your login shell is $P_SHELL_WAS again"
  return 0
}

undo_files() {
  (( KEEP_FILES )) && { skip "Settings kept, as asked"; return 0; }
  local p n=0
  for p in ${P_FILES[@]+"${P_FILES[@]}"}; do
    remove_path "$p" && (( ++n )) || true
  done
  ok "Removed $n file(s) and folder(s)"

  # Directories this installer created only to hold what has just gone. Removed
  # only when empty, so a Wallpapers folder with your own pictures in it stays.
  local leftover
  for leftover in "$HOME/Pictures/Wallpapers" "$HOME/SelfHosted" "$HOME/.zsh"; do
    [[ -d $leftover ]] || continue
    rmdir "$leftover" 2>/dev/null || true
  done

  local pair from to
  for pair in ${P_MOVED[@]+"${P_MOVED[@]}"}; do
    IFS=$'\t' read -r from to <<< "$pair"
    [[ -e $to ]] || continue
    as_root mv "$to" "$from" && ok "Put $from back"
  done
  return 0
}

undo_flatpaks() {
  (( KEEP_PACKAGES )) && return 0
  (( ${#P_FLATPAKS[@]} )) || return 0
  have flatpak || return 0
  local f
  for f in "${P_FLATPAKS[@]}"; do
    flatpak info "$f" >/dev/null 2>&1 || continue
    run_visible flatpak uninstall -y "$f" || warn "Could not remove $f"
  done
  ok "Removed the Flatpak apps"
  return 0
}

undo_packages() {
  (( KEEP_PACKAGES )) && { skip "Programs kept, as asked"; return 0; }
  (( ${#P_PKGS[@]} )) || return 0
  # One transaction, so dnf can work out the dependency order itself.
  if as_root dnf remove -y "${P_PKGS[@]}"; then
    ok "Removed ${#P_PKGS[@]} program(s)"
  else
    soft_fail "Some programs could not be removed" \
              "dnf refused part of the transaction." \
              "sudo dnf remove ${P_PKGS[*]:0:6} ..."
  fi
  return 0
}

undo_sources() {
  (( KEEP_PACKAGES )) && return 0
  local c f
  for c in ${P_COPRS[@]+"${P_COPRS[@]}"}; do
    as_root dnf copr disable -y "$c" || warn "Could not switch off the $c source"
  done
  for f in ${P_REPOFILES[@]+"${P_REPOFILES[@]}"}; do
    [[ -f $f ]] && as_root rm -f "$f"
  done
  (( ${#P_COPRS[@]} + ${#P_REPOFILES[@]} )) && ok "Removed the extra download sources"
  return 0
}

restore_backups() {
  (( RESTORE )) || { skip "Backups left where they are, as asked"; return 0; }
  (( ${#P_BACKUPS[@]} )) || return 0
  # Oldest backup last, so the earliest original wins and the machine ends up
  # as it was before the first install rather than between two of them.
  local i dir n=0
  for (( i = 0; i < ${#P_BACKUPS[@]}; i++ )); do
    dir=${P_BACKUPS[i]}
    [[ -d $dir ]] || continue
    run cp -a "$dir/." "$HOME/" && (( ++n ))
  done
  (( n )) && ok "Put back what the installer had replaced, from $n backup(s)"
  return 0
}

# ------------------------------------------------------------------- main ---
main() {
  (( LIST_ONLY )) && { list_records; exit 0; }

  load_entries
  if (( ${#ENTRY_KIND[@]} == 0 )); then
    printf '\n  %s✓ Nothing to remove.%s Neither the records nor a sweep of every place\n' \
      "$C_OK$C_BOLD" "$C_OFF"
    printf '    this installer writes to found anything on this machine.\n\n'
    exit 0
  fi

  build_plan
  show_plan
  show_detail

  if (( DRY_RUN )); then
    printf '  %sThat was a dry run. Nothing on this machine changed.%s\n\n' "$C_CYAN" "$C_OFF"
    exit 0
  fi

  if ! (( ASSUME_YES )); then
    [[ -t 0 ]] || die "Nothing was removed" \
        "This is not an interactive terminal, so the confirmation could not be asked for." \
        "./uninstall.sh --yes"
    printf '  %sType%s remove %sto go ahead, anything else to stop:%s ' \
      "$C_GREY" "$C_BOLD" "$C_OFF$C_GREY" "$C_OFF"
    local reply; read -r reply
    [[ $reply == remove ]] || { printf '\n  Nothing was removed.\n\n'; exit 0; }
  fi

  sudo_begin

  step "Services"
  undo_services
  undo_boot_splash
  undo_display_manager
  undo_boot_target
  undo_login_shell

  step "Files"
  undo_files

  step "Programs"
  undo_flatpaks
  undo_packages
  undo_sources

  step "Restoring"
  restore_backups

  if (( ${#SKIPPED_PATHS[@]} )); then
    printf '\n  %sNot touched%s  these were in the record but are outside anywhere this\n' \
      "$C_WARN" "$C_OFF"
    printf '              installer owns, so they were left alone:\n'
    local p
    for p in "${SKIPPED_PATHS[@]}"; do printf '    %s\n' "$p"; done
  fi

  printf '\n  %s✓ Done.%s Log: %s\n' "$C_OK$C_BOLD" "$C_OFF" "${LOG_FILE/#$HOME/\~}"
  printf '  %sThe records in logs/ are kept, so this can be re-run.%s\n\n' "$C_GREY" "$C_OFF"
  INSTALL_COMPLETED=1
}

main "$@"
