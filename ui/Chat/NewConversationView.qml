import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import Core
import "../Components"

/*
 * NewConversationView - Ecran de demarrage d'une conversation individuelle
 * Permet de choisir un utilisateur et de creer (ou recuperer) la
 * conversation individuelle correspondante via
 * MessagingContext::startConversationWith().
 *
 * Refonte design (juillet 2026) : alignement sur le style deja retenu pour
 * ConversationsView/ChatView/UsersView -- en-tete 64px a bordure basse
 * seule, recherche integree, lignes de liste "carte" (avec survol et
 * Avatar partage), et contenu centre a largeur maximale pour rester
 * lisible sur les grands ecrans desktop.
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
    signal conversationStarted(var conversationId)

    Rectangle {
        anchors.fill: parent
        color: Theme.background
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ---- En-tete (aligne sur ChatView/ConversationsView : ombre douce
        // flottante plutot qu'un filet 1px) ----
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 72
            color: Theme.surface
            z: 2

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.bottom
                height: 8
                z: -1
                gradient: Gradient {
                    orientation: Gradient.Vertical
                    GradientStop { position: 0.0; color: Theme.shadowSoft }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.spacingLarge
                anchors.rightMargin: Theme.spacingLarge
                spacing: Theme.spacingSmall

                IconButton {
                    glyph: "\uf060"
                    variant: "ghost"
                    onClicked: root.backRequested()
                }

                Label {
                    Layout.fillWidth: true
                    text: qsTr("Nouvelle conversation")
                    font.pixelSize: Theme.fontSizeHeading
                    font.bold: true
                    font.family: Theme.fontFamily
                    color: Theme.text
                    elide: Text.ElideRight
                }
            }
        }

        // ---- Contenu principal : liste centree, largeur maximale ---------
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ColumnLayout {
                id: contentColumn
                width: Math.min(parent.width - 2 * Theme.spacingXl, 720)
                height: parent.height - 2 * Theme.spacingLarge
                x: (parent.width - width) / 2
                y: Theme.spacingLarge
                spacing: Theme.spacingMedium

                Label {
                    text: qsTr("Choisissez un utilisateur")
                    font.pixelSize: Theme.fontSizeSubheading
                    font.bold: true
                    font.family: Theme.fontFamily
                    color: Theme.text
                }

                TextField {
                    id: searchField
                    Layout.fillWidth: true
                    Layout.preferredHeight: 48
                    placeholderText: qsTr("Rechercher un utilisateur...")
                    color: Theme.text
                    font.pixelSize: Theme.fontSizeBody
                    font.family: Theme.fontFamily
                    leftPadding: 40
                    selectByMouse: true

                    background: Rectangle {
                        color: Theme.surfaceAlt
                        radius: Theme.radiusMedium
                        border.color: searchField.activeFocus ? Theme.primary : Theme.border
                        border.width: searchField.activeFocus ? 2 : 1
                        Behavior on border.color { ColorAnimation { duration: 100 } }
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

                    onTextChanged: usersListView.applyFilter(text)
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Theme.radiusLarge
                    color: Theme.surface
                    border.width: 0
                    clip: true

                    Rectangle {
                        anchors.fill: parent
                        anchors.topMargin: 2
                        radius: parent.radius
                        color: Theme.shadowSoft
                        z: -1
                    }

                    // Etat vide : affiche tant qu'aucun autre utilisateur n'existe.
                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: Theme.spacingSmall
                        visible: usersListView.count === 0
                        width: parent.width * 0.7

                        Label {
                            Layout.alignment: Qt.AlignHCenter
                            text: searchField.text.length > 0
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
                        id: usersListView
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
                                usersListView.reloadUsers()
                            }
                        }

                        function reloadUsers() {
                            if (root.messagingContext) {
                                root._allUsers = root.messagingContext.availableUsers()
                            }
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
                                    username: u.username
                                })
                            }
                        }

                        delegate: Rectangle {
                            id: userDelegate
                            width: usersListView.width
                            height: 60
                            color: itemMouse.containsMouse ? Theme.surfaceHover : Theme.surfaceAlt
                            radius: Theme.radiusMedium
                            border.width: 0

                            Behavior on color { ColorAnimation { duration: 100 } }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Theme.spacingMedium
                                anchors.rightMargin: Theme.spacingMedium
                                spacing: Theme.spacingMedium

                                Avatar {
                                    name: username
                                    size: 38
                                }

                                Label {
                                    Layout.fillWidth: true
                                    text: username
                                    font.pixelSize: Theme.fontSizeBody
                                    font.family: Theme.fontFamily
                                    color: Theme.text
                                    elide: Text.ElideRight
                                }

                                Text {
                                    text: "\uf054"
                                    color: Theme.textTertiary
                                    font.family: root.iconFontFamily
                                    font.pixelSize: 13
                                }
                            }

                            MouseArea {
                                id: itemMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.messagingContext) {
                                        const conversationId = root.messagingContext.startConversationWith(userId)
                                        if (conversationId > 0) {
                                            root.conversationStarted(conversationId)
                                        }
                                    }
                                }
                            }
                        }

                        ScrollBar.vertical: ScrollBar {
                            policy: ScrollBar.AsNeeded
                        }
                    }
                }
            }
        }
    }
}
