# Locale, editor and the variables every later fragment depends on.
export LANG=en_US.UTF-8
export EDITOR='nvim'
export VISUAL='nvim'
export MANPATH="/usr/local/man:$MANPATH"
export ZSH="$HOME/.oh-my-zsh"

# Flatpak exports must precede the system dirs so flatpak .desktop files win.
export XDG_DATA_DIRS="/var/lib/flatpak/exports/share:$HOME/.local/share/flatpak/exports/share:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"

# Podman speaks the Docker API; anything expecting DOCKER_HOST finds it here.
export DOCKER_HOST="unix://$XDG_RUNTIME_DIR/podman/podman.sock"
