pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Modules.Plugins

// NothingOS 5-day calendar strip: two days back to two days forward, today
// rendered as an inverted card with the Nothing dot beneath the date. The
// farthest days sit at half opacity. Layout after AumGupta/KWGT-Widgets'
// Nothing Mini Calender (MIT, © Om Gupta).
DesktopPluginComponent {
    id: root

    minWidth: 300
    minHeight: 90
    defaultWidth: 380
    defaultHeight: 110

    property string themeMode: pluginData.themeMode ?? "dark"
    property string backgroundMode: pluginData.background ?? "card"

    readonly property bool useDms: themeMode === "dms"
    readonly property bool isLight: themeMode === "light"
    readonly property color cBg: useDms ? Theme.hostSurface : isLight ? "#F5F5F5" : "#1B1B1D"
    readonly property color cPrimary: useDms ? Theme.primary : isLight ? "#1A1A1A" : "#FFFFFF"
    readonly property color cSecondary: useDms ? Theme.secondary : isLight ? "#666666" : "#AAAAAA"
    readonly property color cAccent: "#D71921"

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

    component DayColumn: Column {
        id: col

        required property int offset
        readonly property date day: {
            const d = new Date(root.now)
            d.setDate(d.getDate() + offset)
            return d
        }
        readonly property bool isToday: offset === 0

        width: strip.width / 5
        height: strip.height
        spacing: height * 0.05
        opacity: Math.abs(offset) === 2 ? 0.5 : 1

        // Today carries its own inverted card; the other days sit on nothing.
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: col.width * 0.86
            height: parent.height
            radius: width * 0.18
            color: col.isToday ? (root.isLight ? "#1B1B1D" : "#FFFFFF") : "transparent"

            Column {
                anchors.centerIn: parent
                spacing: col.height * 0.04

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Qt.formatDate(col.day, "EEE").toUpperCase()
                    font.family: root.dotFont
                    font.pixelSize: col.width * 0.15
                    color: col.isToday ? (root.isLight ? "#FFFFFF" : "#1B1B1D") : root.cPrimary
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Qt.formatDate(col.day, "dd")
                    font.family: root.dotFont
                    font.pixelSize: col.width * 0.3
                    color: col.isToday ? (root.isLight ? "#FFFFFF" : "#1B1B1D") : root.cPrimary
                }

                // The Nothing dot — only under today's number.
                Rectangle {
                    visible: col.isToday
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: col.width * 0.07
                    height: width
                    radius: width / 2
                    color: root.cAccent
                }
            }
        }
    }

    Rectangle {
        visible: root.backgroundMode === "card"
        anchors.fill: parent
        radius: Math.min(width, height) * 0.2
        color: root.cBg
        opacity: 0.95
    }

    Row {
        id: strip
        anchors.fill: parent

        DayColumn { offset: -2 }
        DayColumn { offset: -1 }
        DayColumn { offset: 0 }
        DayColumn { offset: 1 }
        DayColumn { offset: 2 }
    }
}
