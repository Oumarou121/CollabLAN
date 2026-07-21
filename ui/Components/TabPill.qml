import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
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
    property string glyph: ""
    property bool active: false

    signal clicked()

    implicitWidth: tabContent.implicitWidth + Theme.spacingLarge * 2
    implicitHeight: 44
    radius: Theme.radiusMedium
    color: active ? Theme.surface : (mouseArea.containsMouse ? Theme.surfaceHover : "transparent")

    Behavior on color { ColorAnimation { duration: 100 } }

    RowLayout {
        id: tabContent
        anchors.centerIn: parent
        spacing: Theme.spacingSmall

        Label {
            visible: root.glyph.length > 0
            text: root.glyph
            font.family: "FontAwesome"
            font.pixelSize: Theme.fontSizeSmall
            color: root.active ? Theme.primary : Theme.textSecondary
        }

        Label {
            id: labelText
            text: root.label
            font.pixelSize: Theme.fontSizeSmall
            font.bold: root.active
            font.family: Theme.fontFamily
            color: root.active ? Theme.text : Theme.textSecondary
        }
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Theme.spacingSmall
        height: 3
        radius: 2
        color: Theme.primary
        visible: root.active
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
