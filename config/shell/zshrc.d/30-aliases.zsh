# Aliases.  Debian-only entries (apt, nala, .deb helpers) are gone; see
# 41-packages.zsh for their dnf replacements.

# --- system ---
alias updt="sudo dnf upgrade --refresh -y && flatpak update -y"  # Full system upgrade
alias cln="sudo sync; echo 3 | sudo tee /proc/sys/vm/drop_caches" # Drop the page cache
alias apprfrsh='kbuildsycoca6'                                    # Rebuild the KDE app database
alias cls="clear && fastfetch"                                    # Clear and show system info

# --- modern replacements for the classics ---
alias cat="bat"
alias ls="eza --icons --group-directories-first"
alias ll="eza -lah --icons --group-directories-first"
alias htop="btop"
alias grep='rg'
alias rm="trash-put"        # trash-restore and trash-empty undo this
alias vim="nvim"
alias nano="nvim"
alias py="python3"

# --- containers ---
alias docker="podman"
alias docker-compose="podman-compose"
alias cup="podman-compose up -d"
alias cdown="podman-compose down"
alias clogs="podman-compose logs -f"
alias cbuild="podman-compose build"

# --- media ---
alias yt='yt-dlp -f "bv*[vcodec^=avc]+ba[acodec^=mp4a]/b[vcodec^=avc]" --merge-output-format mp4'
alias yt3='yt-dlp -x --audio-format mp3 --audio-quality 320K'
alias ytclip='yt-dlp -f "bv*[vcodec^=avc][height<=720]+ba[acodec^=mp4a]/b[vcodec^=avc][height<=720]" --merge-output-format mp4 --download-sections'

# --- shortcuts ---
alias dev="dev-env"
alias hnt='hint'
