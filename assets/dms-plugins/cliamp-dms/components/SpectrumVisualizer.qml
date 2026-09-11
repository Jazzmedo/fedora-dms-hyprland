import QtQuick
import qs.Common

Item {
    id: root
    property var bands: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    property string visualStyle: "Bars"
    readonly property string style: String(visualStyle || "Bars").toLowerCase().replace(/[^a-z]/g, "")

    clip: true
    Accessible.role: Accessible.Graphic
    Accessible.name: "Live " + visualStyle + " audio spectrum visualizer"

    function bandValue(index) { return Math.max(0, Math.min(1, Number(bands[index] || 0))) }

    Row {
        id: bandRow
        anchors.fill: parent
        anchors.margins: Theme.spacingS
        spacing: root.style === "columns" ? Theme.spacingS : Theme.spacingXS
        visible: root.style !== "wave" && root.style !== "scatter"

        Repeater {
            model: 10
            delegate: Item {
                id: bandDelegate
                required property int index
                readonly property real level: root.bandValue(index)
                readonly property real columnHeight: Math.max(2, level * height)
                width: (bandRow.width - bandRow.spacing * 9) / 10
                height: bandRow.height

                Rectangle {
                    visible: ["bars", "barsdot", "columns", "classicpeak", "flame", "retro", "pulse"].indexOf(root.style) >= 0
                    width: root.style === "columns" ? Math.max(3, parent.width * 0.58) : parent.width
                    height: root.style === "pulse" ? Math.max(2, bandDelegate.columnHeight * 0.82) : bandDelegate.columnHeight
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: root.style === "pulse" ? (parent.height - height) / 2 : parent.height - height
                    radius: root.style === "retro" || root.style === "columns" ? 1 : Math.min(Theme.cornerRadius, width / 2)
                    color: Theme.primary
                    opacity: root.style === "flame" ? 0.55 + bandDelegate.level * 0.45 : 1
                }

                Rectangle {
                    visible: root.style === "barsoutline"
                    width: parent.width
                    height: bandDelegate.columnHeight
                    anchors.bottom: parent.bottom
                    radius: Math.min(Theme.cornerRadius, width / 2)
                    color: "transparent"
                    border.width: 2
                    border.color: Theme.primary
                }

                Rectangle {
                    visible: root.style === "barsdot" || root.style === "classicpeak"
                    width: root.style === "classicpeak" ? parent.width : Math.max(5, parent.width * 0.55)
                    height: root.style === "classicpeak" ? 3 : width
                    radius: height / 2
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: Math.max(0, parent.height - bandDelegate.columnHeight - height - 2)
                    color: Theme.primary
                }

                Rectangle {
                    visible: root.style === "rain"
                    width: Math.max(5, parent.width * 0.55)
                    height: width
                    radius: width / 2
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: bandDelegate.level * Math.max(0, parent.height - height)
                    color: Theme.primary
                    opacity: 0.45 + bandDelegate.level * 0.55
                }

                Column {
                    visible: root.style === "bricks"
                    anchors.fill: parent
                    spacing: 2
                    Repeater {
                        model: 8
                        delegate: Rectangle {
                            required property int index
                            width: parent.width
                            height: (parent.height - parent.spacing * 7) / 8
                            radius: 2
                            color: Theme.primary
                            opacity: bandDelegate.level >= (8 - index) / 8 ? 1 : 0.12
                        }
                    }
                }
            }
        }
    }

    Canvas {
        id: plot
        anchors.fill: parent
        anchors.margins: Theme.spacingS
        visible: root.style === "wave" || root.style === "scatter"
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            ctx.strokeStyle = Theme.primary
            ctx.fillStyle = Theme.primary
            ctx.lineWidth = 3
            if (root.style === "wave") {
                ctx.beginPath()
                for (var index = 0; index < 10; index++) {
                    var x = index * width / 9
                    var y = height - root.bandValue(index) * height * 0.9
                    if (index === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y)
                }
                ctx.stroke()
            } else {
                for (var band = 0; band < 10; band++) {
                    var level = root.bandValue(band)
                    var centerX = (band + 0.5) * width / 10
                    for (var dot = 0; dot < 3; dot++) {
                        var dotY = height - level * height * (0.45 + dot * 0.25)
                        ctx.globalAlpha = 1 - dot * 0.25
                        ctx.beginPath()
                        ctx.arc(centerX + (dot - 1) * 3, dotY, 2.5, 0, Math.PI * 2)
                        ctx.fill()
                    }
                }
                ctx.globalAlpha = 1
            }
        }
    }

    onBandsChanged: plot.requestPaint()
    onStyleChanged: plot.requestPaint()
}
