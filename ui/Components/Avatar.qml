import QtQuick
import Themes

/*
 * Avatar - pastille circulaire avec initiale(s), couleur deterministe
 * derivee du nom (Theme.colorForName), et pastille de statut optionnelle.
 * Reutilisee dans Home, Conversations et Chat pour une identite visuelle
 * coherente d'un utilisateur a l'autre.
 *
 * CORRECTIF (juillet 2026) : quand `name` est vide (nom pas encore
 * resolu / conversation pas encore chargee), l'ancien fallback affichait
 * un simple "?" en texte brut -- visuellement discordant avec le reste
 * de l'app. On affiche desormais une icone "personne" (meme police
 * Font Awesome 4.7 que DashboardCard/IconButton) sur un fond neutre.
 */
Item {
    id: root

    property string name: ""
    property int size: 40
    property bool showStatus: false
    property bool online: false

    implicitWidth: size
    implicitHeight: size

    readonly property bool hasName: name && name.length > 0
    readonly property color bgColor: root.hasName ? Theme.colorForName(name) : Theme.textTertiary
    readonly property string initial: root.hasName ? name.charAt(0).toUpperCase() : ""

    FontLoader {
        id: iconFont
        source: "../Assets/fonts/fontawesome-webfont.ttf"
    }

    Rectangle {
        id: circle
        anchors.fill: parent
        radius: width / 2
        color: root.bgColor

        Text {
            anchors.centerIn: parent
            visible: root.hasName
            text: root.initial
            color: "#FFFFFF"
            font.family: Theme.fontFamily
            font.bold: true
            font.pixelSize: Math.max(10, root.size * 0.4)
        }

        // Icone "personne" (fa-user) : fallback neutre tant que le nom
        // n'est pas encore disponible, plutot qu'un "?" litteral.
        Text {
            anchors.centerIn: parent
            visible: !root.hasName
            text: "\uf007"
            color: "#FFFFFF"
            opacity: 0.85
            font.family: iconFont.name
            font.pixelSize: Math.max(10, root.size * 0.42)
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
