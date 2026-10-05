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

monitor-layout(){ # Rotate a monitor and pick where its windows open and how its workspaces switch
  local script="@@REPO_DIR@@/monitor-layout.sh"
  if [[ ! -x $script ]]; then
    echo "monitor-layout lives in the fedora-nothing repo, which is no longer at @@REPO_DIR@@."
    echo "Run monitor-layout.sh from wherever it is now, then ./install.sh --only=shell there."
    return 1
  fi
  "$script" "$@"
}
