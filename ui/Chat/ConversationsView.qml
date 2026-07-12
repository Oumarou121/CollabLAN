import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import Core
import "../Components"

/*
 * ConversationsView - Vue de selection des conversations
 * Liste les conversations disponibles et permet d'en selectionner une
 */
Item {
    id: root

    property var messagingContext: null
    property var _allConversations: []

    signal backRequested()
    signal conversationSelected(var conversationId)
    signal createGroupRequested()
    signal newConversationRequested()

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
            Layout.preferredHeight: 64
            color: Theme.surface

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

                Label {
                    Layout.fillWidth: true
                    text: qsTr("Discussions")
                    font.pixelSize: Theme.fontSizeHeading
                    font.bold: true
                    font.family: Theme.fontFamily
                    color: Theme.text
                }

                AppButton {
                    variant: "ghost"
                    iconGlyph: "\u2709"
                    text: qsTr("Nouveau")
                    onClicked: root.newConversationRequested()
                }

                AppButton {
                    variant: "primary"
                    iconGlyph: "+"
                    text: qsTr("Groupe")
                    onClicked: root.createGroupRequested()
                }
            }
        }

        // Barre de recherche
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 56
            Layout.margins: 0

            TextField {
                id: searchField
                anchors.fill: parent
                anchors.margins: Theme.spacingMedium
                placeholderText: qsTr("Rechercher une conversation...")
                color: Theme.text
                font.pixelSize: Theme.fontSizeBody
                font.family: Theme.fontFamily
                leftPadding: Theme.spacingLarge
                selectByMouse: true

                background: Rectangle {
                    color: Theme.surfaceAlt
                    radius: Theme.radiusPill
                    border.width: searchField.activeFocus ? 2 : 0
                    border.color: Theme.primary
                }

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.spacingMedium
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\u2315"
                    color: Theme.textTertiary
                    font.pixelSize: 14
                }

                onTextChanged: conversationsListView.applyFilter(text)
            }
        }

        // Liste des conversations
        ListView {
            id: conversationsListView
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: Theme.spacingMedium
            Layout.rightMargin: Theme.spacingMedium
            Layout.bottomMargin: Theme.spacingMedium
            spacing: Theme.spacingSmall
            clip: true

            model: ListModel {
                id: conversationsModel
            }

            function reloadConversations() {
                if (root.messagingContext) {
                    root._allConversations = root.messagingContext.conversationsList()
                }
                applyFilter(searchField.text)
            }

            function applyFilter(query) {
                conversationsModel.clear()
                const needle = (query || "").toLowerCase()
                for (let i = 0; i < root._allConversations.length; ++i) {
                    const item = root._allConversations[i]
                    if (needle.length > 0 && item.name.toLowerCase().indexOf(needle) === -1)
                        continue
                    conversationsModel.append({
                        conversationId: item.conversationId,
                        name: item.name,
                        lastMessage: item.lastMessage || qsTr("Aucun message"),
                        timestamp: item.timestamp ? Qt.formatDateTime(item.timestamp, "hh:mm") : ""
                    })
                }
            }

            Component.onCompleted: reloadConversations()

            // Sans cette Connections, la liste ne se rafraichissait qu'a
            // l'ouverture de l'ecran (Component.onCompleted) : un nouveau
            // message ou un nouveau groupe cree/recu pendant que l'on est
            // deja sur cet ecran n'apparaissait qu'apres en etre sorti puis
            // revenu (issue rapportee : "bugs UI necessitant de sortir et
            // revenir pour les changements").
            Connections {
                target: root.messagingContext
                function onConversationsChanged() {
                    conversationsListView.reloadConversations()
                }
            }

            delegate: Rectangle {
                width: conversationsListView.width
                height: 76
                color: itemMouse.containsMouse ? Theme.surfaceHover : Theme.surface
                radius: Theme.radiusMedium
                border.color: Theme.border
                border.width: 1

                Behavior on color { ColorAnimation { duration: 100 } }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingMedium
                    spacing: Theme.spacingMedium

                    Avatar {
                        name: name
                        size: 44
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Label {
                            text: name
                            font.pixelSize: Theme.fontSizeBody
                            font.bold: true
                            font.family: Theme.fontFamily
                            color: Theme.text
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        Label {
                            text: lastMessage
                            font.pixelSize: Theme.fontSizeSmall
                            font.family: Theme.fontFamily
                            color: Theme.textSecondary
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }

                    Label {
                        text: timestamp
                        font.pixelSize: Theme.fontSizeCaption
                        font.family: Theme.fontFamily
                        color: Theme.textTertiary
                        Layout.alignment: Qt.AlignTop
                    }
                }

                MouseArea {
                    id: itemMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.conversationSelected(conversationId)
                }
            }

            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
            }

            // Etat vide
            Label {
                anchors.centerIn: parent
                visible: conversationsListView.count === 0
                text: searchField.text.length > 0
                      ? qsTr("Aucune conversation ne correspond a votre recherche.")
                      : qsTr("Aucune conversation pour le moment.\nDemarrez-en une nouvelle !")
                horizontalAlignment: Text.AlignHCenter
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeBody
                font.family: Theme.fontFamily
            }
        }
    }
}
