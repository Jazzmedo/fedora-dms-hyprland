# shellcheck shell=bash
# Back up and restore the data of the AI coding agents on this machine — Claude
# Code, Codex, OpenCode and ZCode — the way lib/browser-profiles.sh does for
# browsers. Used by agent-backup.sh.
#
# Three kinds of data travel, chosen on screen:
#
#   chats     conversations, prompts, session logs and project history
#   settings  config files, skills, rules, plugins, model and UI preferences
#   auth      the sign-in tokens and credentials that keep you logged in
#
# Auth is what can sign you in, so it forces encryption on, exactly as cookies
# and certificates do for a browser. Each agent's three lists are written in a
# fixed order — chats, then settings, then auth — so the archive's file list
# (fedora-nothing/files.tsv) and the manifest read the same way on every backup.
#
# An archive is a tar of home-relative paths, zstd-compressed and, when asked,
# GPG-encrypted. A small fedora-nothing/ directory inside records the paths it
# holds and the home directory they came from, so a restore can put back only
# the kinds you ticked and can follow a home that moved.

AP_AGENTS=(claude codex opencode zcode)
AP_BACKUP_ROOT="$HOME/fedora-nothing-backups"
AP_PASS=""          # the backup passphrase, held in memory only

ap_name() {
  case $1 in
    claude)   echo "Claude Code" ;;
    codex)    echo "Codex" ;;
    opencode) echo "OpenCode" ;;
    zcode)    echo "ZCode" ;;
  esac
}

ap_cmd() {
  case $1 in
    claude)   echo claude ;;
    codex)    echo codex ;;
    opencode) echo opencode ;;
    zcode)    echo zcode ;;
  esac
}

# Where the agent keeps its data. These are only ever read here, never created:
# the backup lists whatever already exists and leaves the rest alone.
ap_roots() {
  case $1 in
    claude)   printf '%s\n' "$HOME/.claude" "$HOME/.claude.json" ;;
    codex)    printf '%s\n' "$HOME/.codex" ;;
    opencode) printf '%s\n' "$HOME/.config/opencode" "$HOME/.local/share/opencode" \
                             "$HOME/.local/state/opencode" ;;
    zcode)    printf '%s\n' "$HOME/.zcode" ;;
  esac
}

# The folder to show for an agent: its main one, where the others are read
# from. Printed on its own so callers never reach for `head`.
ap_root() {
  case $1 in
    claude)   echo "$HOME/.claude" ;;
    codex)    echo "$HOME/.codex" ;;
    opencode) echo "$HOME/.config/opencode" ;;
    zcode)    echo "$HOME/.zcode" ;;
  esac
}

# Something of this agent's is on the machine, even if its command is not on
# the PATH (a data folder left behind, or a new install that has not run yet).
ap_present() {
  local d
  while IFS= read -r d; do [[ -e $d || -L $d ]] && return 0; done < <(ap_roots "$1")
  return 1
}

ap_installed() { have "$(ap_cmd "$1")" || ap_present "$1"; }

