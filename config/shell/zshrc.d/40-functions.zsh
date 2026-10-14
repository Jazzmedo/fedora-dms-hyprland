# Portable helper functions. Package-manager helpers live in 41-packages.zsh.

# Fast Tmux Dev Environment Setup
dev-env() {
    local session_name="dev_${PWD:t}" # Names the session after the current folder
    
    # If already inside tmux, don't nest it
    if [ -n "$TMUX" ]; then
        echo "You're already inside a tmux session!"
        return 1
    fi

    # Check if session exists; if so, attach
    tmux has-session -t "$session_name" 2>/dev/null
    if [ $? -eq 0 ]; then
        tmux attach-session -t "$session_name"
        return 0
    fi

    # Create session, split panes
    tmux new-session -d -s "$session_name" -n "Workspace"
    tmux split-window -h -p 35 -t "$session_name":0.0
    tmux split-window -v -p 30 -t "$session_name":0.0
    tmux split-window -v -p 50 -t "$session_name":0.1

    # Send commands to panes
    tmux send-keys -t "$session_name":0.0 "nvim ." C-m
    tmux send-keys -t "$session_name":0.2 "yazi" C-m
    
    # Automatically detect if it's a Node or Python project to prep the log pane
    if [ -f "package.json" ]; then
        tmux send-keys -t "$session_name":0.1 "npm run dev"
    elif [ -f "requirements.txt" ] || [ -f "main.py" ]; then
        tmux send-keys -t "$session_name":0.1 "python3 main.py"
    else
        tmux send-keys -t "$session_name":0.1 "# Run server/logs here"
    fi

    # Focus on Neovim and attach
    tmux select-pane -t "$session_name":0.0
    tmux attach-session -t "$session_name"
}


lazyp(){ git add . && git commit -m "$1That is it." && git push } # Quickly add, commit with a message, and push to Git

lazyc(){ git add . && git commit -m "$1That is it." } # Quickly add and commit with a message


