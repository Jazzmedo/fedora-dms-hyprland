import QtQuick
import qs.Common
import qs.Modules.Plugins
import qs.Widgets

PluginSettings {
    id: settings
    pluginId: "cliampDms"

    StyledText {
        width: parent.width
        text: "CLIAMP Controller talks only to the owner-local CLIAMP socket. Provider secrets remain in CLIAMP's own setup wizard."
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    StyledText {
        width: parent.width
        text: "Required dependencies: CLIAMP 1.63.2+, curl, FFmpeg/ffprobe, GJS, GLib/gdbus, and a systemd user session. The GJS bridge publishes enriched track metadata and artwork through MPRIS."
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    SelectionSetting {
        settingKey: "barPreviewMode"
        label: "DankBar preview"
        description: "Choose a minimal status icon or add current radio information."
        options: [
            { label: "Icon only", value: "icon" },
            { label: "Track title", value: "track" },
            { label: "Station and track", value: "stationTrack" }
        ]
        defaultValue: "icon"
    }

    StringSetting {
        settingKey: "maxTitleWidth"
        label: "Maximum preview width"
        description: "Maximum text width for Track title and Station and track modes (minimum 80 pixels)."
        placeholder: "180"
        defaultValue: "180"
    }

    StringSetting {
        settingKey: "closedPollMs"
        label: "Background refresh interval"
        description: "Status polling interval while the popout is closed, in milliseconds (minimum 1000)."
        placeholder: "3000"
        defaultValue: "3000"
    }

    StringSetting {
        settingKey: "openPollMs"
        label: "Open refresh interval"
        description: "Status polling interval while the popout is open, in milliseconds (minimum 500)."
        placeholder: "1000"
        defaultValue: "1000"
    }

    SliderSetting {
        settingKey: "mprisLatencyCompensationMs"
        label: "MPRIS audio latency compensation"
        description: "Delay the published playback position until synchronized lyrics match the audible line. Use 0 to disable."
        minimum: 0
        maximum: 5000
        unit: " ms"
        defaultValue: 2500
    }

    ToggleSetting {
        settingKey: "showVisualizer"
        label: "Show live visualizer"
        description: "Show CLIAMP's live 10-band spectrum in the Playing tab. The stream runs only while that tab is open."
        defaultValue: true
    }

    SliderSetting {
        settingKey: "visualizerHeight"
        label: "Visualizer height"
        description: "Minimum height; the visualizer expands to use free space in the Playing tab."
        minimum: 48
        maximum: 140
        unit: "px"
        defaultValue: 88
    }

    SliderSetting {
        settingKey: "visualizerFps"
        label: "Visualizer frame rate"
        description: "Updates per second, from 5 to 30. Lower values use less CPU."
        minimum: 5
        maximum: 30
        unit: " FPS"
        defaultValue: 20
    }

    StyledText {
        width: parent.width
        text: "Playback defaults"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    ToggleSetting {
        settingKey: "rememberPlaybackPreferences"
        label: "Remember last playback settings"
        description: "Restore values changed in the widget. Turn this off to apply only the configured defaults below."
        defaultValue: true
    }

    SelectionSetting {
        settingKey: "volumeDisplayMode"
        label: "Volume scale"
        description: "Show the Playing-tab volume control in decibels or as a 0–100% scale. Both control the same CLIAMP volume range."
        options: [
            { label: "Decibels", value: "db" },
            { label: "Percentage", value: "percent" }
        ]
        defaultValue: "db"
    }

    SliderSetting {
        settingKey: "defaultVolume"
        label: "Default volume (dB)"
        description: "Initial CLIAMP volume when no remembered value is used. -50 dB is the minimum and +6 dB is the maximum."
        minimum: -50
        maximum: 6
        unit: " dB"
        defaultValue: -12
    }

    SelectionSetting {
        settingKey: "defaultVisualizer"
        label: "Default visualizer"
        options: [
            { label: "Bars", value: "Bars" }, { label: "BarsDot", value: "BarsDot" },
            { label: "Rain", value: "Rain" }, { label: "BarsOutline", value: "BarsOutline" },
            { label: "Bricks", value: "Bricks" }, { label: "Columns", value: "Columns" },
            { label: "ClassicPeak", value: "ClassicPeak" }, { label: "Wave", value: "Wave" },
            { label: "Scatter", value: "Scatter" }, { label: "Flame", value: "Flame" },
            { label: "Retro", value: "Retro" }, { label: "Pulse", value: "Pulse" }
        ]
        defaultValue: "Bars"
    }

    SelectionSetting {
        settingKey: "defaultSpeed"
        label: "Default playback speed"
        options: [
            { label: "0.75×", value: "0.75" }, { label: "1.0×", value: "1.0" },
            { label: "1.25×", value: "1.25" }, { label: "1.5×", value: "1.5" },
            { label: "2.0×", value: "2.0" }
        ]
        defaultValue: "1.0"
    }

    SelectionSetting {
        settingKey: "defaultRepeat"
        label: "Default repeat mode"
        options: [
            { label: "Off", value: "off" },
            { label: "All", value: "all" },
            { label: "One", value: "one" }
        ]
        defaultValue: "off"
    }

    ToggleSetting { settingKey: "defaultShuffle"; label: "Shuffle by default"; defaultValue: false }
    ToggleSetting { settingKey: "defaultMono"; label: "Mono by default"; defaultValue: false }

    StringSetting {
        settingKey: "customEqPresets"
        label: "Custom equalizer presets"
        description: "JSON list of named 10-band presets. Values are clamped from -12 to +12 dB."
        placeholder: '[{"name":"Warm","bands":[4,3,2,1,0,0,1,2,2,1]}]'
        defaultValue: "[]"
    }

    StringSetting {
        settingKey: "terminal"
        label: "Preferred terminal"
        description: "Optional executable used for terminal-mode CLIAMP and the interactive provider setup, such as kitty or foot."
        placeholder: "Auto-detect"
        defaultValue: ""
    }

    StyledText {
        width: parent.width
        text: "CLIAMP launch mode"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    ToggleSetting {
        settingKey: "launchInBackground"
        label: "Launch CLIAMP in background"
        description: "Off opens the complete CLIAMP TUI in a terminal. On starts the plugin-managed headless service without a terminal. Read the mode details below before enabling it."
        defaultValue: false
    }

    StyledText {
        width: parent.width
        text: "Terminal / foreground mode"
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Full CLIAMP TUI; trusted Lua radio bridge; real queue listing and exact queue jumping; CLIAMP and DMS visualizer styles stay synchronized; native stream metadata plus plugin enrichment. Requires a supported terminal."
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    StyledText {
        width: parent.width
        text: "Background / headless mode"
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "No terminal or TUI. Runs as cliamp-dms-background.service and survives DMS restarts. CLIAMP does not load Lua plugins, expose its full queue, support exact queue jumps, or accept its TUI visualizer command. Selecting a radio station restarts the managed daemon with that one stream, so the prior queue is replaced."
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    StyledText {
        width: parent.width
        text: "Plugin workarounds: remembered volume is passed at startup; the DMS visualizer style is stored and rendered locally; ffprobe polls ICY metadata; iTunes lookup adds matching album artwork; the GJS bridge publishes enriched MPRIS metadata and forwards media controls. Metadata and artwork may appear after a short delay and depend on station/API quality."
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    StringSetting {
        settingKey: "launchProvider"
        label: "Launch provider"
        description: "Provider used by the offline Launch CLIAMP action. It can also be selected in the Providers tab."
        placeholder: "radio"
        defaultValue: "radio"
    }

    StringSetting {
        settingKey: "radioLimit"
        label: "Radio result limit"
        description: "Number of Radio Browser results, between 5 and 100."
        placeholder: "30"
        defaultValue: "30"
    }

    StringSetting {
        settingKey: "radioCountry"
        label: "Radio country filter"
        description: "Optional country name used to narrow Radio Browser results."
        placeholder: "Egypt"
        defaultValue: ""
    }

    StringSetting {
        settingKey: "radioLanguage"
        label: "Radio language filter"
        description: "Optional language used to narrow Radio Browser results."
        placeholder: "Arabic"
        defaultValue: ""
    }
}
