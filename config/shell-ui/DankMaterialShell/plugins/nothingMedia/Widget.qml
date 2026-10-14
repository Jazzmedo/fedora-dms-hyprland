pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import qs.Common
import qs.Modules.Plugins

// NothingOS media player: album art on the left, the Nothing-red panel with
// the track title on the right, and a segmented progress ring riding the seam
// between them. Design after jaxparrow07/nothing-kde-widgets (GPL-3.0) and
// AumGupta/KWGT-Widgets' Media Player 3 (MIT). Everything scales from the
// widget's width/height; nothing is a fixed pixel size except hairlines.
DesktopPluginComponent {
    id: root

    minWidth: 260
    minHeight: 160
    defaultWidth: 340
    defaultHeight: 200

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

    FontLoader {
        id: ndotFont
        source: Qt.resolvedUrl("fonts/ndot-47.ttf")
    }

    readonly property string dotFont:
        ndotFont.status === FontLoader.Ready ? ndotFont.name : "monospace"

    // ─── MPRIS ────────────────────────────────────────────────────────────
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
    readonly property string artUrl: player?.trackArtUrl ?? ""
    readonly property bool isPlaying: player?.playbackState === Mpris.PlaybackState.Playing
    readonly property real trackLength: player?.length ?? 0

    // Position is interpolated locally (250 ms steps) so the ring moves
    // smoothly instead of jumping at the player's own update rate.
    property real interpPos: player?.position ?? 0

    Timer {
        running: root.isPlaying && root.trackLength > 0
        interval: 250
        repeat: true
        onTriggered: root.interpPos = Math.min(root.trackLength, root.interpPos + 250000)
    }

    Connections {
        target: root.player
        function onTrackTitleChanged() { root.interpPos = root.player?.position ?? 0 }
        function onPlaybackStateChanged() { root.interpPos = root.player?.position ?? 0 }
    }

    readonly property real progress:
        root.trackLength > 0 ? Math.min(1, root.interpPos / root.trackLength) : 0

    function togglePlay() {
        if (!root.player) return
        if (root.isPlaying) player.pause()
        else player.play()
    }

    // ─── Card ─────────────────────────────────────────────────────────────
    Rectangle {
        visible: root.backgroundMode === "card"
        anchors.fill: parent
        radius: Math.min(width, height) * 0.12
        color: root.cBg
        opacity: 0.95
        clip: true
    }

    // ─── Album art (left) ─────────────────────────────────────────────────
    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: parent.width * 0.55
        color: root.cSurface
        visible: root.backgroundMode === "card"
        clip: true

        Image {
            anchors.fill: parent
            source: root.artUrl
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
        }

        Label {
            anchors.centerIn: parent
            visible: root.artUrl === ""
            text: "♪"
            font.pixelSize: parent.width * 0.3
            color: root.cSecondary
        }
    }

    // ─── Red panel (right) ────────────────────────────────────────────────
    Rectangle {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: parent.width * 0.45
        color: root.cAccent
        radius: Math.min(width, height) * 0.12
        visible: root.backgroundMode === "card"
        clip: true

        Text {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: parent.width * 0.08
            width: parent.width * 0.82
            text: root.trackTitle !== "" ? root.trackTitle.toUpperCase() : "NOTHING PLAYING"
            font.family: root.dotFont
            font.pixelSize: Math.max(10, parent.height * 0.055)
            wrapMode: Text.Wrap
            color: "#FFFFFF"
        }

        Text {
            anchors.bottom: controlsRow.top
            anchors.right: parent.right
            anchors.margins: parent.width * 0.08
            width: parent.width * 0.82
            text: root.trackArtist
            font.pixelSize: Math.max(8, parent.height * 0.035)
            elide: Text.ElideRight
            color: Qt.rgba(1, 1, 1, 0.7)
        }

        Row {
            id: controlsRow
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottomMargin: parent.height * 0.08
            spacing: parent.width * 0.12

            component GlyphButton: Text {
                required property string glyph
                required property var action

                text: glyph
                font.pixelSize: root.height * 0.07
                color: "#FFFFFF"
                opacity: mouse.containsMouse ? 1 : 0.85

                MouseArea {
                    id: mouse
                    anchors.fill: parent
                    anchors.margins: -8
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: action()
                }
            }

            GlyphButton {
                glyph: "⏮"
                action: () => root.player?.previous()
            }
            GlyphButton {
                glyph: root.isPlaying ? "⏸" : "▶"
                action: () => root.togglePlay()
            }
            GlyphButton {
                glyph: "⏭"
                action: () => root.player?.next()
            }
        }
    }

    // When the card is hidden (transparent mode) the ring alone would float
    // oddly against wallpaper without any chrome, so the title and controls
    // stay on the panel — which is always drawn in accent red regardless.
    Rectangle {
        visible: root.backgroundMode !== "card"
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: parent.width * 0.45
        color: root.cAccent
        radius: Math.min(width, height) * 0.12
        clip: true
    }

    // ─── Segmented progress ring on the seam ──────────────────────────────
    Item {
        id: ring

        readonly property real ringSize: Math.min(parent.height, parent.width * 0.55) * 0.56

        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: parent.width * 0.55

        Rectangle {
            anchors.centerIn: parent
            width: ring.ringSize
            height: width
            radius: width / 2
            color: root.cBg
            border.width: 1
            border.color: root.backgroundMode === "card" ? root.cBg : root.cSurface
            visible: root.backgroundMode === "card"
        }

        Repeater {
            model: 60

            Item {
                required property int index

                anchors.centerIn: parent
                width: 0
                height: 0
                rotation: index * 6

                Rectangle {
                    readonly property bool filled: index < Math.round(root.progress * 60)

                    width: ring.ringSize * 0.055
                    height: ring.ringSize * 0.11
                    radius: width / 2
                    color: filled ? root.cAccent
                                  : Qt.rgba(root.cPrimary.r, root.cPrimary.g, root.cPrimary.b, 0.25)
                    x: -width / 2
                    y: -ring.ringSize / 2 + height * 0.6
                }
            }
        }

        Text {
            anchors.centerIn: parent
            text: root.trackLength > 0
                  ? Math.floor(root.interpPos / 60000) + ":" + ("0" + Math.floor(root.interpPos / 1000 % 60)).slice(-2)
                  : ""
            font.family: root.dotFont
            font.pixelSize: ring.ringSize * 0.17
            color: root.cPrimary
        }
    }
}
