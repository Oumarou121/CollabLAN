import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import Core
import "../Components"

/*
 * ChatView - Interface de conversation individuelle
 * Branchee sur MessagingManager via MessagingContext
 */
Item {
    id: root

    property var messagingContext: null
    property var conversationId: 0
    property string name: ""
    property int currentUserId: messagingContext ? messagingContext.currentUserId() : 0

    // Nom reel du contact/groupe : priorite au nom transmis par ConversationsView,
    // sinon repli sur la resolution cote MessagingContext (utile si ouvert sans nom)
    readonly property string displayName: name.length > 0
        ? name
        : (messagingContext ? messagingContext.conversationDisplayName(conversationId) : qsTr("Conversation"))

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
            Layout.preferredHeight: 64
            color: Theme.surface
            border.width: 0

            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: Theme.border
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.spacingMedium
                anchors.rightMargin: Theme.spacingMedium
                spacing: Theme.spacingSmall

                Rectangle {
                    Layout.preferredWidth: 36
                    Layout.preferredHeight: 36
                    radius: Theme.radiusMedium
                    color: backArea.containsMouse ? Theme.surfaceHover : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "\u2190"
                        color: Theme.text
                        font.pixelSize: 18
                    }

                    MouseArea {
                        id: backArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.backRequested()
                    }
                }

                Avatar {
                    name: root.displayName
                    size: 36
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    Label {
                        text: root.displayName
                        font.pixelSize: Theme.fontSizeSubheading
                        font.bold: true
                        font.family: Theme.fontFamily
                        color: Theme.text
                    }

                    // Le statut "En ligne" fige a ete retire : il n'y a pas
                    // encore de vrai suivi de presence par conversation.
                }
            }
        }

        // Liste des messages
        ListView {
            id: messageListView
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: Theme.spacingMedium
            spacing: Theme.spacingSmall
            clip: true
            verticalLayoutDirection: ListView.TopToBottom

            model: messagingContext ? messagingContext.messageModel : null

            onCountChanged: Qt.callLater(function() { messageListView.positionViewAtEnd() })

            delegate: Item {
                id: messageDelegate
                readonly property bool isMine: senderId === root.currentUserId
                width: messageListView.width
                height: bubble.height + 4

                Row {
                    anchors.right: messageDelegate.isMine ? parent.right : undefined
                    anchors.left: messageDelegate.isMine ? undefined : parent.left
                    width: Math.min(bubbleColumn.implicitWidth + 2 * Theme.spacingMedium,
                                    messageListView.width * 0.72)
                    spacing: Theme.spacingXs

                    Rectangle {
                        id: bubble
                        width: parent.width
                        height: bubbleColumn.implicitHeight + 2 * Theme.spacingSmall
                        radius: Theme.radiusLarge
                        color: messageDelegate.isMine ? Theme.primary : Theme.surface
                        border.width: messageDelegate.isMine ? 0 : 1
                        border.color: Theme.border

                        ColumnLayout {
                            id: bubbleColumn
                            anchors.fill: parent
                            anchors.margins: Theme.spacingSmall
                            spacing: 2

                            Label {
                                Layout.fillWidth: true
                                text: messagingContext ? messagingContext.userName(senderId) : ""
                                visible: !messageDelegate.isMine
                                font.pixelSize: Theme.fontSizeCaption
                                font.bold: true
                                font.family: Theme.fontFamily
                                color: Theme.colorForName(messagingContext ? messagingContext.userName(senderId) : "")
                            }

                            Label {
                                Layout.fillWidth: true
                                text: content
                                wrapMode: Text.WordWrap
                                color: messageDelegate.isMine ? "#FFFFFF" : Theme.text
                                font.pixelSize: Theme.fontSizeBody
                                font.family: Theme.fontFamily
                            }

                            Label {
                                Layout.alignment: Qt.AlignRight
                                text: timestamp ? Qt.formatDateTime(timestamp, "hh:mm") : ""
                                font.pixelSize: Theme.fontSizeCaption
                                font.family: Theme.fontFamily
                                color: messageDelegate.isMine ? "#FFFFFFB0" : Theme.textTertiary
                            }
                        }
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
            Layout.preferredHeight: 76
            color: Theme.surface

            Rectangle {
                anchors.top: parent.top
                width: parent.width
                height: 1
                color: Theme.border
            }

            RowLayout {
                anchors.fill: parent
                anchors.margins: Theme.spacingMedium
                spacing: Theme.spacingSmall

                TextField {
                    id: messageInput
                    Layout.fillWidth: true
                    Layout.preferredHeight: 44
                    placeholderText: qsTr("Ecrivez votre message...")
                    color: Theme.text
                    font.pixelSize: Theme.fontSizeBody
                    font.family: Theme.fontFamily
                    leftPadding: Theme.spacingMedium
                    rightPadding: Theme.spacingMedium
                    selectByMouse: true

                    background: Rectangle {
                        color: Theme.background
                        radius: Theme.radiusPill
                        border.color: messageInput.activeFocus ? Theme.primary : Theme.border
                        border.width: messageInput.activeFocus ? 2 : 1
                        Behavior on border.color { ColorAnimation { duration: 100 } }
                    }

                    onAccepted: sendButton.clicked()
                }

                Rectangle {
                    id: sendButton
                    Layout.preferredWidth: 44
                    Layout.preferredHeight: 44
                    radius: Theme.radiusPill
                    color: messageInput.text.trim().length > 0
                           ? (sendArea.pressed ? Theme.primaryHover : Theme.primary)
                           : Theme.surfaceAlt
                    Behavior on color { ColorAnimation { duration: 100 } }

                    Text {
                        anchors.centerIn: parent
                        text: "\u27A4"
                        color: messageInput.text.trim().length > 0 ? "#FFFFFF" : Theme.textTertiary
                        font.pixelSize: 16
                    }

                    MouseArea {
                        id: sendArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (messageInput.text.trim() !== "" && messagingContext) {
                                messagingContext.sendMessage(messageInput.text)
                                messageInput.text = ""
                                messageInput.forceActiveFocus()
                            }
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

    // Charger la conversation au demarrage
    Component.onCompleted: {
        if (messagingContext && conversationId > 0) {
            messagingContext.setConversation(conversationId)
        }
    }
}
