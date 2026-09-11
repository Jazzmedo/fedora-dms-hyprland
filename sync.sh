#!/usr/bin/env bash
# Pull live configuration changes back into this repo, re-templating the paths
# that are machine-specific so the result stays portable.
#
#   ./sync.sh            show what differs between $HOME and the repo
#   ./sync.sh capture    copy $HOME -> repo
#   ./sync.sh deploy     copy repo -> $HOME (runs install.sh for those stages)
#
# Deployment deliberately goes through install.sh: templating, component
# filtering and backups all live there, and duplicating them here would drift.

set -euo pipefail
REPO_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$REPO_DIR/lib/common.sh"

MANIFEST="$REPO_DIR/config/manifest.tsv"
DRY_RUN=0 NO_BACKUP=1
ACTION=${1:-status}

# Build files must never come back: matugen rewrites them on every theme change.
EXCLUDES=(
  --exclude='.git' --exclude='*.bak' --exclude='*.before-*'
  --exclude='__pycache__' --exclude='.firstlaunch' --exclude='.changelog-*'
  --exclude='plugins/' --exclude='generated/' --exclude='.dms-backups/'
  --exclude='lazy-lock.json.bak' --exclude='*.log'
  --exclude='*.backup[0-9]*' --exclude='*.save' --exclude='*.orig'
)

# Undo everything install.sh's templating did, so the repo copy stays portable.
untemplate() {
  local f=$1
  sed -i \
    -e "s|$HOME|@@HOME@@|g" \
    -e "s|\\b$USER\\b|@@USER@@|g" \
    "$f"
}

each_entry() {
  local repo home comp
  while IFS=$'\t' read -r repo home comp; do
    [[ -z $repo || $repo == \#* ]] && continue
    printf '%s\t%s\t%s\n' "$repo" "$home" "$comp"
  done < "$MANIFEST"
}

cmd_status() {
  step "Differences ($HOME vs repo)"
  local repo home comp n=0
  while IFS=$'\t' read -r repo home comp; do
    local src="$HOME/$home" dst="$REPO_DIR/$repo"
    [[ -e $src ]] || { skip "$home (not on this machine)"; continue; }
    local out
    out=$(rsync -rin --delete "${EXCLUDES[@]}" "$src/" "$dst/" 2>/dev/null || true)
    if [[ -d $src ]]; then
      [[ -n $out ]] && { printf '  %s%s%s\n' "$C_BOLD" "$home" "$C_OFF"
                         printf '      %s\n' $(awk '{print $2}' <<<"$out" | head -8)
                         n=$(( n + $(wc -l <<<"$out") )); }
    else
      cmp -s "$src" "$dst" || { printf '  %s%s%s  differs\n' "$C_BOLD" "$home" "$C_OFF"; (( ++n )); }
    fi
  done < <(each_entry)
  (( n == 0 )) && ok "repo matches this machine" || info "$n path(s) differ"
}

cmd_capture() {
  step "Capturing \$HOME into the repo"
  local repo home comp
  while IFS=$'\t' read -r repo home comp; do
    local src="$HOME/$home" dst="$REPO_DIR/$repo"
    [[ -e $src ]] || { skip "$home (not on this machine)"; continue; }
    if [[ -d $src ]]; then
      mkdir -p "$dst"
      rsync -a --delete "${EXCLUDES[@]}" "$src/" "$dst/"
    else
      mkdir -p "$(dirname "$dst")"
      cp -a "$src" "$dst"
    fi
    ok "$home"
  done < <(each_entry)

  step "Re-templating machine-specific paths"
  local f n=0
  while IFS= read -r -d '' f; do
    grep -qI . "$f" 2>/dev/null || continue
    grep -q "$HOME" "$f" 2>/dev/null || continue
    untemplate "$f"; (( ++n ))
  done < <(find "$REPO_DIR/config" -type f -print0)
  ok "$n file(s) re-templated"

  warn "review 'git diff' before committing: captured files can contain"
  warn "account names, recent-file lists and tokens."
}

cmd_deploy() {
  exec "$REPO_DIR/install.sh" --only=hyprland,dms,themes,apps,shell "${@:2}"
}

case $ACTION in
  status)  cmd_status ;;
  capture) cmd_capture ;;
  deploy)  cmd_deploy "$@" ;;
  *)       die "usage: $0 {status|capture|deploy}" ;;
esac
