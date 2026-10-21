# Desktop-environment parity: what a full DE gives you that this did not

This installer replaces a desktop environment on a Fedora that has none. That
raises a fair question: what does GNOME or KDE actually do for you, silently,
that a compositor-plus-shell setup forgets? This page is the audit, and — as of
the same commit that added it — the fix. Every gap below is now handled in the
component registry; the table says where.

The audit was done against the component registry and the shipped
configuration, line by line against what a stock Fedora KDE or GNOME session
provides. Where a feature depends on a daemon rather than a config file, the
daemon's absence is the finding — a widget that renders but has nothing to
talk to is the kind of gap that survives a glance at the desktop.

## What was already covered

| Domain | Status | What provides it |
| --- | --- | --- |
| Compositor & session | ✅ | Hyprland + plugins, per-monitor workspaces, `monitor-layout` |
| Shell | ✅ | DankMaterialShell: bar, launcher, notifications, clipboard, OSDs, lock, power menu, polkit agent |
| Theming | ✅ | matugen into GTK 3/4, Qt 5/6, KDE, terminals, browsers; fonts, cursors, icons, wallpapers |
| Audio | ✅ | PipeWire + wireplumber, EasyEffects presets, MPRIS media keys |
| Network & VPN | ✅ | NetworkManager + nm-connection-editor, Tailscale and WARP components, mDNS |
| Bluetooth | ✅ | bluez + blueman, DMS control centre |
| Portals & capture | ✅ | xdg-desktop-portal-hyprland/gtk/kde, grim/slurp screenshots, custom share picker |
| Default apps | ✅ | generated `mimeapps.list`, xdg-settings, Mimic for changes |
| Display manager | ✅ | SDDM with the Nothing theme, numlock, greeter compositor |
| Terminal & dev | ✅ | zsh, tmux, Neovim + LazyVim, version managers, containers, AI CLIs |
| Login theme, boot splash | ✅ | SDDM Nothing theme, optional Plymouth splash |
| Recovery | ✅ | file backups, manifests, `doctor.sh`, `report.sh`, `browser-backup.sh` |

## What was missing — and why it mattered

These are the things a DE does that you only notice when they are gone.

**A place to keep passwords.** `libsecret` was installed, but nothing provided
the *service* it talks to. No keyring daemon means browsers offer to save a
password and then cannot, and anything using the standard Secrets API fails or
prompts. Fixed by a core **Secret service** component: `gnome-keyring` with
`gnome-keyring-pam`, unlocked at login through the SDDM PAM stack, plus
`seahorse` to look inside it.

**Battery, power profiles, and plugging things in.** The DMS battery widget is
built on UPower, and its power-profile OSD on `power-profiles-daemon`; neither
daemon was installed, so both widgets were dead on the machines this targets.
UPower also brings udisks2, which is what makes removable drives appear and
automount at all. Fixed by a core **Desktop services** component that also
guarantees `ufw` (in place of the firewalld Fedora's Standard group would
normally provide — the desktop stage disables firewalld so only one firewall
is ever active) and runs `xdg-user-dirs-update` so Documents and Downloads
exist on an install that never had a desktop to make them.

**App autostart.** Applications ship autostart entries in
`/etc/xdg/autostart` and expect the session to run them. Neither
`xdg-desktop-autostart.target` nor `dex` was anywhere in the setup, so
EasyEffects' launcher, KDE Connect helpers, and anything you add later that
relies on autostart never started. Fixed by running
`dex -a -s /etc/xdg/autostart/:~/.config/autostart/` from the session startup
hook (core **App autostart** component).

**A file manager that can leave the local disk.** Dolphin was installed with
its thumbnailers, but without `kio-extras` and the `gvfs` backend set it could
not browse an Android phone over MTP, a Samba share, or an NFS export, and
archives had no GUI. Fixed in the core Dolphin component, alongside a core
**Desktop utilities** component: `ark`, `gwenview`, `okular`, `kate`,
`kcalc`, `filelight`, and `satty` for screenshot annotation — the same apps the
shipped `mimeapps.list` and window rules were already written to expect.

