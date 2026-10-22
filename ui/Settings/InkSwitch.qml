import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Themes

/*
 * InkSwitch - interrupteur Ligne claire : pilule a l'encre quand il est
 * actif, libelle a droite (« Activées » / « Coupées »). L'etat vient de
 * `on` (lie au modele) ; un clic emet switched(nouvelle valeur).
 */
AbstractButton {
    id: root

    property bool on: false
    signal switched(bool value)
    Layout.alignment: Qt.AlignLeft

    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    padding: 0
    implicitHeight: 24
    implicitWidth: 36 + 10 + label.implicitWidth
    Accessible.role: Accessible.CheckBox
    Accessible.checkable: true
    Accessible.checked: root.on
    Accessible.name: root.text
    onClicked: root.switched(!root.on)
    HoverHandler { cursorShape: Qt.PointingHandCursor }

    background: Item {}
    contentItem: Item {
        Rectangle {
            id: track
            anchors.verticalCenter: parent.verticalCenter
            width: 36; height: 20; radius: 10
            color: root.on ? Theme.ink : Theme.lineStrong
            Behavior on color { ColorAnimation { duration: Theme.durationFast } }
            Rectangle {
                y: 3; x: root.on ? 19 : 3
                width: 14; height: 14; radius: 7
                color: Theme.surface0
                Behavior on x { NumberAnimation { duration: Theme.durationFast } }
            }
            Rectangle {
                anchors.fill: parent; anchors.margins: -3
                radius: height / 2
                color: "transparent"
                border.width: root.visualFocus ? 2 : 0
                border.color: Theme.focusRing
            }
        }
        Text {
            id: label
            anchors.verticalCenter: parent.verticalCenter
            x: track.width + 10
            text: root.text
            color: Theme.ink2
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fs(13)
            font.weight: Theme.weightMedium
        }
    }
}
