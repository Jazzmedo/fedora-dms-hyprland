pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.UPower
import qs.Common
import qs.Modules.Plugins

// NothingOS desktop widgets: media player, weather, battery, calendar and
// date, switchable through the widget's Style setting. Designs follow
// jaxparrow07/nothing-kde-widgets (GPL-3.0) and the KWGT layouts of
// AumGupta/KWGT-Widgets (MIT); this implementation is original QML.
DesktopPluginComponent {
    id: root

    minWidth: 300
    minHeight: 200

    property string style: pluginData.style ?? "media"

    // "dms" follows the shell palette (automatic light/dark); "dark" and
    // "light" are the pure Nothing card looks.
    property string themeMode: pluginData.themeMode ?? "dark"
    readonly property bool useDms: themeMode === "dms"
    readonly property bool isLight: themeMode === "light"

    // Nothing card palette — white on black, or the inverse in light mode.
    readonly property color colorBg: useDms ? Theme.surfaceContainer
                                 : isLight ? "#FFFFFF" : "#000000"
    readonly property color colorBorder: useDms ? Theme.outline
                                   : isLight ? "#E0E0E0" : "#1A1A1A"
    readonly property color colorPrimary: useDms ? Theme.primary
                                        : isLight ? "#000000" : "#FFFFFF"
    readonly property color colorSecondary: useDms ? Theme.secondary
                                          : isLight ? "#6B6B6B" : "#808080"
    readonly property color colorSurface: useDms ? Theme.surfaceContainerHigh
                                        : isLight ? "#F0F0F0" : "#141414"

    property string accentColorSource: pluginData.accentColorSource ?? "custom"
    property color customAccentColor: pluginData.accentCustomColor ?? "#D71921"
    readonly property color colorAccent:
        accentColorSource === "primary" ? Theme.primary :
        accentColorSource === "secondary" ? Theme.secondary :
        customAccentColor

    property real backgroundOpacity: (pluginData.backgroundOpacity ?? 100) / 100

    // Weather settings (open-meteo; no API key needed).
    property string latitude: pluginData.latitude ?? "30.0444"
    property string longitude: pluginData.longitude ?? "31.2357"
    property bool imperial: (pluginData.units ?? "metric") === "imperial"

    FontLoader {
        id: dotoFont
        source: Qt.resolvedUrl("Doto-Bold.ttf")
    }

    readonly property string dotFont:
        dotoFont.status === FontLoader.Ready ? dotoFont.name : "monospace"

    SystemClock {
        id: systemClock
        precision: SystemClock.Minutes
    }

    readonly property string dateText:
        systemClock.date
        ? systemClock.date.toLocaleDateString(Qt.locale(), "ddd, MMM d").toUpperCase()
        : ""
    readonly property string dayText:
        systemClock.date ? systemClock.date.toLocaleDateString(Qt.locale(), "dddd").toUpperCase() : ""
    readonly property string timeText:
        systemClock.date ? systemClock.date.toLocaleTimeString(Qt.locale(), "HH:mm") : "--:--"

    component Label: Text {
        font.family: root.dotFont
        font.letterSpacing: 1
        color: root.colorSecondary
    }

    // One shared card: background, border, then the style's content.
    Rectangle {
        anchors.fill: parent
        radius: Theme.cornerRadius * 2
        color: Qt.rgba(root.colorBg.r, root.colorBg.g, root.colorBg.b, root.backgroundOpacity)
        border.width: 1
        border.color: Qt.rgba(root.colorBorder.r, root.colorBorder.g, root.colorBorder.b, root.backgroundOpacity)
    }

    Loader {
        anchors.fill: parent
        anchors.margins: 18

        sourceComponent:
            root.style === "weather" ? weatherStyle :
            root.style === "battery" ? batteryStyle :
            root.style === "calendar" ? calendarStyle :
            root.style === "datetime" ? dateTimeStyle :
            mediaStyle
    }

    // ─── Media ────────────────────────────────────────────────────────────
    // MPRIS through Quickshell: first playing player, else the first one.
    readonly property var player: {
        const players = Mpris.players.values
        if (!players || players.length === 0) return null
        for (let i = 0; i < players.length; i++)
            if (players[i].playbackState === Mpris.PlaybackState.Playing)
                return players[i]
        return players[0]
    }

    readonly property string trackTitle: player?.trackTitle ?? ""
    readonly property string trackArtist: player?.trackArtist ?? ""
    readonly property string trackAlbum: player?.trackAlbum ?? ""
    readonly property string artUrl: player?.trackArtUrl ?? ""
    readonly property bool isPlaying: player?.playbackState === Mpris.PlaybackState.Playing
    readonly property real trackLength: player?.length ?? 0
    readonly property real trackPosition: player?.position ?? 0

    Component {
        id: mediaStyle

        Item {
            anchors.fill: parent

            Column {
                anchors.fill: parent
                spacing: 10

                Row {
                    spacing: 12
                    width: parent.width

                    // Album art, or a Nothing-red placeholder tile.
                    Rectangle {
                        width: 84
                        height: 84
                        radius: 12
                        color: root.colorSurface
                        clip: true

                        Image {
                            anchors.fill: parent
                            source: root.artUrl
                            fillMode: Image.PreserveAspectCrop
                            visible: root.artUrl !== ""
                            asynchronous: true
                        }

                        Label {
                            anchors.centerIn: parent
                            visible: root.artUrl === ""
                            text: "♪"
                            font.pixelSize: 30
                            color: root.colorAccent
                        }
                    }

                    Column {
                        width: parent.width - 84 - 12
                        spacing: 4
                        anchors.verticalCenter: parent.verticalCenter

                        Text {
                            width: parent.width
                            text: root.trackTitle !== "" ? root.trackTitle : "Nothing playing"
                            font.pixelSize: 15
                            font.bold: true
                            elide: Text.ElideRight
                            color: root.colorPrimary
                        }

                        Text {
                            width: parent.width
                            text: root.trackArtist !== "" ? root.trackArtist : "open a player to begin"
                            font.pixelSize: 12
                            elide: Text.ElideRight
                            color: root.colorSecondary
                        }

                        Label {
                            text: root.isPlaying ? "PLAYING" : "PAUSED"
                            font.pixelSize: 10
                            color: root.colorAccent
                        }
                    }
                }

                // Progress — position over length, filled in accent.
                Item {
                    width: parent.width
                    height: 4
                    visible: root.trackLength > 0

                    Rectangle {
                        anchors.fill: parent
                        radius: 2
                        color: root.colorSurface
                    }

                    Rectangle {
                        width: parent.width * Math.min(1, root.trackLength > 0 ? root.trackPosition / root.trackLength : 0)
                        height: parent.height
                        radius: 2
                        color: root.colorAccent
                    }
                }

                Row {
                    spacing: 26
                    anchors.horizontalCenter: parent.horizontalCenter

                    component MediaButton: Rectangle {
                        id: btn

                        required property string glyph
                        required property bool enabledAction
                        signal activated()

                        width: 40
                        height: 32
                        radius: 8
                        color: mouse.containsMouse ? root.colorSurface : "transparent"
                        border.width: 1
                        border.color: root.colorBorder
                        opacity: enabledAction ? 1 : 0.35

                        Label {
                            anchors.centerIn: parent
                            text: btn.glyph
                            font.pixelSize: 14
                            color: root.colorPrimary
                        }

                        MouseArea {
                            id: mouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: btn.enabledAction && btn.activated()
                        }
                    }

                    MediaButton {
                        glyph: "⏮"
                        enabledAction: root.player?.canGoPrevious ?? false
                        onActivated: root.player?.previous()
                    }
                    MediaButton {
                        glyph: root.isPlaying ? "⏸" : "▶"
                        enabledAction: root.isPlaying ? (root.player?.canPause ?? false) : (root.player?.canPlay ?? false)
                        onActivated: root.isPlaying ? root.player?.pause() : root.player?.play()
                    }
                    MediaButton {
                        glyph: "⏭"
                        enabledAction: root.player?.canGoNext ?? false
                        onActivated: root.player?.next()
                    }
                }
            }
        }
    }

    // ─── Weather ──────────────────────────────────────────────────────────
    property var weatherData: null

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

    Timer {
        running: root.style === "weather"
        repeat: true
        interval: 15 * 60 * 1000
        triggeredOnStart: true
        onTriggered: {
            const url = "https://api.open-meteo.com/v1/forecast?latitude=" + root.latitude
                + "&longitude=" + root.longitude
                + "&current=temperature_2m,weather_code"
                + (root.imperial ? "&temperature_unit=fahrenheit" : "")
            const xhr = new XMLHttpRequest()
            xhr.open("GET", url)
            xhr.onreadystatechange = function() {
                if (xhr.readyState !== XMLHttpRequest.DONE) return
                try { root.weatherData = JSON.parse(xhr.responseText).current } catch (e) {}
            }
            xhr.send()
        }
    }

    Component {
        id: weatherStyle

        Item {
            anchors.fill: parent

            Column {
                anchors.centerIn: parent
                spacing: 8

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.weatherData
                        ? Math.round(root.weatherData.temperature_2m) + "°"
                        : "--°"
                    font.family: root.dotFont
                    font.pixelSize: Math.min(parent.width * 0.32, root.height * 0.42)
                    color: root.colorPrimary
                }

                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.weatherData ? root.weatherLabel(root.weatherData.weather_code) : "NO DATA"
                    font.pixelSize: 13
                    color: root.colorAccent
                }

                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.dateText
                    font.pixelSize: 11
                }
            }
        }
    }

    // ─── Battery ──────────────────────────────────────────────────────────
    readonly property var battery: UPower.displayDevice ?? null
    readonly property real batteryPct: {
        if (!battery) return 0
        const p = battery.percentage
        return p <= 1 ? p * 100 : p
    }
    readonly property bool batteryCharging:
        battery ? battery.state === UPowerDeviceState.Charging
                || battery.state === UPowerDeviceState.FullyCharged : false

    Component {
        id: batteryStyle

        Item {
            anchors.fill: parent

            Column {
                anchors.centerIn: parent
                spacing: 8

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Math.round(root.batteryPct) + "%"
                    font.family: root.dotFont
                    font.pixelSize: Math.min(parent.width * 0.32, root.height * 0.42)
                    color: root.batteryPct <= 15 && !root.batteryCharging
                           ? root.colorAccent : root.colorPrimary
                }

                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.batteryCharging ? "CHARGING" : "ON BATTERY"
                    font.pixelSize: 13
                    color: root.batteryCharging ? root.colorAccent : root.colorSecondary
                }

                // Segmented charge bar — ten blocks, filled in accent.
                Row {
                    spacing: 4
                    anchors.horizontalCenter: parent.horizontalCenter

                    Repeater {
                        model: 10

                        Rectangle {
                            required property int index

                            width: 16
                            height: 8
                            radius: 2
                            color: index < Math.round(root.batteryPct / 10)
                                   ? root.colorAccent : root.colorSurface
                            border.width: 1
                            border.color: root.colorBorder
                        }
                    }
                }
            }
        }
    }

    // ─── Calendar ─────────────────────────────────────────────────────────
    // Mini month grid in the style of KWGT's Nothing Mini Calender.
    readonly property int today: systemClock.date ? systemClock.date.getDate() : 0
    readonly property int monthStartDow: {
        if (!systemClock.date) return 0
        const d = new Date(systemClock.date.getFullYear(), systemClock.date.getMonth(), 1)
        return d.getDay()
    }
    readonly property int daysInMonth: {
        if (!systemClock.date) return 30
        return new Date(systemClock.date.getFullYear(),
                        systemClock.date.getMonth() + 1, 0).getDate()
    }
    readonly property string monthName:
        systemClock.date ? systemClock.date.toLocaleDateString(Qt.locale(), "MMMM").toUpperCase() : ""

    component CalendarCell: Item {
        required property int dayNumber
        required property bool isToday

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width, parent.height) * 0.86
            height: width
            radius: width / 2
            color: parent.isToday ? root.colorAccent : "transparent"
        }

        Label {
            anchors.centerIn: parent
            text: dayNumber
            font.pixelSize: 10
            font.family: root.dotFont
            color: parent.isToday ? "#FFFFFF" : root.colorSecondary
        }
    }

    Component {
        id: calendarStyle

        Item {
            anchors.fill: parent

            Column {
                anchors.fill: parent
                spacing: 6

                Row {
                    spacing: 8

                    Text {
                        text: root.monthName
                        font.family: root.dotFont
                        font.pixelSize: 16
                        font.letterSpacing: 2
                        color: root.colorPrimary
                    }

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: timeLabel.implicitWidth + 10
                        height: timeLabel.implicitHeight + 4
                        radius: 5
                        color: root.colorAccent

                        Label {
                            id: timeLabel
                            anchors.centerIn: parent
                            text: root.timeText
                            font.pixelSize: 10
                            color: "#FFFFFF"
                        }
                    }
                }

                Grid {
                    id: grid
                    width: parent.width
                    height: parent.height - 30
                    columns: 7
                    spacing: 2

                    Repeater {
                        model: 7

                        Label {
                            required property int index

                            text: ["S", "M", "T", "W", "T", "F", "S"][index]
                            font.pixelSize: 10
                            horizontalAlignment: Text.AlignHCenter
                            width: grid.width / 7 - 2
                            height: grid.height / 6 - 2
                        }
                    }

                    Repeater {
                        model: root.monthStartDow

                        Item {
                            width: grid.width / 7 - 2
                            height: grid.height / 6 - 2
                        }
                    }

                    Repeater {
                        model: root.daysInMonth

                        CalendarCell {
                            required property int index

                            dayNumber: index + 1
                            isToday: index + 1 === root.today
                            width: grid.width / 7 - 2
                            height: grid.height / 6 - 2
                        }
                    }
                }
            }
        }
    }

    // ─── Date & Time ──────────────────────────────────────────────────────
    Component {
        id: dateTimeStyle

        Item {
            anchors.fill: parent

            Column {
                anchors.centerIn: parent
                spacing: 6

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.timeText
                    font.family: root.dotFont
                    font.pixelSize: Math.min(parent.width * 0.26, root.height * 0.32)
                    color: root.colorPrimary
                }

                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.dayText
                    font.pixelSize: 13
                    color: root.colorAccent
                }

                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.dateText
                    font.pixelSize: 11
                }
            }
        }
    }
}
