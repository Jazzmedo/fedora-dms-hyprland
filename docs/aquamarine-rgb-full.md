# Full RGB colour fix (patched aquamarine)

An optional component. Tick **Full RGB colour fix** in the installer, or run
`./install.sh --only=hyprland` with it selected.

## The problem

A monitor can be driven at *limited* RGB range (16-235) instead of *full*
(0-255). Blacks come out grey, whites dull, and the whole picture looks washed
out. It is most visible on a screen reached through a VGA or HDMI subconnector.

The range is a DRM property on the connector, called `Broadcast RGB`
(`Automatic=0`, `Full=1`, `Limited=2` on Intel). Plasma exposes it in its
display settings. Hyprland does not, and its backend leaves it at the driver's
automatic choice.

Setting the property from outside, with `proptest`, does not stick: aquamarine
owns the connector and rewrites its state on the next atomic commit. The
selection has to be made *inside* that commit, which is why this is a patch to
aquamarine rather than a script or a config line.

## The fix

`assets/aquamarine-rgb-full/broadcast-rgb-full.patch` adds about thirty lines to
`src/backend/drm/impl/Atomic.cpp`. When the environment variable
`AQ_DRM_FORCE_FULL_RGB` names a connector, aquamarine looks that connector's
`Broadcast RGB` property up by name and adds value `1` (Full) to its own atomic
request. `*` targets every connector that has the property. With the variable
unset, behaviour is upstream's.

It touches no public header and does not intentionally change the ABI.

## What the installer does

1. Reads the version of the packaged `aquamarine` and clones that exact tag
   from `https://github.com/hyprwm/aquamarine`.
2. Applies the patch, and stops with a soft failure if it no longer applies.
3. Builds and installs into **`/opt/aquamarine-rgb-full`**. The packaged library
   in `/usr/lib64` is never touched — the isolated `LD_LIBRARY_PATH` below is
   the safety boundary, and the distro's own library stays the fallback.
4. Writes `/usr/local/bin/hyprland-rgb-full`, a wrapper that exports
   `AQ_DRM_FORCE_FULL_RGB` and `LD_LIBRARY_PATH` and then execs `Hyprland`.
5. Adds `/usr/share/wayland-sessions/hyprland-rgb-full.desktop`, shown at the
   login screen as **Hyprland (Full RGB)**. The plain **Hyprland** entry is left
   in place and is the recovery session.
6. Holds `hyprland` and `aquamarine` at their current versions with
   `dnf versionlock`, because the two are a matched pair (see below). Nothing is
   held unless this component is selected and the build succeeded; unticking the
   component releases them again.

### Which connector

The installer picks it from the screens that are actually connected:

- `AQ_FULL_RGB_CONNECTOR` in the environment wins, if set.
- Exactly one external screen (not `eDP-`, `LVDS-`, `DSI-`) — that one.
- None, or several — `*`. The patch is a no-op on a connector that has no
  `Broadcast RGB` property, so this is safe, and it still applies to a monitor
  plugged in later.

To change it afterwards, edit the two lines in `/usr/local/bin/hyprland-rgb-full`
and log out and back in. No rebuild is needed.

## Upgrades: Hyprland and aquamarine are a matched pair

Do not run an updated Hyprland against the previously built aquamarine merely
because the SONAME still matches. Internal ABI or API changes can still break
startup. This is why both packages are held.

1. Record what you have and what is offered:

   ```sh
   dnf list --installed hyprland aquamarine
   dnf list --upgrades  hyprland aquamarine
   dnf versionlock list
   ```

2. Release the pair and update them together:

   ```sh
   sudo dnf versionlock delete hyprland aquamarine
   sudo dnf upgrade hyprland aquamarine
   ```

3. Log out and sign in using the plain **Hyprland** session first. That confirms
   the package update itself works, without loading the patched library.

4. Rebuild against the new version:

   ```sh
   ./install.sh --only=hyprland
   ```

   The installer clones the tag matching the newly installed package, reapplies
   the patch and re-holds the pair. If the patch no longer applies it says so
   and changes nothing; port the `Atomic.cpp` change to the new source by hand
   and update the patch in `assets/aquamarine-rgb-full/`.

5. Check upstream first at each such rebuild. If connector-level `Broadcast RGB`
   selection has become a supported option, prefer it and retire this patch.

`./install.sh --status` reports this component as **partial** when the staged
library no longer matches the installed aquamarine — that is the signal to
rebuild.

## Verifying it works

```sh
# the wrapper is what the session started
tr '\0' '\n' < /proc/$(pidof Hyprland)/environ | grep AQ_DRM_FORCE_FULL_RGB
# the patched library is the one mapped, not the packaged one
grep -c aquamarine-rgb-full /proc/$(pidof Hyprland)/maps
# aquamarine says it set the property
grep -i 'Broadcast RGB' ~/.local/share/hyprland/hyprland.log
# and the kernel agrees: value 1 on the affected connector
modetest -c | grep -A2 'Broadcast RGB'
```

Then look at the screen: dark gradients, black level and saturation are where
the difference shows.

Connector IDs and DRM property IDs are assigned at runtime. Always discover them
again rather than reusing numbers from a previous session; the stable selector is
the connector name.

## Recovery

If the patched session fails to start, pick **Hyprland** at the login screen.
That entry does not set `LD_LIBRARY_PATH` and loads the packaged aquamarine.

Do not try to repair this by replacing system libraries, editing GRUB or adding
kernel parameters. To remove the component entirely, untick it and re-run
`./install.sh --only=hyprland`, or run `./uninstall.sh`.

---

Based on a local write-up (`context.md`) from the original hand-built version of
this fix, generalised here for any machine and any connector.
