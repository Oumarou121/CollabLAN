import QtQuick
import Themes

/*
 * Avatar - pastille circulaire avec initiale(s), teinte deterministe
 * derivee du nom (Theme.colorForName : un meme utilisateur garde la meme
 * couleur partout), pastille de statut optionnelle.
 *
 * Nom vide (pas encore resolu) : icone "personne" sur fond neutre plutot
 * qu'un "?" litteral.
 */
Item {
    id: root

    property string name: ""
    property int size: 40
    property bool showStatus: false
    property bool online: false
    // Statut detaille optionnel ("online" | "away" | "busy" | "offline") ;
    // prioritaire sur `online` quand il est renseigne.
    property string status: ""

    implicitWidth: size
    implicitHeight: size

    readonly property bool hasName: name && name.length > 0
    readonly property color bgColor: hasName ? Theme.colorForName(name) : Theme.sunken
    // Deux initiales si le nom comporte plusieurs mots ("Awa Diallo" ->
    // "AD"), sinon la premiere lettre.
    readonly property string initials: {
        if (!hasName)
            return ""
        const parts = name.trim().split(/[\s._-]+/).filter(function(p) { return p.length > 0 })
        if (parts.length >= 2 && root.size >= 28)
            return (parts[0].charAt(0) + parts[1].charAt(0)).toUpperCase()
        return name.charAt(0).toUpperCase()
    }
    readonly property color statusColor: {
        const s = root.status.length > 0 ? root.status : (root.online ? "online" : "offline")
        if (s === "online") return Theme.successColor
        if (s === "away" || s === "busy") return Theme.markAway
        return Theme.inkDisabled
    }

    Rectangle {
        id: circle
        anchors.fill: parent
        radius: width / 2
        color: root.bgColor

        Text {
            anchors.centerIn: parent
            visible: root.hasName
            text: root.initials
            color: "#FFFFFF"
            font.family: Theme.fontFamily
            font.weight: Theme.weightSemibold
            font.pixelSize: Math.max(10, Math.round(root.size * (root.initials.length > 1 ? 0.36 : 0.42)))
        }

        FaIcon {
            anchors.centerIn: parent
            visible: !root.hasName
            glyph: ""
            color: Theme.ink3
            font.pixelSize: Math.max(10, root.size * 0.42)
        }
    }

    Rectangle {
        visible: root.showStatus
        width: Math.max(8, root.size * 0.28)
        height: width
        radius: width / 2
        color: root.statusColor
        border.width: 2
        border.color: Theme.surface0
        anchors.right: circle.right
        anchors.bottom: circle.bottom
        anchors.rightMargin: -1
        anchors.bottomMargin: -1
    }
}
