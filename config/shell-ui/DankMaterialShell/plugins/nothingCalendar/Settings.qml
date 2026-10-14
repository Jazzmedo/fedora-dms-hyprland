import QtQuick
import qs.Common
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "nothingCalendar"

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

        options: [
            { label: "Card", value: "card" },
            { label: "Transparent", value: "transparent" }
        ]

        defaultValue: "card"
    }
}