# The paths that make up one kind of an agent's data, in the order they are
# stored. Home-relative, one per line. Extending an agent is a matter of adding
# a line here: backup picks it up, and restore knows which kind it belongs to.
ap_paths() {
  case $1:$2 in
    claude:chats)
      printf '%s\n' \
        '.claude/projects' \
        '.claude/history.jsonl' \
        '.claude/plans' ;;
    claude:settings)
      printf '%s\n' \
        '.claude.json' \
        '.claude/settings.json' \
        '.claude/CLAUDE.md' \
        '.claude/statusline-command.sh' \
        '.claude/skills' \
        '.claude/backups' ;;
    claude:auth)
      printf '%s\n' '.claude/.credentials.json' ;;

    codex:chats)
      printf '%s\n' \
        '.codex/sessions' \
        '.codex/archived_sessions' \
        '.codex/history.jsonl' \
        '.codex/thread_history_1.sqlite' ;;
    codex:settings)
      printf '%s\n' \
        '.codex/config.toml' \
        '.codex/skills' \
        '.codex/rules' \
        '.codex/.codex-global-state.json' \
        '.codex/.codex-global-state.json.bak' \
        '.codex/session_index.jsonl' \
        '.codex/state_5.sqlite' ;;
    codex:auth)
      printf '%s\n' '.codex/auth.json' ;;

    opencode:chats)
      printf '%s\n' \
        '.local/share/opencode/opencode.db' \
        '.local/share/opencode/storage' \
        '.local/state/opencode/prompt-history.jsonl' ;;
    opencode:settings)
      printf '%s\n' \
        '.config/opencode/bun.lock' \
        '.config/opencode/package.json' \
        '.config/opencode/package-lock.json' \
        '.config/opencode/.gitignore' \
        '.local/share/opencode/repos' \
        '.local/state/opencode/model.json' \
        '.local/state/opencode/kv.json' \
        '.local/state/opencode/frecency.jsonl' ;;
    opencode:auth)
      printf '%s\n' '.local/share/opencode/auth.json' ;;

    zcode:chats)
      printf '%s\n' \
        '.zcode/cli/db' \
        '.zcode/cli/agents' \
        '.zcode/cli/artifacts' \
        '.zcode/cli/rollout' \
        '.zcode/cli/exec' \
        '.zcode/v2/tasks-index.sqlite' ;;
    zcode:settings)
      printf '%s\n' \
        '.zcode/AGENTS.md' \
        '.zcode/skills' \
        '.zcode/cli/memories' \
        '.zcode/cli/plugins/data' \
        '.zcode/cli/plugins/known_marketplaces.json' \
        '.zcode/v2/setting.json' \
        '.zcode/v2/provider_config.json' \
        '.zcode/v2/bot-config.v3.json' \
        '.zcode/v2/bot-state.v3.json' \
        '.zcode/v2/onboarding-record.json' ;;
    zcode:auth)
      printf '%s\n' \
        '.zcode/v2/credentials.json' \
        '.zcode/v2/certs' ;;
  esac
}

# Which kind a stored path belongs to, empty when this script does not know it.
ap_path_category() {
  local k=$1 p=$2 c
  for c in chats settings auth; do
    if ap_paths "$k" "$c" | grep -Fxq -- "$p"; then printf '%s' "$c"; return 0; fi
  done
  return 1
}

# The paths that exist and whose kind was ticked, in chats/settings/auth order.
ap_selected_paths() {
  local k=$1 items=$2 c p
  for c in chats settings auth; do
    [[ ,$items, == *,$c,* ]] || continue
    while IFS= read -r p; do
      [[ -n $p ]] || continue
      [[ -e $HOME/$p || -L $HOME/$p ]] && printf '%s\n' "$p"
    done < <(ap_paths "$k" "$c")
  done
  return 0
}

# Copy-pasteable install command for this distro's package manager.
ap_install_hint() {
  local c pkgs=() pm
  for pm in dnf apt-get pacman zypper; do have "$pm" && break; done
  for c in "$@"; do
    case $pm:$c in
      dnf:gpg)    pkgs+=(gnupg2) ;;
      zypper:gpg) pkgs+=(gpg2) ;;
      *:gpg)      pkgs+=(gnupg) ;;
      *)          pkgs+=("$c") ;;
    esac
  done
  case $pm in
    pacman) echo "sudo pacman -S ${pkgs[*]}" ;;
    *)      echo "sudo $pm install ${pkgs[*]}" ;;
  esac
}

# ------------------------------------------------------------- encryption ---
ap_ask_passphrase() {   # $1 = confirm (ask twice)
  local again
  while :; do
    read -rsp "  Passphrase: " AP_PASS; printf '\n'
    [[ -n $AP_PASS ]] || { warn "The passphrase cannot be empty"; continue; }
    [[ ${1:-} == confirm ]] || return 0
    read -rsp "  Same passphrase again: " again; printf '\n'
    [[ $AP_PASS == "$again" ]] && return 0
    warn "The two did not match. Try again."
  done
}

ap_encrypt() {   # stdin -> $1
  gpg --batch --yes --quiet --pinentry-mode loopback --passphrase-fd 3 \
      --symmetric --cipher-algo AES256 -o "$1" 3<<<"$AP_PASS"
}

