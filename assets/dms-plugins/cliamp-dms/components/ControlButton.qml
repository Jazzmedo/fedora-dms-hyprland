import QtQuick
import qs.Common
import qs.Widgets

Rectangle {
    id: root

    property string iconName: "help"
    property string label: ""
    property string tooltipText: label
    property bool showIcon: true
    property bool active: false
    property bool enabled: true
    property int buttonSize: 40
    signal clicked()

    width: label.length > 0 ? Math.max(buttonSize, (showIcon ? 19 + Theme.spacingS : 0) + labelText.implicitWidth + Theme.spacingM * 2) : buttonSize
    height: buttonSize
    clip: true
    radius: Theme.cornerRadius
    color: !enabled ? Theme.surfaceContainer : active ? Theme.primaryContainer : area.pressed ? Theme.primaryHover : area.containsMouse ? Theme.primaryHoverLight : Theme.surfaceContainerHigh
    opacity: enabled ? 1 : 0.45
    border.width: active ? 1 : 0
    border.color: Theme.primary
    activeFocusOnTab: enabled
    Accessible.role: Accessible.Button
    Accessible.name: tooltipText || label
    Accessible.checkable: active
    Accessible.checked: active

    Keys.onSpacePressed: if (enabled) root.clicked()
    Keys.onReturnPressed: if (enabled) root.clicked()

    Behavior on color { ColorAnimation { duration: Theme.shorterDuration } }

    Row {
        id: content
        width: root.label.length > 0 ? Math.max(0, root.width - Theme.spacingM * 2) : implicitWidth
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.showIcon && label.length > 0 ? Theme.spacingS : 0

        DankIcon {
            name: root.iconName
            size: 19
            visible: root.showIcon
            color: root.active ? Theme.primary : Theme.surfaceText
            anchors.verticalCenter: parent.verticalCenter
        }

        StyledText {
            id: labelText
            visible: root.label.length > 0
            width: Math.max(0, content.width - (root.showIcon ? 19 + content.spacing : 0))
            text: root.label
            wrapMode: Text.NoWrap
            maximumLineCount: 1
            elide: Text.ElideRight
            color: root.active ? Theme.primary : Theme.surfaceText
            font.pixelSize: Theme.fontSizeSmall
            font.weight: Font.Medium
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        enabled: root.enabled
        hoverEnabled: true
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onPressed: root.forceActiveFocus()
        onClicked: root.clicked()
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 2
        radius: Math.max(0, root.radius - 2)
        color: "transparent"
        border.width: root.activeFocus ? 2 : 0
        border.color: Theme.primary
    }

}
