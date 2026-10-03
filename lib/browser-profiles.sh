# shellcheck shell=bash
# Back up and restore browser extensions, plus cookies and certificates when
# asked. Used by browser-backup.sh and by the installer's apps stage.
#
# Only extensions and their data travel, never history, site data or saved
# passwords: a whole Zen profile is gigabytes of website caches, while its
# extensions are a tenth of that.
#
# Gecko (Zen, Firefox, LibreWolf) names each extension's storage folder after
# a random per-profile UUID, so the extensions.webextensions.uuids pref travels
# with the data and is replayed through user.js. Chromium signs its extension
# registry per machine and disables copied extensions as tampered, so only
# their data is copied and the extensions themselves are reinstalled from the
# Web Store through policy. The data is keyed by extension ID, so it lines up.

BP_BROWSERS=(zen firefox librewolf brave brave_origin vivaldi helium)
BP_BACKUP_ROOT="$HOME/fedora-nothing-backups"
BP_SAFE_SCHEMA=chrome_libsecret_os_crypt_password_v2
BP_PASS=""          # the backup passphrase, held in memory only

bp_engine() { case $1 in zen|firefox|librewolf) echo gecko ;; *) echo chromium ;; esac; }

bp_name() {
  case $1 in
    zen) echo Zen ;; firefox) echo Firefox ;; librewolf) echo LibreWolf ;;
    brave) echo Brave ;; brave_origin) echo "Brave Origin" ;;
    vivaldi) echo Vivaldi ;; helium) echo Helium ;;
  esac
}

bp_cmd() {
  case $1 in
    zen) echo zen ;; firefox) echo firefox ;; librewolf) echo librewolf ;;
    brave) echo brave-browser ;; brave_origin) echo brave-origin-stable ;;
    vivaldi) echo vivaldi-stable ;; helium) echo helium ;;
  esac
}

bp_installed() { have "$(bp_cmd "$1")"; }

# Chromium keeps its cookie key in the keyring under the browser's own name;
# Brave Origin shares Brave's, and Helium uses Chromium's.
bp_safe_apps() {
  case $1 in
    brave|brave_origin) echo brave ;;
    vivaldi)            echo vivaldi ;;
    helium)             echo "chromium helium" ;;
  esac
}

bp_policy_dir() {
  case $1 in
    brave|brave_origin) echo /etc/brave/policies/managed ;;
    vivaldi)            echo /etc/opt/vivaldi/policies/managed ;;
    helium)             echo /etc/helium/policies/managed ;;
  esac
}

# Where the browser keeps its profiles. Zen uses ~/.config/zen or, when run
# from its tarball, ~/.zen. Either is only read here, never created: Zen opens
# an empty profile when ~/.zen appears next to a real one.
bp_root() {
  local d
  case $1 in
    zen)
      for d in "$HOME/.config/zen" "$HOME/.zen"; do
        [[ -f $d/profiles.ini ]] && { echo "$d"; return; }
      done
      echo "$HOME/.config/zen" ;;
    firefox)
      for d in "$HOME/.config/mozilla/firefox" "$HOME/.mozilla/firefox"; do
        [[ -f $d/profiles.ini ]] && { echo "$d"; return; }
      done
      echo "$HOME/.mozilla/firefox" ;;
    librewolf)
      for d in "$HOME/.config/librewolf/librewolf" "$HOME/.librewolf"; do
        [[ -f $d/profiles.ini ]] && { echo "$d"; return; }
      done
      echo "$HOME/.librewolf" ;;
    brave)        echo "$HOME/.config/BraveSoftware/Brave-Browser" ;;
    brave_origin) echo "$HOME/.config/BraveSoftware/Brave-Origin" ;;
    vivaldi)      echo "$HOME/.config/vivaldi" ;;
    helium)       echo "$HOME/.config/net.imput.helium" ;;
  esac
}

