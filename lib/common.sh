# shellcheck shell=bash
# Logging, command execution, backup and templating primitives.
# Sourced by install.sh and every stage. Assumes `set -euo pipefail`.

# ---------------------------------------------------------------- colours ---
if [[ -t 1 && ${NO_COLOR:-} == "" ]]; then
  C_RED=$'\e[38;2;215;25;33m'; C_DIM=$'\e[2m'; C_BOLD=$'\e[1m'
  C_GREY=$'\e[38;5;245m';      C_OK=$'\e[38;5;114m'; C_WARN=$'\e[38;5;179m'
  C_OFF=$'\e[0m';              C_INV=$'\e[7m'
else
  C_RED=""; C_DIM=""; C_BOLD=""; C_GREY=""; C_OK=""; C_WARN=""; C_OFF=""; C_INV=""
fi

LOG_FILE=${LOG_FILE:-}

_stamp() { date '+%H:%M:%S'; }

_log_raw() {
  [[ -n $LOG_FILE ]] && printf '%s %s\n' "$(date '+%F %T')" "$*" >>"$LOG_FILE"
  return 0
}

step()  { printf '\n%s▌ %s%s\n' "$C_RED$C_BOLD" "$*" "$C_OFF";     _log_raw "STEP  $*"; }
info()  { printf '  %s·%s %s\n'  "$C_GREY" "$C_OFF" "$*";           _log_raw "INFO  $*"; }
ok()    { printf '  %s✓%s %s\n'  "$C_OK"   "$C_OFF" "$*";           _log_raw "OK    $*"; }
skip()  { printf '  %s·%s %s%s%s\n' "$C_GREY" "$C_OFF" "$C_DIM" "$*" "$C_OFF"; _log_raw "SKIP  $*"; }
warn()  { printf '  %s!%s %s\n'  "$C_WARN" "$C_OFF" "$*" >&2;       _log_raw "WARN  $*"; }
die()   { printf '\n%s✘ %s%s\n\n' "$C_RED$C_BOLD" "$*" "$C_OFF" >&2; _log_raw "FATAL $*"; exit 1; }

# A stage failure that must not abort the whole install.
soft_fail() { warn "$*"; SOFT_FAILURES+=("$*"); }
SOFT_FAILURES=()

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

# Same, but the output is meant for the user to watch (dnf, git clone).
run_visible() {
  if (( DRY_RUN )); then
    printf '  %s$ %s%s\n' "$C_DIM" "$*" "$C_OFF"
    _log_raw "DRY   $*"
    return 0
  fi
  _log_raw "RUN   $*"
  "$@"
}

as_root() { run_visible sudo "$@"; }

# retry <attempts> <cmd...> — for network-bound commands.
retry() {
  local attempts=$1; shift
  local n=1
  until run_visible "$@"; do
    (( n++ >= attempts )) && return 1
    warn "failed, retrying ($n/$attempts): $1"
    sleep $(( n * 2 ))
  done
}

have()      { command -v "$1" >/dev/null 2>&1; }
rpm_has()   { rpm -q "$1" >/dev/null 2>&1; }

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
    info "backing up replaced files to ${BACKUP_DIR/#$HOME/\~}"
  fi
  local rel=${target#"$HOME"/}
  run mkdir -p "$BACKUP_DIR/$(dirname "$rel")"
  run cp -a "$target" "$BACKUP_DIR/$rel"
}

# ------------------------------------------------------------ templating ---
# Placeholders resolved at deploy time. Set by stages before deploy_tree runs.
: "${TPL_HOME:=$HOME}"
: "${TPL_USER:=$USER}"
: "${TPL_MONITOR:=}"
: "${TPL_ZEN_PROFILE:=}"
: "${TPL_OBSIDIAN_VAULT:=$HOME/Documents/Obsidian}"

# Rewrite @@PLACEHOLDER@@ in a text file, in place.
apply_template() {
  local f=$1
  run sed -i \
    -e "s|@@HOME@@|$TPL_HOME|g" \
    -e "s|@@USER@@|$TPL_USER|g" \
    -e "s|@@MONITOR@@|$TPL_MONITOR|g" \
    -e "s|@@ZEN_PROFILE@@|$TPL_ZEN_PROFILE|g" \
    -e "s|@@OBSIDIAN_VAULT@@|$TPL_OBSIDIAN_VAULT|g" \
    "$f"
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
  return 0
}

# deploy_tree <srcdir> <destdir> — mirrors a directory, templating text files.
deploy_tree() {
  local src=$1 dest=$2
  [[ -d $src ]] || { warn "missing source tree: $src"; return 1; }
  backup_path "$dest"
  run mkdir -p "$dest"
  run cp -aL "$src/." "$dest/"
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
  (( DRY_RUN )) && { info "ini: [$section] $key=$value -> $file"; return 0; }
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

# Edit a JSON file with a python lambda over the parsed object.
json_edit() {
  local file=$1 script=$2
  (( DRY_RUN )) && { info "json: edit $file"; return 0; }
  python3 - "$file" "$script" <<'PY'
import sys, json
path, script = sys.argv[1], sys.argv[2]
with open(path) as fh: data = json.load(fh)
exec(script, {'data': data, 'json': json})
with open(path, 'w') as fh: json.dump(data, fh, indent=2, ensure_ascii=False); fh.write('\n')
PY
}
