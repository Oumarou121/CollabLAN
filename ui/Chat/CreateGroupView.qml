import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import Core
import "../Components"

/*
 * CreateGroupView - sous-page "Nouveau groupe" : nom + membres, puis
 * MessagingContext::createGroup(name, memberIds).
 *
 * La selection est memorisee hors du modele de liste (selectedIds) : la
 * filtrer par la recherche ne perd plus les membres deja coches (defaut de
 * la version precedente, qui reconstruisait le modele avec selected=false).
 */
Item {
    id: root

    property var messagingContext: null
    property var _allUsers: []
    property var selectedIds: ({})
    property int selectedCount: 0
    property string errorText: ""

    signal backRequested()
    signal groupCreated(var groupId)

    readonly property string breadcrumbLeaf: qsTr("Nouveau groupe")

    function toggle(userId) {
        const copy = Object.assign({}, root.selectedIds)
        if (copy[userId]) delete copy[userId]
        else copy[userId] = true
        root.selectedIds = copy
        root.selectedCount = Object.keys(copy).length
    }

    function submit() {
        root.errorText = ""
        const name = groupNameField.text.trim()
        if (name.length === 0) {
            root.errorText = qsTr("Donnez un nom au groupe.")
            return
        }
        if (!root.messagingContext)
            return
        const members = Object.keys(root.selectedIds).map(function(k) { return parseInt(k) })
        const groupId = root.messagingContext.createGroup(name, members)
        if (groupId > 0)
            root.groupCreated(groupId)
        else
            root.errorText = qsTr("Le groupe n'a pas pu être créé. Vérifiez votre connexion au serveur puis réessayez.")
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.bg
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        AppHeader {
            title: qsTr("Nouveau groupe")
            subtitle: qsTr("Une conversation partagée avec plusieurs collègues du réseau local.")
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

            ColumnLayout {
                Layout.fillWidth: true
                Layout.margins: Theme.cardPadding
                spacing: Theme.spacingMedium

                AppTextField {
                    id: groupNameField
                    Layout.fillWidth: true
                    label: qsTr("Nom du groupe")
                    isRequired: true
                    placeholderText: qsTr("Ex. : Comptabilité, Équipe logistique")
                    hasError: root.errorText.length > 0 && groupNameField.text.trim().length === 0
                    helperText: hasError ? root.errorText : ""
                    onAccepted: root.submit()
                    Component.onCompleted: field.forceActiveFocus()
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: qsTr("Membres")
                        color: Theme.ink2
                        font.pixelSize: Theme.fs(12)
                        font.weight: Theme.weightSemibold
                        font.family: Theme.fontFamily
                    }
                    StatusBadge {
                        visible: root.selectedCount > 0
                        text: root.selectedCount === 1 ? qsTr("1 sélectionné")
                                                       : qsTr("%1 sélectionnés").arg(root.selectedCount)
                        tone: "accent"
                        compact: true
                    }
                    Item { Layout.fillWidth: true }
                }

                AppSearchField {
                    id: searchField
                    Layout.fillWidth: true
                    compact: true
                    placeholderText: qsTr("Rechercher un utilisateur")
                    onTextChanged: usersListView.applyFilter(text)
                }
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
                        availableUsersModel.append({ userId: u.userId, username: u.username })
                    }
                }

                delegate: CheckDelegate {
                    id: memberRow
                    required property var userId
                    required property string username
                    readonly property bool isSelected: root.selectedIds[memberRow.userId] === true

                    width: ListView.view.width
                    height: Theme.rowHeight - 4
                    leftPadding: Theme.cardPadding
                    rightPadding: Theme.cardPadding
                    checked: memberRow.isSelected
                    hoverEnabled: true
                    Accessible.name: memberRow.username
                    onClicked: root.toggle(memberRow.userId)

                    HoverHandler { cursorShape: Qt.PointingHandCursor }

                    background: Rectangle {
                        color: memberRow.isSelected ? Theme.alpha(Theme.accentColor, 0.06)
                                                    : (memberRow.hovered ? Theme.hover : "transparent")
                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: 1
                            color: Theme.line
                        }
                    }

                    indicator: Rectangle {
                        x: memberRow.width - width - memberRow.rightPadding
                        anchors.verticalCenter: parent.verticalCenter
                        width: 18
                        height: 18
                        radius: 5
                        color: memberRow.isSelected ? Theme.accentColor : Theme.surface0
                        border.width: memberRow.isSelected ? 0 : 1
                        border.color: Theme.lineStrong

                        FaIcon {
                            anchors.centerIn: parent
                            visible: memberRow.isSelected
                            glyph: ""
                            color: Theme.accentInk
                            font.pixelSize: Theme.fs(10)
                        }
                    }

                    contentItem: RowLayout {
                        spacing: 12
                        Avatar {
                            name: memberRow.username
                            size: 32
                        }
                        Text {
                            text: memberRow.username
                            color: Theme.ink
                            font.pixelSize: Theme.fs(14)
                            font.weight: memberRow.isSelected ? Theme.weightSemibold : Theme.weightRegular
                            font.family: Theme.fontFamily
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            Layout.rightMargin: 28
                        }
                    }
                }

                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            }

            EmptyState {
                visible: usersListView.count === 0
                Layout.fillWidth: true
                Layout.fillHeight: true
                compact: true
                iconName: searchField.text.length > 0 ? "search" : "users"
                title: searchField.text.length > 0 ? qsTr("Aucun utilisateur ne correspond")
                                                   : qsTr("Aucun autre utilisateur")
                description: searchField.text.length > 0 ? qsTr("Effacez la recherche pour voir tous les utilisateurs.")
                                                         : qsTr("Les comptes créés sur ce réseau apparaîtront ici.")
            }

            // ---- Pied : erreur + actions ----
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: Theme.line
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.margins: Theme.cardPadding
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    visible: root.errorText.length > 0 && groupNameField.text.trim().length > 0
                    spacing: 6
                    FaIcon {
                        glyph: ""
                        color: Theme.dangerInk
                        font.pixelSize: Theme.fs(12)
                    }
                    Text {
                        Layout.fillWidth: true
                        text: root.errorText
                        color: Theme.dangerInk
                        font.pixelSize: Theme.fs(12)
                        font.family: Theme.fontFamily
                        wrapMode: Text.WordWrap
                    }
                }
                Item {
                    Layout.fillWidth: true
                    visible: !(root.errorText.length > 0 && groupNameField.text.trim().length > 0)
                }

                AppButton {
                    text: qsTr("Annuler")
                    variant: "ghost"
                    onClicked: root.backRequested()
                }
                AppButton {
                    text: root.selectedCount > 0 ? qsTr("Créer le groupe (%1)").arg(root.selectedCount + 1)
                                                 : qsTr("Créer le groupe")
                    variant: "primary"
                    enabled: groupNameField.text.trim().length > 0
                    onClicked: root.submit()
                }
            }
        }
    }
}
