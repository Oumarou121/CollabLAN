import QtQuick
import QtQuick.Controls
import Themes

/*
 * Toast - notification visuelle ephemere reutilisable (issue #58).
 *
 * Affiche un titre + un message, se rend visible avec un fondu, reste a
 * l'ecran `duration` ms puis se retire (fondu sortant) et emet
 * dismissed() pour que l'hote (ToastHost.qml) le retire de la file.
 *
 * category determine la couleur d'accent (barre laterale + icone) afin
 * que le style du toast reste coherent avec le type d'evenement recu
 * (message / transfert / connexion / deconnexion).
 */
Rectangle {
    id: root

    property string title: ""
    property string message: ""
    property string category: "message" // "message" | "transfer" | "connection" | "disconnection"
    property int duration: 4000

    signal dismissed()

    readonly property color accentColor: {
        switch (category) {
        case "transfer": return Theme.primary
        case "connection": return Theme.success
        case "disconnection": return Theme.textSecondary
        case "group": return Theme.accent
        default: return Theme.accent
        }
    }

    readonly property string iconGlyph: {
        switch (category) {
        case "transfer": return "\u21C5"       // fleches haut/bas (transfert)
        case "connection": return "\u25CF"      // point plein (en ligne)
        case "disconnection": return "\u25CB"   // point vide (hors ligne)
        case "group": return "\u2637"           // symbole groupe/postes
        default: return "\u2709"                // enveloppe (message)
        }
    }

    width: Math.min(360, parent ? parent.width - 32 : 360)
    height: contentColumn.implicitHeight + Theme.spacingMedium * 2
    radius: Theme.radiusMedium
    color: Theme.surface
    border.color: Theme.border
    border.width: 1

    // Legere ombre portee simulee par un rectangle en fond, decale.
    Rectangle {
        anchors.fill: parent
        anchors.topMargin: 3
        radius: parent.radius
        color: Theme.shadow
        z: -1
    }

    opacity: 0
    scale: 0.96

    Rectangle {
        id: accentBar
        width: 4
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        radius: 2
        color: root.accentColor
    }

    Row {
        id: contentRow
        anchors.left: accentBar.right
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Theme.spacingMedium
        anchors.rightMargin: Theme.spacingSmall
        spacing: Theme.spacingSmall

        Text {
            id: iconLabel
            text: root.iconGlyph
            color: root.accentColor
            font.pixelSize: Theme.fontSizeHeading
            anchors.verticalCenter: parent.verticalCenter
        }

        Column {
            id: contentColumn
            width: contentRow.width - contentRow.spacing * 3 - closeLabel.width - iconLabel.width
            spacing: 2
            anchors.verticalCenter: parent.verticalCenter

            Text {
                text: root.title
                color: Theme.text
                font.pixelSize: Theme.fontSizeBody
                font.bold: true
                width: parent.width
                elide: Text.ElideRight
            }
            Text {
                text: root.message
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeSmall
                width: parent.width
                elide: Text.ElideRight
                maximumLineCount: 2
                wrapMode: Text.Wrap
            }
        }

        Text {
            id: closeLabel
            text: "\u2715"
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSizeSmall
            anchors.verticalCenter: parent.verticalCenter

            MouseArea {
                anchors.fill: parent
                anchors.margins: -8
                cursorShape: Qt.PointingHandCursor
                onClicked: root.hide()
            }
        }
    }

    Behavior on opacity { NumberAnimation { duration: 150 } }
    Behavior on scale { NumberAnimation { duration: 150 } }

    Timer {
        id: autoHideTimer
        interval: root.duration
        running: false
        repeat: false
        onTriggered: root.hide()
    }

    function show() {
        opacity = 1
        scale = 1
        autoHideTimer.restart()
    }

    function hide() {
        autoHideTimer.stop()
        opacity = 0
        scale = 0.96
        hideTimer.start()
    }

    // Laisse le temps au fondu sortant de jouer avant de signaler la
    // suppression definitive (evite un "saut" visuel dans la ListView hote).
    Timer {
        id: hideTimer
        interval: 160
        running: false
        repeat: false
        onTriggered: root.dismissed()
    }

    Component.onCompleted: show()
}
