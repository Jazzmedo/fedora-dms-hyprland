# fedora-nothing

Turns a barebones Fedora into a Nothing-styled Hyprland desktop: Hyprland with
DankMaterialShell and its plugins, the Nothing login theme, Ndot 57 as the
system font, and kitty, Zen and Dolphin as the defaults.

```sh
git clone https://github.com/Jazzmedo/fedora-dms-hyprland-setup
cd ~/fedora-dms-hyprland-setup
./install.sh
```

One screen. The checklist opens with everything ticked; untick what you do not
want, press Enter, and it installs. Space toggles one component, `a` toggles a
whole group, `q` cancels. Nothing is touched before you press Enter, and your
password is asked for once, straight after.

## What a run looks like

Each step announces itself, says what it is about to do, and shows how far
along you are. Slow steps show a spinner with a running clock, so nothing ever
looks frozen.

```
╭──────────────────────────────────────────────────────────────────────╮
│  Step 6 of 13  ·  Window manager                                     │
│  Sets up the window manager and works out your screen layout.        │
│  ███████████████████████░░░░░░░░░░░░░░░░░░░░░░░░░░   46%    4m 12s   │
╰──────────────────────────────────────────────────────────────────────╯

  ✓ Copied the window manager settings into place
  → Screen eDP-1: 1920x1080, landscape
  · Windows already arrange themselves the scrolling way
  ⠹ Building the touchpad gesture add-on 38s
```

`✓` done, `→` worth knowing, `·` already there so nothing to do, `▲` a warning,
`✗` a part that failed. Nothing that fails leaves you guessing:

```
  ✗ The CLIAMP music player needs the Go toolchain, which is not installed
      Why:  It has to be compiled from source.
      Fix:  Re-run ./install.sh and tick language runtimes
      This part did not finish. Everything else carries on.
```

Anything still outstanding is repeated at the end, cause and command together.
The run then checks its own work, because a command succeeding is not the same
as the outcome happening: `chsh` can return zero while the login shell stays
put, and copying a greeter theme succeeds whether or not the login screen will
load it.

```
  Checking it actually worked

  ✓ zsh is your login shell
  ✓ The login screen is set to the Nothing theme
  ✗ The Nothing typefaces are installed
      Fix:  ./install.sh --only=fonts
```

