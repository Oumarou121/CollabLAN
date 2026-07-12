import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import Core

/*
 * NewConversationView - Ecran de demarrage d'une conversation individuelle
 * Permet de choisir un utilisateur et de creer (ou recuperer) la
 * conversation individuelle correspondante via
 * MessagingContext::startConversationWith().
 */
Item {
    id: root

    property var messagingContext: null

    signal backRequested()
    signal conversationStarted(var conversationId)

    Rectangle {
        anchors.fill: parent
        color: Theme.background
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Header
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 60
            color: Theme.surface
            border.color: Theme.border
            border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 10

                Button {
                    text: "←"
                    Layout.preferredWidth: 40
                    Layout.preferredHeight: 40
                    background: Rectangle {
                        color: parent.pressed ? Theme.accentDark : Theme.accent
                        radius: 5
                    }
                    contentItem: Label {
                        text: parent.text
                        color: Theme.text
                        font.pixelSize: 20
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    onClicked: root.backRequested()
                }

                Label {
                    Layout.fillWidth: true
                    text: "Nouvelle conversation"
                    font.pixelSize: 18
                    font.bold: true
                    color: Theme.text
                }
            }
        }

        // Contenu principal : liste des utilisateurs disponibles
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: Theme.background

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 12

                Label {
                    text: "Choisissez un utilisateur"
                    font.pixelSize: 14
                    color: Theme.text
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: Theme.surface
                    radius: 5
                    border.color: Theme.border
                    border.width: 1

                    // Etat vide : affiche tant qu'aucun autre utilisateur n'existe.
                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 8
                        visible: usersListView.count === 0
                        width: parent.width * 0.7

                        Label {
                            Layout.alignment: Qt.AlignHCenter
                            text: "Aucun autre utilisateur disponible"
                            font.pixelSize: 14
                            color: Theme.textSecondary
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                        }
                    }

                    ListView {
                        id: usersListView
                        anchors.fill: parent
                        anchors.margins: 5
                        spacing: 5
                        clip: true

                        model: ListModel {
                            id: availableUsersModel
                        }

                        Component.onCompleted: {
                            reloadUsers()
                        }

                        Connections {
                            target: root.messagingContext
                            function onAvailableUsersChanged() {
                                reloadUsers()
                            }
                        }

                        function reloadUsers() {
                            availableUsersModel.clear()
                            if (root.messagingContext) {
                                const users = root.messagingContext.availableUsers()
                                for (let i = 0; i < users.length; ++i) {
                                    availableUsersModel.append({
                                        userId: users[i].userId,
                                        username: users[i].username
                                    })
                                }
                            }
                        }

                        delegate: Rectangle {
                            width: usersListView.width
                            height: 44
                            color: Theme.surfaceAlt
                            radius: 5

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 10

                                Rectangle {
                                    Layout.preferredWidth: 30
                                    Layout.preferredHeight: 30
                                    radius: 15
                                    color: Theme.primary

                                    Text {
                                        anchors.centerIn: parent
                                        text: username && username.length > 0 ? username.charAt(0).toUpperCase() : "?"
                                        color: Theme.primaryText
                                        font.pixelSize: 13
                                        font.bold: true
                                    }
                                }

                                Label {
                                    Layout.fillWidth: true
                                    text: username
                                    font.pixelSize: 14
                                    color: Theme.text
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    if (root.messagingContext) {
                                        const conversationId = root.messagingContext.startConversationWith(userId)
                                        if (conversationId > 0) {
                                            root.conversationStarted(conversationId)
                                        }
                                    }
                                }
                            }
                        }

                        ScrollBar.vertical: ScrollBar {
                            policy: ScrollBar.AsNeeded
                        }
                    }
                }
            }
        }
    }
}
