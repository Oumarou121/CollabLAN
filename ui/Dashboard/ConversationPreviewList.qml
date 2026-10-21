import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import "../Components"

/*
 * ConversationPreviewList - apercu des conversations recentes (tableau de
 * bord, role utilisateur). Donnees : MessagingContext.conversationsList()
 * (name, lastMessage, timestamp, unreadCount, conversationId).
 *
 * N'affiche aucun etat "livre"/"lu" : l'application ne le connait pas.
 */
ColumnLayout {
    id: root
    spacing: 0

    property var conversations: []

    signal conversationActivated(int conversationId)
    signal newConversationRequested()

    function timeLabel(value) {
        if (!value)
            return ""
        const d = new Date(value)
        if (isNaN(d.getTime()))
            return ""
        const today = new Date()
        if (d.toDateString() === today.toDateString())
            return d.toLocaleTimeString(Qt.locale(), "HH:mm")
        return d.toLocaleDateString(Qt.locale(), "d MMM")
    }

    EmptyState {
        visible: root.conversations.length === 0
        Layout.fillWidth: true
        Layout.fillHeight: true
        iconName: "chat"
        title: qsTr("Aucune conversation")
        description: qsTr("Écrivez à un collègue connecté au réseau local.")
        actionText: qsTr("Nouvelle conversation")
        onActionClicked: root.newConversationRequested()
    }

    Repeater {
        model: root.conversations

        delegate: ItemDelegate {
            id: row
            required property var modelData
            required property int index

            Layout.fillWidth: true
            implicitHeight: Theme.compact ? 48 : 56
            padding: 0
            leftPadding: 6
            rightPadding: 6
            hoverEnabled: true
            Accessible.name: row.modelData.name + (row.modelData.unreadCount > 0
                             ? ", " + qsTr("%1 non lu(s)").arg(row.modelData.unreadCount) : "")
            onClicked: root.conversationActivated(row.modelData.conversationId || 0)

            HoverHandler { cursorShape: Qt.PointingHandCursor }

            background: Rectangle {
                radius: Theme.radiusRow
                color: row.hovered ? Theme.hover : "transparent"
            }

            contentItem: RowLayout {
                spacing: 10

                Avatar {
                    name: row.modelData.name || ""
                    size: 32
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Text {
                            text: row.modelData.name || ""
                            color: Theme.ink
                            font.pixelSize: Theme.fs(13)
                            font.weight: row.modelData.unreadCount > 0 ? Theme.weightSemibold : Theme.weightMedium
                            font.family: Theme.fontFamily
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        Text {
                            text: root.timeLabel(row.modelData.timestamp)
                            color: Theme.ink3
                            font.pixelSize: Theme.fs(11)
                            font.family: Theme.fontFamily
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Text {
                            text: row.modelData.lastMessage || qsTr("Aucun message")
                            color: row.modelData.unreadCount > 0 ? Theme.ink2 : Theme.ink3
                            font.pixelSize: Theme.fs(12)
                            font.family: Theme.fontFamily
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        Rectangle {
                            visible: row.modelData.unreadCount > 0
                            Layout.preferredWidth: Math.max(18, unread.implicitWidth + 10)
                            Layout.preferredHeight: 18
                            radius: 9
                            color: Theme.accentColor

                            Text {
                                id: unread
                                anchors.centerIn: parent
                                text: row.modelData.unreadCount > 99 ? "99+" : row.modelData.unreadCount
                                color: Theme.accentInk
                                font.pixelSize: Theme.fs(10)
                                font.weight: Theme.weightBold
                                font.family: Theme.fontFamily
                            }
                        }
                    }
                }
            }
        }
    }

    Item { Layout.fillHeight: true; visible: root.conversations.length > 0 }
}
