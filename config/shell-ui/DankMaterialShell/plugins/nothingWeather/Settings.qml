import QtQuick
import qs.Common
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "nothingWeather"

    StringSetting {
        settingKey: "location"
        label: "Location"
        description: "A city name (geocoded through open-meteo) or raw \"lat,lon\". Defaults to Cairo."
        placeholder: "Cairo"
        defaultValue: "Cairo"
    }

    SelectionSetting {
        settingKey: "units"
        label: "Temperature Units"

        options: [
            { label: "Celsius", value: "metric" },
            { label: "Fahrenheit", value: "imperial" }
        ]

        defaultValue: "metric"
    }

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

    SelectionSetting {
        settingKey: "accentColorSource"
        label: "Accent Color"
        description: "Colors the condition pill."

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
