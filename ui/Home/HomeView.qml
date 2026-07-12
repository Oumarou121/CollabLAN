import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import "../Components"

/*
 * HomeView - ecran "Home" (issue #6 : navigation de base Login -> Home)
 *
 * Point d'entree apres connexion. Navigation laterale (sidebar) vers les
 * modules Chat, Users, FileTransfer, Call et Administration, et un
 * tableau de bord avec acces rapides sous forme de cartes.
 */
Item {
    id: root

    property string username: ""

    signal logoutRequested()
    signal usersRequested()
    signal chatRequested()
    signal fileTransferRequested()
    signal callRequested()
    signal callHistoryRequested()
    signal adminRequested()

    Rectangle {
        anchors.fill: parent
        color: Theme.background
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ---------------------------------------------------------------
        // Sidebar de navigation
        // ---------------------------------------------------------------
        Rectangle {
            Layout.preferredWidth: 248
            Layout.fillHeight: true
            color: Theme.sidebarBackground

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.spacingMedium
                spacing: Theme.spacingSmall

                // Logo / marque
                RowLayout {
                    Layout.fillWidth: true
                    Layout.bottomMargin: Theme.spacingLarge
                    spacing: Theme.spacingSmall

                    Rectangle {
                        width: 36
                        height: 36
                        radius: Theme.radiusMedium
                        color: Theme.primary

                        Text {
                            anchors.centerIn: parent
                            text: "CL"
                            color: "#FFFFFF"
                            font.pixelSize: 14
                            font.bold: true
                        }
                    }

                    Label {
                        text: qsTr("CollabLAN")
                        font.pixelSize: Theme.fontSizeHeading
                        font.bold: true
                        font.family: Theme.fontFamily
                        color: Theme.sidebarText
                    }

                    Item { Layout.fillWidth: true }
                }

                Label {
                    text: qsTr("NAVIGATION")
                    font.pixelSize: Theme.fontSizeCaption
                    font.bold: true
                    font.family: Theme.fontFamily
                    color: Theme.sidebarTextMuted
                    Layout.bottomMargin: Theme.spacingXs
                }

                SidebarNavItem {
                    Layout.fillWidth: true
                    icon: "\u2709"
                    label: qsTr("Discussions")
                    onClicked: root.chatRequested()
                }
                SidebarNavItem {
                    Layout.fillWidth: true
                    icon: "\u25CE"
                    label: qsTr("Postes connectes")
                    onClicked: root.usersRequested()
                }
                SidebarNavItem {
                    Layout.fillWidth: true
                    icon: "\u21C5"
                    label: qsTr("Transfert de fichiers")
                    onClicked: root.fileTransferRequested()
                }
                SidebarNavItem {
                    Layout.fillWidth: true
                    icon: "\u260E"
                    label: qsTr("Appel")
                    onClicked: root.callRequested()
                }
                SidebarNavItem {
                    Layout.fillWidth: true
                    icon: "\u23F1"
                    label: qsTr("Historique des appels")
                    onClicked: root.callHistoryRequested()
                }

                Item { Layout.preferredHeight: Theme.spacingMedium }

                Label {
                    text: qsTr("SYSTEME")
                    font.pixelSize: Theme.fontSizeCaption
                    font.bold: true
                    font.family: Theme.fontFamily
                    color: Theme.sidebarTextMuted
                    Layout.bottomMargin: Theme.spacingXs
                }

                SidebarNavItem {
                    Layout.fillWidth: true
                    icon: "\u2699"
                    label: qsTr("Administration")
                    onClicked: root.adminRequested()
                }

                Item { Layout.fillHeight: true }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Theme.sidebarBorder
                }

                // Profil utilisateur + actions rapides (theme / deconnexion)
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.spacingSmall
                    spacing: Theme.spacingSmall

                    Avatar {
                        name: root.username
                        size: 34
                    }

                    Label {
                        Layout.fillWidth: true
                        text: root.username
                        color: Theme.sidebarText
                        font.pixelSize: Theme.fontSizeBody
                        font.family: Theme.fontFamily
                        elide: Text.ElideRight
                    }

                    ThemeToggleButton {
                        Layout.preferredWidth: 32
                        Layout.preferredHeight: 32
                    }

                    Rectangle {
                        Layout.preferredWidth: 32
                        Layout.preferredHeight: 32
                        radius: Theme.radiusMedium
                        color: logoutArea.containsMouse ? Theme.sidebarHover : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: "\u23FB"
                            color: Theme.sidebarTextMuted
                            font.pixelSize: 14
                        }

                        MouseArea {
                            id: logoutArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.logoutRequested()
                        }

                        ToolTip.visible: logoutArea.containsMouse
                        ToolTip.delay: 400
                        ToolTip.text: qsTr("Se deconnecter")
                    }
                }
            }
        }

        // ---------------------------------------------------------------
        // Contenu principal : tableau de bord
        // ---------------------------------------------------------------
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Flickable {
                anchors.fill: parent
                contentWidth: width
                contentHeight: contentColumn.implicitHeight + 2 * Theme.spacingXl
                clip: true

                ColumnLayout {
                    id: contentColumn
                    width: Math.min(parent.width - 2 * Theme.spacingXl, 960)
                    x: Theme.spacingXl
                    y: Theme.spacingXl
                    spacing: Theme.spacingLarge

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingXs

                        Label {
                            text: qsTr("Bienvenue, %1").arg(root.username)
                            font.pixelSize: Theme.fontSizeTitle
                            font.bold: true
                            font.family: Theme.fontFamily
                            color: Theme.text
                        }

                        Label {
                            text: qsTr("Voici un acces rapide aux modules de votre reseau local.")
                            font.pixelSize: Theme.fontSizeBody
                            font.family: Theme.fontFamily
                            color: Theme.textSecondary
                        }
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: root.width > 760 ? 3 : (root.width > 520 ? 2 : 1)
                        columnSpacing: Theme.spacingMedium
                        rowSpacing: Theme.spacingMedium

                        DashboardCard {
                            Layout.fillWidth: true
                            icon: "\u2709"
                            title: qsTr("Discussions")
                            description: qsTr("Retrouvez vos conversations et groupes.")
                            onClicked: root.chatRequested()
                        }
                        DashboardCard {
                            Layout.fillWidth: true
                            icon: "\u25CE"
                            title: qsTr("Postes connectes")
                            description: qsTr("Voir qui est present sur le reseau.")
                            onClicked: root.usersRequested()
                        }
                        DashboardCard {
                            Layout.fillWidth: true
                            icon: "\u21C5"
                            title: qsTr("Transfert de fichiers")
                            description: qsTr("Envoyez et recevez des fichiers.")
                            onClicked: root.fileTransferRequested()
                        }
                        DashboardCard {
                            Layout.fillWidth: true
                            icon: "\u260E"
                            title: qsTr("Appel")
                            description: qsTr("Demarrez un appel audio.")
                            onClicked: root.callRequested()
                        }
                        DashboardCard {
                            Layout.fillWidth: true
                            icon: "\u23F1"
                            title: qsTr("Historique des appels")
                            description: qsTr("Consultez vos appels emis et recus.")
                            onClicked: root.callHistoryRequested()
                        }
                        DashboardCard {
                            Layout.fillWidth: true
                            icon: "\u2699"
                            title: qsTr("Administration")
                            description: qsTr("Gerez les utilisateurs et les postes.")
                            onClicked: root.adminRequested()
                        }
                    }
                }
            }
        }
    }

}
