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

    signal peerClicked(var peer)
    signal messageRequested(var peer)
    signal transferRequested(var peer)
    signal callRequested(var peer)

    // Zone supérieure vide pour laisser l'espace au contrôle segmenté partagé
    Item {
        width: parent.width
        height: 50
    }

    // Header du tableau
    Rectangle {
        id: header
        width: parent.width
        height: 40
        color: Theme.dashboardSurfaceAlt
        border.width: 1
        border.color: Theme.dashboardLine

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            spacing: 12

            Label {
                Layout.preferredWidth: 200
                text: qsTr("Poste")
                color: Theme.dashboardInkTertiary
                font.pixelSize: 12
                font.bold: true
                font.family: Theme.fontFamily
            }

            Label {
                Layout.preferredWidth: 140
                text: qsTr("Adresse IP")
                color: Theme.dashboardInkTertiary
                font.pixelSize: 12
                font.bold: true
                font.family: Theme.fontFamily
            }

            Label {
                Layout.preferredWidth: 120
                text: qsTr("Statut")
                color: Theme.dashboardInkTertiary
                font.pixelSize: 12
                font.bold: true
                font.family: Theme.fontFamily
            }

            Item {
                Layout.fillWidth: true
            }

            Label {
                Layout.preferredWidth: 80
                text: qsTr("Actions")
                color: Theme.dashboardInkTertiary
                font.pixelSize: 12
                font.bold: true
                font.family: Theme.fontFamily
            }
        }
    }

    // Liste des postes
    ScrollView {
        width: parent.width
        Layout.fillHeight: true
        clip: true

        ListView {
            id: peerListView
            model: root.peers.length + root.offlinePeers.length
            spacing: 0

            delegate: Rectangle {
                width: peerListView.width
                height: 56
                color: "transparent"
                border.width: 0
                border.color: Theme.dashboardLine

                // Fond alterné pour les lignes
                Rectangle {
                    anchors.fill: parent
                    color: index % 2 === 0 ? Theme.dashboardSurface : Theme.dashboardSurfaceAlt
                }

                // Bordure inférieure
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 1
                    color: Theme.dashboardLine
                }

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
                        color: isOnline ? Theme.dashboardPrimarySoft : "#F3F6F6"
                        border.width: 2
                        border.color: statusColor

                        Text {
                            anchors.centerIn: parent
                            text: "\uf108"
                            color: isOnline ? Theme.dashboardPrimary : "#8A98A0"
                            font.pixelSize: 14
                            font.family: "FontAwesome"
                        }
                    }

                    // Nom du poste
                    Label {
                        Layout.preferredWidth: 200
                        text: peerName
                        color: Theme.dashboardInk
                        font.pixelSize: 13
                        font.bold: true
                        font.family: Theme.fontFamily
                        elide: Text.ElideRight
                    }

                    // Adresse IP
                    Label {
                        Layout.preferredWidth: 140
                        text: peerData.address || ""
                        color: Theme.dashboardInkSecondary
                        font.pixelSize: 12
                        font.family: Theme.fontFamily
                        elide: Text.ElideRight
                    }

                    // Statut
                    Rectangle {
                        Layout.preferredWidth: 100
                        Layout.preferredHeight: 24
                        radius: 12
                        color: statusBackgroundColor

                        Label {
                            anchors.centerIn: parent
                            text: statusLabel
                            color: statusTextColor
                            font.pixelSize: 11
                            font.bold: true
                            font.family: Theme.fontFamily
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    // Actions
                    Row {
                        spacing: 8

                        Rectangle {
                            width: 32
                            height: 32
                            radius: 6
                            color: "transparent"
                            border.width: 1
                            border.color: isOnline ? Theme.dashboardLine : "#E4E8E7"
                            enabled: isOnline
                            opacity: enabled ? 1 : 0.5

                            Text {
                                anchors.centerIn: parent
                                text: "\uf0e0"
                                color: isOnline ? Theme.dashboardPrimary : "#B4C1C5"
                                font.pixelSize: 13
                                font.family: "FontAwesome"
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: if (enabled) root.messageRequested(getPeerData())
                            }
                        }

                        Rectangle {
                            width: 32
                            height: 32
                            radius: 6
                            color: "transparent"
                            border.width: 1
                            border.color: isOnline ? Theme.dashboardLine : "#E4E8E7"
                            enabled: isOnline
                            opacity: enabled ? 1 : 0.5

                            Text {
                                anchors.centerIn: parent
                                text: "\uf1d8"
                                color: isOnline ? Theme.dashboardPrimary : "#B4C1C5"
                                font.pixelSize: 13
                                font.family: "FontAwesome"
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: if (enabled) root.transferRequested(getPeerData())
                            }
                        }

                        Rectangle {
                            width: 32
                            height: 32
                            radius: 6
                            color: "transparent"
                            border.width: 1
                            border.color: isOnline ? Theme.dashboardLine : "#E4E8E7"
                            enabled: isOnline && status !== "calling"
                            opacity: enabled ? 1 : 0.5

                            Text {
                                anchors.centerIn: parent
                                text: "\uf095"
                                color: isOnline ? Theme.dashboardPrimary : "#B4C1C5"
                                font.pixelSize: 13
                                font.family: "FontAwesome"
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: if (enabled) root.callRequested(getPeerData())
                            }
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
                    case "away": return Theme.dashboardWarning
                    case "busy": return Theme.dashboardWarning
                    case "offline": return "#B4C1C5"
                    default: return Theme.dashboardSuccess
                    }
                }

                readonly property color statusBackgroundColor: {
                    switch (status) {
                    case "transferring": return Theme.dashboardPrimarySoft
                    case "calling": return Theme.dashboardCallSoft
                    case "away": return Theme.dashboardWarningSoft
                    case "busy": return Theme.dashboardWarningSoft
                    case "offline": return "#F3F6F6"
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
