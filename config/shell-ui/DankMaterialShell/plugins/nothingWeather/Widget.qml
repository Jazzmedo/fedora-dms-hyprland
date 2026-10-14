pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import qs.Common
import qs.Modules.Plugins

// NothingOS weather: giant dot-matrix temperature, condition pill and a
// hi/lo row, with a dot-styled icon recolored from the palette. Layout after
// jaxparrow07/nothing-kde-widgets (GPL-3.0) and AumGupta/KWGT-Widgets'
// Nothing Temp (MIT). Data: open-meteo.com, no API key. Square widgets get a
// column layout; anything wider than 1.6x its height switches to a row.
DesktopPluginComponent {
    id: root

    minWidth: 180
    minHeight: 140
    defaultWidth: 240
    defaultHeight: 200
    resizable: true

    property string themeMode: pluginData.themeMode ?? "dark"
    property string backgroundMode: pluginData.background ?? "card"
    property string accentColorSource: pluginData.accentColorSource ?? "custom"
    property color customAccentColor: pluginData.accentCustomColor ?? "#D71921"
    property string location: pluginData.location ?? "Cairo"
    property string units: pluginData.units ?? "metric"

    readonly property bool useDms: themeMode === "dms"
    readonly property bool isLight: themeMode === "light"
    readonly property color cBg: useDms ? Theme.hostSurface : isLight ? "#F5F5F5" : "#1B1B1D"
    readonly property color cPrimary: useDms ? Theme.primary : isLight ? "#1A1A1A" : "#FFFFFF"
    readonly property color cSecondary: useDms ? Theme.secondary : isLight ? "#666666" : "#AAAAAA"
    readonly property color cAccent:
        accentColorSource === "primary" ? Theme.primary :
        accentColorSource === "secondary" ? Theme.secondary : customAccentColor

    readonly property bool isWide: width >= height * 1.6
    readonly property bool isLoading: forecast === null

    FontLoader {
        id: ndotFont
        source: Qt.resolvedUrl("fonts/ndot-47.ttf")
    }

    readonly property string dotFont:
        ndotFont.status === FontLoader.Ready ? ndotFont.name : "monospace"

    // ─── Open-meteo ───────────────────────────────────────────────────────
    property var forecast: null
    property var coords: null

    function weatherLabel(code) {
        if (code === 0) return "CLEAR"
        if (code <= 2) return "CLOUDY"
        if (code === 3) return "OVERCAST"
        if (code <= 48) return "FOG"
        if (code <= 57) return "DRIZZLE"
        if (code <= 67) return "RAIN"
        if (code <= 77) return "SNOW"
        if (code <= 82) return "SHOWERS"
        if (code <= 86) return "SNOW"
        return "STORM"
    }

    function iconName(code, isDay) {
        let base
        if (code === 0) base = "sunny"
        else if (code <= 2) base = "partly_cloudy_day"
        else if (code === 3 || code <= 48) base = "cloudy"
        else if (code <= 67) base = "rain_or_mist"
        else if (code <= 77) base = "snow_fall"
        else if (code <= 82) base = "rain_or_mist"
        else if (code <= 86) base = "snow_fall"
        else base = "thunder"
        if (base === "sunny" && isDay === false) base = "cloudy"
        if (base === "partly_cloudy_day" && isDay === false) base = "partly_cloudy_night"
        return base + ".svg"
    }

    function resolveCoords() {
        const loc = location.trim()
        if (/^-?\d+(\.\d+)?\s*,\s*-?\d+(\.\d+)?$/.test(loc)) {
            const parts = loc.split(",")
            return { lat: parts[0].trim(), lon: parts[1].trim() }
        }
        return null
    }

    function fetchWeather() {
        const unit = units === "imperial" ? "&temperature_unit=fahrenheit" : ""
        const go = (lat, lon) => {
            const xhr = new XMLHttpRequest()
            xhr.open("GET", "https://api.open-meteo.com/v1/forecast?latitude=" + lat
                     + "&longitude=" + lon
                     + "&current=temperature_2m,weather_code,is_day"
                     + "&daily=temperature_2m_max,temperature_2m_min"
                     + "&forecast_days=1" + unit)
            xhr.onreadystatechange = function() {
                if (xhr.readyState !== XMLHttpRequest.DONE) return
                try { forecast = JSON.parse(xhr.responseText) } catch (e) {}
            }
            xhr.send()
        }
        const fixed = resolveCoords()
        if (fixed) { go(fixed.lat, fixed.lon); return }
        const geocode = new XMLHttpRequest()
        geocode.open("GET", "https://geocoding-api.open-meteo.com/v1/search?name="
                     + encodeURIComponent(location) + "&count=1")
        geocode.onreadystatechange = function() {
            if (geocode.readyState !== XMLHttpRequest.DONE) return
            try {
                const hit = JSON.parse(geocode.responseText).results?.[0]
                if (hit) go(hit.latitude, hit.longitude)
            } catch (e) {}
        }
        geocode.send()
    }

    Timer {
        running: true
        repeat: true
        interval: 30 * 60 * 1000
        triggeredOnStart: true
        onTriggered: root.fetchWeather()
    }

    Connections {
        function onLocationChanged() { root.fetchWeather() }
        function onUnitsChanged() { root.fetchWeather() }
        target: root
    }

    readonly property real curTemp:
        forecast ? Math.round(forecast.current.temperature_2m) : 0
    readonly property string condition:
        forecast ? weatherLabel(forecast.current.weather_code) : "···"
    readonly property real tempHi:
        forecast ? Math.round(forecast.daily.temperature_2m_max[0]) : 0
    readonly property real tempLo:
        forecast ? Math.round(forecast.daily.temperature_2m_min[0]) : 0
    readonly property string iconFile:
        forecast ? iconName(forecast.current.weather_code,
                            forecast.current.is_day === 1)
                 : "cloudy.svg"

    // ─── Card ─────────────────────────────────────────────────────────────
    Rectangle {
        visible: root.backgroundMode === "card"
        anchors.fill: parent
        radius: Math.min(width, height) * 0.12
        color: root.cBg
        opacity: 0.95
    }

    // ─── Content ──────────────────────────────────────────────────────────
    component ConditionPill: Rectangle {
        radius: height / 2
        color: "transparent"
        border.width: 1
        border.color: root.cAccent

        Text {
            anchors.centerIn: parent
            text: root.condition
            font.family: root.dotFont
            font.pixelSize: parent.height * 0.42
            font.letterSpacing: 1
            color: root.cAccent
        }
    }

    component HiLoRow: Text {
        text: "↑ " + root.tempHi + "°   ↓ " + root.tempLo + "°"
        font.family: root.dotFont
        font.pixelSize: Math.max(10, root.height * 0.09)
        color: root.cSecondary
    }

    component WeatherIcon: Item {
        Image {
            id: raw
            anchors.fill: parent
            source: Qt.resolvedUrl("icons/" + root.iconFile)
            sourceSize: Qt.size(width, height)
            fillMode: Image.PreserveAspectFit
            visible: false
            asynchronous: true
        }

        MultiEffect {
            anchors.fill: parent
            source: raw
            colorization: 1
            colorizationColor: root.cPrimary
        }
    }

    Row {
        visible: root.isWide
        anchors.centerIn: parent
        spacing: width * 0.06

        WeatherIcon {
            width: root.height * 0.55
            height: root.height * 0.55
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            text: root.curTemp + "°"
            font.family: root.dotFont
            font.pixelSize: root.height * 0.62
            color: root.cPrimary
            anchors.verticalCenter: parent.verticalCenter
        }

        Column {
            spacing: root.height * 0.05
            anchors.verticalCenter: parent.verticalCenter

            ConditionPill {
                width: root.width * 0.22
                height: root.height * 0.2
            }

            HiLoRow {}
        }
    }

    Column {
        visible: !root.isWide
        anchors.centerIn: parent
        spacing: parent.height * 0.05

        Item {
            width: parent.width
            height: root.height * 0.38

            WeatherIcon {
                width: height
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: tempText.left
                anchors.rightMargin: parent.width * 0.06
                height: parent.height * 0.9
            }

            Text {
                id: tempText
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.isLoading ? "--°" : root.curTemp + "°"
                font.family: root.dotFont
                font.pixelSize: root.height * 0.95
                color: root.cPrimary
            }
        }

        ConditionPill {
            width: parent.width * 0.7
            height: root.height * 0.14
            anchors.horizontalCenter: parent.horizontalCenter
        }

        HiLoRow {
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }
}
