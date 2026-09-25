import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import "../Components"

/*
 * DashboardSidebar - Sidebar selon la maquette HTML exacte
 * Width: 216px (réduit à 180px pour compact, 55px pour très compact)
 * Padding: 14px 10px 12px
 * Gap: 1px
 * Nav item height: 34px
 * Nav item radius: 8px
 */
Item {
    id: root
    width: implicitWidth
    implicitWidth: isCompact ? 55 : 180
    property bool isCompact: false
    property string username: ""
    property string serverStatus: "Serveur actif"
    property color serverStatusColor: "#2E9A66"
    property int unreadMessages: 0
    property int activeTransfers: 0
    property int pendingAdmin: 0
    property bool isAdmin: false
    // Route active dans la navigation ("home", "chat", "transfer",
    // "folder", "call", "peers") - fournie par l'écran hôte (ou par
    // DashboardShell) plutôt que hardcodée, pour que chaque écran migré
    // vers le Dashboard puisse mettre en évidence sa propre entrée.
    property string activeRoute: "home"

    signal homeRequested()
    signal chatRequested()
    signal transferRequested()
    signal foldersRequested()
    signal callRequested()
    signal peersRequested()
    signal adminRequested()
    signal settingsRequested()
    signal logoutRequested()

    Rectangle {
        anchors.fill: parent
        color: "#E4EAE9"
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: isCompact ? 8 : 14
        anchors.leftMargin: isCompact ? 6 : 10
        anchors.rightMargin: isCompact ? 6 : 10
        anchors.bottomMargin: isCompact ? 8 : 12
        spacing: 1

        // Branding - padding: 2px 8px 16px selon nouvelle maquette
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: isCompact ? 36 : 44
            Layout.topMargin: isCompact ? 2 : 2
            Layout.leftMargin: isCompact ? 5 : 8
            Layout.rightMargin: isCompact ? 5 : 8
            Layout.bottomMargin: isCompact ? 8 : 16
            spacing: isCompact ? 6 : 10

            Rectangle {
                Layout.preferredWidth: 30
                Layout.preferredHeight: 30
                radius: 8
                color: "#0B5C70"

                Label {
                    anchors.centerIn: parent
                    text: "\uf015"
                    color: "#FFFFFF"
                    font.pixelSize: 18
                    font.family: "FontAwesome"
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                visible: !root.isCompact

                Label {
                    text: qsTr("LocaLink")
                    color: "#15222B"
                    font.pixelSize: 15
                    font.bold: true
                    font.family: Theme.fontFamily
                }

                Label {
                    text: qsTr("Espace entreprise")
                    color: "#62717A"
                    font.pixelSize: 11
                    font.family: Theme.fontFamily
                }
            }
        }

        // Navigation principale
        Repeater {
            model: [
                { route: "home", icon: "\uf015", label: "Vue d'ensemble" },
                { route: "chat", icon: "\uf0e5", label: "Discussions" },
                { route: "transfer", icon: "\uf1d8", label: "Transferts" },
                { route: "folder", icon: "\uf07b", label: "Dossiers partagés" },
                { route: "call", icon: "\uf095", label: "Appels" },
                { route: "peers", icon: "\uf108", label: "Postes" }
            ]
            delegate: Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 32

                readonly property bool isActive: modelData.route === root.activeRoute

                Rectangle {
                    anchors.fill: parent
                    radius: 8
                    color: {
                        if (parent.isActive) return "#FFFFFF"
                        if (navMouse.containsMouse) return Qt.rgba(1, 1, 1, 0.55)
                        return "transparent"
                    }
                    visible: parent.isActive || navMouse.containsMouse
                }

                readonly property string itemLabel: modelData.label || ""
                readonly property string itemIcon: modelData.icon || ""

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: isCompact ? 6 : 10
                    anchors.rightMargin: isCompact ? 6 : 10
                    spacing: isCompact ? 6 : 10

                    FaIcon {
                        glyph: itemIcon
                        color: parent.parent.isActive ? "#0B5C70" : (navMouse.containsMouse ? "#15222B" : "#4A5961")
                        font.pixelSize: 16
                        Layout.preferredWidth: root.isCompact ? -1 : 17
                        Layout.alignment: root.isCompact ? Qt.AlignHCenter : Qt.AlignVCenter
                    }

                    Label {
                        text: itemLabel ? qsTr(itemLabel) : ""
                        color: parent.parent.isActive ? "#0B5C70" : (navMouse.containsMouse ? "#15222B" : "#4A5961")
                        font.pixelSize: 12
                        font.weight: parent.parent.isActive ? 650 : 500
                        font.family: Theme.fontFamily
                        Layout.fillWidth: true
                        visible: !root.isCompact
                        elide: Text.ElideRight
                    }

                    // Badge pour transferts
                    Rectangle {
                        visible: {
                            if (modelData.route === "transfer" && root.activeTransfers > 0 && !root.isCompact) return true
                            if (modelData.route === "chat" && root.unreadMessages > 0 && !root.isCompact) return true
                            return false
                        }
                        Layout.preferredWidth: Math.max(18, badgeContent.width + 10)
                        Layout.preferredHeight: 18
                        radius: 9
                        color: modelData.route === "chat" ? "#0B5C70" : "#C27A0E"

                        RowLayout {
                            id: badgeContent
                            anchors.centerIn: parent
                            spacing: 0

                            Label {
                                text: {
                                    if (modelData.route === "transfer") return root.activeTransfers > 99 ? "99+" : root.activeTransfers
                                    if (modelData.route === "chat") return root.unreadMessages > 99 ? "99+" : root.unreadMessages
                                    return ""
                                }
                                color: "#FFFFFF"
                                font.pixelSize: 11
                                font.bold: true
                                font.family: Theme.fontFamily
                            }
                        }
                    }
                }

                MouseArea {
                    id: navMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        switch(modelData.route) {
                            case "home": root.homeRequested(); break
                            case "chat": root.chatRequested(); break
                            case "transfer": root.transferRequested(); break
                            case "folder": root.foldersRequested(); break
                            case "call": root.callRequested(); break
                            case "peers": root.peersRequested(); break
                        }
                    }
                }
            }
        }

        // Séparateur - height 14px
        Item {
            Layout.preferredHeight: 14
        }

        // Navigation secondaire
        Repeater {
            model: [
                { route: "journal", icon: "\uf03a", label: "Journal" },
                { route: "admin", icon: "\uf132", label: "Administration" }
            ]
            delegate: Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                visible: modelData.route !== "admin" || root.isAdmin

                Rectangle {
                    anchors.fill: parent
                    radius: 8
                    color: navMouse2.containsMouse ? Qt.rgba(1, 1, 1, 0.55) : "transparent"
                    visible: navMouse2.containsMouse
                }

                readonly property string itemLabel: modelData.label || ""
                readonly property string itemIcon: modelData.icon || ""

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: isCompact ? 6 : 10
                    anchors.rightMargin: isCompact ? 6 : 10
                    spacing: isCompact ? 6 : 10

                    FaIcon {
                        glyph: itemIcon
                        color: navMouse2.containsMouse ? "#15222B" : "#4A5961"
                        font.pixelSize: 16
                        Layout.preferredWidth: root.isCompact ? -1 : 17
                        Layout.alignment: root.isCompact ? Qt.AlignHCenter : Qt.AlignVCenter
                    }

                    Label {
                        text: itemLabel ? qsTr(itemLabel) : ""
                        color: navMouse2.containsMouse ? "#15222B" : "#4A5961"
                        font.pixelSize: 12
                        font.weight: 500
                        font.family: Theme.fontFamily
                        Layout.fillWidth: true
                        visible: !root.isCompact
                    }

                    // Badge admin
                    Rectangle {
                        visible: modelData.route === "admin" && root.pendingAdmin > 0 && !root.isCompact
                        Layout.preferredWidth: Math.max(18, badgeContent.width + 10)
                        Layout.preferredHeight: 18
                        radius: 9
                        color: "#C27A0E"

                        RowLayout {
                            id: badgeContent
                            anchors.centerIn: parent
                            spacing: 0

                            Label {
                                text: root.pendingAdmin > 99 ? "99+" : root.pendingAdmin
                                color: "#FFFFFF"
                                font.pixelSize: 11
                                font.bold: true
                                font.family: Theme.fontFamily
                            }
                        }
                    }
                }

                MouseArea {
                    id: navMouse2
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (modelData.route === "admin") root.adminRequested()
                    }
                }
            }
        }

        Item { Layout.fillHeight: true }

        // Paramètres
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 32

            Rectangle {
                anchors.fill: parent
                radius: 8
                color: navMouse3.containsMouse ? Qt.rgba(1, 1, 1, 0.55) : "transparent"
                visible: navMouse3.containsMouse
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: isCompact ? 6 : 10
                anchors.rightMargin: isCompact ? 6 : 10
                spacing: isCompact ? 6 : 10

                FaIcon {
                    glyph: "\uf1de"
                    color: navMouse3.containsMouse ? "#15222B" : "#4A5961"
                    font.pixelSize: 16
                    Layout.preferredWidth: root.isCompact ? -1 : 17
                    Layout.alignment: root.isCompact ? Qt.AlignHCenter : Qt.AlignVCenter
                }

                Label {
                    text: qsTr("Paramètres")
                    color: navMouse3.containsMouse ? "#15222B" : "#4A5961"
                    font.pixelSize: 12
                    font.weight: 500
                    font.family: Theme.fontFamily
                    Layout.fillWidth: true
                    visible: !root.isCompact
                }
            }

            MouseArea {
                id: navMouse3
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.settingsRequested()
            }
        }

        // Profil utilisateur - padding: 10px 8px 0, margin-top: 6px, border-top selon HTML
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 50
            Layout.topMargin: 6

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 1
                color: "#C8D2CF"
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: isCompact ? 6 : 8
                anchors.rightMargin: isCompact ? 6 : 8
                anchors.topMargin: 10
                spacing: isCompact ? 6 : 10

                Rectangle {
                    Layout.preferredWidth: 30
                    Layout.preferredHeight: 30
                    radius: 15
                    color: "#0B5C70"

                    Label {
                        anchors.centerIn: parent
                        text: (root.username || "U").charAt(0).toUpperCase()
                        color: "#FFFFFF"
                        font.pixelSize: 14
                        font.bold: true
                        font.family: Theme.fontFamily
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    visible: !root.isCompact

                    Label {
                        text: root.username || qsTr("Utilisateur")
                        color: "#15222B"
                        font.pixelSize: 12
                        font.bold: true
                        font.family: Theme.fontFamily
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    // Sélecteur de statut local
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        visible: typeof discoveryService !== "undefined"

                        Repeater {
                            model: [
                                { status: "online", icon: "\uf00c", color: "#2E9A66" },
                                { status: "away", icon: "\uf111", color: "#C27A0E" },
                                { status: "busy", icon: "\uf07b", color: "#C27A0E" }
                            ]

                            Rectangle {
                                Layout.preferredWidth: 24
                                Layout.preferredHeight: 24
                                radius: 12
                                color: typeof discoveryService !== "undefined" && discoveryService.localStatus === modelData.status ? modelData.color : "#DDE4E2"

                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.icon
                                    color: typeof discoveryService !== "undefined" && discoveryService.localStatus === modelData.status ? "#FFFFFF" : "#62717A"
                                    font.pixelSize: 10
                                    font.family: "FontAwesome"
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (typeof discoveryService !== "undefined") {
                                            discoveryService.localStatus = modelData.status
                                        }
                                    }
                                }
                            }
                        }

                        Item { Layout.fillWidth: true }
                    }
                }
            }
        }

        // Bouton Déconnexion
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 32
            Layout.topMargin: 8

            Rectangle {
                anchors.fill: parent
                radius: 8
                color: logoutMouseArea.containsMouse ? Qt.rgba(1, 1, 1, 0.55) : "transparent"
                visible: logoutMouseArea.containsMouse
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: isCompact ? 6 : 10
                anchors.rightMargin: isCompact ? 6 : 10
                spacing: isCompact ? 6 : 10

                FaIcon {
                    glyph: "\uf08b"
                    color: logoutMouseArea.containsMouse ? "#15222B" : "#4A5961"
                    font.pixelSize: 16
                    Layout.preferredWidth: root.isCompact ? -1 : 17
                    Layout.alignment: root.isCompact ? Qt.AlignHCenter : Qt.AlignVCenter
                }

                Label {
                    text: qsTr("Déconnexion")
                    color: logoutMouseArea.containsMouse ? "#15222B" : "#4A5961"
                    font.pixelSize: 12
                    font.family: Theme.fontFamily
                    Layout.fillWidth: true
                    visible: !root.isCompact
                }
            }

            MouseArea {
                id: logoutMouseArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.logoutRequested()
            }
        }
    }
}
