import QtQuick
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    layerNamespacePlugin: "lyricsOnPanel"

    // Show a sleepy placeholder whenever there is no active lyric line.
    readonly property bool hasLyric: root.currentLyric.length > 0
    readonly property bool shouldShowLyric: playbackStatus === "playing" && hasLyric && !currentTrackIgnored

    // Config from pluginData (defaults match configGeneral.qml)
    property bool config_yesPlayMusicChecked: pluginData.playerMode === "yesplaymusic"
    property bool config_lxMusicChecked: pluginData.playerMode === "lxmusic"
    property bool config_spotifyChecked: pluginData.playerMode === "spotify"
    property bool config_compatibleModeChecked: pluginData.playerMode === "global"

    property int config_lyricTextSize: pluginData.lyricTextSize ?? 12
    property bool config_lyricTextBold: pluginData.lyricTextBold ?? false
    property bool config_lyricTextItalic: pluginData.lyricTextItalic ?? false
    property int config_lyricTextVerticalOffset: pluginData.lyricTextVerticalOffset ?? 1
    property int config_preferedWidgetWidth: pluginData.preferedWidgetWidth ?? 550
    property string config_ignoredTracks: String(pluginData.ignoredTracks ?? "")

    property int config_lxMusicPort: pluginData.lxMusicPort ?? 23330

    // Server config
    readonly property string serverHost: "127.0.0.1"
    readonly property int serverPort: 23560
    // The backend's HTTP port, for the plain-HTTP polling below.
    readonly property int httpPort: 23561

    // State
    property string playbackStatus: "stopped"
    property string currentLyric: ""
    property string currentPlayerIdentity: ""
    property string currentPlayerBusName: ""
    property string currentTitle: ""
    property string currentArtist: ""
    property string currentTrackUrl: ""
    property int positionMs: 0
    property bool hasActivePlayer: false
    property var availablePlayers: []
    property string selectedPlayer: ""
    readonly property string currentIgnoreKey: {
        var title = currentTitle.trim()
        var artist = currentArtist.trim()
        if (title && artist)
            return title + " — " + artist
        if (title)
            return title
        return currentTrackUrl.trim()
    }
    readonly property bool currentTrackIgnored: isTrackIgnored(currentIgnoreKey)
    // Throttle polling so poll responses don't create a busy loop.
    readonly property int pollInterval: playbackStatus === "playing"
        ? 250
        : (hasActivePlayer ? 1000 : 3000)

    property string requestedPlayer: {
        if (selectedPlayer) {
            return selectedPlayer
        } else if (config_yesPlayMusicChecked) {
            return "org.mpris.MediaPlayer2.yesplaymusic"
        } else if (config_spotifyChecked) {
            return "org.mpris.MediaPlayer2.spotify"
        } else if (config_lxMusicChecked) {
            return "org.mpris.MediaPlayer2.lx-music-desktop"
        } else {
            return ""
        }
    }

    horizontalBarPill: Component {
        Item {
            implicitWidth: root.shouldShowLyric ? lyricTextH.implicitWidth : sleepyTextH.implicitWidth
            implicitHeight: root.shouldShowLyric ? lyricTextH.implicitHeight : sleepyTextH.implicitHeight

            StyledText {
                id: lyricTextH
                visible: root.shouldShowLyric
                // Decoupled from the live value so the old line can fade OUT
                // before the new line is swapped in.
                property string displayText: ""
                text: displayText
                font.pixelSize: root.config_lyricTextSize
                font.bold: root.config_lyricTextBold
                font.italic: root.config_lyricTextItalic
                color: Theme.surfaceText
                anchors.centerIn: parent

                Component.onCompleted: displayText = root.currentLyric

                Connections {
                    target: root
                    function onCurrentLyricChanged() {
                        if (root.hasLyric)
                            lineAnimH.restart()
                    }
                }

                SequentialAnimation {
                    id: lineAnimH
                    NumberAnimation { target: lyricTextH; property: "opacity"; to: 0; duration: 130; easing.type: Easing.InCubic }
                    PropertyAction { target: lyricTextH; property: "displayText"; value: root.currentLyric }
                    PropertyAction { target: lyricTextH; property: "scale"; value: 0.94 }
                    ParallelAnimation {
                        NumberAnimation { target: lyricTextH; property: "opacity"; to: 1; duration: 240; easing.type: Easing.OutCubic }
                        NumberAnimation { target: lyricTextH; property: "scale"; to: 1; duration: 240; easing.type: Easing.OutCubic }
                    }
                }
              }

            StyledText {
                id: sleepyTextH
                visible: !root.shouldShowLyric
                text: "Zzz"
                font.pixelSize: root.config_lyricTextSize
                font.bold: true
                font.italic: true
                color: Theme.surfaceText
                anchors.centerIn: parent
            }

        }
    }

    verticalBarPill: Component {
        Item {
            implicitWidth: root.shouldShowLyric ? lyricTextV.implicitWidth : sleepyTextV.implicitWidth
            implicitHeight: root.shouldShowLyric ? lyricTextV.implicitHeight : sleepyTextV.implicitHeight
            
            StyledText {
                id: lyricTextV
                visible: root.shouldShowLyric
                property string displayText: ""
                text: displayText
                font.pixelSize: root.config_lyricTextSize - 2
                font.bold: root.config_lyricTextBold
                color: Theme.surfaceText
                anchors.centerIn: parent

                Component.onCompleted: displayText = root.currentLyric

                Connections {
                    target: root
                    function onCurrentLyricChanged() {
                        if (root.hasLyric)
                            lineAnimV.restart()
                    }
                }

                SequentialAnimation {
                    id: lineAnimV
                    NumberAnimation { target: lyricTextV; property: "opacity"; to: 0; duration: 130; easing.type: Easing.InCubic }
                    PropertyAction { target: lyricTextV; property: "displayText"; value: root.currentLyric }
                    PropertyAction { target: lyricTextV; property: "scale"; value: 0.94 }
                    ParallelAnimation {
                        NumberAnimation { target: lyricTextV; property: "opacity"; to: 1; duration: 240; easing.type: Easing.OutCubic }
                        NumberAnimation { target: lyricTextV; property: "scale"; to: 1; duration: 240; easing.type: Easing.OutCubic }
                    }
                }
            }

            StyledText {
                id: sleepyTextV
                visible: !root.shouldShowLyric
                text: "Zzz"
                font.pixelSize: Math.max(root.config_lyricTextSize - 2, 1)
                font.bold: true
                font.italic: true
                color: Theme.surfaceText
                anchors.centerIn: parent
            }

        }
    }

    popoutContent: Component {
        PopoutComponent {
            id: popoutColumn

            headerText: "Media source"
            detailsText: "Choose which player the lyrics follow"
            showCloseButton: false

            Item {
                width: parent.width
                implicitHeight: playerList.contentHeight

                ListView {
                    id: playerList
                    anchors.fill: parent
                    model: root.availablePlayers
                    spacing: 2

                    delegate: StyledRect {
                        width: playerList.width
                        height: 42
                        radius: Theme.cornerRadius
                        color: modelData === root.currentPlayerBusName
                            ? Theme.primaryHoverLight
                            : (playerMouse.containsMouse ? Theme.surfaceContainerHigh : "transparent")
                        activeFocusOnTab: true
                        Accessible.role: Accessible.RadioButton
                        Accessible.name: root.playerDisplayName(modelData)
                        Accessible.checked: modelData === root.currentPlayerBusName

                        DankIcon {
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.spacingM
                            anchors.verticalCenter: parent.verticalCenter
                            name: root.playerIconName(modelData)
                            size: 19
                            color: modelData === root.currentPlayerBusName ? Theme.primary : Theme.surfaceVariantText
                        }

                        StyledText {
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.spacingM + 19 + Theme.spacingS
                            anchors.right: selectedIcon.left
                            anchors.rightMargin: Theme.spacingS
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.playerDisplayName(modelData)
                            color: Theme.surfaceText
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: modelData === root.currentPlayerBusName ? Font.Medium : Font.Normal
                            elide: Text.ElideRight
                        }

                        DankIcon {
                            id: selectedIcon
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.spacingM
                            anchors.verticalCenter: parent.verticalCenter
                            visible: modelData === root.currentPlayerBusName
                            name: "check_circle"
                            size: 19
                            color: Theme.primary
                        }

                        MouseArea {
                            id: playerMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.selectedPlayer = modelData
                                popoutColumn.closePopout()
                            }
                        }

                        Keys.onSpacePressed: {
                            root.selectedPlayer = modelData
                            popoutColumn.closePopout()
                        }
                        Keys.onReturnPressed: {
                            root.selectedPlayer = modelData
                            popoutColumn.closePopout()
                        }

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 2
                            radius: Math.max(0, parent.radius - 2)
                            color: "transparent"
                            border.width: parent.activeFocus ? 2 : 0
                            border.color: Theme.primary
                        }
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Theme.outline
                opacity: 0.35
            }

            StyledRect {
                width: parent.width
                height: 48
                radius: Theme.cornerRadius
                color: ignoreArea.containsMouse && root.currentIgnoreKey !== ""
                    ? Theme.surfaceContainerHigh
                    : "transparent"
                opacity: root.currentIgnoreKey ? 1 : 0.5
                activeFocusOnTab: root.currentIgnoreKey !== ""
                Accessible.role: Accessible.Button
                Accessible.name: root.currentTrackIgnored ? "Unignore current item" : "Ignore current item"

                DankIcon {
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.spacingM
                    anchors.verticalCenter: parent.verticalCenter
                    name: root.currentTrackIgnored ? "undo" : "visibility_off"
                    size: 19
                    color: root.currentTrackIgnored ? Theme.primary : Theme.surfaceVariantText
                }

                Column {
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.spacingM + 19 + Theme.spacingS
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.spacingM
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1

                    StyledText {
                        text: root.currentTrackIgnored ? "Unignore current item" : "Ignore current item"
                        color: Theme.surfaceText
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.Medium
                    }

                    StyledText {
                        text: root.currentTrackIgnored ? "Allow lyrics for it again" : "Hide lyrics for this track or video"
                        color: Theme.surfaceVariantText
                        font.pixelSize: Math.max(Theme.fontSizeSmall - 1, 10)
                    }
                }

                MouseArea {
                    id: ignoreArea
                    anchors.fill: parent
                    enabled: root.currentIgnoreKey !== ""
                    hoverEnabled: enabled
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: root.toggleCurrentTrackIgnore()
                }

                Keys.onSpacePressed: if (ignoreArea.enabled) root.toggleCurrentTrackIgnore()
                Keys.onReturnPressed: if (ignoreArea.enabled) root.toggleCurrentTrackIgnore()

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 2
                    radius: Math.max(0, parent.radius - 2)
                    color: "transparent"
                    border.width: parent.activeFocus ? 2 : 0
                    border.color: Theme.primary
                }
            }
        }
    }

    popoutWidth: 320
    popoutHeight: Math.max(availablePlayers.length * 44 + 156, 200)

    // HTTP polling transport. Fedora's Qt6 packaging ships no QtWebSockets QML
    // module, so the backend serves the same payload over plain HTTP and this
    // polls it with a built-in XMLHttpRequest; failures retry at pollInterval.
    function sendPollRequest() {
        var xhr = new XMLHttpRequest()
        var player = requestedPlayer ? encodeURIComponent(requestedPlayer) : ""
        xhr.open("GET", "http://" + serverHost + ":" + httpPort + "/poll?player=" + player)
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return
            if (xhr.status === 200) {
                try {
                    handlePollResponse(JSON.parse(xhr.responseText))
                } catch (e) {
                    console.log("Error parsing poll response:", e)
                }
            } else {
                hasActivePlayer = false
                currentLyric = ""
            }
            pollTimer.restart()
        }
        xhr.send()
    }

    Timer {
        id: pollTimer
        interval: root.pollInterval
        running: true
        repeat: false
        onTriggered: sendPollRequest()
    }

    function handlePollResponse(data) {
        if (!data || !data.player) {
            hasActivePlayer = false
            currentLyric = ""
            currentTitle = ""
            currentArtist = ""
            currentTrackUrl = ""
            playbackStatus = "stopped"
            return
        }

        hasActivePlayer = true
        playbackStatus = data.playback_status || "stopped"
        positionMs = data.position_ms || 0

        if (data.player) {
            currentPlayerIdentity = data.player.identity || ""
            currentPlayerBusName = data.player.bus_name || ""
        }

        if (data.track) {
            currentTitle = data.track.title || ""
            currentArtist = data.track.artist || ""
            currentTrackUrl = data.track.url || ""
        } else {
            currentTitle = ""
            currentArtist = ""
            currentTrackUrl = ""
        }

        if (data.lyrics && data.lyrics.current_lyric) {
            currentLyric = data.lyrics.current_lyric
        } else {
            currentLyric = ""
        }

        if (data.available_players) {
            availablePlayers = data.available_players
        }
    }

    function ignoredTrackEntries() {
        return config_ignoredTracks.split(/\r?\n/).map(function(entry) {
            return entry.trim()
        }).filter(function(entry) {
            return entry.length > 0
        })
    }

    function playerDisplayName(busName) {
        var name = String(busName || "").replace("org.mpris.MediaPlayer2.", "")
        var lower = name.toLowerCase()
        if (lower.indexOf("firefox") === 0)
            return "Firefox"
        if (lower.indexOf("chromium") === 0)
            return "Chromium"
        if (lower.indexOf("chrome") === 0)
            return "Google Chrome"
        if (lower.indexOf("spotify") === 0)
            return "Spotify"
        if (lower.indexOf("cliamp") === 0)
            return "Cliamp"

        name = name.replace(/\.instance[_-]?\d+.*/, "").replace(/[._-]+/g, " ").trim()
        return name ? name.charAt(0).toUpperCase() + name.slice(1) : "Media player"
    }

    function playerIconName(busName) {
        var name = String(busName || "").toLowerCase()
        if (name.indexOf("firefox") !== -1 || name.indexOf("chrome") !== -1 || name.indexOf("chromium") !== -1)
            return "language"
        if (name.indexOf("spotify") !== -1)
            return "graphic_eq"
        return "music_note"
    }

    function isTrackIgnored(key) {
        if (!key)
            return false
        return ignoredTrackEntries().indexOf(key.trim()) !== -1
    }

    function toggleCurrentTrackIgnore() {
        var key = currentIgnoreKey.trim()
        if (!key || !pluginService || !pluginId)
            return

        var entries = ignoredTrackEntries()
        var index = entries.indexOf(key)
        if (index === -1)
            entries.push(key)
        else
            entries.splice(index, 1)

        pluginService.savePluginData(pluginId, "ignoredTracks", entries.join("\n"))
    }

}
