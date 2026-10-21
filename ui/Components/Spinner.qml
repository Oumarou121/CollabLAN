import QtQuick
import Themes

/*
 * Spinner - indicateur d'activite indetermine du design system (arc
 * tournant), colorable : utilise dans les boutons en cours d'action et
 * les ecrans de chargement. Remplace le BusyIndicator du style Basic, dont
 * la couleur fixe etait illisible sur un bouton plein.
 */
Item {
    id: root

    property color color: Theme.accentColor
    property real lineWidth: Math.max(2, Math.round(width / 9))
    property bool running: visible

    implicitWidth: 18
    implicitHeight: 18

    Accessible.role: Accessible.Animation
    Accessible.name: qsTr("Chargement en cours")

    Canvas {
        id: arc
        anchors.fill: parent
        antialiasing: true
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const r = Math.min(width, height) / 2 - root.lineWidth / 2
            ctx.lineWidth = root.lineWidth
            ctx.lineCap = "round"
            // Piste discrete puis arc de progression.
            ctx.strokeStyle = Qt.rgba(root.color.r, root.color.g, root.color.b, 0.22)
            ctx.beginPath()
            ctx.arc(width / 2, height / 2, r, 0, Math.PI * 2)
            ctx.stroke()
            ctx.strokeStyle = root.color
            ctx.beginPath()
            ctx.arc(width / 2, height / 2, r, -Math.PI / 2, Math.PI * 0.9)
            ctx.stroke()
        }

        RotationAnimator on rotation {
            from: 0
            to: 360
            duration: 800
            loops: Animation.Infinite
            running: root.running
        }
    }

    onColorChanged: arc.requestPaint()
    onWidthChanged: arc.requestPaint()
}
