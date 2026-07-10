import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import Core

/*
 * ChatView - Interface de conversation individuelle
 * Branchée sur MessagingManager via MessagingContext
 */
Item {
    id: root

    property var messagingContext: null
    property var conversationId: 0

    signal backRequested()

    Rectangle {
        anchors.fill: parent
        color: Theme.background
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Header de la conversation
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 60
            color: Theme.secondaryBackground

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
                    text: "Conversation"
                    font.pixelSize: 18
                    font.bold: true
                    color: Theme.text
                }
            }
        }

        // Liste des messages
        ListView {
            id: messageListView
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: 10
            spacing: 10
            clip: true

            model: messagingContext ? messagingContext.messageModel : null

            delegate: Rectangle {
                width: messageListView.width
                height: messageColumn.height + 20
                color: senderId === currentUserId ? Theme.accent : Theme.surface
                radius: 10
                anchors.horizontalCenter: senderId === currentUserId ? Qt.AlignRight : Qt.AlignLeft

                property int currentUserId: 1  // TODO: Récupérer depuis UserManager

                Column {
                    id: messageColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 10
                    spacing: 5

                    Label {
                        width: parent.width
                        text: messagingContext ? messagingContext.userName(senderId) : ""
                        visible: senderId !== currentUserId
                        font.pixelSize: 11
                        font.bold: true
                        color: Theme.textSecondary
                    }

                    Label {
                        width: parent.width
                        text: content
                        wrapMode: Text.WordWrap
                        color: Theme.text
                        font.pixelSize: 14
                    }

                    Label {
                        text: timestamp ? Qt.formatDateTime(timestamp, "hh:mm:ss") : ""
                        font.pixelSize: 10
                        color: Theme.textSecondary
                        anchors.right: parent.right
                    }
                }
            }

            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
            }
        }

        // Zone de saisie de message
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 80
            color: Theme.secondaryBackground

            RowLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 10

                TextField {
                    id: messageInput
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    placeholderText: "Écrivez votre message..."
                    color: Theme.text
                    background: Rectangle {
                        color: Theme.background
                        radius: 5
                        border.color: messageInput.activeFocus ? Theme.accent : Theme.border
                        border.width: messageInput.activeFocus ? 2 : 1
                    }
                }

                Button {
                    Layout.preferredWidth: 80
                    Layout.preferredHeight: 50
                    text: "Envoyer"
                    background: Rectangle {
                        color: parent.pressed ? Theme.accentDark : Theme.accent
                        radius: 5
                    }
                    contentItem: Label {
                        text: parent.text
                        color: Theme.text
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    onClicked: {
                        if (messageInput.text.trim() !== "" && messagingContext) {
                            messagingContext.sendMessage(messageInput.text)
                            messageInput.text = ""
                        }
                    }
                }
            }
        }
    }

    // Charger la conversation lorsque conversationId change
    onConversationIdChanged: {
        if (messagingContext && conversationId > 0) {
            messagingContext.setConversation(conversationId)
        }
    }

    // Charger la conversation au démarrage
    Component.onCompleted: {
        if (messagingContext && conversationId > 0) {
            messagingContext.setConversation(conversationId)
        }
    }
}
