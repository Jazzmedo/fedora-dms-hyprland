# shellcheck shell=bash
# Logging, command execution, backup and templating primitives.
# Sourced by install.sh and every stage. Assumes `set -euo pipefail`.

# An unexpected non-zero exit under `set -e` used to end the run silently, so a
# crash looked exactly like a clean finish. Checking at exit rather than
# trapping ERR is deliberate: with errtrace, every `[[ ]]` that happens to be
# false inside a loop fires the trap, and the real failure drowns in noise.
CURRENT_STAGE="startup"
INSTALL_COMPLETED=0

# The ONE exit handler. Bash traps are global, not scoped to a function, so a
# stage that installs its own `trap ... EXIT` silently replaces this one.
# 00-preflight.sh used to do exactly that to kill its sudo keepalive, which
# meant twelve of the thirteen stages ran with no crash report at all: a stage
# that died took the rest of the run with it and printed nothing.
SUDO_KEEPALIVE=""

install_exit_trap() {
  local code=$1

  spin_cleanup 2>/dev/null || true
  [[ -n $SUDO_KEEPALIVE ]] && { kill "$SUDO_KEEPALIVE" 2>/dev/null || true; }

  (( INSTALL_COMPLETED )) && return 0
  (( code == 0 )) && return 0        # an intentional early exit, such as --status

  printf '\n%s✘ the installer stopped during the "%s" stage%s\n' \
    "$C_RED$C_BOLD" "$CURRENT_STAGE" "$C_OFF" >&2
  printf '  %sexit status%s  %s\n' "$C_GREY" "$C_OFF" "$code" >&2
  [[ -n ${LOG_FILE:-} ]] && \
    printf '  %slast log line%s %s\n' "$C_GREY" "$C_OFF" "$(tail -1 "$LOG_FILE" 2>/dev/null)" >&2
  # Naming the stages that never ran is the fact that was missing when this
  # died mid-install and six stages were skipped without a word.
  local -a remaining=()
  local seen=0 s
  for s in "${STAGES_TO_RUN[@]:-}"; do
    [[ $s == "$CURRENT_STAGE" ]] && { seen=1; continue; }
    (( seen )) && remaining+=("${STAGE_TITLE[$s]:-$s}")
  done
  if (( ${#remaining[@]} )); then
    printf '  %sthese did not run:%s %s\n' "$C_GREY" "$C_OFF" "${remaining[*]}" >&2
  fi

  printf '\n  %sWhat to do:%s re-run ./install.sh — it picks up where it stopped.\n' \
    "$C_GREY" "$C_OFF" >&2
  printf '  %sFor help:%s    ./doctor.sh, or ./report.sh to collect the details.%s\n\n' \
    "$C_GREY" "$C_OFF" "$C_OFF" >&2
  _log_raw "FATAL stage=$CURRENT_STAGE status=$code"
}

# ---------------------------------------------------------------- colours ---
# One decision for both streams. Testing stdout alone, as this used to, gave
# uncoloured warnings when stdout was redirected and raw escape codes in the
# file when stderr was.
#   COLOR_MODE=auto    colour when either stream is a terminal (the default)
#   COLOR_MODE=always  colour regardless, for `| tee run.log`
#   COLOR_MODE=never   never, same as NO_COLOR=1
COLOR_MODE=${COLOR_MODE:-auto}
# An explicit --color= wins over the environment; NO_COLOR only decides the
# default.
[[ -n ${NO_COLOR:-} && -z ${COLOR_MODE_EXPLICIT:-} ]] && COLOR_MODE=never

set_colors() {
  COLOR_ON=0
  case $COLOR_MODE in
    always) COLOR_ON=1 ;;
    never)  COLOR_ON=0 ;;
    *)      [[ -t 1 || -t 2 ]] && COLOR_ON=1 ;;
  esac

  if (( COLOR_ON )); then
    C_RED=$'\e[38;2;215;25;33m'   # Nothing red
    C_OK=$'\e[38;5;114m'          # done
    C_WARN=$'\e[38;5;179m'        # needs attention
    C_CYAN=$'\e[38;5;80m'         # happening now
    C_BLUE=$'\e[38;5;75m'
    C_MAGENTA=$'\e[38;5;176m'
    C_GREY=$'\e[38;5;245m'
    C_DIM=$'\e[2m'; C_BOLD=$'\e[1m'; C_OFF=$'\e[0m'
  else
    C_RED=""; C_OK=""; C_WARN=""; C_CYAN=""; C_BLUE=""; C_MAGENTA=""
    C_GREY=""; C_DIM=""; C_BOLD=""; C_OFF=""
  fi
}
set_colors

