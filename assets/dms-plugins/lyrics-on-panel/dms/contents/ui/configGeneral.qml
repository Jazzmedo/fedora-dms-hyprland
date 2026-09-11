import QtQuick
import QtQuick.Controls as QQC2
import qs.Common
import qs.Modules.Plugins
import qs.Widgets

PluginSettings {
    id: pluginSettings
    pluginId: "lyricsOnPanel"

    StyledText {
        width: parent.width
        text: "Lyrics on Panel"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Display synchronized lyrics in the bar"
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    // Player Selection
    SelectionSetting {
        settingKey: "playerMode"
        label: "Player Mode"
        description: "Select which player's lyric to show"
        options: [
            { label: "Global Mode", value: "global" },
            { label: "YesPlayMusic", value: "yesplaymusic" },
            { label: "Spotify", value: "spotify" },
            { label: "LX Music", value: "lxmusic" }
        ]
        defaultValue: "global"
    }

    // Text Settings
    StyledText {
        width: parent.width
        text: "Lyric Text"
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Font.Bold
        color: Theme.surfaceText
        topPadding: Theme.spacingM
    }

    SliderSetting {
        settingKey: "lyricTextSize"
        label: "Lyric text size"
        defaultValue: 12
        minimum: 1
        maximum: 24
    }

    SliderSetting {
        settingKey: "lyricTextVerticalOffset"
        label: "Lyric text vertical offset"
        defaultValue: 1
        minimum: -10
        maximum: 10
    }

    ToggleSetting {
        settingKey: "lyricTextBold"
        label: "Bold text"
        defaultValue: false
    }

    ToggleSetting {
        settingKey: "lyricTextItalic"
        label: "Italic text"
        defaultValue: false
    }

    Column {
        id: ignoredTracksSetting
        width: parent.width
        spacing: Theme.spacingS

        property string savedValue: ""
        property bool initialized: false

        function loadValue() {
            var loaded = String(pluginSettings.loadValue("ignoredTracks", ""))
            if (ignoredTracksArea.activeFocus && initialized)
                return
            savedValue = loaded
            ignoredTracksArea.text = loaded
            initialized = true
        }

        function commit() {
            if (!initialized || ignoredTracksArea.text === savedValue)
                return
            savedValue = ignoredTracksArea.text
            pluginSettings.saveValue("ignoredTracks", savedValue)
        }

        Component.onCompleted: Qt.callLater(loadValue)

        StyledText {
            text: "Ignored items"
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Font.Medium
            color: Theme.surfaceText
        }

        StyledText {
            width: parent.width
            text: "One track or video per line. Use “Ignore current item” from the widget, or edit this list manually."
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            wrapMode: Text.WordWrap
        }

        Rectangle {
            width: parent.width
            height: 120
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerHigh
            border.width: ignoredTracksArea.activeFocus ? 2 : 1
            border.color: ignoredTracksArea.activeFocus ? Theme.primary : Theme.outline

            QQC2.ScrollView {
                anchors.fill: parent
                anchors.margins: 2
                clip: true

                QQC2.TextArea {
                    id: ignoredTracksArea
                    placeholderText: "No ignored items"
                    placeholderTextColor: Theme.surfaceVariantText
                    color: Theme.surfaceText
                    selectionColor: Theme.primary
                    selectedTextColor: Theme.onPrimary
                    font.family: SettingsData.monoFontFamily || SettingsData.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    wrapMode: TextEdit.NoWrap
                    selectByMouse: true
                    textFormat: TextEdit.PlainText
                    background: null
                    leftPadding: Theme.spacingS
                    rightPadding: Theme.spacingS
                    topPadding: Theme.spacingS
                    bottomPadding: Theme.spacingS

                    onTextChanged: {
                        if (ignoredTracksSetting.initialized)
                            saveIgnoredTracks.restart()
                    }
                    onActiveFocusChanged: {
                        if (!activeFocus)
                            ignoredTracksSetting.commit()
                    }
                }
            }
        }

        Timer {
            id: saveIgnoredTracks
            interval: 500
            repeat: false
            onTriggered: ignoredTracksSetting.commit()
        }
    }

    // Widget Settings
    StyledText {
        width: parent.width
        text: "Widget"
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Font.Bold
        color: Theme.surfaceText
        topPadding: Theme.spacingM
    }

    StringSetting {
        settingKey: "preferedWidgetWidth"
        label: "Prefered Widget Width"
        placeholder: "550"
        defaultValue: "550"
    }

    StringSetting {
        settingKey: "lxMusicPort"
        label: "LX Music Local Port"
        placeholder: "23330"
        defaultValue: "23330"
    }
}
