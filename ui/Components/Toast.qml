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
    property string category: "message" // "message" | "transfer" | "connection" | "disconnection" | "group" | "folder"
    property int duration: 4000

    // Design A (carte enrichie, cf. notification_design_concepts.html)
    // reserve aux messages : avatar + nom d'expediteur, le reste
    // (transfert/connexion/deconnexion/groupe/dossier) reste sur le
    // design B (pilule compacte, une ligne).
    readonly property bool isCard: category === "message"

    // Emis quand l'utilisateur clique "Repondre" sur une carte message.
    // NB: notificationRequested() ne transporte aujourd'hui ni l'id de
    // l'expediteur ni celui de la conversation -- le titre (nom resolu,
    // cf. NotificationManager::onMessageReceived) est tout ce qu'on peut
    // remonter pour l'instant. Pour ouvrir reellement la conversation
    // correspondante il faudra etendre le signal C++ avec un identifiant.
    signal replyRequested(string senderName)
    signal dismissed()

    readonly property color accentColor: {
        switch (category) {
        case "transfer": return Theme.primary
        case "connection": return Theme.success
        case "disconnection": return Theme.textSecondary
        case "group": return Theme.accent
        case "folder": return Theme.primary
        default: return Theme.accent
        }
    }

    readonly property string iconGlyph: {
        switch (category) {
        case "transfer": return "\u21C5"       // fleches haut/bas (transfert)
        case "connection": return "\u25CF"      // point plein (en ligne)
        case "disconnection": return "\u25CB"   // point vide (hors ligne)
        case "group": return "\u2637"           // symbole groupe/postes
        case "folder": return "\u25A1"          // dossier
        default: return "\u2709"                // enveloppe (message)
        }
    }

    function initials(name) {
        const trimmed = (name || "").trim()
        if (trimmed.length === 0)
            return ""
        const parts = trimmed.split(/\s+/)
        if (parts.length === 1)
            return parts[0].substring(0, 2).toUpperCase()
        return (parts[0].charAt(0) + parts[parts.length - 1].charAt(0)).toUpperCase()
    }

    // Horodatage relatif (cf. maquette "il y a 2 min"). createdAt est fige
    // a l'affichage du toast ; _tick force la reevaluation de elapsedText()
    // toutes les 30s (un toast reste rarement affiche plus de 4s par
    // defaut, mais peut etre laisse ouvert plus longtemps par l'utilisateur).
    property real createdAt: 0
    property int _tick: 0

    function elapsedText() {
        _tick // force la dependance au timer
        const diffMin = Math.floor((Date.now() - createdAt) / 60000)
        if (diffMin < 1)
            return qsTr("à l'instant")
        if (diffMin === 1)
            return qsTr("il y a 1 min")
        return qsTr("il y a %1 min").arg(diffMin)
    }

    Timer {
        interval: 30000
        running: root.isCard
        repeat: true
        onTriggered: root._tick++
    }

    width: root.isCard
           ? Math.min(360, parent ? parent.width - 32 : 360)
           : Math.min(pillRow.implicitWidth + Theme.spacingMedium * 2, parent ? parent.width - 32 : 320)
    height: root.isCard ? cardColumn.implicitHeight + Theme.spacingMedium * 2 : 44
    radius: root.isCard ? Theme.radiusMedium : Theme.radiusPill
    color: Theme.surface
    border.color: Theme.border
    border.width: 1
    clip: true

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

    // ---- Design A : carte enrichie (messages) -----------------------------

    Row {
        id: cardRow
        visible: root.isCard
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: Theme.spacingMedium
        anchors.rightMargin: Theme.spacingSmall
        anchors.topMargin: Theme.spacingMedium
        spacing: Theme.spacingSmall

        Rectangle {
            id: avatar
            width: 36
            height: 36
            radius: 18
            color: Theme.colorForName(root.title)

            Text {
                anchors.centerIn: parent
                text: root.initials(root.title)
                color: "#FFFFFF"
                font.pixelSize: Theme.fontSizeSmall
                font.bold: true
            }
        }

        Column {
            id: cardColumn
            width: cardRow.width - cardRow.spacing * 2 - avatar.width - closeLabelCard.width
            spacing: 3

            Row {
                width: parent.width
                spacing: Theme.spacingXs

                Text {
                    id: senderName
                    text: root.title
                    color: Theme.text
                    font.pixelSize: Theme.fontSizeBody
                    font.bold: true
                    elide: Text.ElideRight
                    width: parent.width - timestampLabel.width - Theme.spacingXs
                }
                Text {
                    id: timestampLabel
                    text: root.elapsedText()
                    color: Theme.textTertiary
                    font.pixelSize: Theme.fontSizeCaption
                }
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

            Text {
                text: qsTr("Répondre")
                color: Theme.primary
                font.pixelSize: Theme.fontSizeSmall
                font.bold: true
                topPadding: 2

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -4
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.replyRequested(root.title)
                }
            }
        }

        Text {
            id: closeLabelCard
            text: "\u2715"
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSizeSmall

            MouseArea {
                anchors.fill: parent
                anchors.margins: -8
                cursorShape: Qt.PointingHandCursor
                onClicked: root.hide()
            }
        }
    }

    // Barre de progression (temps restant avant disparition automatique).
    Rectangle {
        id: progressBar
        visible: root.isCard
        height: 2
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        color: root.accentColor
        width: parent.width * progressFraction

        property real progressFraction: 1.0
    }

    // ---- Design B : pilule minimaliste (transfert / connexion / etc.) -----

    Row {
        id: pillRow
        visible: !root.isCard
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Theme.spacingMedium
        anchors.rightMargin: Theme.spacingSmall
        spacing: Theme.spacingSmall

        Text {
            text: root.iconGlyph
            color: root.accentColor
            font.pixelSize: Theme.fontSizeBody
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            id: pillMessage
            text: root.message
            color: Theme.text
            font.pixelSize: Theme.fontSizeSmall
            elide: Text.ElideRight
            anchors.verticalCenter: parent.verticalCenter
            width: pillRow.width - pillRow.spacing * 2 - closeLabelPill.width - 16
        }

        Text {
            id: closeLabelPill
            text: "\u2715"
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSizeCaption
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
        if (isCard) {
            progressBar.progressFraction = 1.0
            progressAnimation.restart()
        }
    }

    NumberAnimation {
        id: progressAnimation
        target: progressBar
        property: "progressFraction"
        from: 1.0
        to: 0.0
        duration: root.duration
        easing.type: Easing.Linear
    }

    function hide() {
        autoHideTimer.stop()
        progressAnimation.stop()
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

    Component.onCompleted: {
        createdAt = Date.now()
        show()
    }
}
