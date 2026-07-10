import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import Core

/*
 * ConversationsView - Vue de sélection des conversations
 * Liste les conversations disponibles et permet d'en sélectionner une
 */
Item {
    id: root

    property var messagingContext: null

    signal backRequested()
    signal conversationSelected(var conversationId)
    signal createGroupRequested()

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
                    text: "Conversations"
                    font.pixelSize: 18
                    font.bold: true
                    color: Theme.text
                }

                Button {
                    text: "+"
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
                    onClicked: {
                        root.createGroupRequested()
                    }
                }
            }
        }

        // Liste des conversations
        ListView {
            id: conversationsListView
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: 10
            spacing: 10
            clip: true

            model: ListModel {
                id: conversationsModel
            }

            Component.onCompleted: {
                if (root.messagingContext) {
                    const items = root.messagingContext.conversationsList()
                    for (let i = 0; i < items.length; ++i) {
                        conversationsModel.append({
                            conversationId: items[i].conversationId,
                            name: items[i].name,
                            lastMessage: items[i].lastMessage || "",
                            timestamp: items[i].timestamp ? Qt.formatDateTime(items[i].timestamp, "hh:mm") : ""
                        })
                    }
                }
            }

            delegate: Rectangle {
                width: conversationsListView.width
                height: 80
                color: Theme.surface
                radius: 10
                border.color: Theme.border
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 10

                    Rectangle {
                        Layout.preferredWidth: 50
                        Layout.preferredHeight: 50
                        radius: 25
                        color: Theme.primary

                        Text {
                            anchors.centerIn: parent
                            text: name.charAt(0)
                            color: Theme.primaryText
                            font.pixelSize: 20
                            font.bold: true
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 5

                        Label {
                            text: name
                            font.pixelSize: 14
                            font.bold: true
                            color: Theme.text
                        }

                        Label {
                            text: lastMessage
                            font.pixelSize: 12
                            color: Theme.textSecondary
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }

                    Label {
                        text: timestamp
                        font.pixelSize: 10
                        color: Theme.textSecondary
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        root.conversationSelected(conversationId)
                    }
                }
            }

            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
            }
        }
    }
}
