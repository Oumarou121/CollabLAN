import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import Core
import "../Components"

/*
 * ConversationsView - liste des conversations (panneau gauche de
 * l'espace Discussions).
 *
 * Donnees : MessagingContext.conversationsList() (conversationId, name,
 * lastMessage, timestamp, unreadCount), rechargee a chaque signal
 * conversationsChanged. Recherche locale et filtre "Non lues".
 * Aucun etat d'envoi/lecture n'est affiche : l'application ne le connait
 * pas.
 */
Item {
    id: root

    property var messagingContext: null
    property var _allConversations: []

    // Conserves pour compatibilite (la navigation est fournie par AppShell).
    property bool showBackButton: false
    property bool compactActions: true
    property var selectedConversationId: null
    readonly property string iconFontFamily: "FontAwesome"

    property bool unreadOnly: false

    signal backRequested()
    signal conversationSelected(var conversationId, string name)
    signal createGroupRequested()
    signal newConversationRequested()

    function timeLabel(value) {
        if (!value)
            return ""
        const d = new Date(value)
        if (isNaN(d.getTime()))
            return ""
        const now = new Date()
        if (d.toDateString() === now.toDateString())
            return d.toLocaleTimeString(Qt.locale(), "HH:mm")
        const yesterday = new Date(now.getTime() - 86400000)
        if (d.toDateString() === yesterday.toDateString())
            return qsTr("Hier")
        if (now.getTime() - d.getTime() < 6 * 86400000)
            return d.toLocaleDateString(Qt.locale(), "ddd")
        return d.toLocaleDateString(Qt.locale(), "d MMM")
    }

    readonly property int unreadConversations: {
        let n = 0
        for (let i = 0; i < root._allConversations.length; i++)
            if ((root._allConversations[i].unreadCount || 0) > 0) n++
        return n
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.surface0
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ---- En-tete ----------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Theme.cardPadding
            Layout.rightMargin: Theme.cardPadding - 4
            Layout.topMargin: 14
            Layout.bottomMargin: 10
            spacing: 8

            IconButton {
                visible: root.showBackButton
                glyph: ""
                tooltip: qsTr("Retour")
                onClicked: root.backRequested()
            }

            Text {
                Layout.fillWidth: true
                text: qsTr("Discussions")
                color: Theme.ink
                font.pixelSize: Theme.fs(16)
                font.weight: Theme.weightBold
                font.family: Theme.fontFamily
                elide: Text.ElideRight
                Accessible.role: Accessible.Heading
            }

            IconButton {
                id: newButton
                glyph: ""
                variant: "soft"
                size: Theme.controlHeightSmall + 2
                iconSize: Theme.fs(13)
                tooltip: qsTr("Nouvelle conversation ou nouveau groupe")
                onClicked: newMenu.popup(newButton, newButton.width - newMenu.implicitWidth, newButton.height + 4)
            }

            AppMenu {
                id: newMenu
                AppMenuItem {
                    text: qsTr("Nouvelle conversation")
                    iconGlyph: ""
                    onTriggered: root.newConversationRequested()
                }
                AppMenuItem {
                    text: qsTr("Nouveau groupe")
                    iconGlyph: ""
                    onTriggered: root.createGroupRequested()
                }
            }
        }

        AppSearchField {
            id: searchField
            Layout.fillWidth: true
            Layout.leftMargin: Theme.cardPadding
            Layout.rightMargin: Theme.cardPadding
            compact: true
            placeholderText: qsTr("Rechercher une conversation")
            onTextChanged: conversationsListView.applyFilter()
        }

        AppSegmentedControl {
            Layout.fillWidth: true
            Layout.leftMargin: Theme.cardPadding
            Layout.rightMargin: Theme.cardPadding
            Layout.topMargin: 10
            Layout.bottomMargin: 8
            small: true
            model: [ { label: qsTr("Toutes") },
                     { label: root.unreadConversations > 0 ? qsTr("Non lues (%1)").arg(root.unreadConversations)
                                                           : qsTr("Non lues") } ]
            currentIndex: root.unreadOnly ? 1 : 0
            onActivated: function(index) {
                root.unreadOnly = index === 1
                conversationsListView.applyFilter()
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Theme.line
        }

        ListView {
            id: conversationsListView
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: 6
            clip: true
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds

            model: ListModel { id: conversationsModel }

            function reloadConversations() {
                if (root.messagingContext)
                    root._allConversations = root.messagingContext.conversationsList() || []
                applyFilter()
            }

            function applyFilter() {
                conversationsModel.clear()
                const needle = (searchField.text || "").toLowerCase()
                for (let i = 0; i < root._allConversations.length; ++i) {
                    const item = root._allConversations[i]
                    if (needle.length > 0 && (item.name || "").toLowerCase().indexOf(needle) === -1)
                        continue
                    if (root.unreadOnly && !(item.unreadCount > 0))
                        continue
                    conversationsModel.append({
                        conversationId: item.conversationId,
                        name: item.name || "",
                        lastMessage: item.lastMessage || "",
                        timeText: root.timeLabel(item.timestamp),
                        unreadCount: item.unreadCount || 0
                    })
                }
            }

            Component.onCompleted: reloadConversations()

            Connections {
                target: root.messagingContext
                ignoreUnknownSignals: true
                function onConversationsChanged() { conversationsListView.reloadConversations() }
            }

            delegate: ItemDelegate {
                id: row
                required property var conversationId
                required property string name
                required property string lastMessage
                required property string timeText
                required property int unreadCount

                readonly property bool isSelected: root.selectedConversationId !== null
                                                   && root.selectedConversationId !== undefined
                                                   && row.conversationId === root.selectedConversationId

                width: ListView.view.width
                height: Theme.compact ? 54 : 62
                leftPadding: Theme.cardPadding - 6
                rightPadding: Theme.cardPadding - 6
                leftInset: 8
                rightInset: 8
                hoverEnabled: true
                highlighted: row.isSelected
                Accessible.name: row.name + (row.unreadCount > 0 ? ", " + qsTr("%1 non lu(s)").arg(row.unreadCount) : "")
                onClicked: root.conversationSelected(row.conversationId, row.name)

                HoverHandler { cursorShape: Qt.PointingHandCursor }

                background: Rectangle {
                    radius: Theme.radiusRow
                    color: row.isSelected ? Theme.accentSoft : (row.hovered ? Theme.hover : "transparent")

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: -2
                        radius: parent.radius + 2
                        color: "transparent"
                        border.width: 2
                        border.color: Theme.focusRing
                        visible: row.visualFocus
                    }
                }

                contentItem: RowLayout {
                    spacing: 10

                    Avatar {
                        Layout.leftMargin: 8
                        name: row.name
                        size: 36
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Text {
                                text: row.name
                                color: Theme.ink
                                font.pixelSize: Theme.fs(13)
                                font.weight: row.unreadCount > 0 ? Theme.weightSemibold : Theme.weightMedium
                                font.family: Theme.fontFamily
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            Text {
                                text: row.timeText
                                color: row.unreadCount > 0 ? (Theme.darkMode ? Theme.accentHover : Theme.accentColor) : Theme.ink3
                                font.pixelSize: Theme.fs(11)
                                font.weight: row.unreadCount > 0 ? Theme.weightSemibold : Theme.weightRegular
                                font.family: Theme.fontFamily
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Text {
                                text: row.lastMessage.length > 0 ? row.lastMessage : qsTr("Aucun message")
                                color: row.unreadCount > 0 ? Theme.ink2 : Theme.ink3
                                font.pixelSize: Theme.fs(12)
                                font.italic: row.lastMessage.length === 0
                                font.family: Theme.fontFamily
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            Rectangle {
                                visible: row.unreadCount > 0
                                Layout.rightMargin: 8
                                Layout.preferredWidth: Math.max(18, unreadText.implicitWidth + 10)
                                Layout.preferredHeight: 18
                                radius: 9
                                color: Theme.accentColor

                                Text {
                                    id: unreadText
                                    anchors.centerIn: parent
                                    text: row.unreadCount > 99 ? "99+" : row.unreadCount
                                    color: Theme.accentInk
                                    font.pixelSize: Theme.fs(10)
                                    font.weight: Theme.weightBold
                                    font.family: Theme.fontFamily
                                }
                            }
                            Item { visible: row.unreadCount === 0; Layout.preferredWidth: 8 }
                        }
                    }
                }
            }

            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        }

        EmptyState {
            visible: conversationsListView.count === 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: Theme.cardPadding
            compact: true
            iconName: searchField.text.length > 0 || root.unreadOnly ? "search" : "chat"
            title: searchField.text.length > 0 ? qsTr("Aucune conversation ne correspond")
                 : root.unreadOnly ? qsTr("Aucun message non lu")
                 : qsTr("Aucune conversation")
            description: searchField.text.length > 0 ? qsTr("Vérifiez l'orthographe ou effacez la recherche.")
                       : root.unreadOnly ? qsTr("Vous êtes à jour.")
                       : qsTr("Démarrez une discussion avec un collègue connecté au réseau.")
            actionText: searchField.text.length > 0 || root.unreadOnly ? "" : qsTr("Nouvelle conversation")
            onActionClicked: root.newConversationRequested()
        }
    }
}
