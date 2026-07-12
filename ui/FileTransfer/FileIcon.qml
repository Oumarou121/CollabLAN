import QtQuick
import Themes

/*
 * FileIcon - icone "fichier" style explorateur (feuille avec coin replie),
 * utilisee dans les vues grille et liste de FileTransferView. La couleur
 * s'adapte au sens du transfert (reception/envoi) et une pastille de coin
 * indique la direction, a la maniere des icones de statut d'un explorateur
 * de fichiers moderne (Windows 11 / Nautilus).
 */
Item {
    id: root

    property color accentColor: Theme.primary
    property bool received: true
    property real size: 34
    // 0..100, -1 pour masquer la barre de progression sur l'icone
    property real percent: -1
    property bool failed: false

    implicitWidth: size * 0.82
    implicitHeight: size

    readonly property real foldSize: size * 0.28

    // Corps de la page.
    Rectangle {
        id: page
        anchors.fill: parent
        radius: 4
        color: Theme.surface
        border.width: 1
        border.color: Theme.border

        // Bandeau colore en tete de page (rappelle la couleur du dossier
        // parent / du correspondant).
        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: parent.height * 0.32
            radius: 4
            color: root.accentColor
            opacity: 0.85

            Rectangle {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                height: parent.radius
                color: parent.color
            }
        }

        // Lignes de "texte" suggerant le contenu du fichier.
        Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: parent.width * 0.16
            anchors.bottomMargin: parent.height * 0.14
            spacing: parent.height * 0.09

            Repeater {
                model: 2
                Rectangle {
                    width: index === 0 ? page.width * 0.5 : page.width * 0.34
                    height: 2
                    radius: 1
                    color: Theme.border
                }
            }
        }
    }

    // Coin replie (triangle) en haut a droite, signature visuelle d'une
    // icone de "fichier" par opposition a une icone de "dossier".
    Canvas {
        anchors.top: parent.top
        anchors.right: parent.right
        width: root.foldSize
        height: root.foldSize
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            ctx.beginPath()
            ctx.moveTo(width, 0)
            ctx.lineTo(width, height)
            ctx.lineTo(0, 0)
            ctx.closePath()
            ctx.fillStyle = Theme.background
            ctx.fill()
        }
    }

    // Pastille de direction (bas droite), comme un badge de statut de
    // synchronisation dans un explorateur (OneDrive/Nextcloud...).
    Rectangle {
        width: root.size * 0.4
        height: width
        radius: width / 2
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: -width * 0.18
        anchors.bottomMargin: -width * 0.12
        color: root.failed ? Theme.error : (root.received ? Theme.accent : Theme.primary)
        border.width: 2
        border.color: Theme.surface

        Text {
            anchors.centerIn: parent
            text: root.failed ? "!" : (root.received ? "\u2193" : "\u2191")
            color: Theme.primaryText
            font.pixelSize: root.size * 0.22
            font.bold: true
        }
    }
}