LOG_FILE=${LOG_FILE:-}

_log_raw() {
  [[ -n $LOG_FILE ]] && printf '%s %s\n' "$(date '+%F %T')" "$*" >>"$LOG_FILE"
  return 0
}

# Each class gets its own glyph and colour. They used to share: info and skip
# were both a grey dot, so "doing this" and "not doing this" looked identical,
# and soft_fail rendered exactly like warn, so a broken step read as an aside.
step()  { printf '\n%s▌ %s%s\n' "$C_RED$C_BOLD" "$*" "$C_OFF";     _log_raw "STEP  $*"; }
info()  { printf '  %s→%s %s\n'  "$C_CYAN" "$C_OFF" "$*";           _log_raw "INFO  $*"; }
ok()    { printf '  %s✓%s %s\n'  "$C_OK"   "$C_OFF" "$*";           _log_raw "OK    $*"; }
skip()  { printf '  %s·%s %s%s%s\n' "$C_GREY" "$C_OFF" "$C_DIM" "$*" "$C_OFF"; _log_raw "SKIP  $*"; }
warn()  { printf '  %s▲%s %s\n'  "$C_WARN" "$C_OFF" "$*" >&2;       _log_raw "WARN  $*"; }

# why/fix: an indented explanation under a failure. Callers pass them as the
# second and third arguments; every one-argument call site still works.
_detail() {
  local why=${1:-} fix=${2:-}
  [[ -n $why ]] && printf '      %sWhy:%s  %s\n' "$C_GREY" "$C_OFF" "$why" >&2
  [[ -n $fix ]] && printf '      %sFix:%s  %s%s%s\n' "$C_GREY" "$C_OFF" "$C_BOLD" "$fix" "$C_OFF" >&2
  return 0
}

die() {
  printf '\n  %s✘ %s%s\n' "$C_RED$C_BOLD" "$1" "$C_OFF" >&2
  _detail "${2:-}" "${3:-}"
  printf '\n' >&2
  _log_raw "FATAL $1${2:+ | why: $2}${3:+ | fix: $3}"
  exit 1
}

# A stage failure that must not abort the whole install. Recorded in three
# parallel arrays rather than one string, so the closing summary can reprint
# the cause and the command together instead of a flattened line.
SOFT_FAILURES=()
SOFT_WHY=()
SOFT_FIX=()

soft_fail() {
  printf '  %s✗%s %s\n' "$C_WARN$C_BOLD" "$C_OFF" "$1" >&2
  _detail "${2:-}" "${3:-}"
  printf '      %sThis part did not finish. Everything else carries on.%s\n' \
    "$C_GREY" "$C_OFF" >&2
  _log_raw "SOFT  $1${2:+ | why: $2}${3:+ | fix: $3}"
  SOFT_FAILURES+=("$1")
  SOFT_WHY+=("${2:-}")
  SOFT_FIX+=("${3:-}")
  return 0
}

# ------------------------------------------------------------- execution ---
# run <cmd...> — echo in dry-run, execute otherwise, and log either way.
run() {
  if (( DRY_RUN )); then
    printf '  %s$ %s%s\n' "$C_DIM" "$*" "$C_OFF"
    _log_raw "DRY   $*"
    return 0
  fi
  _log_raw "RUN   $*"
  if [[ -n $LOG_FILE ]]; then
    "$@" >>"$LOG_FILE" 2>&1
  else
    "$@"
  fi
}

# Same, but the output is meant for the user to watch (dnf, git clone). It is
# also teed into the log: this output is the bulk of what a failing run prints,
# and it used to reach the terminal only, so "see the log" pointed at a file
# that did not contain the error.
run_visible() {
  if (( DRY_RUN )); then
    printf '  %s$ %s%s\n' "$C_DIM" "$*" "$C_OFF"
    _log_raw "DRY   $*"
    return 0
  fi
  _log_raw "RUN   $*"
  if [[ -n $LOG_FILE ]]; then
    # pipefail is set, so the status is the command's, not tee's.
    "$@" 2>&1 | tee -a "$LOG_FILE"
  else
    "$@"
  fi
}

