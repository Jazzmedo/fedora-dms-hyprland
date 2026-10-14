pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.UPower
import qs.Common
import qs.Modules.Plugins

// NothingOS battery: a disc whose red conic sweep empties as the charge
// drops, percentage in the dot-matrix face, charging state beneath. Layout
// after AumGupta/KWGT-Widgets' Nothing Battery (MIT, © Om Gupta). On a
// machine without a battery it says so instead of showing a fake 0%.
DesktopPluginComponent {
    id: root

    minWidth: 140
    minHeight: 160
    defaultWidth: 200
    defaultHeight: 220
    forceSquare: false

    property string themeMode: pluginData.themeMode ?? "dark"
    property string backgroundMode: pluginData.background ?? "card"
    property string accentColorSource: pluginData.accentColorSource ?? "custom"
    property color customAccentColor: pluginData.accentCustomColor ?? "#D71921"

    readonly property bool useDms: themeMode === "dms"
    readonly property bool isLight: themeMode === "light"
    readonly property color cBg: useDms ? Theme.hostSurface : isLight ? "#F5F5F5" : "#1B1B1D"
    readonly property color cSurface: useDms ? Theme.cardSurface : isLight ? "#FFFFFF" : "#2A2A2A"
    readonly property color cPrimary: useDms ? Theme.primary : isLight ? "#1A1A1A" : "#FFFFFF"
    readonly property color cSecondary: useDms ? Theme.secondary : isLight ? "#666666" : "#AAAAAA"
    readonly property color cAccent:
        accentColorSource === "primary" ? Theme.primary :
        accentColorSource === "secondary" ? Theme.secondary : customAccentColor

    readonly property var battery: UPower.displayDevice ?? null
    readonly property bool hasBattery: battery !== null
    readonly property real pct: {
        if (!battery) return 0
        const p = battery.percentage
        return Math.max(0, Math.min(100, p <= 1 ? p * 100 : p))
    }
    readonly property bool charging: battery
        && (battery.state === UPowerDeviceState.Charging
            || battery.state === UPowerDeviceState.FullyCharged)
    readonly property bool low: pct <= 20 && !charging

    FontLoader {
        id: ndotFont
        source: Qt.resolvedUrl("fonts/ndot-47.ttf")
    }

    readonly property string dotFont:
        ndotFont.status === FontLoader.Ready ? ndotFont.name : "monospace"

    // ─── Card ─────────────────────────────────────────────────────────────
    Rectangle {
        visible: root.backgroundMode === "card"
        anchors.fill: parent
        radius: Math.min(width, height) * 0.12
        color: root.cBg
        opacity: 0.95
    }

    // ─── The gauge ────────────────────────────────────────────────────────
    Canvas {
        id: gauge

        readonly property real discSize: Math.min(root.width, root.height * 0.72) * 0.66

        width: discSize
        height: discSize
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -parent.height * 0.04

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const cx = width / 2, cy = height / 2, r = width / 2

            // Disc base.
            ctx.beginPath()
            ctx.arc(cx, cy, r, 0, Math.PI * 2)
            ctx.fillStyle = root.cSurface
            ctx.fill()

            // Red sweep, from 12 o'clock, shrinking with the charge. Canvas
            // conic gradients need a visible stop right at the sweep edge or
            // the last arc bleeds anti-aliased pixels.
            if (root.pct > 0) {
                const sweep = root.pct / 100
                const grad = ctx.createConicGradient(-Math.PI / 2, cx, cy)
                grad.addColorStop(0, root.cAccent)
                grad.addColorStop(Math.max(0.001, sweep), root.cAccent)
                grad.addColorStop(Math.min(1, sweep + 0.001), "transparent")
                grad.addColorStop(1, "transparent")
                ctx.beginPath()
                ctx.arc(cx, cy, r, 0, Math.PI * 2)
                ctx.fillStyle = grad
                ctx.fill()
            }

            // Inner disc returns to the card color; the sweep reads as a
            // ring and the percentage stays legible over either color.
            ctx.beginPath()
            ctx.arc(cx, cy, r * 0.74, 0, Math.PI * 2)
            ctx.fillStyle = root.cBg
            ctx.fill()
        }

        Connections {
            function onPctChanged() { gauge.requestPaint() }
            function onChargingChanged() { gauge.requestPaint() }
            function onThemeModeChanged() { gauge.requestPaint() }
            function onAccentColorSourceChanged() { gauge.requestPaint() }
            target: root
        }

        Connections {
            function onWidthChanged() { gauge.requestPaint() }
            function onHeightChanged() { gauge.requestPaint() }
            target: gauge
        }

        Text {
            anchors.centerIn: parent
            text: root.hasBattery ? Math.round(root.pct) + "%" : "AC"
            font.family: root.dotFont
            font.pixelSize: gauge.width * 0.24
            color: root.cPrimary
        }
    }

    Text {
        id: stateLabel
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: parent.height * 0.08
        text: !root.hasBattery ? "NO BATTERY"
              : root.charging ? "CHARGING"
              : root.low ? "LOW" : "ON BATTERY"
        font.family: root.dotFont
        font.pixelSize: Math.max(10, root.height * 0.06)
        font.letterSpacing: 1
        color: !root.hasBattery ? root.cSecondary
             : (root.charging || root.low) ? root.cAccent : root.cSecondary
    }
}
