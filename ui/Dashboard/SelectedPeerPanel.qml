import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import "../Components"
import "transferFormat.js" as Fmt

/*
 * SelectedPeerPanel - panneau "Poste selectionne" du tableau de bord
 * (supervision). Affiche le poste choisi sur la carte reseau : identite,
 * activite en cours (transfert ou appel), adresse, derniere activite et,
 * pour un administrateur, le niveau de confiance.
 *
 * Purement presentationnel : les actions emettent des signaux, traites par
 * HomeView avec les fonctions metier existantes (les autorisations reelles
 * restent controlees cote metier et reseau).
 */
Rectangle {
    id: root

    // Poste selectionne (objet de NetworkWorkspace.peerById), ou null.
    property var peer: null
    property string userName: ""
    property string addressText: ""
    property string lastActivityText: ""
    // Vide : ligne masquee (non administrateur ou information indisponible).
    property string trustText: ""
    property string callText: ""

    signal messageRequested()
    signal sendFileRequested()
    signal callRequested()

    readonly property bool hasPeer: root.peer !== null && root.peer !== undefined
    readonly property string status: root.hasPeer ? (root.peer.status || "online") : "online"
    readonly property bool offline: root.status === "offline"
    readonly property var transfer: root.hasPeer ? root.peer.transfer : null

    readonly property string statusLabel: {
        switch (root.status) {
        case "transferring": return qsTr("En transfert")
        case "calling": return qsTr("En appel")
        case "away": return qsTr("Absent")
        case "busy": return qsTr("Occupé")
        case "offline": return qsTr("Hors ligne")
        default: return qsTr("En ligne")
        }
    }
    readonly property string statusTone: {
        switch (root.status) {
        case "transferring": return "accent"
        case "calling": return "call"
        case "away":
        case "busy": return "warning"
        case "offline": return "neutral"
        default: return "success"
        }
    }
    readonly property color ringColor: {
        switch (root.status) {
        case "transferring": return Theme.markTransfer
        case "calling": return Theme.callColor
        case "away":
        case "busy": return Theme.markAway
        case "offline": return Theme.nodeOfflineLine
        default: return Theme.successColor
        }
    }

    component KeyText: Text {
        color: Theme.ink3
        font.pixelSize: Theme.fs(12.5)
        font.family: Theme.fontFamily
    }
    component ValueText: Text {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignRight
        color: Theme.ink
        font.pixelSize: Theme.fs(12.5)
        font.weight: Theme.weightMedium
        font.family: Theme.fontFamily
        elide: Text.ElideLeft
    }

    radius: Theme.radiusCard
    color: Theme.surface0
    border.width: 1
    border.color: Theme.line
    implicitHeight: column.implicitHeight

    ColumnLayout {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 0

        // ---- En-tete ------------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 16
            Layout.rightMargin: 16
            Layout.topMargin: 14
            Layout.bottomMargin: 10
            Layout.minimumHeight: 24
            spacing: 10

            Text {
                text: qsTr("Poste sélectionné")
                color: Theme.ink
                font.pixelSize: Theme.fs(14)
                font.weight: Theme.weightSemibold
                font.family: Theme.fontFamily
                Accessible.role: Accessible.Heading
            }
            Item { Layout.fillWidth: true }
            StatusBadge {
                visible: root.hasPeer
                text: root.statusLabel
                tone: root.statusTone
                compact: true
            }
        }

        // ---- Aucun poste --------------------------------------------------
        EmptyState {
            visible: !root.hasPeer
            Layout.fillWidth: true
            Layout.bottomMargin: 16
            compact: true
            iconName: "peers"
            title: qsTr("Aucun poste sélectionné")
            description: qsTr("Cliquez sur un poste de la carte pour afficher ses détails.")
        }

        // ---- Identite -----------------------------------------------------
        RowLayout {
            visible: root.hasPeer
            Layout.fillWidth: true
            Layout.leftMargin: 16
            Layout.rightMargin: 16
            Layout.bottomMargin: 12
            spacing: 12

            Rectangle {
                Layout.preferredWidth: 44
                Layout.preferredHeight: 44
                radius: 22
                color: root.offline ? Theme.nodeOffline : Theme.accentSoft
                border.width: 2.5
                border.color: root.ringColor

                FaIcon {
                    anchors.centerIn: parent
                    glyph: ""
                    color: root.offline ? Theme.nodeOfflineInk : Theme.navActiveInk
                    font.pixelSize: Theme.fs(17)
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                Text {
                    id: nameText
                    Layout.fillWidth: true
                    text: root.hasPeer ? root.peer.name : ""
                    color: Theme.ink
                    font.pixelSize: Theme.fs(15)
                    font.weight: Theme.weightBold
                    font.family: Theme.fontFamily
                    elide: Text.ElideRight

                    // Nom complet en infobulle s'il est tronque.
                    HoverHandler { id: nameHover }
                    ToolTip.visible: nameHover.hovered && nameText.truncated
                    ToolTip.text: nameText.text
                }
                Text {
                    Layout.fillWidth: true
                    text: root.userName.length > 0 ? root.userName : qsTr("Utilisateur inconnu")
                    color: Theme.ink3
                    font.pixelSize: Theme.fs(12)
                    font.family: Theme.fontFamily
                    elide: Text.ElideRight
                }
            }
        }

        // ---- Transfert en cours -------------------------------------------
        Rectangle {
            visible: root.hasPeer && root.transfer !== null && root.transfer !== undefined
            Layout.fillWidth: true
            Layout.leftMargin: 16
            Layout.rightMargin: 16
            Layout.bottomMargin: 12
            implicitHeight: xferCol.implicitHeight + 20
            radius: Theme.radiusMedium
            color: Theme.surface1
            border.width: 1
            border.color: Theme.line

            ColumnLayout {
                id: xferCol
                anchors.fill: parent
                anchors.margins: 10
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 5

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    FaIcon {
                        glyph: root.transfer && root.transfer.incoming ? "" : ""
                        color: Theme.markTransfer
                        font.pixelSize: Theme.fs(11)
                    }
                    Text {
                        Layout.fillWidth: true
                        text: root.transfer ? (root.transfer.fileName || "") : ""
                        color: Theme.ink
                        font.pixelSize: Theme.fs(12.5)
                        font.weight: Theme.weightSemibold
                        font.family: Theme.fontFamily
                        elide: Text.ElideMiddle
                    }
                    Text {
                        text: root.transfer ? Math.round(root.transfer.percent || 0) + " %" : ""
                        color: Theme.ink3
                        font.pixelSize: Theme.fs(12)
                        font.family: Theme.fontFamily
                    }
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 5
                    radius: 3
                    color: Theme.sunken
                    Rectangle {
                        width: parent.width * Math.max(0, Math.min(1, root.transfer ? (root.transfer.percent || 0) / 100 : 0))
                        height: parent.height
                        radius: 3
                        color: Theme.accentColor
                        Behavior on width { NumberAnimation { duration: Theme.durationNormal } }
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: root.transfer && root.transfer.totalBytes > 0
                          ? qsTr("%1 sur %2 · %3").arg(Fmt.formatBytesPrecise(root.transfer.bytesTransferred || 0))
                                                  .arg(Fmt.formatBytesPrecise(root.transfer.totalBytes))
                                                  .arg(root.transfer.incoming ? qsTr("réception") : qsTr("envoi"))
                          : ""
                    visible: text.length > 0
                    color: Theme.ink3
                    font.pixelSize: Theme.fs(11.5)
                    font.family: Theme.fontFamily
                    elide: Text.ElideRight
                }
            }
        }

        // ---- Appel en cours -----------------------------------------------
        Rectangle {
            visible: root.hasPeer && root.callText.length > 0
            Layout.fillWidth: true
            Layout.leftMargin: 16
            Layout.rightMargin: 16
            Layout.bottomMargin: 12
            implicitHeight: 40
            radius: Theme.radiusMedium
            color: Theme.surface1
            border.width: 1
            border.color: Theme.line

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 8
                FaIcon { glyph: ""; color: Theme.callColor; font.pixelSize: Theme.fs(12) }
                Text {
                    Layout.fillWidth: true
                    text: root.callText
                    color: Theme.ink
                    font.pixelSize: Theme.fs(12.5)
                    font.weight: Theme.weightSemibold
                    font.family: Theme.fontFamily
                    elide: Text.ElideRight
                }
            }
        }

        // ---- Proprietes ---------------------------------------------------
        Rectangle {
            visible: root.hasPeer
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Theme.line
        }
        GridLayout {
            visible: root.hasPeer
            Layout.fillWidth: true
            Layout.leftMargin: 16
            Layout.rightMargin: 16
            Layout.topMargin: 12
            Layout.bottomMargin: 12
            columns: 2
            columnSpacing: 14
            rowSpacing: 7

            KeyText { text: qsTr("Adresse") }
            ValueText { text: root.addressText.length > 0 ? root.addressText : "—" }
            KeyText { text: qsTr("Dernière activité") }
            ValueText { text: root.lastActivityText.length > 0 ? root.lastActivityText : "—" }
            KeyText { visible: root.trustText.length > 0; text: qsTr("Confiance") }
            RowLayout {
                visible: root.trustText.length > 0
                Layout.fillWidth: true
                spacing: 5
                Item { Layout.fillWidth: true }
                FaIcon { glyph: ""; color: Theme.ink3; font.pixelSize: Theme.fs(11) }
                Text {
                    text: root.trustText
                    color: Theme.ink
                    font.pixelSize: Theme.fs(12.5)
                    font.weight: Theme.weightMedium
                    font.family: Theme.fontFamily
                }
            }
        }

        // ---- Actions ------------------------------------------------------
        GridLayout {
            visible: root.hasPeer
            Layout.fillWidth: true
            Layout.topMargin: 12
            Layout.leftMargin: 16
            Layout.rightMargin: 16
            Layout.bottomMargin: 14
            columns: 3
            columnSpacing: 8

            AppButton {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                size: "small"
                text: qsTr("Message")
                iconGlyph: ""
                enabled: !root.offline
                tooltip: root.offline ? qsTr("Poste hors ligne") : qsTr("Écrire à %1").arg(root.hasPeer ? root.peer.name : "")
                onClicked: root.messageRequested()
            }
            AppButton {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                size: "small"
                text: qsTr("Fichier")
                iconGlyph: ""
                enabled: !root.offline
                tooltip: root.offline ? qsTr("Poste hors ligne") : qsTr("Envoyer un fichier à %1").arg(root.hasPeer ? root.peer.name : "")
                onClicked: root.sendFileRequested()
            }
            AppButton {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                size: "small"
                text: qsTr("Appeler")
                iconGlyph: ""
                enabled: !root.offline && root.status !== "calling"
                tooltip: root.offline ? qsTr("Poste hors ligne")
                       : root.status === "calling" ? qsTr("Appel déjà en cours")
                       : qsTr("Appeler %1").arg(root.hasPeer ? root.peer.name : "")
                onClicked: root.callRequested()
            }
        }
    }
}
