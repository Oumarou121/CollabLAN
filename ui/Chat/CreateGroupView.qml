import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import Core

/*
 * CreateGroupView - Écran de création de groupe
 * Permet de créer un nouveau groupe avec nom et sélection de membres
 */
Item {
    id: root

    property var messagingContext: null

    signal backRequested()
    signal groupCreated(var groupId)

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
                    text: "Créer un groupe"
                    font.pixelSize: 18
                    font.bold: true
                    color: Theme.text
                }
            }
        }

        // Contenu principal
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: Theme.background

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 20

                // Nom du groupe
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Label {
                        text: "Nom du groupe"
                        font.pixelSize: 14
                        color: Theme.text
                    }

                    TextField {
                        id: groupNameField
                        Layout.fillWidth: true
                        Layout.preferredHeight: 40
                        placeholderText: "Entrez le nom du groupe"
                        color: Theme.text
                        background: Rectangle {
                            color: Theme.surface
                            radius: 5
                            border.color: groupNameField.activeFocus ? Theme.accent : Theme.border
                            border.width: groupNameField.activeFocus ? 2 : 1
                        }
                    }
                }

                // Sélection des membres
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 8

                    Label {
                        text: "Membres"
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

                        ListView {
                            id: membersListView
                            anchors.fill: parent
                            anchors.margins: 5
                            spacing: 5
                            clip: true

                            model: ListModel {
                                id: availableUsersModel
                            }

                            Component.onCompleted: {
                                if (root.messagingContext) {
                                    const users = root.messagingContext.availableUsers()
                                    for (let i = 0; i < users.length; ++i) {
                                        availableUsersModel.append({
                                            userId: users[i].userId,
                                            username: users[i].username,
                                            selected: false
                                        })
                                    }
                                }
                            }

                            delegate: Rectangle {
                                width: membersListView.width
                                height: 40
                                color: selected ? Theme.accent : Theme.surfaceAlt
                                radius: 5

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    spacing: 10

                                    CheckBox {
                                        checked: selected
                                        onCheckedChanged: {
                                            availableUsersModel.setProperty(index, "selected", checked)
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
                                        availableUsersModel.setProperty(index, "selected", !selected)
                                    }
                                }
                            }

                            ScrollBar.vertical: ScrollBar {
                                policy: ScrollBar.AsNeeded
                            }
                        }
                    }
                }

                // Boutons d'action
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Button {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 40
                        text: "Annuler"

                        background: Rectangle {
                            color: parent.pressed ? Theme.surfaceAlt : Theme.surface
                            radius: 5
                            border.color: Theme.border
                            border.width: 1
                        }

                        contentItem: Label {
                            text: parent.text
                            color: Theme.text
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }

                        onClicked: root.backRequested()
                    }

                    Button {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 40
                        text: "Créer le groupe"

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
                            if (groupNameField.text.trim() !== "" && root.messagingContext) {
                                // Récupérer les membres sélectionnés
                                var selectedMembers = []
                                for (var i = 0; i < availableUsersModel.count; i++) {
                                    if (availableUsersModel.get(i).selected) {
                                        selectedMembers.push(availableUsersModel.get(i).userId)
                                    }
                                }

                                const groupId = root.messagingContext.createGroup(groupNameField.text, selectedMembers)
                                if (groupId > 0) {
                                    root.groupCreated(groupId)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
