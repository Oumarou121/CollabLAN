import QtQuick
import QtQuick.Controls
import Themes

/*
 * AppSwitch - interrupteur du design system (reglages on/off appliques
 * immediatement). Etat porte aussi par la position de la pastille, pas
 * seulement par la couleur.
 */
Switch {
    id: root

    implicitHeight: 26
    spacing: Theme.spacingSmall
    font.pixelSize: Theme.fs(13)
    font.family: Theme.fontFamily
    focusPolicy: Qt.StrongFocus

    HoverHandler {
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    }

    indicator: Rectangle {
        x: 0
        y: (root.height - height) / 2
        width: 42
        height: 24
        radius: height / 2
        color: root.checked ? Theme.accentColor : Theme.sunken
        border.width: root.checked ? 0 : 1
        border.color: Theme.lineStrong
        opacity: root.enabled ? 1 : 0.5

        Behavior on color { ColorAnimation { duration: Theme.durationFast } }

        Rectangle {
            width: 18
            height: 18
            radius: 9
            anchors.verticalCenter: parent.verticalCenter
            x: root.checked ? parent.width - width - 3 : 3
            color: "#FFFFFF"
            border.width: root.checked ? 0 : 1
            border.color: Theme.lineStrong

            Behavior on x { NumberAnimation { duration: Theme.durationFast; easing.type: Easing.OutQuad } }
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: -3
            radius: parent.radius + 3
            color: "transparent"
            border.width: 2
            border.color: Theme.focusRing
            visible: root.visualFocus
        }
    }

    contentItem: Text {
        visible: root.text.length > 0
        text: root.text
        color: root.enabled ? Theme.ink : Theme.inkDisabled
        font: root.font
        leftPadding: root.indicator.width + root.spacing
        verticalAlignment: Text.AlignVCenter
    }
}
