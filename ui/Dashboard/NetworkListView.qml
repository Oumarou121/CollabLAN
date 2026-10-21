import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import "../Components"

/*
 * NetworkListView - Vue liste des postes réseau
 * Affiche les postes sous forme de tableau avec nom, IP, statut et actions
 * Design conforme à la maquette HTML V2.1
 */
Column {
    id: root
    spacing: 0

    property var peers: []
    property var offlinePeers: []
    property string localPeerName: "Ce poste"
    property string localPeerStatusLabel: "Serveur actif"
    property var activeTransfers: []
    property var activeCalls: []
    // Espace reserve en haut (titre de la carte en mode "chrome").
    property real topSpacing: 50

    signal peerClicked(var peer)
    signal messageRequested(var peer)
    signal transferRequested(var peer)
    signal callRequested(var peer)

    // Zone supérieure vide pour laisser l'espace au contrôle segmenté partagé
    Item {
        width: parent.width
        height: root.topSpacing
    }

    // Header du tableau - modernisation (priorité 17 du brief) : plus de
    // bandeau plein + bordure, juste un hairline inférieur et un libellé
    // discret (comme l'en-tête "Nom/Taille/Statut/Date" de Transfer Files).
    Rectangle {
        id: header
        width: parent.width
        height: 34
        color: "transparent"

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            color: Theme.hairline
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            spacing: 12

            Label {
                Layout.preferredWidth: 200
                text: qsTr("Poste")
                color: Theme.dashboardInkTertiary
                font.pixelSize: Theme.fs(11)
                font.weight: Theme.weightSemibold
                font.family: Theme.fontFamily
            }

            Label {
                Layout.preferredWidth: 140
                text: qsTr("Adresse IP")
                color: Theme.dashboardInkTertiary
                font.pixelSize: Theme.fs(11)
                font.weight: Theme.weightSemibold
                font.family: Theme.fontFamily
            }

            Label {
                Layout.preferredWidth: 120
                text: qsTr("Statut")
                color: Theme.dashboardInkTertiary
                font.pixelSize: Theme.fs(11)
                font.weight: Theme.weightSemibold
                font.family: Theme.fontFamily
            }

            Item {
                Layout.fillWidth: true
            }

            Label {
                Layout.preferredWidth: 80
                text: qsTr("Actions")
                color: Theme.dashboardInkTertiary
                font.pixelSize: Theme.fs(11)
                font.weight: Theme.weightSemibold
                font.family: Theme.fontFamily
            }
        }
    }

    // Liste des postes
    ScrollView {
        width: parent.width
        // Hauteur bornee a l'espace restant : la liste defile au lieu de deborder.
        height: Math.max(0, root.height - root.topSpacing - header.height)
        clip: true

        ListView {
            id: peerListView
            model: root.peers.length + root.offlinePeers.length
            spacing: 0

            delegate: Rectangle {
                id: rowRoot
                width: peerListView.width
                height: 56
                // Modernisation (priorité 17) : plus de zébrage alterné -
                // toutes les lignes partagent le même fond, séparées par un
                // hairline, avec une surface de survol pour l'interaction.
                color: rowHover.hovered ? Theme.surfaceLevel3 : "transparent"
                Behavior on color { ColorAnimation { duration: 100 } }

                // Bordure inférieure
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 1
                    color: Theme.hairline
                }

                HoverHandler { id: rowHover }

                // Zone de clic sur toute la ligne (ouvre le detail du poste) :
                // declaree AVANT les actions ci-dessous pour que les boutons
                // Message/Transferer/Appeler (a l'interieur de la RowLayout,
                // donc dessines par-dessus) recoivent les clics en priorite.
                // Declaree apres, elle les interceptait tous - le bouton
                // Appeler semblait ne rien faire.
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.peerClicked(getPeerData())
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 12

                    // Avatar
                    Rectangle {
                        Layout.preferredWidth: 32
                        Layout.preferredHeight: 32
                        radius: 16
                        color: isOnline ? Theme.dashboardPrimarySoft : Theme.dashboardNodeOffline
                        border.width: 2
                        border.color: statusColor

                        Text {
                            anchors.centerIn: parent
                            text: "\uf108"
                            color: isOnline ? Theme.dashboardPrimary : Theme.dashboardNodeOfflineInk
                            font.pixelSize: Theme.fs(14)
                            font.family: "FontAwesome"
                        }
                    }

                    // Nom du poste - dominant (priorité 8 du brief)
                    Label {
                        Layout.preferredWidth: 200
                        text: peerName
                        color: Theme.dashboardInk
                        font.pixelSize: Theme.fs(14)
                        font.weight: Theme.weightSemibold
                        font.family: Theme.fontFamily
                        elide: Text.ElideRight
                    }

                    // Adresse IP
                    Label {
                        Layout.preferredWidth: 140
                        text: peerData.address || ""
                        color: Theme.dashboardInkSecondary
                        font.pixelSize: Theme.fs(12)
                        font.family: Theme.fontFamily
                        elide: Text.ElideRight
                    }

                    // Statut - badge doux, moins "pastille lourde" (priorité 18)
                    Rectangle {
                        Layout.preferredWidth: statusRowContent.implicitWidth + 20
                        Layout.preferredHeight: 22
                        radius: Theme.radiusPill
                        color: statusBackgroundColor

                        Row {
                            id: statusRowContent
                            anchors.centerIn: parent
                            spacing: 5

                            Rectangle {
                                width: 6; height: 6; radius: 3
                                anchors.verticalCenter: parent.verticalCenter
                                color: statusTextColor
                            }
                            Label {
                                text: statusLabel
                                color: statusTextColor
                                font.pixelSize: Theme.fs(11)
                                font.weight: Theme.weightSemibold
                                font.family: Theme.fontFamily
                            }
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    // Actions : boutons d'icone du design system (clavier,
                    // info-bulle, nom accessible), jamais attenues : un bouton
                    // grise se confondrait avec un bouton desactive.
                    Row {
                        spacing: 2

                        IconButton {
                            id: msgAction
                            glyph: ""
                            size: 30
                            iconSize: Theme.fs(13)
                            enabled: isOnline
                            tooltip: isOnline ? qsTr("Envoyer un message à %1").arg(peerName)
                                              : qsTr("%1 est hors ligne").arg(peerName)
                            Accessible.name: qsTr("Envoyer un message à %1").arg(peerName)
                            onClicked: root.messageRequested(getPeerData())
                        }

                        IconButton {
                            id: xferAction
                            glyph: ""
                            size: 30
                            iconSize: Theme.fs(13)
                            enabled: isOnline
                            tooltip: isOnline ? qsTr("Envoyer un fichier à %1").arg(peerName)
                                              : qsTr("%1 est hors ligne").arg(peerName)
                            Accessible.name: qsTr("Envoyer un fichier à %1").arg(peerName)
                            onClicked: root.transferRequested(getPeerData())
                        }

                        IconButton {
                            id: callAction
                            glyph: ""
                            size: 30
                            iconSize: Theme.fs(13)
                            enabled: isOnline && status !== "calling"
                            tooltip: !isOnline ? qsTr("%1 est hors ligne").arg(peerName)
                                   : status === "calling" ? qsTr("%1 est déjà en communication").arg(peerName)
                                   : qsTr("Appeler %1").arg(peerName)
                            Accessible.name: qsTr("Appeler %1").arg(peerName)
                            onClicked: root.callRequested(getPeerData())
                        }
                    }
                }

                readonly property bool isOnline: index < root.peers.length
                readonly property var peerData: isOnline ? root.peers[index] : root.offlinePeers[index - root.peers.length]
                readonly property string peerName: peerData.name || ""
                readonly property string status: peerData.status || (isOnline ? "online" : "offline")

                readonly property color statusColor: {
                    switch (status) {
                    case "transferring": return Theme.dashboardPrimary
                    case "calling": return Theme.dashboardCall
                    case "away": return Theme.dashboardMarkAway
                    case "busy": return Theme.dashboardMarkAway
                    case "offline": return Theme.dashboardNodeOfflineLine
                    default: return Theme.dashboardSuccess
                    }
                }

                readonly property color statusBackgroundColor: {
                    switch (status) {
                    case "transferring": return Theme.dashboardPrimarySoft
                    case "calling": return Theme.dashboardCallSoft
                    case "away": return Theme.dashboardWarningSoft
                    case "busy": return Theme.dashboardWarningSoft
                    case "offline": return Theme.dashboardNodeOffline
                    default: return Theme.dashboardSuccessSoft
                    }
                }

                readonly property color statusTextColor: {
                    switch (status) {
                    case "transferring": return Theme.dashboardPrimary
                    case "calling": return Theme.dashboardCall
                    case "away": return Theme.dashboardWarningText
                    case "busy": return Theme.dashboardWarningText
                    case "offline": return Theme.dashboardInkTertiary
                    default: return Theme.dashboardSuccessText
                    }
                }

                readonly property string statusLabel: {
                    switch (status) {
                    case "transferring": return qsTr("En transfert")
                    case "calling": return qsTr("En appel")
                    case "away": return qsTr("Absent")
                    case "busy": return qsTr("Occupé")
                    case "offline": return qsTr("Hors ligne")
                    default: return qsTr("En ligne")
                    }
                }

                function getPeerData() {
                    return peerData
                }
            }
        }
    }
}
