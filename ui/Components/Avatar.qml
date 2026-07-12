import QtQuick
import Themes

/*
 * Avatar - pastille circulaire avec initiale(s), couleur deterministe
 * derivee du nom (Theme.colorForName), et pastille de statut optionnelle.
 * Reutilisee dans Home, Conversations et Chat pour une identite visuelle
 * coherente d'un utilisateur a l'autre.
 */
Item {
    id: root

    property string name: ""
    property int size: 40
    property bool showStatus: false
    property bool online: false

    implicitWidth: size
    implicitHeight: size

    readonly property color bgColor: Theme.colorForName(name)
    readonly property string initial: name && name.length > 0 ? name.charAt(0).toUpperCase() : "?"

    Rectangle {
        id: circle
        anchors.fill: parent
        radius: width / 2
        color: root.bgColor

        Text {
            anchors.centerIn: parent
            text: root.initial
            color: "#FFFFFF"
            font.family: Theme.fontFamily
            font.bold: true
            font.pixelSize: Math.max(10, root.size * 0.4)
        }
    }

    Rectangle {
        visible: root.showStatus
        width: Math.max(8, root.size * 0.28)
        height: width
        radius: width / 2
        color: root.online ? Theme.success : Theme.textTertiary
        border.width: 2
        border.color: Theme.surface
        anchors.right: circle.right
        anchors.bottom: circle.bottom
        anchors.rightMargin: -1
        anchors.bottomMargin: -1
    }
}
