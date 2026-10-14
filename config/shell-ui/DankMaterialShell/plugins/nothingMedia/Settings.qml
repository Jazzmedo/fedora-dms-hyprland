import QtQuick
import qs.Common
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "nothingMedia"

    SelectionSetting {
        settingKey: "themeMode"
        label: "Theme"
        description: "DMS follows the shell palette in light and dark; Dark and Light are the pure Nothing card colors."

        options: [
            { label: "DMS (auto)", value: "dms" },
            { label: "Dark", value: "dark" },
            { label: "Light", value: "light" }
        ]

        defaultValue: "dark"
    }

    SelectionSetting {
        settingKey: "background"
        label: "Background"
        description: "Card draws the Nothing card behind everything; Transparent floats the player on the wallpaper (the red panel stays)."

        options: [
            { label: "Card", value: "card" },
            { label: "Transparent", value: "transparent" }
        ]

        defaultValue: "card"
    }

    SelectionSetting {
        settingKey: "accentColorSource"
        label: "Accent Color"
        description: "Colors the panel, ring and progress."

        options: [
            { label: "Nothing Red", value: "custom" },
            { label: "DMS Primary", value: "primary" },
            { label: "DMS Secondary", value: "secondary" }
        ]

        defaultValue: "custom"
    }

    ColorSetting {
        settingKey: "accentCustomColor"
        label: "Custom Accent Color"
        visible: pluginData.accentColorSource === "custom" || pluginData.accentColorSource === undefined
        defaultValue: "#D71921"
    }
}