ap_decrypt() {   # $1 -> stdout
  gpg --batch --quiet --pinentry-mode loopback --passphrase-fd 3 --decrypt "$1" 3<<<"$AP_PASS"
}

ap_unpack() {   # archive dest-dir
  if [[ $1 == *.gpg ]]; then
    ap_decrypt "$1" | zstd -q -d | tar -xf - -C "$2"
  else
    zstd -q -d -c "$1" | tar -xf - -C "$2"
  fi
}

# ------------------------------------------------------------------ backup ---
# Writes $dest/<key>.tar.zst (or .tar.zst.gpg) and appends to the manifest.
# $3 is a comma-separated list: chats, settings, auth.
ap_backup_one() {
  local key=$1 dest=$2 items=$3 tmp meta out
  tmp=$(mktemp -d)
  meta="$tmp/fedora-nothing"
  mkdir -p "$meta"

  local -a files=()
  local p
  while IFS= read -r p; do files+=("$p"); done < <(ap_selected_paths "$key" "$items")
  if (( ${#files[@]} == 0 )); then
    rm -rf "$tmp"
    warn "$(ap_name "$key") has nothing to back up yet"
    return 0
  fi

  # What was stored, and the home it came from, so a restore can filter by kind
  # and follow a home that moved.
  printf '%s\n' "${files[@]}" > "$meta/files.tsv"
  printf '%s' "$HOME" > "$meta/home"

  out="$dest/$key.tar.zst"
  if [[ -n $AP_PASS ]]; then
    out+=.gpg
    tar -cf - -C "$HOME" "${files[@]}" -C "$tmp" fedora-nothing \
      | zstd -q -T0 -10 | ap_encrypt "$out"
  else
    tar -cf - -C "$HOME" "${files[@]}" -C "$tmp" fedora-nothing \
      | zstd -q -f -T0 -10 -o "$out"
  fi
  printf 'agent\t%s\t%s\t%s\n' "$key" "$items" "${#files[@]}" >> "$dest/manifest.txt"
  rm -rf "$tmp"
  ok "$(ap_name "$key"): ${#files[@]} item(s), $(du -h "$out" | cut -f1)"
}

# ----------------------------------------------------------------- restore ---
ap_manifest_agents() { awk -F'\t' '$1 == "agent" {print $2}' "$1/manifest.txt"; }
ap_manifest_items()  { awk -F'\t' -v k="$2" '$1 == "agent" && $2 == k {print $3}' "$1/manifest.txt"; }
ap_manifest_count()  { awk -F'\t' -v k="$2" '$1 == "agent" && $2 == k {print $4}' "$1/manifest.txt"; }
ap_is_encrypted()    { compgen -G "$1/*.gpg" >/dev/null; }
ap_is_agent_backup() { [[ -f $1/manifest.txt ]] && grep -q "$(printf '^agent\t')" "$1/manifest.txt"; }

# The agent's own archive; there is no cross-agent restore, unlike browsers,
# whose extension data is interchangeable within an engine family.
ap_source_for() {
  local dir=$1 target=$2 k
  for k in $(ap_manifest_agents "$dir"); do
    [[ $k == "$target" ]] && { echo "$k"; return 0; }
  done
  return 1
}

# Restore $source's backup into this machine. $4: the kinds to restore.
ap_restore_one() {
  local dir=$1 key=$2 items=$3 archive tmp meta
  archive="$dir/$key.tar.zst"
  [[ -f $archive ]] || archive+=.gpg
  local name; name=$(ap_name "$key")
  [[ -f $archive ]] || { soft_fail "No $name backup in ${dir/#$HOME/\~}"; return 0; }

  tmp=$(mktemp -d)
  if ! ap_unpack "$archive" "$tmp" 2>/dev/null; then
    rm -rf "$tmp"
    soft_fail "Could not open the $name backup" \
              "The passphrase is wrong or the file is damaged." "./agent-backup.sh"
    return 0
  fi
  meta="$tmp/fedora-nothing"
  if [[ -d $meta ]]; then mv "$meta" "$tmp.meta"; meta="$tmp.meta"; else meta=""; fi

  # Which stored paths to put back: those whose kind was ticked. A path this
  # script does not recognise is restored rather than dropped, so a backup made
  # by a later version is never silently emptied.
  local -a paths=()
  local p cat
  if [[ -n $meta && -f $meta/files.tsv ]]; then
    while IFS= read -r p; do
      [[ -n $p ]] || continue
      cat=$(ap_path_category "$key" "$p") || cat=""
      if [[ -z $cat || ,$items, == *,$cat,* ]]; then paths+=("$p"); fi
    done < "$meta/files.tsv"
  else
    while IFS= read -r p; do paths+=("$p"); done \
      < <(cd "$tmp" && find . -mindepth 1 -maxdepth 1 -printf '%P\n' 2>/dev/null)
  fi

  # Anything this is about to replace goes to ~/.fedora-nothing-backup first,
  # then is removed so the restored copy replaces it instead of mixing with it.
  local n=0
  for p in "${paths[@]}"; do
    [[ -e $tmp/$p || -L $tmp/$p ]] || continue
    if [[ -e $HOME/$p || -L $HOME/$p ]]; then
      backup_path "$HOME/$p"
      rm -rf "${HOME:?}/$p"
    fi
    mkdir -p "$HOME/$(dirname "$p")"
    cp -a "$tmp/$p" "$HOME/$p"
    # A database restored next to the write-ahead log of the one it replaced
    # is a corrupt database waiting to be read. The log files are transient and
    # never stored in a backup, so drop whatever the running agent left behind.
    case $p in
      *.db|*.sqlite|*.sqlite3) rm -f "$HOME/$p"-wal "$HOME/$p"-shm "$HOME/$p"-journal ;;
    esac
    (( ++n )) || true
  done

  # A home that moved: point the plain-text settings at the new one. Only the
  # files the backup lists are rewritten one by one; chat logs keep the paths
  # they recorded, and directories (skills, plugin data) are left alone.
  if [[ -n $meta && -f $meta/home ]]; then
    local old; old=$(<"$meta/home")
    if [[ -n $old && $old != "$HOME" ]]; then
      for p in "${paths[@]}"; do
        [[ -f $HOME/$p ]] || continue
        grep -qI . "$HOME/$p" 2>/dev/null || continue
        sed -i "s|$old/|$HOME/|g" "$HOME/$p" 2>/dev/null || true
      done
      info "$name: updated the paths that pointed at the old home"
    fi
  fi

  rm -rf "$tmp" "$meta"
  ok "$name: $n item(s) restored"
}

# A numbered list of the agent backups in ~/fedora-nothing-backups, newest
# first, plus a typed path. Prints the chosen folder.
ap_pick_backup() {
  local dirs=() d i reply
  if [[ -d $AP_BACKUP_ROOT ]]; then
    while IFS= read -r d; do
      ap_is_agent_backup "$d" && dirs+=("$d")
    done < <(ls -1dt "$AP_BACKUP_ROOT"/*/ 2>/dev/null | sed 's:/$::')
  fi
  {
    printf '  %sBackups%s\n' "$C_BOLD" "$C_OFF"
    for i in "${!dirs[@]}"; do
      printf '    %d) %s  %s%s%s\n' $(( i + 1 )) "${dirs[i]/#$HOME/\~}" "$C_GREY" \
        "$(ap_manifest_agents "${dirs[i]}" | while read -r d; do printf '%s ' "$(ap_name "$d")"; done)" "$C_OFF"
    done
    printf '    o) Another folder, such as a USB drive\n'
  } >&2
  while :; do
    read -rp "  Choose [1]: " reply
    [[ -z $reply && ${#dirs[@]} -gt 0 ]] && reply=1
    if [[ $reply == [oO] || ${#dirs[@]} -eq 0 && -z $reply ]]; then
      read -rep "  Folder: " d
      d=${d/#\~/$HOME}
    elif [[ $reply =~ ^[0-9]+$ ]] && (( reply >= 1 && reply <= ${#dirs[@]} )); then
      d=${dirs[reply - 1]}
    else
      continue
    fi
    ap_is_agent_backup "$d" && { printf '%s' "$d"; return 0; }
    warn "No agent backup in ${d/#$HOME/\~} (it has no manifest.txt)"
  done
}
