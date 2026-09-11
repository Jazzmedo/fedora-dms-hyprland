import QtQuick
import qs.Common
import qs.Widgets

Item {
    id: root

    property int bandIndex: 0
    property string frequency: "1k"
    property real value: 0
    property real previewValue: value
    property bool enabled: true
    property bool dragging: false
    signal valueCommitted(real value)

    width: 34
    height: 146
    opacity: enabled ? 1 : 0.45
    activeFocusOnTab: enabled
    Accessible.role: Accessible.Slider
    Accessible.name: frequency + " equalizer band"
    Accessible.description: Math.round(previewValue) + " decibels"

    onValueChanged: if (!dragging) previewValue = value

    function clampValue(nextValue) {
        return Math.max(-12, Math.min(12, Math.round(nextValue)))
    }

    function setFromY(y) {
        previewValue = clampValue(12 - ((y - track.y) / track.height) * 24)
    }

    function commit(nextValue) {
        previewValue = clampValue(nextValue)
        valueCommitted(previewValue)
    }

    Keys.onUpPressed: if (enabled) commit(previewValue + 1)
    Keys.onDownPressed: if (enabled) commit(previewValue - 1)

    StyledText {
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        text: (root.previewValue > 0 ? "+" : "") + Math.round(root.previewValue)
        font.pixelSize: Theme.fontSizeSmall
        color: root.dragging || root.activeFocus ? Theme.primary : Theme.surfaceVariantText
    }

    StyledRect {
        id: track
        anchors.top: parent.top
        anchors.topMargin: 28
        anchors.horizontalCenter: parent.horizontalCenter
        width: 8
        height: 90
        radius: 4
        color: Theme.outline

        Rectangle {
            width: parent.width
            height: 1
            y: parent.height / 2
            color: Theme.surfaceText
            opacity: 0.55
        }

        StyledRect {
            readonly property real zeroY: track.height / 2
            readonly property real valueY: (12 - root.previewValue) / 24 * track.height
            y: Math.min(zeroY, valueY)
            width: parent.width
            height: Math.max(2, Math.abs(valueY - zeroY))
            radius: 4
            color: Theme.primary
        }

        StyledRect {
            width: 20
            height: 8
            radius: 4
            x: (track.width - width) / 2
            y: Math.max(0, Math.min(track.height - height, (12 - root.previewValue) / 24 * track.height - height / 2))
            color: Theme.primary
            border.width: root.activeFocus ? 2 : 0
            border.color: Theme.onPrimary
        }
    }

    MouseArea {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: track.top
        anchors.bottom: track.bottom
        enabled: root.enabled
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPressed: mouse => {
            root.forceActiveFocus()
            root.dragging = true
            root.setFromY(mouse.y + track.y)
        }
        onPositionChanged: mouse => {
            if (pressed)
                root.setFromY(mouse.y + track.y)
        }
        onReleased: {
            root.dragging = false
            root.valueCommitted(root.previewValue)
        }
        onWheel: wheel => {
            root.commit(root.previewValue + (wheel.angleDelta.y > 0 ? 1 : -1))
            wheel.accepted = true
        }
    }

    StyledText {
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.frequency
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
    }
}
