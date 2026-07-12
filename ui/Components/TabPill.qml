import QtQuick
import QtQuick.Controls
import Themes

/*
 * TabPill - onglet en forme de pilule utilise dans le selecteur d'onglets
 * de AdminView (Journal d'audit / Machines autorisees / Utilisateurs / ...).
 *
 * label: texte affiche dans l'onglet
 * active: true si cet onglet est actuellement selectionne
 */
Rectangle {
    id: root

    property string label: ""
    property bool active: false

    signal clicked()

    implicitWidth: labelText.implicitWidth + Theme.spacingMedium * 2
    implicitHeight: 30
    radius: Theme.radiusPill
    color: active ? Theme.primary : (mouseArea.containsMouse ? Theme.surfaceHover : "transparent")

    Behavior on color { ColorAnimation { duration: 100 } }

    Label {
        id: labelText
        anchors.centerIn: parent
        text: root.label
        font.pixelSize: Theme.fontSizeSmall
        font.bold: root.active
        font.family: Theme.fontFamily
        color: root.active ? Theme.primaryText : Theme.text
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