# Ask for the password once, up front, and hold the grant open for the run.
# Called from main() before any stage, so the prompt happens at a predictable
# moment rather than in the middle of somebody's dnf output.
sudo_begin() {
  (( DRY_RUN )) && return 0

  if ! sudo -n true 2>/dev/null; then
    printf '\n  %s→%s %sYour password is needed to install software. This is the only time.%s\n' \
      "$C_CYAN" "$C_OFF" "$C_BOLD" "$C_OFF"
    sudo -v || die "That password was not accepted." "" "Run ./install.sh again."
  fi

  # sudoers can be configured to forget the password immediately, in which case
  # every one of the fifty-odd privileged commands asks again and no keepalive
  # can help. Say so rather than let it look like a bug in the installer.
  if sudo -n true 2>/dev/null; then
    ( while kill -0 $$ 2>/dev/null; do sudo -n true 2>/dev/null || break; sleep 50; done ) &
    SUDO_KEEPALIVE=$!
  else
    warn "This system is set to forget the password immediately (timestamp_timeout=0), so it will ask again for each step"
  fi
  return 0
}

# Refresh before handing the command to the pipeline below. sudo writes its
# prompt to the terminal, but its errors go to stderr, and run_visible merges
# stderr into a pipe to tee -- so a prompt that appears there is confusing and
# a failure message is buried. Prompting here keeps both in front of the user.
sudo_refresh() {
  (( DRY_RUN )) && return 0
  sudo -n true 2>/dev/null && return 0
  sudo -v
}

as_root() { sudo_refresh; run_visible sudo "$@"; }

# retry <attempts> <cmd...> — for network-bound commands.
retry() {
  local attempts=$1; shift
  local n=1
  until run_visible "$@"; do
    (( n++ >= attempts )) && return 1
    warn "that did not work, trying again ($n of $attempts)"
    sleep $(( n * 2 ))
  done
}

# Count matching files under a directory, 0 when it does not exist.
#
# The obvious `n=$(find "$d" -type f | wc -l)` is a trap under `set -euo
# pipefail`: find exits 1 for a missing directory, pipefail makes that the
# status of the whole pipeline, and set -e then ends the run with nothing
# printed. That is what stopped the themes stage on a machine that did not have
# a wallpaper collection yet, and took five later stages with it.
count_files() {
  local dir=$1; shift
  [[ -d $dir ]] || { printf '0'; return 0; }
  local n
  n=$( { find "$dir" "$@" -type f 2>/dev/null || true; } | wc -l )
  printf '%s' "$n"
}

