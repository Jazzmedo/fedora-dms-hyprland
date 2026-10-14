import QtQuick
import qs.Common
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "nothingWidgets"

    SelectionSetting {
        settingKey: "style"
        label: "Widget"

        options: [
            { label: "Media Player", value: "media" },
            { label: "Weather", value: "weather" },
            { label: "Battery", value: "battery" },
            { label: "Calendar", value: "calendar" },
            { label: "Date & Time", value: "datetime" }
        ]

        defaultValue: "media"
    }

    SelectionSetting {
        settingKey: "themeMode"
        label: "Theme"
        description: "DMS follows the shell palette in both light and dark; Dark and Light are the pure Nothing card colors."

        options: [
            { label: "DMS (auto)", value: "dms" },
            { label: "Dark", value: "dark" },
            { label: "Light", value: "light" }
        ]

        defaultValue: "dark"
    }

    SelectionSetting {
        settingKey: "accentColorSource"
        label: "Accent Color"

        options: [
            { label: "DMS Primary", value: "primary" },
            { label: "DMS Secondary", value: "secondary" },
            { label: "Custom", value: "custom" }
        ]

        defaultValue: "custom"
    }

    ColorSetting {
        settingKey: "accentCustomColor"
        label: "Custom Accent Color"
        visible: pluginData.accentColorSource === "custom" || pluginData.accentColorSource === undefined
        defaultValue: "#D71921"
    }

    SliderSetting {
        settingKey: "backgroundOpacity"
        label: "Background Opacity"
        defaultValue: 100
        minimum: 0
        maximum: 100
        unit: "%"
    }

    // Weather-only settings.
    StringSetting {
        settingKey: "latitude"
        label: "Latitude"
        description: "Weather comes from open-meteo.com; only used by the Weather widget."
        defaultValue: "30.0444"
        visible: pluginData.style === "weather"
    }

    StringSetting {
        settingKey: "longitude"
        label: "Longitude"
        defaultValue: "31.2357"
        visible: pluginData.style === "weather"
    }

    SelectionSetting {
        settingKey: "units"
        label: "Temperature Units"
        options: [
            { label: "Celsius", value: "metric" },
            { label: "Fahrenheit", value: "imperial" }
        ]
        defaultValue: "metric"
        visible: pluginData.style === "weather"
    }
}
