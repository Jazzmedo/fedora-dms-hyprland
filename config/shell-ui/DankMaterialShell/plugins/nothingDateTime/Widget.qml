pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Modules.Plugins

// NothingOS date & time: a pure typographic card in the dot-matrix face —
// weekday, the time in Nothing red, month and the ordinal day. Layout after
// AumGupta/KWGT-Widgets' Nothing Date_Time (MIT, © Om Gupta).
DesktopPluginComponent {
    id: root

    minWidth: 200
    minHeight: 160
    defaultWidth: 240
    defaultHeight: 220

    property string themeMode: pluginData.themeMode ?? "dark"
    property string backgroundMode: pluginData.background ?? "card"
    property string accentColorSource: pluginData.accentColorSource ?? "custom"
    property color customAccentColor: pluginData.accentCustomColor ?? "#D71921"

    readonly property bool useDms: themeMode === "dms"
    readonly property bool isLight: themeMode === "light"
    readonly property color cBg: useDms ? Theme.hostSurface : isLight ? "#F5F5F5" : "#1B1B1D"
    readonly property color cPrimary: useDms ? Theme.primary : isLight ? "#1A1A1A" : "#FFFFFF"
    readonly property color cAccent:
        accentColorSource === "primary" ? Theme.primary :
        accentColorSource === "secondary" ? Theme.secondary : customAccentColor

    FontLoader {
        id: ndotFont
        source: Qt.resolvedUrl("fonts/ndot-47.ttf")
    }

    readonly property string dotFont:
        ndotFont.status === FontLoader.Ready ? ndotFont.name : "monospace"

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    readonly property date now: clock.date || new Date()
    readonly property string weekday: Qt.formatDate(now, "EEE").toUpperCase()
    readonly property string ampm: Qt.formatDate(now, "a").toUpperCase()
    readonly property string timeText: Qt.formatTime(now, "hh:mm")
    readonly property string monthName: Qt.formatDate(now, "MMMM").toUpperCase()
    readonly property int dayNum: now.getDate()

    function ordinal(n) {
        if (n % 100 >= 11 && n % 100 <= 13) return "TH"
        if (n % 10 === 1) return "ST"
        if (n % 10 === 2) return "ND"
        if (n % 10 === 3) return "RD"
        return "TH"
    }

    // Everything is a fraction of the card; the time is the largest line and
    // the whole stack centers at any shape the user drags the widget to.
    readonly property real unit: Math.min(width * 0.16, height * 0.115)

    Rectangle {
        visible: root.backgroundMode === "card"
        anchors.fill: parent
        radius: Math.min(width, height) * 0.12
        color: root.cBg
        opacity: 0.95
    }

    Column {
        anchors.left: parent.left
        anchors.leftMargin: parent.width * 0.09
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.unit * 0.12

        Text {
            text: root.weekday + " · " + root.ampm
            font.family: root.dotFont
            font.pixelSize: root.unit * 0.62
            font.letterSpacing: 1
            color: root.cPrimary
        }

        Text {
            text: root.timeText
            font.family: root.dotFont
            font.pixelSize: root.unit * 1.35
            color: root.cAccent
        }

        Text {
            text: root.monthName
            font.family: root.dotFont
            font.pixelSize: root.unit * 0.62
            font.letterSpacing: 1
            color: root.cPrimary
        }

        Text {
            text: root.dayNum + root.ordinal(root.dayNum)
            font.family: root.dotFont
            font.pixelSize: root.unit * 0.62
            font.letterSpacing: 1
            color: root.cPrimary
        }
    }
}
