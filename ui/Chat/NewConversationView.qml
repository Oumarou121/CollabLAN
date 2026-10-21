import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import Core
import "../Components"

/*
 * NewConversationView - sous-page "Nouvelle conversation" : choisir un
 * utilisateur et ouvrir (ou retrouver) la conversation individuelle via
 * MessagingContext::startConversationWith().
 */
Item {
    id: root

    property var messagingContext: null
    property var _allUsers: []

    signal backRequested()
    signal conversationStarted(var conversationId)

    readonly property string breadcrumbLeaf: qsTr("Nouvelle conversation")

    function statusLabel(status) {
        switch (status) {
        case "online": return qsTr("En ligne")
        case "away": return qsTr("Absent")
        case "busy": return qsTr("Occupé")
        default: return qsTr("Hors ligne")
        }
    }

    function startWith(userId) {
        if (!root.messagingContext)
            return
        const conversationId = root.messagingContext.startConversationWith(userId)
        if (conversationId > 0)
            root.conversationStarted(conversationId)
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.bg
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        AppHeader {
            title: qsTr("Nouvelle conversation")
            subtitle: qsTr("Choisissez la personne à qui écrire. Si une conversation existe déjà, elle sera rouverte.")
            showBackButton: true
            onBackRequested: root.backRequested()
        }

        Card {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.maximumWidth: 760
            Layout.leftMargin: Theme.pagePadding
            Layout.rightMargin: Theme.pagePadding
            Layout.bottomMargin: Theme.pagePadding
            contentPadding: 0

            AppSearchField {
                id: searchField
                Layout.fillWidth: true
                Layout.margins: Theme.cardPadding
                placeholderText: qsTr("Rechercher un utilisateur")
                onTextChanged: usersListView.applyFilter(text)
                Component.onCompleted: field.forceActiveFocus()
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: Theme.line
            }

            ListView {
                id: usersListView
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                keyNavigationEnabled: true
                boundsBehavior: Flickable.StopAtBounds

                model: ListModel { id: availableUsersModel }

                Component.onCompleted: reloadUsers()

                Connections {
                    target: root.messagingContext
                    ignoreUnknownSignals: true
                    function onAvailableUsersChanged() { usersListView.reloadUsers() }
                }

                function reloadUsers() {
                    if (root.messagingContext)
                        root._allUsers = root.messagingContext.availableUsers() || []
                    applyFilter(searchField.text)
                }

                function applyFilter(query) {
                    availableUsersModel.clear()
                    const needle = (query || "").toLowerCase()
                    for (let i = 0; i < root._allUsers.length; ++i) {
                        const u = root._allUsers[i]
                        if (needle.length > 0 && u.username.toLowerCase().indexOf(needle) === -1)
                            continue
                        availableUsersModel.append({
                            userId: u.userId,
                            username: u.username,
                            status: root.messagingContext ? root.messagingContext.userStatus(u.userId) : ""
                        })
                    }
                }

                delegate: ItemDelegate {
                    id: userRow
                    required property var userId
                    required property string username
                    required property string status

                    width: ListView.view.width
                    height: Theme.rowHeight
                    leftPadding: Theme.cardPadding
                    rightPadding: Theme.cardPadding
                    hoverEnabled: true
                    highlighted: ListView.isCurrentItem && usersListView.activeFocus
                    Accessible.name: qsTr("Écrire à %1").arg(userRow.username)
                    onClicked: root.startWith(userRow.userId)
                    Keys.onReturnPressed: root.startWith(userRow.userId)

                    HoverHandler { cursorShape: Qt.PointingHandCursor }

                    background: Rectangle {
                        color: userRow.hovered || userRow.highlighted ? Theme.hover : "transparent"
                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: 1
                            color: Theme.line
                        }
                    }

                    contentItem: RowLayout {
                        spacing: 12

                        Avatar {
                            name: userRow.username
                            size: 34
                            showStatus: userRow.status.length > 0
                            status: userRow.status
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            Text {
                                text: userRow.username
                                color: Theme.ink
                                font.pixelSize: Theme.fs(14)
                                font.weight: Theme.weightMedium
                                font.family: Theme.fontFamily
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            Text {
                                visible: userRow.status.length > 0
                                text: root.statusLabel(userRow.status)
                                color: Theme.ink3
                                font.pixelSize: Theme.fs(12)
                                font.family: Theme.fontFamily
                            }
                        }

                        AppButton {
                            text: qsTr("Écrire")
                            iconGlyph: ""
                            variant: userRow.hovered ? "soft" : "ghost"
                            size: "small"
                            focusPolicy: Qt.NoFocus
                            onClicked: root.startWith(userRow.userId)
                        }
                    }
                }

                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            }

            EmptyState {
                visible: usersListView.count === 0
                Layout.fillWidth: true
                Layout.fillHeight: true
                iconName: searchField.text.length > 0 ? "search" : "users"
                title: searchField.text.length > 0 ? qsTr("Aucun utilisateur ne correspond")
                                                   : qsTr("Aucun autre utilisateur")
                description: searchField.text.length > 0
                             ? qsTr("Vérifiez l'orthographe du nom ou effacez la recherche.")
                             : qsTr("Les comptes créés sur ce réseau apparaîtront ici.")
            }
        }
    }
}