# The profile the browser opens by default, or a non-zero exit if there is
# none yet.
bp_profile() {
  local root p
  root=$(bp_root "$1")
  if [[ $(bp_engine "$1") == chromium ]]; then
    p="$root/Default"
  else
    [[ -f $root/profiles.ini ]] || return 1
    p=$(python3 - "$root" <<'PY'
import configparser, os, sys
root = sys.argv[1]
c = configparser.RawConfigParser()
c.optionxform = str
c.read(os.path.join(root, 'profiles.ini'))
def pick():
    for s in c.sections():                       # what the browser last used
        if s.startswith('Install') and c.has_option(s, 'Default'):
            return c.get(s, 'Default'), True
    profiles = [s for s in c.sections() if s.startswith('Profile')]
    for s in profiles:
        if c.get(s, 'Default', fallback='0') == '1':
            return c.get(s, 'Path'), c.get(s, 'IsRelative', fallback='1') == '1'
    if profiles:
        s = profiles[0]
        return c.get(s, 'Path'), c.get(s, 'IsRelative', fallback='1') == '1'
    return None, None
path, rel = pick()
if path:
    print(os.path.join(root, path) if rel else path)
PY
)
  fi
  [[ -n $p && -d $p ]] || return 1
  printf '%s' "$p"
}

bp_running() {
  case $1 in
    zen)          pgrep -x zen || pgrep -f '/opt/zen/zen' ;;
    firefox)      pgrep -x firefox ;;
    librewolf)    pgrep -x librewolf ;;
    brave)        pgrep -f '/opt/brave.com/brave/' ;;
    brave_origin) pgrep -f '/opt/brave.com/brave-origin/' ;;
    vivaldi)      pgrep -f '/opt/vivaldi/' ;;
    helium)       pgrep -f '/opt/helium/' ;;
  esac >/dev/null 2>&1
}

# A browser that has never run has no profile to restore into. One headless
# start creates it, and the timeout ends it.
bp_first_run() {
  local key=$1 cmd
  cmd=$(bp_cmd "$key")
  info "Starting $(bp_name "$key") once in the background to create its profile"
  if [[ $(bp_engine "$key") == gecko ]]; then
    timeout 25 "$cmd" --headless about:blank >/dev/null 2>&1 || true
  else
    timeout 20 "$cmd" --headless=new --no-first-run --disable-gpu about:blank >/dev/null 2>&1 || true
  fi
  sleep 1
}

# ------------------------------------------------------------- encryption ---
bp_ask_passphrase() {   # $1 = confirm (ask twice)
  local again
  while :; do
    read -rsp "  Passphrase: " BP_PASS; printf '\n'
    [[ -n $BP_PASS ]] || { warn "The passphrase cannot be empty"; continue; }
    [[ ${1:-} == confirm ]] || return 0
    read -rsp "  Same passphrase again: " again; printf '\n'
    [[ $BP_PASS == "$again" ]] && return 0
    warn "The two did not match. Try again."
  done
}

bp_encrypt() {   # stdin -> $1
  gpg --batch --yes --quiet --pinentry-mode loopback --passphrase-fd 3 \
      --symmetric --cipher-algo AES256 -o "$1" 3<<<"$BP_PASS"
}

bp_decrypt() {   # $1 -> stdout
  gpg --batch --quiet --pinentry-mode loopback --passphrase-fd 3 --decrypt "$1" 3<<<"$BP_PASS"
}

