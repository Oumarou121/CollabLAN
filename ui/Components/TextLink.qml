import QtQuick
import QtQuick.Controls
import Themes

/*
 * TextLink - lien d'action de Ligne claire : texte d'encre de marque suivi
 * d'une fleche, souligne au survol. Pour « Tous les transferts », « Examiner »,
 * « Ouvrir la conversation »...
 */
AbstractButton {
    id: root

    property bool arrow: true
    property real fontSize: Theme.fs(12.5)
    property string tooltip: ""

    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    padding: 0
    implicitWidth: row.implicitWidth
    implicitHeight: Math.max(row.implicitHeight, 20)
    Accessible.role: Accessible.Link
    Accessible.name: root.text

    readonly property color tone: !root.enabled ? Theme.inkDisabled : Theme.navActiveInk

    HoverHandler { cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }

    ToolTip.visible: root.tooltip.length > 0 && root.hovered
    ToolTip.text: root.tooltip
    ToolTip.delay: 500

    background: Rectangle {
        color: "transparent"
        Rectangle {
            anchors.fill: parent
            anchors.margins: -3
            radius: Theme.radiusSheet
            color: "transparent"
            border.width: 2
            border.color: Theme.focusRing
            visible: root.visualFocus
        }
    }

    contentItem: Row {
        id: row
        spacing: 4

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.text
            color: root.tone
            font.family: Theme.fontFamily
            font.pixelSize: root.fontSize
            font.weight: Theme.weightSemibold
            font.underline: root.hovered && root.enabled
        }
        // Le decalage au survol se fait DANS un conteneur : une Row impose
        // la position x de ses enfants directs.
        Item {
            visible: root.arrow
            anchors.verticalCenter: parent.verticalCenter
            width: arrowIcon.width + 2
            height: arrowIcon.height

            LineIcon {
                id: arrowIcon
                x: root.hovered ? 2 : 0
                path: "M4.5 12h15 M13.5 6l6 6-6 6"
                color: root.tone
                size: Math.round(root.fontSize * 1.1)
                strokeWidth: 2
                Behavior on x { NumberAnimation { duration: Theme.durationFast } }
            }
        }
    }
}
