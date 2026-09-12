<div align="center">

# fedora-nothing

**A complete Hyprland desktop for a barebones Fedora, in one command.**

Hyprland and DankMaterialShell, themed end to end, with every application,
service and dotfile that makes it a daily driver.

<img src="assets/screenshots/desktop.png" alt="The desktop" width="900">

![Fedora](https://img.shields.io/badge/Fedora-41%2B-51A2DA?style=flat-square&logo=fedora&logoColor=white)
![Hyprland](https://img.shields.io/badge/Hyprland-Wayland-58E1FF?style=flat-square)
![Shell](https://img.shields.io/badge/DankMaterialShell-1.6-A277FF?style=flat-square)
![Bash](https://img.shields.io/badge/Bash-idempotent-4EAA25?style=flat-square&logo=gnubash&logoColor=white)

</div>

---

```sh
git clone https://github.com/Jazzmedo/fedora-dms-hyprland-setup
cd fedora-dms-hyprland-setup
./install.sh
```

One screen. The checklist opens with everything ticked; untick what you do not
want, press Enter, and it installs. `Space` toggles one component, `a` toggles
a whole group, `q` cancels. Nothing is touched before you press Enter, and your
password is asked for once, straight after.

## 📑 Contents

| | |
|---|---|
| [🎨 The look](#-the-look) · [✨ What you get](#-what-you-get) | what it builds |
| [💿 Installing Fedora first](#-installing-fedora-first) · [▶️ Running it](#️-running-it) | getting there |
| [🧩 Components](#-components) · [⚙️ Options](#️-options) | choosing |
| [🖥️ Displays](#️-displays-and-layout) · [⌨️ Shell](#️-the-terminal) · [🔤 Fonts](#-fonts) | customising |
| [🛠️ Editing the configuration](#️-editing-the-configuration) · [🔁 Pulling changes back](#-pulling-changes-back) | changing it |
| [🚑 When something breaks](#-when-something-breaks) · [🧹 Removing it](#-removing-it-again) | undoing |

## 🎨 The look

The desktop is not tied to one theme. Three ship, each with its own wallpaper
collection, and switching between them recolours **everything at once**:

| Theme | Palette |
|---|---|
| 🔴 **Nothing Matrix** | black, dot-matrix, one signal red accent |
| 🟣 **Catppuccin** | mocha, lavender accent |
| 🟠 **Gruvbox Material** | warm, soft contrast |

One colour change reaches the shell, GTK 3 and 4, Qt 5 and 6, KDE applications,
kitty, Neovim, btop, cava, fastfetch, starship, tmux, Vesktop, OBS, Obsidian,
Zen and the terminal music player. [matugen](https://github.com/InioX/matugen)
generates each palette from the wallpaper and writes every template; the shell
triggers it.

The desktop picture follows the theme too. Change the theme and a watcher picks
the matching collection, choosing a landscape or portrait image per monitor.
Every shipped theme has a collection, which is the reason there are three and
not ten: a theme with no images recoloured the whole desktop and left the
previous picture behind. To add one, drop images into
`assets/wallpapers/<theme-slug>/horizontal/` and re-run.

The Nothing identity is the default rather than the point. Ndot 57 is the UI
face, the login screen and the boot splash match it, and a different theme
changes the colours around it without touching the layout.

## ✨ What you get

**🪟 Desktop** — Hyprland, scrolling or dwindle tiling, touchpad gestures
through hyprgrass, per-monitor workspaces worked out from your actual screens.

**🎛️ Shell** — DankMaterialShell: bar, launcher, notifications, control centre,
lock screen, dashboard, plus nine plugins including a dot-matrix clock, an emoji
launcher, quick capture and a music widget.

**🖼️ Theming** — matugen across every toolkit, wallpapers that follow the theme,
a matching SDDM login screen and an optional Plymouth boot splash.

**⌨️ Terminal** — zsh with oh-my-zsh, starship, a fastfetch greeting, tmux,
yazi, and the modern CLI set: eza, bat, ripgrep, fd, fzf, trash-cli, grc.

**📦 Applications** — kitty, Zen, Dolphin, Helium, Brave, Vesktop, Obsidian,
OBS, qBittorrent, mpv, Strawberry, CLIAMP, EasyEffects, with the file
associations that make them the defaults.

**🧑‍💻 Development** — Neovim with LazyVim, podman, pyenv, nvm, rustup, Go,
yt-dlp.

**🔒 Services** — Tailscale, Cloudflare WARP, a second niri session at the login
screen, and a handful of system tweaks.

## 💿 Installing Fedora first

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

## ▶️ Running it

Each step announces itself, says what it is about to do, and shows how far along
you are. Slow steps show a spinner with a running clock, so nothing ever looks
frozen.

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

`✓` done · `→` worth knowing · `·` already there · `▲` a warning · `✗` failed.
Nothing that fails leaves you guessing:

```
  ✗ The CLIAMP music player needs the Go toolchain, which is not installed
      Why:  It has to be compiled from source.
      Fix:  Re-run ./install.sh and tick language runtimes
      This part did not finish. Everything else carries on.
```

A failed step never takes the run down with it. Anything outstanding is repeated
at the end, cause and command together.

**It then checks its own work**, because a command succeeding is not the same as
the outcome happening. `chsh` can return zero while the login shell stays put,
and copying a greeter theme succeeds whether or not the login screen will load
it.

```
  Checking it actually worked

  ✓ zsh is your login shell
  ✓ The starship prompt is installed
  ✓ SDDM is the login screen that starts
  ✗ The Nothing typefaces are installed
      Fix:  ./install.sh --only=fonts
```

Colour turns itself off when the output is piped or `NO_COLOR` is set; use
`--color=always` to keep it through `tee`.

**Re-running is safe.** Every step checks before it acts, and anything replaced
is copied to `~/.fedora-nothing-backup/<timestamp>/` first. To repair one part:

```sh
./install.sh --only=themes
```

Your choices are remembered in `~/.config/fedora-nothing/selection.conf` and
come back ticked next time. The checklist is always shown, so a choice made once
can always be changed; `--reset-selection` throws the file away.

### The order the steps run in

Software sources, then the graphics driver, then every package in one
transaction, then fonts, then the desktop shell, and only then the
configuration. The shell is installed before any settings are deployed because
it arrives through its own installer, which sets up a desktop of its own and
writes into the same directories this repository does. Ours land on top of
anything it wrote, never underneath.

## 🧩 Components

**Always installed** — Hyprland with hyprgrass, DankMaterialShell and its
plugins, PipeWire with pavucontrol, kitty, Zen, Dolphin, the SDDM theme, the
typefaces, the three themes with their wallpapers, and the XDG associations.

| Group | Components |
|---|---|
| ⌨️ Shell & development | zsh + oh-my-zsh · starship · modern CLI tools · btop, fastfetch, cava · yazi · Neovim + LazyVim · tmux · language runtimes |
| 🌐 Browsers | Helium · Brave Origin (Zen is in the base group) |
| 📦 Applications | Vesktop · qBittorrent · OBS · Obsidian · CLIAMP · Lyrics on Panel · mpv · Strawberry · EasyEffects · Flatpak · Gear Lever |
| 🔒 Services & sessions | Tailscale · Cloudflare WARP · niri session · boot splash · system tweaks |
| 🪟 Layout | scrolling or dwindle |
| 🖥️ Graphics | AMD · Intel · NVIDIA · VM, detected from `lspci` |

The lock screen, clipboard history, colour picker, emoji picker and screenshots
are all driven by the shell over IPC, backed by hyprlock, cliphist, hyprpicker,
the emojiLauncher plugin, and grim and slurp through the quickCapture plugin.

Applications come from rpms wherever one exists: Vesktop and Obsidian from the
rpm their own project publishes, EasyEffects from Fedora. Flatpak is opt-in and
only Gear Lever, which manages AppImages, actually needs it; selecting it turns
Flatpak on automatically.

Two plugins come from personal forks rather than the plugin registry:
**cliampDms**, which also builds the CLIAMP player and stages its Lua bridge,
and **lyricsOnPanel**, whose MPRIS backend is built into a virtualenv and run as
a user service.

### Seeing what is already installed

```sh
./install.sh --status
```

Every component is reported as installed, partial or missing, along with the
facts that belong to a stage rather than a component: which SDDM theme is
configured, the default systemd target, your login shell, whether the shell is
running and where its binary is, the default browser, and how many plugins are
on disk.

The checklist shows the same thing inline, so a re-run reads as repair rather
than reinstall:

```
[x] ✓ CLIAMP              already installed
[x] ~ zsh + oh-my-zsh     partially installed, a re-run completes it
[x]   Helium              not installed yet
```

Membership in a package list is not the test. A component can own no rpms at
all, as Vesktop does, or own them and still be unusable, as zsh is before it
becomes your login shell, so each declares how to detect itself in
`lib/components.sh`.

## ⚙️ Options

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

### Moving to real hardware

A virtual machine does not exercise the real driver branch, the Wayland greeter,
Plymouth on real firmware, or your actual screens. Install in two passes so that
nothing which can stop you reaching a desktop goes in untested:

```sh
./install.sh --dry-run             # the detected GPU, screens and full plan
./install.sh --skip=sddm,optional  # everything that cannot break booting
./doctor.sh                        # confirm the desktop is sound
./install.sh --only=sddm,optional  # then the login screen and boot splash
```

On NVIDIA with Secure Boot enabled, the driver will not load until its key is
enrolled. The installer prints the two commands and you reboot into the blue MOK
screen once.

## 🖥️ Displays and layout

The installer reads the connected outputs from the kernel before Hyprland
starts, and writes three files from what it finds: `dms/outputs.lua` places each
monitor, `monitors.lua` splits the ten workspaces evenly across them, and
`monitors.env` gives the same facts to the shell scripts. A portrait monitor
gets a vertically scrolling tape; a landscape one scrolls across. Connectors
reporting only a 640x480 fallback mode are ignored, because docks and unused
DisplayPort ports read as connected while offering nothing usable.

After plugging in or removing a monitor:

```sh
./install.sh --only=hyprland
```

Two tiling layouts are offered:

* 🌀 **Scrolling** is what this configuration was built around. Windows sit on
  an endless tape you scroll along, Niri-style.
* 🪟 **Dwindle** is stock Hyprland's binary split.

`SUPER + SHIFT + L` toggles the current workspace between the two, and
`SUPER + CTRL + SHIFT + L` toggles all of them. Three-finger tap opens the
overview, four-finger swipes move windows, four-finger tap switches the layout.

## ⌨️ The terminal

`.zshrc` is a six-line loader. The real content is in `config/shell/zshrc.d/`,
one numbered fragment per concern, sourced in order:

| Fragment | Holds |
|---|---|
| `00-env` `10-path` | environment, PATH, one entry per directory that exists |
| `20-version-managers` | nvm, pyenv, cargo, loaded lazily |
| `25-oh-my-zsh` | plugins, completion, syntax highlighting |
| `30-aliases` `40-functions` `41-packages` | the aliases and helpers |
| `50-hint` | `hint` prints a cheat sheet of everything above |
| `60-fastfetch` | the greeting on a new terminal |
| `70-prompt` | starship, initialised after oh-my-zsh |

The fetch is drawn without frames: names to the left of a single rule in the
current accent colour, values to the right. It is a matugen template, so the
rule changes colour with the theme.

```
HARDWARE     │
  OS        │  Fedora Linux 44 x86_64
󰌢  Host      │  Precision 3520
  Kernel    │  Linux 7.2.4
             │
SYSTEM       │
󰏖  Packages  │  2841 (rpm), 12 (flatpak)
󰃭  Age       │  2026-02-11 [212 days]
```

It greets you once per terminal, and stays quiet where output would be wrong:
without a terminal attached, inside Neovim's `:terminal`, and in extra tmux
panes. `FF_IN_TMUX=1` greets in every pane.

## 🔤 Fonts

Ndot 57 becomes the sans-serif and UI font everywhere, including the login
screen. It is a dot-matrix display face with no monospace metrics, so monospace
stays on JetBrainsMono Nerd Font Mono. Terminals, Neovim and code therefore stay
aligned while the interface reads as Nothing.

## 🎬 The boot splash

Ticking **Boot splash** replaces the wall of service messages at startup with a
row of dots and the name, drawn in Ndot. It is a Plymouth theme built from four
solid-colour images scaled at runtime rather than from artwork, so it is sharp
at any resolution and adds under a kilobyte to the startup image.

Installing it rebuilds the initrd, which is the slow part of that step and the
part that matters: a theme that is only on disk is never seen. The typeface is
copied into the startup image too, through a dracut drop-in, since
`/usr/share/fonts` does not exist that early.

On a machine with an encrypted disk the splash is also what asks for the
passphrase, so the theme implements the password prompt. Without one you get a
splash that never asks and a boot that stops there.

```sh
sudo plymouthd; sudo plymouth --show-splash; sleep 8; sudo plymouth --quit  # preview
sudo plymouth-set-default-theme -R bgrt                                      # revert
```

Num Lock is switched on at the console and at the login screen, both.

## 🛠️ Editing the configuration

```
install.sh              entrypoint: checklist, then stages in order
lib/common.sh           logging, dry-run, backups, templating, the change ledger
lib/components.sh       the component registry — the single source of truth
lib/verify.sh           the closing checks, shared with doctor.sh
lib/ui.sh               the checklist
lib/stages/             one file per stage, named for the order it runs in
lib/dms_settings.py     rewrites settings.json for this machine and selection
config/                 dotfiles, grouped by what they do
assets/                 fonts, the SDDM theme, wallpapers, icon themes, Plymouth
bin/                    helper scripts that land in ~/.local/bin
uninstall.sh            undo a run
sync.sh                 pull live changes back into this repo
doctor.sh · report.sh   diagnose
```

`config/` is grouped by concern, not mirrored from `$HOME`:

| Directory | Holds |
|---|---|
| `config/desktop/` | Hyprland modules, niri, systemd user units |
| `config/shell/` | zsh fragments, starship, tmux |
| `config/terminal/` | kitty |
| `config/editor/` | Neovim |
| `config/tools/` | btop, cava, fastfetch, yazi, cliamp |
| `config/theming/` | matugen templates, GTK, Qt, KDE colour schemes |
| `config/shell-ui/` | DankMaterialShell settings and themes |
| `config/apps/` | per-application configuration |
| `config/system/` | browser policies, sysctl, systemd units |

The Hyprland config is split into modules loaded by `hyprland.lua`: `env.lua`,
`settings.lua`, `gestures.lua`, `animations.lua`, `rules.lua`, `quattro.lua` and
`binds.lua`. Anything under `config/desktop/hypr/dms/` is written by the shell
and will be overwritten.

Two mechanisms keep these files portable:

* `@@HOME@@`, `@@USER@@`, `@@MONITOR@@`, `@@ZEN_PROFILE@@` and
  `@@OBSIDIAN_VAULT@@` are substituted when a file is deployed.
* a line ending in `-- @component:NAME` or `# @component:NAME` is deleted when
  that component was not selected, so a keybinding for an app you did not
  install simply does not exist.

## 🔁 Pulling changes back

```sh
./sync.sh status     # what differs between this machine and the repo
./sync.sh capture    # copy $HOME into the repo and re-template the paths
./sync.sh deploy     # the other direction, through install.sh
```

Read `git diff` after a capture: application configs pick up account names and
recent-file lists.

## 🚑 When something breaks

```sh
./doctor.sh          # check a finished install
./report.sh          # write a pasteable report of the whole machine
./report.sh -        # the same, to stdout
```

The report gathers the Fedora version, the graphics hardware, the enabled
repositories, which key packages and plugins actually landed, the state of the
systemd user units, and the warnings and failures from the newest installer log.
Home paths, the username, the hostname, email addresses and anything shaped like
a token are redacted, so the result is safe to paste.

Every run leaves two files in `logs/`: the full log, `install-<timestamp>.log`,
and a record of what it changed, `install-<timestamp>.manifest`. `latest.log`
and `latest.manifest` point at the newest pair. They are ignored by git, and
fall back to `~/.cache/fedora-nothing/` if the repository is not writable.

### It will not reach the login screen

A machine that hangs after a reboot is not stuck, it is waiting on a login
screen that cannot draw. Press **ctrl-alt-F3** for a text console and log in
there. Nothing about the installed system prevents that.

```sh
systemctl status sddm            # running, or restarting in a loop
journalctl -b -u sddm -n 50      # why it stopped
sudo systemctl set-default multi-user.target && sudo reboot   # boot to a console
```

The usual cause in a virtual machine is the greeter's graphics mode. The
installer picks the older X11 mode there, because the software rendering a
virtual machine provides cannot reliably run a Qt greeter on a Wayland
compositor. To apply that to a machine installed before this:

```sh
sudo rm -f /etc/sddm.conf.d/10-wayland.conf
sudo dnf install xorg-x11-server-Xorg
sudo systemctl restart sddm
sudo systemctl set-default graphical.target   # once it works again
```

### The wallpaper does not follow the theme

```sh
journalctl --user -u dms-theme-wallpapers -n 40
```

The watcher names the theme it read, the collection it matched, and how many
outputs it reached. If it says no collection was found, the folder name under
`~/Pictures/Wallpapers/theme-collections/` does not match the theme's name.

## 🧹 Removing it again

```sh
./uninstall.sh --dry-run     # show what would go, change nothing
./uninstall.sh               # ask once, then undo it
```

It does two things. It reverses what the manifests record: services enabled,
files created, packages installed, sources added, the login shell, the login
screen, the boot target. Then it sweeps every place this installer, and the
installers it runs, can leave something behind, and removes whatever is actually
there. The sweep catches what no manifest can know about: the desktop shell
arrives through `install.danklinux.com`, the music player through
`cliamp.stream`, the Rust toolchain through `rustup`, and each writes where it
pleases. It also catches installs made before manifests existed.

Files that were replaced rather than created are restored from
`~/.fedora-nothing-backup/`. Directories left empty by the removal, such as
`~/Pictures/Wallpapers`, are pruned; ones with your own files in them are not.

The two halves differ in what they can know. A manifest records that a package
was absent before the run, so removing it is certainly right. A sweep only sees
that a package is present now, so it may name one that predates your first
install. The plan lists every package before anything happens, and
`--recorded-only` restricts the run to the manifests.

Two safeguards are unconditional. A path is only removed if it lies somewhere
this installer owns, so `~/Documents`, `~/.ssh` and the like are refused even if
a manifest names them, and a short list of packages that would break the system
rather than the desktop is never handed to `dnf remove`. Anything refused is
printed.

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

## 🙏 Credits

The SDDM theme is [Darkkal44](https://github.com/Darkkal44)'s Nothing theme, MIT
licensed. DankMaterialShell is by
[AvengeMedia](https://github.com/AvengeMedia/DankMaterialShell). The Nothing
Clock plugin is by [samgrande](https://github.com/samgrande/Dank-Nothing-Clock).
Colour generation is [matugen](https://github.com/InioX/matugen). The Nothing
typefaces are Nothing Technology's and are included here for personal use.