Colour turns itself off when the output is piped or `NO_COLOR` is set; use
`--color=always` to keep it through `tee`.

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
--reset-selection  forget last run's choices and start from all-ticked
--color=WHEN       auto | always | never
--status           report what is already installed, then exit
--list-stages      print the stage names
```

The steps run in one deliberate order: the software sources, then the graphics
driver, then every package in a single transaction, then the fonts, then the
desktop shell, and only then the configuration. The shell is installed before
any settings are deployed because it comes from its own installer, which sets
up a desktop of its own and writes into the same directories this repository
does. Ours land on top of anything it wrote, never underneath.

Re-running is safe. Every step checks before it acts, and anything replaced is
copied to `~/.fedora-nothing-backup/<timestamp>/` first. To repair one part:

```sh
./install.sh --only=themes
```

Your choices are remembered in `~/.config/fedora-nothing/selection.conf` and
come back ticked on the next run. The checklist is always shown, so a choice
made once can always be changed; `--reset-selection` throws the file away.

## What gets installed

**Always** — Hyprland with the hyprgrass touchpad plugin, DankMaterialShell and
nine plugins, PipeWire with pavucontrol, kitty, Zen, Dolphin, the Nothing SDDM
theme, the Nothing typefaces, ten DMS themes, three wallpaper collections, and
the XDG associations that route files to the right application.

The lock screen, clipboard history, colour picker, emoji picker and screenshot
tools are all driven by DMS over IPC, backed by hyprlock, cliphist, hyprpicker,
the emojiLauncher plugin and grim/slurp plus the quickCapture plugin.

Applications come from rpms wherever one exists: Vesktop and Obsidian from the
rpm their own project publishes, EasyEffects from Fedora. Flatpak is opt-in and
only Gear Lever, which manages AppImages, actually needs it. Selecting Gear
Lever turns Flatpak on automatically.

Two plugins are installed from your own forks rather than the DMS registry:
**cliampDms** from `Jazzmedo/cliamp-dms` on the `playback-offset` branch, which
also builds the CLIAMP player and stages its Lua bridge, and **lyricsOnPanel**
from `Jazzmedo/lyrics-on-panel` on the `niri-enhancments` branch, whose MPRIS
backend is built into a virtualenv and run as a user service.

**Optional** — zsh with oh-my-zsh and starship, Neovim with LazyVim, tmux,
yazi, the modern CLI set (eza, bat, ripgrep, fd, fzf, trash-cli), btop,
fastfetch, cava, podman, pyenv, nvm, Rust, Go, Helium, Brave Origin, Vesktop,
qBittorrent, OBS, Obsidian, CLIAMP, mpv, Strawberry, EasyEffects, Tailscale,
Cloudflare WARP, the niri session, and a set of system tweaks.

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

### Seeing what is already installed

```sh
./install.sh --status
```

Reports every component as installed, partial or missing, plus the facts that
belong to a stage rather than a component: which SDDM theme is configured, the
default systemd target, your login shell, whether dms is running and where its
binary is, the default browser, and how many DMS plugins are on disk.

The picker shows the same thing inline, so a re-run reads as repair rather than
reinstall:

```
[x] ✓ CLIAMP              already installed
[x] ~ zsh + oh-my-zsh     partially installed, a re-run completes it
[x]   Helium              not installed yet
```

Membership in a package list is not the test. A component can own no rpms at
all, as Vesktop does, or own them and still be unusable, as zsh is before it
becomes your login shell, so components declare how to detect themselves in
`lib/components.sh`. The plan then separates what will be installed from what
will be repaired from what is already satisfied.

Components already present are re-selected automatically on a re-run, because
deselecting one would not uninstall it, only stop the installer from checking
it.

### If it will not reach the login screen

A machine that hangs after a reboot is not stuck, it is waiting on a login
screen that cannot draw. Press **ctrl-alt-F3** for a text console and log in
there. Nothing about the installed system prevents that.

```sh
systemctl status sddm            # is it running, or restarting in a loop
journalctl -b -u sddm -n 50      # why it stopped
sudo systemctl set-default multi-user.target && sudo reboot   # boot to a console instead
```

The usual cause in a virtual machine is the greeter's graphics mode. The
installer now picks the older X11 mode there, because the software rendering a
virtual machine provides cannot reliably run a Qt greeter on a Wayland
compositor. To apply that to a machine installed before this:

```sh
sudo rm -f /etc/sddm.conf.d/10-wayland.conf
sudo dnf install xorg-x11-server-Xorg
sudo systemctl restart sddm
```

To put the graphical boot back afterwards:

```sh
sudo systemctl set-default graphical.target
```

### Reporting a failed install

```sh
./report.sh          # writes ~/.cache/fedora-nothing/report-<timestamp>.txt
./report.sh -        # same, to stdout
```

It gathers the Fedora version, the graphics hardware, the enabled
repositories, which key packages and DMS plugins actually landed, the state of
the systemd user units, and the warnings and errors from the newest installer
log. Home paths, the username, the hostname, email addresses and anything
shaped like a token are redacted, so the result is safe to paste.

Every run leaves two files in `logs/` inside this repository: the full log,
`install-<timestamp>.log`, and a record of what it changed,
`install-<timestamp>.manifest`. `latest.log` and `latest.manifest` point at the
newest pair. They are ignored by git. If the repository is not writable they
fall back to `~/.cache/fedora-nothing/`. Steps that fail without stopping the
install are also listed at the end of every run.

### Removing it again

```sh
./uninstall.sh --dry-run     # show what would go, change nothing
./uninstall.sh               # ask once, then undo it
```

It does two things. It reverses what the manifests record: services enabled,
files created, packages installed, sources added, the login shell, the login
screen, the boot target. Then it sweeps every place this installer, and the
installers it runs, can leave something, and removes whatever is actually
there. The sweep is what catches the parts no manifest can know about: the
desktop shell arrives through `install.danklinux.com`, the music player
through `cliamp.stream`, the Rust toolchain through `rustup`, and each writes
where it pleases. It also catches installs made before manifests existed.

Files that were replaced rather than created are restored from
`~/.fedora-nothing-backup/`. Directories left empty by the removal, such as
`~/Pictures/Wallpapers`, are pruned; ones with your own files in them are not.

The two halves differ in what they can know. A manifest records that a package
was absent before the run, so removing it is certainly right. A sweep only sees
that a package is present now, so it may name one that predates your first
install. The plan lists every package before anything happens, and
`--recorded-only` restricts the run to the manifests.

Two safeguards are unconditional. A path is only removed if it lies somewhere
this installer owns, so `~/Documents`, `~/.ssh` and the like are refused even
if a manifest names them, and a short list of packages that would break the
system rather than the desktop is never handed to `dnf remove`. Anything it
refuses is printed.

| Option | |
|---|---|
| `--dry-run` | show the plan, change nothing |
| `--keep-packages` | remove settings, leave the programs |
| `--keep-files` | remove the programs, leave the settings |
| `--recorded-only` | undo only the manifests, sweep nothing |
| `--from-log FILE` | work out an install that predates the manifests |
| `--list` | show the records available |

`--from-log` is the fallback for a machine installed before this existed. It
infers the same list from the prose log, which cannot say what was already
present beforehand, so it prints a warning and you should read the plan.

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
