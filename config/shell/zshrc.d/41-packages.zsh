# Package helpers, ported from the Debian originals (nala/apt/dpkg) to dnf.
# The Debian-only sudo() wrapper that rewrote "sudo apt" to "sudo nala" is gone:
# on Fedora there is nothing to rewrite.

# Interactive package search and install.  Was aptt() over apt-cache + nala.
dnfi() {
  local bat_cmd=$(command -v bat || command -v batcat || echo cat)
  local pkgs=$(dnf repoquery --qf '%{name}' --latest-limit 1 2>/dev/null | sort -u | fzf \
    --multi \
    --height 80% \
    --layout=reverse \
    --border=rounded \
    --info=inline \
    --header=" ⚡ [TAB]: Select | [CTRL-D]: None | [ENTER]: Install " \
    --header-first \
    --prompt=" 🔍 " \
    --pointer="👉" \
    --marker="X " \
    --bind "ctrl-d:deselect-all" \
    --color="bg+:-1,gutter:-1,border:#586e75,header:#859900,prompt:#268bd2,pointer:#cb4b16,marker:#859900,hl:#d33682,hl+:#d33682" \
    --preview "dnf info {1} 2>/dev/null | $bat_cmd --color=always --style=plain" \
    --preview-window="right,60%,border-left")

  [[ -z $pkgs ]] && { print -P "%F{red}✘ Selection cancelled.%f"; return 1 }
  local pkg_array=(${(f)pkgs})
  print -P "%F{cyan}󰏖 Installing via dnf:%f %F{yellow}${pkg_array}%f"
  sudo dnf install -y $pkg_array
}

# Install a local .rpm.  Was dpkgg()/dbapt() for .deb files.
rpmi() { sudo dnf install -y "$@" }
compdef '_files -g "*.rpm"' rpmi

fp() { # Interactive Flatpak search and install using fzf
  local bat_cmd
  command -v batcat > /dev/null && bat_cmd="batcat" || bat_cmd="bat"
  command -v $bat_cmd > /dev/null || bat_cmd="cat"

  print -P "%F{blue}🔄 Gathering Flatpak list...%f"
  local pkgs=$(flatpak remote-ls flathub --system --columns=application | fzf \
    --multi \
    --height 80% \
    --layout=reverse \
    --border=rounded \
    --info=inline \
    --header=" ⚡ [TAB]: Select | [CTRL-D]: None | [ENTER]: Install " \
    --header-first \
    --prompt=" 🔍 Flatpak: " \
    --pointer="👉" \
    --marker="X " \
    --bind "ctrl-d:deselect-all" \
    --color="bg+:-1,gutter:-1,border:#586e75,header:#859900,prompt:#268bd2,pointer:#cb4b16,marker:#859900,hl:#d33682,hl+:#d33682" \
    --preview "flatpak remote-info --system flathub {1} | $bat_cmd --color=always --style=plain" \
    --preview-window="right,60%,border-left")

  if [ -z "$pkgs" ]; then
    print -P "%F{red}✘ Selection cancelled.%f"
    return 1
  fi

  local pkg_array=(${(f)pkgs})
  print -P "%F{purple}󰏖 Installing:%f %F{yellow}${pkg_array}%f"
  flatpak install -y --system flathub $pkgs
}

# Universal uninstall picker across dnf, flatpak and snap.  Was prg().
prg() {
  local bat_cmd=$(command -v bat || command -v batcat || echo cat)
  local list_parts=()

  # dnf: only packages installed by a user action, not pulled in as deps.
  command -v dnf >/dev/null && list_parts+=("dnf repoquery --userinstalled --qf '%{name}' 2>/dev/null | sort -u | awk '{print \"dnf:\"\$1}'")
  command -v flatpak >/dev/null && list_parts+=("flatpak list --app --columns=application 2>/dev/null | awk '{print \"fp:\"\$1}'")
  command -v snap >/dev/null && list_parts+=("snap list 2>/dev/null | tail -n +2 | grep -vE 'core|bare|gtk-common|gnome-[0-9]' | awk '{print \"snap:\"\$1}'")

  local list_cmd=$(IFS="; "; echo "${list_parts[*]}")
  local selected=$(eval "$list_cmd" | fzf \
    --multi \
    --height 80% \
    --layout=reverse \
    --border=rounded \
    --info=inline \
    --header=" [TAB]: Select | [CTRL-D]: None | [ENTER]: Purge All " \
    --header-first \
    --prompt="Search Installed Apps: " \
    --pointer="👉" \
    --marker="X " \
    --bind "ctrl-d:deselect-all" \
    --color="bg+:-1,border:#ff5555,header:#ff5555,prompt:#ff5555,hl:#ffb86c" \
    --preview "
      item={}
      if [[ \$item == dnf:* ]]; then
        dnf info \${item#dnf:} 2>/dev/null | $bat_cmd --color=always --style=plain
      elif [[ \$item == fp:* ]]; then
        flatpak info \${item#fp:} | $bat_cmd --color=always --style=plain
      elif [[ \$item == snap:* ]]; then
        snap info \${item#snap:} | $bat_cmd --color=always --language=yaml --style=plain
      fi" \
    --preview-window="right,60%,border-left")

  [[ -z $selected ]] && { print -P "%F{red}✘ Nothing selected.%f"; return 1 }

  local item source name
  for item in ${(f)selected}; do
    source=${item%%:*}; name=${item#*:}
    case $source in
      dnf)  print -P "%F{red}󰩹 Removing dnf package:%f $name"
            sudo dnf remove -y "$name" && sudo dnf autoremove -y ;;
      fp)   print -P "%F{red}󰩹 Removing flatpak:%f $name"
            flatpak uninstall -y --delete-data "$name" ;;
      snap) print -P "%F{red}󰩹 Removing snap:%f $name"
            sudo snap remove --purge "$name"; rm -rf ~/snap/"$name" 2>/dev/null ;;
    esac
  done

  command -v dnf >/dev/null && sudo dnf clean packages
  command -v flatpak >/dev/null && flatpak uninstall --unused -y
}