# Throwing away a scratch directory must never end the run. Anything unpacked
# or copied by a root command leaves root-owned files behind, and then the
# user's own `rm -rf` fails with "Permission denied", which under `set -e` is
# fatal. That is what killed the apps stage after Zen had installed correctly.
clean_tmp() {
  local d=${1:-}
  [[ -n $d && -d $d && $d == /tmp/* ]] || return 0
  rm -rf "$d" 2>/dev/null && return 0
  as_root rm -rf "$d" 2>/dev/null || true
  return 0
}

have()      { command -v "$1" >/dev/null 2>&1; }
rpm_has()   { rpm -q "$1" >/dev/null 2>&1; }

# --------------------------------------------------- user services ---
# `systemctl --user` talks to a systemd instance that only exists inside a
# registered login session. Started over su, or from a session logind never
# registered, every call fails with
#
#   Failed to connect to user scope bus via local transport: Operation not permitted
#
# and one unguarded call ended an entire install, taking six later stages with
# it. Nothing here may ever be fatal.
USER_BUS_STATE=""

user_bus_ok() {
  if [[ -z $USER_BUS_STATE ]]; then
    if systemctl --user show-environment >/dev/null 2>&1; then
      USER_BUS_STATE=ok
    else
      USER_BUS_STATE=unavailable
    fi
  fi
  [[ $USER_BUS_STATE == ok ]]
}

_unit_file() {
  local unit=$1 d
  for d in "$HOME/.config/systemd/user" /etc/systemd/user \
           /usr/local/lib/systemd/user /usr/lib/systemd/user; do
    [[ -f $d/$unit ]] && { printf '%s' "$d/$unit"; return 0; }
  done
  return 1
}

# Enabling a unit is only a symlink into <target>.wants. With no bus to ask,
# make the symlink directly: at the next login the result is identical, which
# is the login where these services were going to start anyway.
enable_user_unit() {
  local unit=$1 file
  file=$(_unit_file "$unit") || return 1

  if user_bus_ok; then
    run systemctl --user enable "$unit" && return 0
  fi

  local dir="$HOME/.config/systemd/user"
  local target ok=1
  while read -r target; do
    [[ -n $target ]] || continue
    ok=0
    run mkdir -p "$dir/$target.wants"
    run ln -sfn "$file" "$dir/$target.wants/$unit"
  done < <(sed -n 's/^WantedBy=//p' "$file" | tr ' ' '\n')
  return "$ok"
}

# Pointless without a bus, and harmless to skip: a user manager that is not
# running reads every unit fresh when it starts.
user_daemon_reload() {
  user_bus_ok || return 0
  run systemctl --user daemon-reload || true
  return 0
}

# --------------------------------------------------------------- ledger ---
# What this run changed, in a form a machine can undo.
#
# The prose log says what was attempted; it cannot say what was already there.
# "dnf install -y kitty" appears identically whether kitty arrived with this
# run or three months ago, and removing what the machine already had is the one
# mistake an uninstaller must not make. So every change that is ours to reverse
# is also appended here as a tab-separated line, and uninstall.sh replays it
# backwards. Anything not in this file is left alone.
#
#   file <path>            a file or directory this run put there
#   pkg <name>             an rpm that was absent before this run installed it
#   flatpak <id>           a flatpak this run installed
#   copr <owner/project>   a community source this run enabled
#   repofile <path>        a .repo file this run added
#   unit-user <unit>       a user service this run enabled
#   unit-system <unit>     a system service this run enabled
#   symlink <path>         a link this run created
#   edited <path>          an existing file this run modified in place
#   moved <from> <to>      a file this run renamed out of the way
#   shell <user> <before>  the login shell as it was before chsh
#   target <before>        the systemd default target as it was before
#   backup <dir>           where the originals of edited files were copied
MANIFEST_FILE=${MANIFEST_FILE:-}

record() {
  [[ -n $MANIFEST_FILE ]] || return 0
  (( DRY_RUN )) && return 0
  local kind=$1; shift
  printf '%s\t%s\n' "$kind" "$(IFS=$'\t'; printf '%s' "$*")" >>"$MANIFEST_FILE"
  return 0
}

# Record only the rpms that are not already on the machine, before installing
# them. Called with the same list that is about to be handed to dnf.
record_new_pkgs() {
  local p
  for p in "$@"; do
    [[ $p == -* ]] && continue
    rpm_has "$p" || record pkg "$p"
  done
  return 0
}

# Record an rpm file's package name, for the ones fetched from GitHub.
record_rpm_file() {
  local f=$1 name
  name=$(rpm -qp --qf '%{NAME}' "$f" 2>/dev/null) || return 0
  [[ -n $name ]] && ! rpm_has "$name" && record pkg "$name"
  return 0
}

# --------------------------------------------------------------- backups ---
# Anything the installer is about to clobber is moved here first, preserving
# the path relative to $HOME so a restore is a plain `cp -a` back.
BACKUP_DIR=""
backup_path() {
  local target=$1
  [[ -e $target || -L $target ]] || return 0
  (( NO_BACKUP )) && return 0
  if [[ -z $BACKUP_DIR ]]; then
    BACKUP_DIR="$HOME/.fedora-nothing-backup/$(date +%Y%m%d-%H%M%S)"
    run mkdir -p "$BACKUP_DIR"
    record backup "$BACKUP_DIR"
    info "Anything replaced is being copied to ${BACKUP_DIR/#$HOME/\~} first"
  fi
  local rel=${target#"$HOME"/}
  run mkdir -p "$BACKUP_DIR/$(dirname "$rel")"
  run cp -a "$target" "$BACKUP_DIR/$rel"
  record edited "$target"
}

# ------------------------------------------------------------ templating ---
# Placeholders resolved at deploy time. Set by stages before deploy_tree runs.
: "${TPL_HOME:=$HOME}"
: "${TPL_USER:=$USER}"
: "${TPL_MONITOR:=}"
: "${TPL_ZEN_PROFILE:=}"
: "${TPL_TERMINAL:=foot}"
: "${TPL_ALT_TERMINAL:=$TPL_TERMINAL}"
: "${TPL_BROWSER:=zen}"
: "${TPL_BROWSER_DESKTOP:=app.zen_browser.zen.desktop}"
: "${TPL_BROWSER_PRIVATE:=--private-window}"
: "${TPL_OBSIDIAN_VAULT:=$HOME/Documents/Obsidian}"

# Rewrite @@PLACEHOLDER@@ in a text file, in place.
apply_template() {
  local f=$1
  run sed -i \
    -e "s|@@HOME@@|$TPL_HOME|g" \
    -e "s|@@USER@@|$TPL_USER|g" \
    -e "s|@@MONITOR@@|$TPL_MONITOR|g" \
    -e "s|@@ALT_TERMINAL@@|$TPL_ALT_TERMINAL|g" \
    -e "s|@@TERMINAL@@|$TPL_TERMINAL|g" \
    -e "s|@@BROWSER_DESKTOP@@|$TPL_BROWSER_DESKTOP|g" \
    -e "s|@@BROWSER_PRIVATE@@|$TPL_BROWSER_PRIVATE|g" \
    -e "s|@@BROWSER@@|$TPL_BROWSER|g" \
    -e "s|@@ZEN_PROFILE@@|$TPL_ZEN_PROFILE|g" \
    -e "s|@@OBSIDIAN_VAULT@@|$TPL_OBSIDIAN_VAULT|g" \
    "$f"
}

# The command, launcher entry and private-window flag of each browser
# component, for the @@BROWSER*@@ placeholders, mimeapps and xdg-settings.
set_browser_templates() {
  case $1 in
    zen)          TPL_BROWSER=zen                 TPL_BROWSER_DESKTOP=app.zen_browser.zen.desktop ;;
    firefox)      TPL_BROWSER=firefox             TPL_BROWSER_DESKTOP=org.mozilla.firefox.desktop ;;
    librewolf)    TPL_BROWSER=librewolf           TPL_BROWSER_DESKTOP=librewolf.desktop ;;
    brave)        TPL_BROWSER=brave-browser       TPL_BROWSER_DESKTOP=brave-browser.desktop ;;
    brave_origin) TPL_BROWSER=brave-origin-stable TPL_BROWSER_DESKTOP=brave-origin.desktop ;;
    vivaldi)      TPL_BROWSER=vivaldi-stable      TPL_BROWSER_DESKTOP=vivaldi-stable.desktop ;;
    helium)       TPL_BROWSER=helium              TPL_BROWSER_DESKTOP=helium.desktop ;;
    *)            return 1 ;;
  esac
  case $1 in
    zen|firefox|librewolf) TPL_BROWSER_PRIVATE=--private-window ;;
    *)                     TPL_BROWSER_PRIVATE=--incognito ;;
  esac
}

# Strip lines tagged `-- @component:<name>` (or `# @component:<name>`) whose
# component was not selected. This is how keybinds and config entries for
# deselected apps disappear without a second copy of the file.
strip_unselected() {
  local f=$1 comp
  local -a drop=()
  while read -r comp; do
    [[ -z $comp ]] && continue
    is_selected "$comp" || drop+=("$comp")
  done < <(grep -oP '(?<=@component:)[a-zA-Z0-9_-]+' "$f" 2>/dev/null | sort -u)
  (( ${#drop[@]} == 0 )) && return 0
  local c
  for c in "${drop[@]}"; do
    run sed -i "/@component:${c}\$/d" "$f"
  done
}

# deploy_file <src> <dest> [mode]
deploy_file() {
  local src=$1 dest=$2 mode=${3:-}
  [[ -e $src ]] || { warn "missing source: $src"; return 1; }
  backup_path "$dest"
  run mkdir -p "$(dirname "$dest")"
  run cp -aL "$src" "$dest"
  if file "$src" 2>/dev/null | grep -q text; then
    apply_template "$dest"
    strip_unselected "$dest"
  fi
  [[ -n $mode ]] && run chmod "$mode" "$dest"
  record file "$dest"
  return 0
}

# deploy_seed <src> <dest> — like deploy_file, but only when dest is absent.
#
# For files this repository ships once and the desktop shell owns thereafter:
# the kitty palette, the GTK and Qt colour files, the KDE colour schemes. They
# have to exist, because kitty's config includes them and Qt reads them at
# startup, but copying the captured copy over the generated one on every run is
# how a re-install used to reset every open window to the palette of whichever
# machine this repository was captured from.
deploy_seed() {
  local src=$1 dest=$2 mode=${3:-}
  if [[ -e $dest ]]; then
    return 0
  fi
  deploy_file "$src" "$dest" ${mode:+"$mode"}
}

# deploy_tree <srcdir> <destdir> — mirrors a directory, templating text files.
# A `seed/` directory inside a tree is never copied as a directory. Its
# contents are files the desktop shell regenerates, deployed individually with
# deploy_seed so an existing one is left alone.
deploy_tree() {
  local src=$1 dest=$2
  [[ -d $src ]] || { warn "missing source tree: $src"; return 1; }
  backup_path "$dest"
  run mkdir -p "$dest"
  run cp -aL "$src/." "$dest/"
  # Copied wholesale, then removed: cp has no exclude, and a Fedora Custom
  # install cannot be assumed to have anything that does.
  if [[ -d $src/seed ]]; then run rm -rf "$dest/seed"; fi
  record file "$dest"
  (( DRY_RUN )) && return 0
  local f
  while IFS= read -r -d '' f; do
    grep -qI . "$f" 2>/dev/null || continue     # skip binaries
    apply_template "$f"
    strip_unselected "$f"
  done < <(find "$dest" -type f -print0)
}

# ------------------------------------------------------------------ misc ---
# Set a key in an ini-style file without a full parser, creating it if absent.
ini_set() {
  local file=$1 section=$2 key=$3 value=$4
  run mkdir -p "$(dirname "$file")"
  if [[ -e $file ]]; then record edited "$file"; else record file "$file"; fi
  (( DRY_RUN )) && { _log_raw "DRY   ini [$section] $key=$value -> $file"; return 0; }
  python3 - "$file" "$section" "$key" "$value" <<'PY'
import sys, os, re
path, section, key, value = sys.argv[1:5]
lines = open(path).read().split('\n') if os.path.exists(path) else []
out, in_sec, done, seen_sec = [], False, False, False
for ln in lines:
    m = re.match(r'^\s*\[(.+)\]\s*$', ln)
    if m:
        if in_sec and not done:
            out.append(f'{key}={value}'); done = True
        in_sec = (m.group(1) == section)
        seen_sec = seen_sec or in_sec
    elif in_sec and re.match(rf'^\s*{re.escape(key)}\s*=', ln):
        ln = f'{key}={value}'; done = True
    out.append(ln)
if not seen_sec:
    if out and out[-1].strip(): out.append('')
    out += [f'[{section}]', f'{key}={value}']
elif not done:
    out.append(f'{key}={value}')
open(path, 'w').write('\n'.join(out).rstrip('\n') + '\n')
PY
}

# merge_policy <policies.json> <json> — deep-merge a fragment into a browser's
# enterprise policy file, as root. Several stages share one file per browser,
# so copying over it would drop what another stage put there.
merge_policy() {
  local file=$1 fragment=$2 merged
  (( DRY_RUN )) && { _log_raw "DRY   merge policy into $file"; return 0; }
  merged=$(cat "$file" 2>/dev/null | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except ValueError:
    data = {}
def merge(a, b):
    for k, v in b.items():
        a[k] = merge(a[k], v) if isinstance(v, dict) and isinstance(a.get(k), dict) else v
    return a
print(json.dumps(merge(data, json.loads(sys.argv[1])), indent=2, ensure_ascii=False))
' "$fragment") || return 1
  as_root mkdir -p "$(dirname "$file")"
  printf '%s\n' "$merged" | as_root tee "$file" >/dev/null
}

# Edit a JSON file with a python lambda over the parsed object.
json_edit() {
  local file=$1 script=$2
  (( DRY_RUN )) && { _log_raw "DRY   json edit $file"; return 0; }
  python3 - "$file" "$script" <<'PY'
import sys, json
path, script = sys.argv[1], sys.argv[2]
with open(path) as fh: data = json.load(fh)
exec(script, {'data': data, 'json': json})
with open(path, 'w') as fh: json.dump(data, fh, indent=2, ensure_ascii=False); fh.write('\n')
PY
}
