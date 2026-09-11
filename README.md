# fedora-nothing

Turns a barebones Fedora into a Nothing-styled Hyprland desktop: Hyprland with
DankMaterialShell and its plugins, the Nothing login theme, Ndot 57 as the
system font, and kitty, Zen and Dolphin as the defaults.

```sh
git clone https://github.com/Jazzmedo/fedora-dms-hyprland-setup
cd ~/fedora-dms-hyprland-setup
./install.sh
```

The installer opens a checklist first. Space toggles a component, `a` toggles a
whole group, enter starts. Nothing is touched before you press enter.

## Installing Fedora first

Use the **Fedora Everything** ISO. On the Software Selection screen:

| Setting | Choose |
|---|---|
| Base Environment | **Fedora Custom Operating System** |
| Guest Agents | only in a virtual machine |
| Common NetworkManager Submodules | yes |
| Standard | yes |
| Hardware Support | yes, or Wi-Fi and GPU firmware may be missing |

Leave every other group unticked. Set the hostname and switch the network on
before installing, leave the root account disabled, and tick "Make this user
administrator". The first boot lands on a text console; that is expected.

## Options

```
--yes, -y          accept the default selection, ask nothing
--preset=NAME      minimal | standard | full
--gpu=VENDOR       amd | intel | nvidia | vm   (default: detected from lspci)
--layout=NAME      scrolling | dwindle          (default: scrolling)
--only=A,B         run only these stages
--skip=A,B         run everything except these stages
--dry-run          print every command without running one
--no-backup        do not copy replaced files aside
--list-stages      print the stage names
```

Re-running is safe. Every step checks before it acts, and anything replaced is
copied to `~/.fedora-nothing-backup/<timestamp>/` first. To repair one part:

```sh
./install.sh --only=themes
```

Your choices are remembered in `~/.config/fedora-nothing/selection.conf` and
reused on the next run.

## What gets installed

**Always** — Hyprland with the hyprgrass touchpad plugin, DankMaterialShell and
nine plugins, PipeWire with pavucontrol, kitty, Zen, Dolphin, the Nothing SDDM
theme, the Nothing typefaces, ten DMS themes, three wallpaper collections, and
the XDG associations that route files to the right application.

The lock screen, clipboard history, colour picker, emoji picker and screenshot
tools are all driven by DMS over IPC, backed by hyprlock, cliphist, hyprpicker,
the emojiLauncher plugin and grim/slurp plus the quickCapture plugin.

**Optional** — zsh with oh-my-zsh and starship, Neovim with LazyVim, tmux,
yazi, the modern CLI set (eza, bat, ripgrep, fd, fzf, trash-cli), btop,
fastfetch, cava, podman, pyenv, nvm, Rust, Go, Helium, Brave Origin, Vesktop,
qBittorrent, OBS, Obsidian, CLIAMP, EasyEffects, Tailscale, Cloudflare WARP,
the niri session, SearXNG, and a set of system tweaks.

## Layout

```
install.sh              entrypoint: picker, then stages in order
lib/common.sh           logging, dry-run, backups, templating
lib/components.sh       the component registry — the single source of truth
lib/ui.sh               the checklist
lib/stages/             one file per stage, named for the order it runs in
lib/dms_settings.py     rewrites settings.json for this machine and selection
config/                 dotfiles, grouped by what they do
assets/                 fonts, the SDDM theme, wallpapers, icon themes
bin/                    helper scripts that land in ~/.local/bin
sync.sh                 pull live changes back into this repo
```

### Editing configuration

`config/` is grouped by concern, not mirrored from `$HOME`:

| Directory | Holds |
|---|---|
| `config/desktop/` | Hyprland modules, niri, systemd user units |
| `config/shell/` | zsh fragments, starship, tmux |
| `config/terminal/` | kitty |
| `config/editor/` | Neovim |
| `config/tools/` | btop, cava, fastfetch, yazi, cliamp |
| `config/theming/` | matugen, GTK, Qt, KDE colour schemes |
| `config/shell-ui/` | DankMaterialShell settings and themes |
| `config/apps/` | per-application configuration |
| `config/system/` | browser policies, sysctl |

The Hyprland config is split into modules loaded by `hyprland.lua`: `env.lua`,
`settings.lua`, `gestures.lua`, `animations.lua`, `rules.lua`, `quattro.lua`
and `binds.lua`. Anything under `config/desktop/hypr/dms/` is written by
DankMaterialShell and will be overwritten.

`.zshrc` is a six-line loader. The real content is in
`config/shell/zshrc.d/`, one numbered fragment per concern, sourced in order.

Two mechanisms keep these files portable:

* `@@HOME@@`, `@@USER@@`, `@@MONITOR@@`, `@@ZEN_PROFILE@@` and
  `@@OBSIDIAN_VAULT@@` are substituted when a file is deployed.
* a line ending in `-- @component:NAME` or `# @component:NAME` is deleted when
  that component was not selected, so a keybinding for an app you did not
  install simply does not exist.

### Pulling changes back

```sh
./sync.sh status     # what differs between this machine and the repo
./sync.sh capture    # copy $HOME into the repo and re-template the paths
./sync.sh deploy     # the other direction, through install.sh
```

Read `git diff` after a capture: application configs pick up account names and
recent-file lists.

## Displays and layout

The installer reads the connected outputs from the kernel before Hyprland
starts, and writes three files from what it finds: `dms/outputs.lua` places
each monitor, `monitors.lua` splits the ten workspaces evenly across them, and
`monitors.env` gives the same facts to the shell scripts. A portrait monitor
gets a vertically scrolling tape; a landscape one scrolls across. Connectors
that report only a 640x480 fallback mode are ignored, because docks and unused
DisplayPort ports read as connected while offering nothing usable.

After plugging in or removing a monitor:

```sh
./install.sh --only=hyprland
```

The picker also asks which tiling layout to start in:

* **Scrolling** is what this configuration was built around. Windows sit on an
  endless tape you scroll along, Niri-style.
* **Dwindle** is stock Hyprland's binary split.

Either way, `SUPER + SHIFT + L` toggles the current workspace between the two,
and `SUPER + CTRL + SHIFT + L` toggles all of them.

## Fonts

Ndot 57 becomes the sans-serif and UI font everywhere, including the login
screen. It is a dot-matrix display face with no monospace metrics, so
monospace stays on JetBrainsMono Nerd Font Mono. Terminals, Neovim and code
therefore stay aligned while the interface reads as Nothing.

## Credits

The SDDM theme is [Darkkal44](https://github.com/Darkkal44)'s Nothing theme,
MIT licensed. DankMaterialShell is by
[AvengeMedia](https://github.com/AvengeMedia/DankMaterialShell). The Nothing
Clock plugin is by [samgrande](https://github.com/samgrande/Dank-Nothing-Clock).
The Nothing typefaces are Nothing Technology's and are included here for
personal use.
