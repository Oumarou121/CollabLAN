import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import "../Components"

/*
 * PeerDetailsPanel - Panneau de détails du poste sélectionné sur la carte
 * réseau, transcrit depuis .pop dans la maquette HTML (localink-workspace-v2-1.html).
 *
 * Structure conforme à la maquette :
 * - Pastille indicatrice (.nt) pointant vers le poste
 * - En-tête (.ph) : icône, nom, IP, bouton X
 * - Section transfert (.xfl) : statut, barre de progression, compte connecté
 * - Actions (.ac) : Envoyer fichier (plein), Appeler, Message
 *
 * Largeur maquette : 224px
 */
Rectangle {
    id: root
    width: 224
    implicitHeight: contentColumn.implicitHeight + 24
    radius: Theme.radiusMedium
    color: Theme.dashboardSurface
    border.width: 1
    border.color: Theme.dashboardLineStrong

    property string peerName: ""
    property string peerAddress: ""
    // online | away | busy | transferring | calling | offline
    property string peerStatus: "online"
    property string accountName: ""
    // { fileName, direction ("Envoi"/"Réception"), percent }
    property var activeTransfer: null

    // Pastille indicatrice - "left" (panneau à gauche du poste, pastille à
    // droite) ou "right" (panneau à droite, pastille à gauche)
    property string notchSide: "right"
    property real notchOffset: 30

    signal closeRequested()
    signal sendFileRequested()
    signal callRequested()
    signal messageRequested()

    // Bloque la propagation vers le fond du canevas
    MouseArea {
        anchors.fill: parent
        onClicked: {}
    }

    readonly property color statusColor: {
        switch (root.peerStatus) {
        case "transferring": return Theme.dashboardPrimary
        case "calling": return Theme.dashboardCall
        case "away": return Theme.dashboardWarning
        case "busy": return Theme.dashboardWarning
        case "offline": return Theme.dashboardInkTertiary
        default: return Theme.dashboardSuccess
        }
    }
    readonly property string statusLabel: {
        switch (root.peerStatus) {
        case "transferring": return qsTr("En transfert")
        case "calling": return qsTr("En appel")
        case "away": return qsTr("Absent")
        case "busy": return qsTr("Occupé")
        case "offline": return qsTr("Hors ligne")
        default: return qsTr("En ligne")
        }
    }

    // Pastille (notch) pointant vers le poste sélectionné - .nt dans la maquette
    Rectangle {
        width: 10
        height: 10
        color: Theme.dashboardSurface
        rotation: 45
        y: root.notchOffset
        x: root.notchSide === "right" ? -5 : root.width - 5
        border.width: 1
        border.color: Theme.dashboardLineStrong
        z: -1
    }

    ColumnLayout {
        id: contentColumn
        anchors.fill: parent
        anchors.margins: 12
        spacing: 12

        // En-tête (.ph) : icône, hostname, IP, fermeture
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Rectangle {
                Layout.preferredWidth: 36
                Layout.preferredHeight: 36
                radius: 18
                color: Theme.dashboardPrimarySoft

                Text {
                    anchors.centerIn: parent
                    text: "\uf108"
                    color: Theme.dashboardPrimary
                    font.pixelSize: 18
                    font.family: "FontAwesome"
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Label {
                    text: root.peerName
                    color: Theme.dashboardInk
                    font.pixelSize: 14
                    font.bold: true
                    font.family: Theme.fontFamily
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                Label {
                    text: root.peerAddress
                    color: Theme.dashboardInkTertiary
                    font.pixelSize: 12
                    font.family: Theme.fontFamily
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }

            Rectangle {
                Layout.preferredWidth: 26
                Layout.preferredHeight: 26
                radius: 13
                color: "transparent"
                border.width: 1
                border.color: Theme.dashboardLine

                Text {
                    anchors.centerIn: parent
                    text: "\uf00d"
                    color: Theme.dashboardInkTertiary
                    font.pixelSize: 14
                    font.family: "FontAwesome"
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.closeRequested()
                }
            }
        }

        // Section transfert (.xfl) : statut, barre de progression, compte connecté
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    Layout.preferredWidth: 8
                    Layout.preferredHeight: 8
                    radius: 4
                    color: root.statusColor
                }
                Label {
                    text: root.statusLabel
                    color: Theme.dashboardInkSecondary
                    font.pixelSize: 12
                    font.bold: true
                    font.family: Theme.fontFamily
                }
                Item { Layout.fillWidth: true }
                Label {
                    visible: root.activeTransfer !== null
                    text: root.activeTransfer ? (root.activeTransfer.percent + " %") : ""
                    color: Theme.dashboardInk
                    font.pixelSize: 12
                    font.bold: true
                    font.family: Theme.fontFamily
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 4
                radius: 2
                color: "#D9E2E0"
                visible: root.activeTransfer !== null

                Rectangle {
                    height: parent.height
                    radius: 2
                    color: Theme.dashboardPrimary
                    width: parent.width * (root.activeTransfer ? root.activeTransfer.percent / 100 : 0)
                }
            }

            Label {
                visible: root.activeTransfer !== null
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: root.activeTransfer
                      ? ((root.activeTransfer.direction === "Réception" ? qsTr("Envoi de ") : qsTr("Réception de ")) + root.activeTransfer.fileName)
                      : ""
                color: Theme.dashboardInkTertiary
                font.pixelSize: 11
                font.family: Theme.fontFamily
            }

            Label {
                visible: root.accountName.length > 0
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: qsTr("Compte connecté : ") + root.accountName
                color: Theme.dashboardInkTertiary
                font.pixelSize: 11
                font.family: Theme.fontFamily
            }
        }

        // Actions (.ac) : Envoyer fichier (plein), Appeler, Message
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                radius: 8
                color: Theme.dashboardPrimary
                enabled: root.peerStatus !== "offline"
                opacity: enabled ? 1 : 0.5

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 8

                    Text {
                        text: "\uf1d8"
                        color: Theme.dashboardSurface
                        font.pixelSize: 14
                        font.family: "FontAwesome"
                    }

                    Label {
                        text: qsTr("Envoyer un fichier")
                        color: Theme.dashboardSurface
                        font.pixelSize: 13
                        font.bold: true
                        font.family: Theme.fontFamily
                        Layout.fillWidth: true
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: if (enabled) root.sendFileRequested()
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32
                    radius: 8
                    color: "transparent"
                    border.width: 1
                    border.color: Theme.dashboardLine
                    enabled: root.peerStatus !== "offline" && root.peerStatus !== "calling"
                    opacity: enabled ? 1 : 0.5

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 8

                        Text {
                            text: "\uf095"
                            color: Theme.dashboardPrimary
                            font.pixelSize: 14
                            font.family: "FontAwesome"
                        }

                        Label {
                            text: qsTr("Appeler")
                            color: Theme.dashboardPrimary
                            font.pixelSize: 13
                            font.bold: true
                            font.family: Theme.fontFamily
                            Layout.fillWidth: true
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: if (enabled) root.callRequested()
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32
                    radius: 8
                    color: "transparent"
                    border.width: 1
                    border.color: Theme.dashboardLine

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 8

                        Text {
                            text: "\uf0e0"
                            color: Theme.dashboardPrimary
                            font.pixelSize: 14
                            font.family: "FontAwesome"
                        }

                        Label {
                            text: qsTr("Message")
                            color: Theme.dashboardPrimary
                            font.pixelSize: 13
                            font.bold: true
                            font.family: Theme.fontFamily
                            Layout.fillWidth: true
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.messageRequested()
                    }
                }
            }
        }
    }
}