installfonts() { # Unzips, installs .ttf/.otf fonts from ~/fonts to local share, and clears the source folder
    local SOURCE="/home/hanafi/fonts"
    local TARGET="$HOME/.local/share/fonts/installed-fonts"
    local TEMP_DIR=$(mktemp -d)
    if [ ! -d "$SOURCE" ] || [ -z "$(ls -A "$SOURCE")" ]; then
        echo "📂 Folder $SOURCE is empty or doesn't exist."
        return 1
    fi
    echo "📦 Extracting zips from $SOURCE..."
    for f in "$SOURCE"/*.zip(.N); do unzip -q -o "$f" -d "$TEMP_DIR"; done
    cp "$SOURCE"/*.{ttf,otf}(.N) "$TEMP_DIR/" 2>/dev/null
    mkdir -p "$TARGET"
    find "$TEMP_DIR" -type f \( -name "*.ttf" -o -name "*.otf" \) -exec mv -v {} "$TARGET/" \;
    echo "🔄 Refreshing system font cache..."
    fc-cache -f
    echo "🧹 Emptying $SOURCE..."
    rm -rf "$SOURCE"/*
    rm -rf "$TEMP_DIR"
    echo "✅ Fonts installed and source folder cleared!"
}

dstop() { # Stops all running Docker containers and shuts down the Docker system service
  local containers=$(docker ps -q)
  if [ -n "$containers" ]; then
    echo "Stopping containers: $containers"
    docker stop $containers
  else
    echo "No containers running."
  fi
  echo "Stopping Docker service..."
  sudo systemctl stop docker
}

fetch(){ # Standard Git fetch and pull from origin main
  git fetch origin
  git pull origin main
}

orgd() { # Sort ~/Downloads into category folders, purging known junk first
    # 1. Environment Setup
    local dl_dir="$HOME/Downloads"
    cd "$dl_dir" || return

    # Localize options to this function only
    setopt local_options extended_glob null_glob dot_glob

    local folders=("Compressed" "Video" "Audio" "Images" "Documents" "Programs" "Other")
    typeset -A counts
    local purged_count=0

    # 2. PURGE JUNK (Delete first)
    # (.) ensures we only match regular files.
    # null_glob (enabled above) safely handles empty matches without errors.
    local junk=(
        *\[SubSource\].zip(.)
        *.torrent(.)
        *.srt(.)
        Compressed/*\[SubSource\].zip(.)
        Other/*.torrent(.)
        Other/*.srt(.)
    )

    if (( ${#junk} > 0 )); then
        purged_count=${#junk}
        # Quote array to safely handle filenames with spaces
        rm -rf -- "${junk[@]}"
    fi

    # 3. ENSURE DIRECTORIES EXIST
    mkdir -p "${folders[@]}"

    # 4. DEFINE FILE LISTS
    local c_files=(*.(zip|rar|7z|tar|gz|bz2|xz|iso)(.))
    # Programs: AppImages, distro packages, flatpak bundles and installers.
    # (#i) makes the match case-insensitive: .AppImage is the usual spelling.
    local p_files=(*.(#i)(appimage|deb|rpm|flatpak|flatpakref|flatpakrepo|snap|appbundle|run|bundle|pkg|apk|xbps|eopkg|pkg.tar.zst)(.))
    local v_files=(*.(mp4|mkv|mov|avi|flv|wmv|webm|m4v)(.))
    local a_files=(*.(mp3|wav|flac|m4a|aac|ogg|wma|opus)(.))
    local i_files=(*.(jpg|jpeg|png|gif|svg|webp|bmp|ico|tiff)(.))
    local d_files=(*.(pdf|doc|docx|txt|rtf|odt|xls|xlsx|ppt|pptx|epub|csv)(.))

    # 5. MOVE LOGIC (Only runs if files exist)
    [[ ${#p_files} -gt 0 ]] && { mv -- "${p_files[@]}" Programs/ 2>/dev/null; counts[Programs]=${#p_files} }
    [[ ${#c_files} -gt 0 ]] && { mv -- "${c_files[@]}" Compressed/ 2>/dev/null; counts[Compressed]=${#c_files} }
    [[ ${#v_files} -gt 0 ]] && { mv -- "${v_files[@]}" Video/ 2>/dev/null; counts[Video]=${#v_files} }
    [[ ${#a_files} -gt 0 ]] && { mv -- "${a_files[@]}" Audio/ 2>/dev/null; counts[Audio]=${#a_files} }
    [[ ${#i_files} -gt 0 ]] && { mv -- "${i_files[@]}" Images/ 2>/dev/null; counts[Images]=${#i_files} }
    [[ ${#d_files} -gt 0 ]] && { mv -- "${d_files[@]}" Documents/ 2>/dev/null; counts[Documents]=${#d_files} }

    # 6. THE "OTHER" CATEGORY (Catch-all for leftovers and hidden files)
    local others=()
    for file in *(.); do
        # Skip category folders themselves
        [[ " ${folders[@]} " == *" ${file} "* ]] && continue
        others+=("$file")
    done

    if (( ${#others} > 0 )); then
        mv -- "${others[@]}" Other/ 2>/dev/null
        counts[Other]=${#others}
    fi

    # 7. BEAUTIFUL COLORFUL REPORT
    # Using printf/echo -e ensures ANSI escapes render correctly in all zsh configs
    echo -e "\n\033[1;35m╭──────────────────────────────────────────╮\033[0m"
    echo -e "\033[1;35m│\033[0m  📂  \033[1;37mDOWNLOADS MANAGER ACTIVATED\033[0m         \033[1;35m│\033[0m"
    echo -e "\033[1;35m╰──────────────────────────────────────────╯\033[0m"

    if [[ $purged_count -gt 0 ]]; then
        echo -e " 🔥 \033[1;31mPURGED\033[0m: $purged_count junk files (.srt, .torrent, etc.)"
    fi

    local total=0
    typeset -A icons=(
        [Compressed]="📦" [Video]="🎬" [Audio]="🎵"
        [Images]="🖼️" [Documents]="📄" [Programs]="🚀" [Other]="🌀"
    )

    for f in "${folders[@]}"; do
        if (( ${counts[$f]:-0} > 0 )); then
            printf " %s \033[1;34m%-11s\033[0m \033[1;32m──▶\033[0m  %d files moved\n" \
                "${icons[$f]}" "$f" "${counts[$f]}"
            ((total += counts[$f]))
        fi
    done

    echo -e "\033[1;35m────────────────────────────────────────────\033[0m"
    if (( total == 0 && purged_count == 0 )); then
        echo -e " ✨ \033[1;32mDownloads folder is already spotless!\033[0m"
    else
        echo -e " ✅ \033[1;37mSuccess:\033[0m $total files organized."
    fi
    echo ""
}

tnl() { # Expose a local port through tunnl.gg over ssh
  if [[ -z "$1" ]]; then
    echo "Usage: tnl <port>"
    return 1
  fi

  ssh -t -R "80:localhost:$1" stable@proxy.tunnl.gg
}

kp() { # Pick a process listening on a port and force kill it
  # 1. Fetch processes listening on ports (TCP/UDP)
  local bat_cmd=$(command -v bat || command -v batcat || echo "cat")
  local selected
  selected=$(lsof -iTCP -iUDP -sTCP:LISTEN -n -P 2>/dev/null | awk 'NR>1 {print $1, $2, $3, $9}' | sort -u | \
    fzf --header="SELECT A PROCESS TO FORCE KILL (ENTER: select | ESC: cancel)" \
        --no-multi \
        --preview='
          pid=$(echo {} | awk "{print \$2}");
          echo -e "\033[1;34m=== Process Details (PID: $pid) ===\033[0m\n";
          ps -p $pid -o user,pid,ppid,%cpu,%mem,start,time,command | '"$bat_cmd"' --language=log --style=plain --color=always
        ' \
        --preview-window=bottom:50%)

  # Exit if no process was selected (e.g. pressed ESC)
  [[ -z "$selected" ]] && return 0

  # 2. Extract PID and process info
  local pname pid user port
  pname=$(echo "$selected" | awk '{print $1}')
  pid=$(echo "$selected" | awk '{print $2}')
  user=$(echo "$selected" | awk '{print $3}')
  port=$(echo "$selected" | awk '{print $4}')

  # 3. Prompt for confirmation
  echo -ne "\n\033[1;33mAre you sure you want to force kill process \033[1;31m$pname\033[1;33m (PID: \033[1;31m$pid\033[1;33m, Port: \033[1;36m$port\033[1;33m)? [y/N]: \033[0m"
  read -r reply

  if [[ "$reply" =~ ^[Yy]$ ]]; then
    if kill -9 "$pid" 2>/dev/null; then
      echo "\033[1;32mSuccessfully killed process $pname (PID: $pid).\033[0m"
    else
      echo "\033[1;31mFailed to kill process $pname (PID: $pid). Try running with sudo:\033[0m"
      echo "sudo kill -9 $pid"
    fi
  else
    echo "Aborted."
  fi
}

dbe() { # Configures a macvlan bridge to allow the host to communicate with the Kali Kasm container
    echo "[-] Creating macvlan-proxy for enp0s31f6..."
    sudo ip link add macvlan-proxy link enp0s31f6 type macvlan mode bridge
    echo "[-] Assigning IP 192.168.100.201..."
    sudo ip addr add 192.168.100.201/32 dev macvlan-proxy
    echo "[-] Bringing interface up..."
    sudo ip link set macvlan-proxy up
    echo "[-] Routing host traffic to Kali container (192.168.100.200)..."
    sudo ip route add 192.168.100.200/32 dev macvlan-proxy
    echo "[+] Done. Host can now talk to Kali container."
    docker container start kali_kasm
}

dbd() { # Removes the macvlan bridge and stops the Kali container
    echo "[-] Removing route and macvlan-proxy interface..."
    sudo ip link delete macvlan-proxy 2>/dev/null
    if [ $? -eq 0 ]; then
        echo "[+] Successfully disabled bridge."
    else
        echo "[!] Bridge was not active or already removed."
    fi
    docker container stop kali_kasm
}

monitor-layout(){ # Rotate a monitor and pick where its windows open and how its workspaces switch
  local script="@@REPO_DIR@@/monitor-layout.sh"
  if [[ ! -x $script ]]; then
    echo "monitor-layout lives in the fedora-nothing repo, which is no longer at @@REPO_DIR@@."
    echo "Run monitor-layout.sh from wherever it is now, then ./install.sh --only=shell there."
    return 1
  fi
  "$script" "$@"
}
