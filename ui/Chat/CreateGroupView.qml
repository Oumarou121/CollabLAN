import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import Core
import "../Components"

/*
 * CreateGroupView - Écran de création de groupe
 * Permet de créer un nouveau groupe avec nom et sélection de membres
 *
 * Refonte design (juillet 2026) : meme alignement que NewConversationView
 * -- en-tete 64px a bordure basse seule, contenu centre a largeur
 * maximale, lignes de membre "carte" avec etat selectionne visible via
 * une pastille + une teinte primaire attenuee (plutot que le fond plein
 * Theme.accent d'origine, illisible avec Theme.text par-dessus).
 */
Item {
    id: root

    property var messagingContext: null
    property var _allUsers: []

    // Police d'icones Font Awesome 4.7.0, memes glyphes que Home.
    FontLoader {
        id: iconFont
        source: "../Assets/fonts/fontawesome-webfont.ttf"
    }
    readonly property string iconFontFamily: iconFont.name

    signal backRequested()
    signal groupCreated(var groupId)

    Rectangle {
        anchors.fill: parent
        color: Theme.background
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ---- En-tete --------------------------------------------------
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

                IconButton {
                    glyph: "\uf060"
                    variant: "ghost"
                    onClicked: root.backRequested()
                }

                Label {
                    Layout.fillWidth: true
                    text: qsTr("Créer un groupe")
                    font.pixelSize: Theme.fontSizeHeading
                    font.bold: true
                    font.family: Theme.fontFamily
                    color: Theme.text
                    elide: Text.ElideRight
                }
            }
        }

        // ---- Contenu principal : centre, largeur maximale --------------
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ColumnLayout {
                width: Math.min(parent.width - 2 * Theme.spacingXl, 720)
                height: parent.height - 2 * Theme.spacingLarge
                x: (parent.width - width) / 2
                y: Theme.spacingLarge
                spacing: Theme.spacingLarge

                // Nom du groupe
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingSmall

                    Label {
                        text: qsTr("Nom du groupe")
                        font.pixelSize: Theme.fontSizeSubheading
                        font.bold: true
                        font.family: Theme.fontFamily
                        color: Theme.text
                    }

                    TextField {
                        id: groupNameField
                        Layout.fillWidth: true
                        Layout.preferredHeight: 40
                        placeholderText: qsTr("Entrez le nom du groupe")
                        color: Theme.text
                        font.pixelSize: Theme.fontSizeBody
                        font.family: Theme.fontFamily
                        leftPadding: Theme.spacingMedium
                        selectByMouse: true

                        background: Rectangle {
                            color: Theme.surfaceAlt
                            radius: Theme.radiusMedium
                            border.color: groupNameField.activeFocus ? Theme.primary : Theme.border
                            border.width: groupNameField.activeFocus ? 2 : 1
                        }
                    }
                }

                // Sélection des membres
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: Theme.spacingSmall

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingSmall

                        Label {
                            text: qsTr("Membres")
                            font.pixelSize: Theme.fontSizeSubheading
                            font.bold: true
                            font.family: Theme.fontFamily
                            color: Theme.text
                        }

                        Item { Layout.fillWidth: true }

                        Rectangle {
                            visible: selectedCount.count > 0
                            Layout.preferredWidth: selectedLabel.implicitWidth + Theme.spacingMedium * 2
                            Layout.preferredHeight: 24
                            radius: height / 2
                            color: Theme.primaryMuted

                            Label {
                                id: selectedLabel
                                anchors.centerIn: parent
                                text: qsTr("%n sélectionné(s)", "", selectedCount.count)
                                font.pixelSize: Theme.fontSizeCaption
                                font.family: Theme.fontFamily
                                color: Theme.primary
                            }
                        }
                    }

                    // Compteur reactif des membres actuellement selectionnes.
                    QtObject {
                        id: selectedCount
                        property int count: 0
                    }

                    TextField {
                        id: memberSearchField
                        Layout.fillWidth: true
                        Layout.preferredHeight: 40
                        placeholderText: qsTr("Rechercher un utilisateur...")
                        color: Theme.text
                        font.pixelSize: Theme.fontSizeBody
                        font.family: Theme.fontFamily
                        leftPadding: Theme.spacingLarge
                        selectByMouse: true

                        background: Rectangle {
                            color: Theme.surfaceAlt
                            radius: Theme.radiusPill
                            border.width: memberSearchField.activeFocus ? 2 : 0
                            border.color: Theme.primary
                        }

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.spacingMedium
                            anchors.verticalCenter: parent.verticalCenter
                            text: "\uf002"
                            color: Theme.textTertiary
                            font.family: root.iconFontFamily
                            font.pixelSize: 13
                        }

                        onTextChanged: membersListView.applyFilter(text)
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: Theme.radiusLarge
                        color: Theme.surface
                        border.color: Theme.border
                        border.width: 1
                        clip: true

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: Theme.spacingSmall
                            visible: membersListView.count === 0
                            width: parent.width * 0.7

                            Label {
                                Layout.alignment: Qt.AlignHCenter
                                text: memberSearchField.text.length > 0
                                      ? qsTr("Aucun utilisateur ne correspond a votre recherche.")
                                      : qsTr("Aucun autre utilisateur disponible")
                                font.pixelSize: Theme.fontSizeBody
                                font.family: Theme.fontFamily
                                color: Theme.textSecondary
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                            }
                        }

                        ListView {
                            id: membersListView
                            anchors.fill: parent
                            anchors.margins: Theme.spacingMedium
                            spacing: Theme.spacingSmall
                            clip: true

                            model: ListModel {
                                id: availableUsersModel
                            }

                            Component.onCompleted: reloadUsers()

                            Connections {
                                target: root.messagingContext
                                function onAvailableUsersChanged() {
                                    membersListView.reloadUsers()
                                }
                            }

                            function reloadUsers() {
                                if (root.messagingContext) {
                                    root._allUsers = root.messagingContext.availableUsers()
                                }
                                applyFilter(memberSearchField.text)
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
                                        selected: false
                                    })
                                }
                                recomputeSelectedCount()
                            }

                            function recomputeSelectedCount() {
                                let n = 0
                                for (let i = 0; i < availableUsersModel.count; ++i) {
                                    if (availableUsersModel.get(i).selected) n++
                                }
                                selectedCount.count = n
                            }

                            delegate: Rectangle {
                                id: memberDelegate
                                width: membersListView.width
                                height: 56
                                color: selected
                                       ? Theme.primaryMuted
                                       : (itemMouse.containsMouse ? Theme.surfaceHover : Theme.surfaceAlt)
                                radius: Theme.radiusMedium
                                border.color: selected ? Theme.primary : Theme.border
                                border.width: selected ? 2 : 1

                                Behavior on color { ColorAnimation { duration: 100 } }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: Theme.spacingMedium
                                    anchors.rightMargin: Theme.spacingMedium
                                    spacing: Theme.spacingMedium

                                    Avatar {
                                        name: username
                                        size: 34
                                    }

                                    Label {
                                        Layout.fillWidth: true
                                        text: username
                                        font.pixelSize: Theme.fontSizeBody
                                        font.family: Theme.fontFamily
                                        color: Theme.text
                                        elide: Text.ElideRight
                                    }

                                    Rectangle {
                                        Layout.preferredWidth: 22
                                        Layout.preferredHeight: 22
                                        radius: Theme.radiusSmall
                                        color: selected ? Theme.primary : "transparent"
                                        border.color: selected ? Theme.primary : Theme.border
                                        border.width: 2

                                        Text {
                                            anchors.centerIn: parent
                                            visible: selected
                                            text: "\uf00c"
                                            color: Theme.primaryText
                                            font.family: root.iconFontFamily
                                            font.pixelSize: 11
                                        }
                                    }
                                }

                                MouseArea {
                                    id: itemMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        availableUsersModel.setProperty(index, "selected", !selected)
                                        membersListView.recomputeSelectedCount()
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
                    spacing: Theme.spacingMedium

                    AppButton {
                        Layout.fillWidth: true
                        variant: "outline"
                        text: qsTr("Annuler")
                        onClicked: root.backRequested()
                    }

                    AppButton {
                        Layout.fillWidth: true
                        variant: "primary"
                        text: qsTr("Créer le groupe")
                        enabled: groupNameField.text.trim().length > 0
                        onClicked: {
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
