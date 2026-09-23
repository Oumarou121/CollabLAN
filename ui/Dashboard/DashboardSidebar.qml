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

                readonly property bool isActive: modelData.route === "home"

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

        // Statut serveur - padding: 9px 10px, radius 10px, margin-bottom: 6px selon HTML
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 36
            Layout.bottomMargin: 6
            radius: 10
            color: Qt.rgba(1, 1, 1, 0.6)

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: isCompact ? 6 : 9
                anchors.rightMargin: isCompact ? 6 : 10
                spacing: isCompact ? 6 : 9

                Rectangle {
                    Layout.preferredWidth: isCompact ? 6 : 8
                    Layout.preferredHeight: isCompact ? 6 : 8
                    radius: isCompact ? 3 : 4
                    color: "#2E9A66"
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    visible: !root.isCompact

                    Label {
                        text: root.serverStatus
                        color: "#15222B"
                        font.pixelSize: 12
                        font.bold: true
                        font.family: Theme.fontFamily
                    }

                    Label {
                        text: qsTr("Ce poste")
                        color: "#62717A"
                        font.pixelSize: 11
                        font.family: Theme.fontFamily
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
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
                    spacing: 1
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

                    Label {
                        text: qsTr("Session active")
                        color: "#62717A"
                        font.pixelSize: 11
                        font.family: Theme.fontFamily
                    }
                }

                FaIcon {
                    glyph: "\u25BE"
                    color: "#62717A"
                    font.pixelSize: 12
                    visible: !root.isCompact
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: profileMenu.open()
            }
        }
    }

    // Menu profil
    Popup {
        id: profileMenu
        x: root.width - width - 10
        y: root.height - height - 70
        width: 200
        padding: 8
        modal: false
        closePolicy: Popup.CloseOnPressOutside | Popup.CloseOnEscape

        background: Rectangle {
            radius: 12
            color: "#FFFFFF"
            border.width: 1
            border.color: "#DDE4E2"
        }

        contentItem: ColumnLayout {
            spacing: 2

            Label {
                text: root.serverStatus
                color: "#4A5961"
                font.pixelSize: 12
                Layout.margins: 6
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: "#DDE4E2"
            }

            Button {
                text: qsTr("Paramètres")
                flat: true
                onClicked: { profileMenu.close(); root.settingsRequested() }
            }

            Button {
                text: qsTr("Déconnexion")
                flat: true
                onClicked: { profileMenu.close(); root.logoutRequested() }
            }
        }
    }
}
