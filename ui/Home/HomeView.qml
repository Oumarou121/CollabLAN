import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import "../Components"

/*
 * HomeView - ecran "Home" (issue #6 : navigation de base Login -> Home)
 *
 * Point d'entree apres connexion. Affiche un accueil avec le nom
 * d'utilisateur transmis par LoginView, le bouton de theme et un bouton
 * de deconnexion qui ramene vers Login. La navigation vers les autres
 * modules (Chat, Users, FileTransfer, Call, Settings, Admin) sera ajoutee
 * dans une issue dediee.
 */
Item {
    id: root

    property string username: ""

    signal logoutRequested()
    signal usersRequested()

    Rectangle {
        anchors.fill: parent
        color: Theme.background
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Barre superieure
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 64
            color: Theme.surface
            border.color: Theme.border
            border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.spacingLarge
                anchors.rightMargin: Theme.spacingLarge
                spacing: Theme.spacingMedium

                Rectangle {
                    width: 36
                    height: 36
                    radius: 10
                    color: Theme.primary

                    Text {
                        anchors.centerIn: parent
                        text: "CL"
                        color: Theme.primaryText
                        font.pixelSize: 14
                        font.bold: true
                    }
                }

                Label {
                    text: qsTr("CollabLAN")
                    font.pixelSize: Theme.fontSizeHeading
                    font.bold: true
                    font.family: Theme.fontFamily
                    color: Theme.text
                }

                Item { Layout.fillWidth: true }

                RowLayout {
                    spacing: Theme.spacingSmall

                    Rectangle {
                        width: 32
                        height: 32
                        radius: 16
                        color: Theme.surfaceAlt

                        Text {
                            anchors.centerIn: parent
                            text: root.username.length > 0 ? root.username.charAt(0).toUpperCase() : "?"
                            color: Theme.text
                            font.pixelSize: Theme.fontSizeSmall
                            font.bold: true
                        }
                    }

                    Label {
                        text: root.username
                        color: Theme.text
                        font.pixelSize: Theme.fontSizeBody
                    }
                }

                Button {
                    text: qsTr("Postes connectes")
                    Layout.leftMargin: Theme.spacingSmall
                    Layout.preferredHeight: 36

                    background: Rectangle {
                        radius: Theme.radiusSmall
                        color: parent.hovered ? Theme.surfaceAlt : "transparent"
                        border.width: 1
                        border.color: Theme.border
                    }

                    contentItem: Text {
                        text: qsTr("Postes connectes")
                        color: Theme.text
                        font.pixelSize: Theme.fontSizeSmall
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    onClicked: root.usersRequested()
                }

                ThemeToggleButton {
                    Layout.leftMargin: Theme.spacingSmall
                }

                Button {
                    text: qsTr("Se deconnecter")
                    Layout.leftMargin: Theme.spacingSmall
                    Layout.preferredHeight: 36

                    background: Rectangle {
                        radius: Theme.radiusSmall
                        color: parent.hovered ? Theme.surfaceAlt : "transparent"
                        border.width: 1
                        border.color: Theme.border
                    }

                    contentItem: Text {
                        text: qsTr("Se deconnecter")
                        color: Theme.text
                        font.pixelSize: Theme.fontSizeSmall
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    onClicked: root.logoutRequested()
                }
            }
        }

        // Contenu principal
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.spacingLarge
                spacing: Theme.spacingMedium

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Theme.radiusLarge
                    color: Theme.surface
                    border.color: Theme.border
                    border.width: 1

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: Theme.spacingSmall
                        width: parent.width * 0.7

                        Label {
                            Layout.alignment: Qt.AlignHCenter
                            text: qsTr("Bienvenue, %1 !").arg(root.username)
                            font.pixelSize: Theme.fontSizeHeading
                            font.bold: true
                            color: Theme.text
                            horizontalAlignment: Text.AlignHCenter
                        }

                        Label {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.fillWidth: true
                            text: qsTr("Les modules Chat, Users, FileTransfer, Call et Settings seront accessibles ici prochainement.")
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeBody
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }
        }
    }
}