**Idle, lock and suspend defaults.** `hypridle` and `hyprlock` were installed,
but every idle, lock and suspend timeout shipped as `0` — a desktop that never
blanks, never locks, and never suspends unless you ask. The shipped DMS
settings now default to a blank after three minutes, a lock after five on
battery and ten on AC, and a suspend after twenty on battery; `lockBeforeSuspend`
is on. Change any of it in DMS Settings.

**Printing and scanning.** Nothing: no cups, no SANE, no printer tool. Now an
optional **Printing** component: `cups`, `cups-filters`, KDE's print-manager
for the settings module, `sane-backends-drivers-scanners` and `skanpage`.

**Firmware updates.** No `fwupd`, so `fwupdmgr` and the vendor updates it
delivers were unavailable. Now an optional **Firmware** component that
enables the refresh timer as well as installing the daemon.

**Bluetooth file transfer.** `bluez` pairs and streams audio, but without
`bluez-obex` there is no OBEX, so pushing a file to or from a phone fails.
Added to the core packages.

**Screenshot annotation.** `satty` is installed with the utilities, and
`SUPER + ALT + P` grabs a region and opens it there — Print-family keys stay
with DMS's own captures.

**Night light.** DMS has one; it had no key. `SUPER + ALT + N` toggles it.

**Office suite.** Deliberately optional and unticked: LibreOffice is half a
gigabyte and people know whether they want it. The `kf6` VCL environment was
already being exported for it. Tick **Office** in the installer.

**System snapshots.** Now an optional **Backups** component (`timeshift`).
The installer's own backups protect its files, not your disk.

**Draw on screen.** The `SUPER + ALT + D` bind shipped before the tool it
calls existed in any install path. wayscriber now has an optional **Draw**
component that installs the RPM its project publishes, so the bind finally
points at something.

## Out of scope, on purpose

- **Input methods (fcitx5/ibus):** Arabic is typed through the kernel's
  `us,ara` XKB layout with Alt+Shift switching, which every toolkit honours
  natively. An IME stack earns its complexity for CJK input, which is not this
  setup's use case.
- **Screen reader and on-screen keyboard:** real accessibility is more than
  installing `orca`; it needs testing nobody here can do honestly. The
  magnifier (`SUPER + ALT + =`), sticky-key support via XKB options, and
  wayscriber are what exists.
- **A package manager GUI:** this desktop is terminal-first by design.
- **Mail client and calendar:** covered by the browser and Obsidian for the
  people who want them; personal choices rather than desktop plumbing.

## The scoreboard

| Domain | Before | After |
| --- | --- | --- |
| Secret service / keyring | ❌ | ✅ core, PAM-unlocked at login |
| Battery + power profiles | ❌ (dead widgets) | ✅ core |
| Removable-drive automount | ❌ | ✅ core (udisks2 via upower) |
| Firewall | ⚠️ only if Fedora's group brought it | ✅ core, guaranteed |
| XDG autostart | ❌ | ✅ core (dex) |
| Standard user folders | ❌ | ✅ core (xdg-user-dirs) |
| Dolphin: MTP / SMB / NFS | ❌ | ✅ core (kio-extras + gvfs) |
| Image viewer / PDF / archive / editor / calculator / disk usage | ❌ | ✅ core utilities |
| Idle / lock / suspend defaults | ⚠️ all disabled | ✅ sane defaults, adjustable |
| Printing & scanning | ❌ | ✅ optional component |
| Firmware updates | ❌ | ✅ optional component |
| Office suite | ❌ | ✅ optional component |
| System snapshots | ❌ | ✅ optional component |
| Draw on screen | ⚠️ bind with no tool | ✅ optional component |
| Bluetooth file transfer | ❌ | ✅ core (bluez-obex) |
| Screenshot annotation | ❌ | ✅ core (satty) + SUPER+ALT+P |
| Night light key | ⚠️ setting only | ✅ SUPER+ALT+N |
