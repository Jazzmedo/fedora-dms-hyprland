# Cliamp Controller for DankMaterialShell

Control [CLIAMP](https://github.com/bjarneo/cliamp) from DankBar. The plugin follows the active DMS theme and supports playback, internet radio, favorites, providers, audio devices, equalizer presets, visualizers, and enriched MPRIS metadata.

## Requirements

- DankMaterialShell 1.4+
- CLIAMP 1.63.2+
- `curl`
- `socat` for provider search through CLIAMP's local IPC socket
- `yt-dlp` for the YouTube single-track search fallback
- FFmpeg (`ffprobe`) for radio metadata
- GJS and GLib (`gjs`, `gdbus`) for enriched MPRIS
- A systemd user session (`systemd-run`) for background mode
- A supported terminal for the CLIAMP TUI and provider setup

Check the commands after installing the packages:

```sh
command -v cliamp curl ffprobe gjs gdbus systemd-run
```

## Manual installation

Clone the plugin into DMS. The destination must be named `cliampDms`:

```sh
mkdir -p ~/.config/DankMaterialShell/plugins
git clone <repository-url> ~/.config/DankMaterialShell/plugins/cliampDms
chmod +x ~/.config/DankMaterialShell/plugins/cliampDms/scripts/*
dms ipc plugin-scan scan
dms ipc plugin-scan status cliampDms
```

Then open **DMS Settings → Plugins**, enable **CLIAMP Controller**, and add `cliampDms` to DankBar. Run `dms restart` if it does not appear.

To update it:

```sh
cd ~/.config/DankMaterialShell/plugins/cliampDms
git pull --ff-only
dms ipc plugin-scan reload cliampDms
```

## Settings

- **DankBar:** icon-only, track-title, or station-and-track preview; maximum title width; open and closed refresh intervals.
- **Visualizer:** show/hide, height, frame rate, and default style.
- **Playback:** remember the last values or configure default volume, speed, repeat, shuffle, and mono.
- **Volume:** display the CLIAMP range as decibels or mapped from 0–100%.
- **Equalizer:** built-in presets and custom 10-band JSON presets, for example:

  ```json
  [{"name":"Warm","bands":[4,3,2,1,0,0,1,2,2,1]}]
  ```

- **Launch:** preferred terminal, foreground/background mode, and default provider.
- **Radio:** result limit plus optional country and language filters.

## Optional third-party bridge

> [!IMPORTANT]
> `cliamp/cliamp-dms-bridge.lua` is bundled with this plugin but is not part of, maintained by, or endorsed by CLIAMP. Review its source before installing and trusting it. Use it at your own discretion.

The bridge enables immediate radio playback and full foreground queue jumping. The Radio tab can install and trust its exact content. Fully restart CLIAMP afterward. Updated bridge content must be reviewed and trusted again.

Provider credentials remain inside CLIAMP's setup wizard. The plugin uses network access for Radio Browser and best-effort public music metadata lookups.

## Headless-mode limitations

Background mode runs CLIAMP without a terminal, but it is not equivalent to the foreground TUI:

- Lua plugins and the optional bridge are unavailable.
- CLIAMP does not expose its complete queue or exact queue jumping.
- Selecting a station restarts the daemon with that stream and replaces its queue.
- Only the DMS visualizer style is saved and rendered.
- Metadata is polled with `ffprobe`, so details and artwork may be delayed or unavailable.
- Station changes restart audio, though remembered volume is restored.
- Provider setup still opens an interactive terminal.

Use foreground mode for the complete queue, bridge, and CLIAMP TUI. Use background mode for terminal-free playback.

## Troubleshooting

- **CLIAMP unavailable:** verify the requirements with `command -v`, then start CLIAMP.
- **Plugin missing:** scan it, check `dms ipc plugin-scan status cliampDms`, then restart DMS.
- **Bridge unavailable:** restart every CLIAMP instance after installing or updating it.
- **No radio results:** check `curl` and your connection to Radio Browser.
- **Incomplete metadata:** station data, album details, and artwork are best effort.
- **MPRIS not updating:** reload the plugin or restart DMS. Foreground CLIAMP publishes its native feed while the plugin publishes enriched metadata and artwork as **Cliamp Enriched**.

## Development

```sh
qmltestrunner -input tests
qmllint CliampWidget.qml CliampSettings.qml StartupCheck.qml components/*.qml
bash -n scripts/cliamp-dms-helper scripts/cliamp-dms-cli
dms ipc plugin-scan reload cliampDms
```

## License and attribution

This is an independent community integration. It is not affiliated with or endorsed by CLIAMP or DankMaterialShell.