# ------------------------------------------------------------------ backup ---
# Writes $dest/<key>.tar.zst (or .tar.zst.gpg) and appends to the manifest.
# $3 is a comma-separated item list: extensions, cookies, certs.
bp_backup_one() {
  local key=$1 dest=$2 items=$3 profile engine tmp
  profile=$(bp_profile "$key") || { warn "$(bp_name "$key") has no profile to back up"; return 0; }
  engine=$(bp_engine "$key")
  tmp=$(mktemp -d)
  local meta="$tmp/fedora-nothing"
  mkdir -p "$meta"
  local files=() f

  if [[ $engine == gecko ]]; then
    for f in extensions extensions.json extension-preferences.json \
             extension-settings.json browser-extension-data; do
      [[ -e $profile/$f ]] && files+=("$f")
    done
    for f in "$profile"/storage/default/moz-extension+++*; do
      [[ -e $f ]] && files+=("${f#"$profile"/}")
    done
    grep -h '"extensions.webextensions.uuids"' "$profile/prefs.js" > "$meta/uuids.pref" 2>/dev/null || true
    python3 - "$profile/extensions.json" > "$meta/extensions.tsv" <<'PY'
import json, sys
try:
    addons = json.load(open(sys.argv[1]))['addons']
except Exception:
    addons = []
for a in addons:
    if a.get('location') == 'app-profile' and a.get('type') in ('extension', 'theme', 'dictionary', 'locale'):
        name = (a.get('defaultLocale') or {}).get('name') or a['id']
        print(f"{a['id']}\t1\t{name}")
PY
    if [[ ,$items, == *,cookies,* ]]; then
      for f in cookies.sqlite cookies.sqlite-wal; do [[ -e $profile/$f ]] && files+=("$f"); done
    fi
    if [[ ,$items, == *,certs,* ]]; then
      for f in cert9.db key4.db pkcs11.txt; do [[ -e $profile/$f ]] && files+=("$f"); done
    fi
  else
    # Extensions you installed, from the Web Store (1) or loaded unpacked (4),
    # plus built-in ones that keep data, such as Helium's uBlock Origin, whose
    # filter lists are yours too. Brave keeps them in Preferences, Chrome in
    # Secure Preferences. Column 2: 1 = Web Store, 0 = by hand, 2 = built in.
    python3 - "$profile" > "$meta/extensions.tsv" <<'PY'
import glob, json, os, sys
prof = sys.argv[1]
settings = {}
for f in ('Preferences', 'Secure Preferences'):
    try:
        settings.update(json.load(open(os.path.join(prof, f))).get('extensions', {}).get('settings', {}))
    except Exception:
        pass
def name_of(eid, m):
    n = m.get('name', eid)
    if n.startswith('__MSG_') and n.endswith('__'):
        key = n[6:-2].lower()
        for d in sorted(glob.glob(os.path.join(prof, 'Extensions', eid, '*'))):
            loc = m.get('default_locale', 'en')
            for l in (loc, 'en', 'en_US'):
                try:
                    msgs = json.load(open(os.path.join(d, '_locales', l, 'messages.json')))
                    for k, v in msgs.items():
                        if k.lower() == key:
                            return v.get('message', n)
                except Exception:
                    pass
    return n
def has_data(eid):
    return (os.path.exists(os.path.join(prof, 'Local Extension Settings', eid))
            or glob.glob(os.path.join(prof, 'IndexedDB', f'chrome-extension_{eid}_*')))
for eid, s in settings.items():
    loc = s.get('location')
    if loc in (1, 4):
        store = 1 if loc == 1 and s.get('from_webstore', True) else 0
    elif has_data(eid):
        store = 2
    else:
        continue
    print(f"{eid}\t{store}\t{name_of(eid, s.get('manifest') or {})}")
PY
    local id
    while IFS=$'\t' read -r id _ _; do
      for f in "Local Extension Settings/$id" "Sync Extension Settings/$id" "$profile/IndexedDB/chrome-extension_${id}_"*; do
        f=${f#"$profile"/}
        [[ -e $profile/$f ]] && files+=("$f")
      done
    done < "$meta/extensions.tsv"
    if [[ ,$items, == *,cookies,* ]]; then
      for f in Cookies Cookies-journal; do [[ -e $profile/$f ]] && files+=("$f"); done
      # The cookies are unreadable on another machine without the key the
      # browser encrypted them with, which lives in the keyring.
      local app pw
      for app in $(bp_safe_apps "$key"); do
        have secret-tool || break
        pw=$(secret-tool lookup xdg:schema "$BP_SAFE_SCHEMA" application "$app" 2>/dev/null) || continue
        [[ -n $pw ]] && printf '%s' "$pw" > "$meta/safe-storage.$app"
      done
    fi
  fi

  local n; n=$(wc -l < "$meta/extensions.tsv")
  local out="$dest/$key.tar.zst"
  if [[ -n $BP_PASS ]]; then
    out+=.gpg
    tar -cf - -C "$profile" "${files[@]}" -C "$tmp" fedora-nothing | zstd -q -T0 -10 | bp_encrypt "$out"
  else
    tar -cf - -C "$profile" "${files[@]}" -C "$tmp" fedora-nothing | zstd -q -f -T0 -10 -o "$out"
  fi
  {
    printf 'browser\t%s\t%s\t%s\n' "$key" "$engine" "$items"
    local id store name
    while IFS=$'\t' read -r id store name; do
      printf 'ext\t%s\t%s\t%s\t%s\n' "$key" "$id" "$store" "$name"
    done < "$meta/extensions.tsv"
  } >> "$dest/manifest.txt"
  rm -rf "$tmp"
  ok "$(bp_name "$key"): $n extensions, $(du -h "$out" | cut -f1)"
}

# Certificates shared by every Chromium browser, and the ones you added to the
# whole system. $2: certs and/or syscerts.
bp_backup_shared() {
  local dest=$1 items=$2 tmp
  tmp=$(mktemp -d)
  mkdir -p "$tmp/shared"
  [[ ,$items, == *,certs,* && -d $HOME/.pki/nssdb ]] && cp -a "$HOME/.pki/nssdb" "$tmp/shared/nssdb"
  if [[ ,$items, == *,syscerts,* ]]; then
    local f
    mkdir -p "$tmp/shared/system-certs"
    for f in /etc/pki/ca-trust/source/anchors/* /usr/local/share/ca-certificates/*; do
      [[ -f $f ]] && cp "$f" "$tmp/shared/system-certs/"
    done
  fi
  if [[ -n $(ls -A "$tmp/shared") ]]; then
    local out="$dest/shared.tar.zst"
    if [[ -n $BP_PASS ]]; then
      out+=.gpg
      tar -cf - -C "$tmp/shared" . | zstd -q -T0 | bp_encrypt "$out"
    else
      tar -cf - -C "$tmp/shared" . | zstd -q -f -T0 -o "$out"
    fi
    printf 'shared\t%s\n' "$items" >> "$dest/manifest.txt"
  fi
  rm -rf "$tmp"
}

bp_system_cert_count() {
  local f n=0
  for f in /etc/pki/ca-trust/source/anchors/* /usr/local/share/ca-certificates/*; do
    [[ -f $f ]] && (( ++n ))
  done
  printf '%d' "$n"
}

# ----------------------------------------------------------------- restore ---
bp_manifest_browsers() { awk -F'\t' '$1 == "browser" {print $2}' "$1/manifest.txt"; }
bp_manifest_items()    { awk -F'\t' -v k="$2" '$1 == "browser" && $2 == k {print $4}' "$1/manifest.txt"; }
bp_manifest_extcount() { awk -F'\t' -v k="$2" '$1 == "ext" && $2 == k' "$1/manifest.txt" | wc -l; }
bp_manifest_shared()   { awk -F'\t' '$1 == "shared" {print $2}' "$1/manifest.txt"; }
bp_is_encrypted()      { compgen -G "$1/*.gpg" >/dev/null; }

# The backup to restore a browser from: its own, or else one from a browser
# with the same engine and the most extensions, since their extension data
# is interchangeable.
bp_source_for() {
  local dir=$1 target=$2 k best="" n most=-1
  for k in $(bp_manifest_browsers "$dir"); do
    [[ $k == "$target" ]] && { echo "$k"; return 0; }
    [[ $(bp_engine "$k") == "$(bp_engine "$target")" ]] || continue
    n=$(bp_manifest_extcount "$dir" "$k")
    (( n > most )) && { best=$k; most=$n; }
  done
  [[ -n $best ]] && echo "$best"
}

bp_unpack() {   # archive dest-dir
  if [[ $1 == *.gpg ]]; then
    bp_decrypt "$1" | zstd -q -d | tar -xf - -C "$2"
  else
    zstd -q -d -c "$1" | tar -xf - -C "$2"
  fi
}

# Restore $source's backup into $target. $4: the items to restore.
bp_restore_one() {
  local dir=$1 target=$2 source=$3 items=$4 archive tmp profile
  archive="$dir/$source.tar.zst"
  [[ -f $archive ]] || archive+=.gpg
  local name; name=$(bp_name "$target")
  tmp=$(mktemp -d)
  if ! bp_unpack "$archive" "$tmp" 2>/dev/null; then
    rm -rf "$tmp"
    soft_fail "Could not open the backup for $name" "The passphrase is wrong or the file is damaged." "./browser-backup.sh"
    return 0
  fi
  local meta="$tmp/fedora-nothing"
  mv "$meta" "$tmp.meta"; meta="$tmp.meta"

  profile=$(bp_profile "$target") || { bp_first_run "$target"; profile=$(bp_profile "$target"); } || {
    rm -rf "$tmp" "$meta"
    soft_fail "$name has no profile to restore into" "Starting it once did not create one." "open $name once, close it, then run ./browser-backup.sh"
    return 0
  }

  [[ ,$items, == *,cookies,* ]] || rm -f "$tmp"/cookies.sqlite* "$tmp"/Cookies "$tmp"/Cookies-journal
  [[ ,$items, == *,certs,* ]]   || rm -f "$tmp"/cert9.db "$tmp"/key4.db "$tmp"/pkcs11.txt

  # What is about to be replaced goes to ~/.fedora-nothing-backup first, and
  # is then removed so restored folders replace it instead of mixing with it.
  local f
  while IFS= read -r f; do
    [[ -e $profile/$f ]] || continue
    backup_path "$profile/$f"
    rm -rf "${profile:?}/$f"
  done < <(cd "$tmp" && for f in *; do
             case $f in
               storage) printf '%s\n' storage/default/* ;;
               'Local Extension Settings'|'Sync Extension Settings'|IndexedDB|extensions) printf '%s\n' "$f"/* ;;
               *) printf '%s\n' "$f" ;;
             esac
           done)
  cp -a "$tmp/." "$profile/"

  if [[ $(bp_engine "$target") == gecko ]]; then
    if [[ -s $meta/uuids.pref ]]; then
      [[ -f $profile/user.js ]] && sed -i '/"extensions.webextensions.uuids"/d' "$profile/user.js"
      { printf '// Added by fedora-nothing: keeps restored extensions attached to their data.\n'
        cat "$meta/uuids.pref"; } >> "$profile/user.js"
    fi
    # Makes the browser rescan extensions/ and drop the old home's paths.
    rm -f "$profile/addonStartup.json.lz4" "$profile/compatibility.ini"
  else
    local app
    for app in "$meta"/safe-storage.*; do
      [[ -f $app ]] || continue
      [[ ,$items, == *,cookies,* ]] || break
      if have secret-tool; then
        secret-tool store --label="${app##*.} Safe Storage" xdg:schema "$BP_SAFE_SCHEMA" \
          application "${app##*.}" < "$app" \
          || warn "Could not put back the cookie key for $name; its cookies will not load"
      else
        warn "secret-tool is missing, so $name's restored cookies cannot be read"
      fi
    done
    # Reinstall the Web Store extensions through policy; the data above waits
    # for them under the same IDs.
    local store_ids=() manual=() id store ename
    while IFS=$'\t' read -r id store ename; do
      case $store in 1) store_ids+=("$id") ;; 0) manual+=("$ename") ;; esac
    done < "$meta/extensions.tsv"
    if (( ${#store_ids[@]} )); then
      local json
      json=$(printf '%s\n' "${store_ids[@]}" | python3 -c '
import json, sys
print(json.dumps({"ExtensionSettings": {i.strip(): {
    "installation_mode": "normal_installed",
    "update_url": "https://clients2.google.com/service/update2/crx"} for i in sys.stdin if i.strip()}}))')
      merge_policy "$(bp_policy_dir "$target")/fedora-nothing-extensions.json" "$json" \
        && record file "$(bp_policy_dir "$target")/fedora-nothing-extensions.json" \
        || soft_fail "Could not tell $name to reinstall your extensions" "" "./browser-backup.sh"
    fi
    (( ${#manual[@]} )) && warn "$name: install these by hand, they were not from the Web Store: $(IFS=,; echo "${manual[*]}")"
  fi

  local n; n=$(wc -l < "$meta/extensions.tsv")
  rm -rf "$tmp" "$meta"
  if [[ $source == "$target" ]]; then
    ok "$name: $n extensions and their data restored"
  else
    ok "$name: $n extensions and their data restored from the $(bp_name "$source") backup"
  fi
}

bp_restore_shared() {   # dir items
  local dir=$1 items=$2 archive tmp
  archive="$dir/shared.tar.zst"
  [[ -f $archive ]] || archive+=.gpg
  [[ -f $archive ]] || return 0
  tmp=$(mktemp -d)
  bp_unpack "$archive" "$tmp" 2>/dev/null || { rm -rf "$tmp"; soft_fail "Could not open the shared certificates in the backup"; return 0; }
  if [[ ,$items, == *,certs,* && -d $tmp/nssdb ]]; then
    backup_path "$HOME/.pki/nssdb"
    mkdir -p "$HOME/.pki"
    rm -rf "$HOME/.pki/nssdb"
    cp -a "$tmp/nssdb" "$HOME/.pki/nssdb"
    ok "Restored the certificates the Chromium browsers share"
  fi
  if [[ ,$items, == *,syscerts,* && -n $(ls -A "$tmp/system-certs" 2>/dev/null) ]]; then
    if have update-ca-trust; then
      as_root cp "$tmp"/system-certs/* /etc/pki/ca-trust/source/anchors/
      as_root update-ca-trust
    else
      as_root cp "$tmp"/system-certs/* /usr/local/share/ca-certificates/
      as_root update-ca-certificates
    fi
    ok "Restored the certificates you had added to the system"
  fi
  rm -rf "$tmp"
}

# Close a browser before touching its profile: its databases are half-written
# while it runs. Returns 1 when the user chose to skip it.
bp_wait_closed() {
  local key=$1 reply
  while bp_running "$key"; do
    printf '  %s?%s %s is open. Close it, then: [R]etry / [S]kip it / [Q]uit ' \
      "$C_RED" "$C_OFF" "$(bp_name "$key")"
    read -rn1 reply; printf '\n'
    case $reply in
      [sS]) return 1 ;;
      [qQ]) die "Stopped; nothing was changed for $(bp_name "$key")" ;;
    esac
  done
  return 0
}

# A numbered list of the backups in ~/fedora-nothing-backups, newest first,
# plus a typed path. Prints the chosen folder.
bp_pick_backup() {
  local dirs=() d i reply
  if [[ -d $BP_BACKUP_ROOT ]]; then
    while IFS= read -r d; do
      [[ -f $d/manifest.txt ]] && dirs+=("$d")
    done < <(ls -1dt "$BP_BACKUP_ROOT"/*/ 2>/dev/null | sed 's:/$::')
  fi
  {
    printf '  %sBackups%s\n' "$C_BOLD" "$C_OFF"
    for i in "${!dirs[@]}"; do
      printf '    %d) %s  %s%s%s\n' $(( i + 1 )) "${dirs[i]/#$HOME/\~}" "$C_GREY" \
        "$(bp_manifest_browsers "${dirs[i]}" | while read -r d; do printf '%s ' "$(bp_name "$d")"; done)" "$C_OFF"
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
    [[ -f $d/manifest.txt ]] && { printf '%s' "$d"; return 0; }
    warn "No browser backup in ${d/#$HOME/\~} (it has no manifest.txt)"
  done
}

# The installer's restore: every browser being installed that has a matching
# backup gets everything the backup holds.
bp_restore_for_install() {
  local dir=$1 k src any=0 items
  for k in "${BP_BROWSERS[@]}"; do
    is_selected "$k" && bp_installed "$k" || continue
    src=$(bp_source_for "$dir" "$k") || continue
    bp_wait_closed "$k" || continue
    items=$(bp_manifest_items "$dir" "$src")
    bp_restore_one "$dir" "$k" "$src" "$items"
    any=1
  done
  (( any )) && bp_restore_shared "$dir" "$(bp_manifest_shared "$dir")"
  (( any )) || skip "None of the browsers being installed has a backup in ${dir/#$HOME/\~}"
  return 0
}
