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

    // CORRECTIF (refonte UI type WhatsApp Web) : cette vue est desormais
    // utilisee a la fois en plein ecran (navigation classique par pile,
    // showBackButton: true) et comme panneau de gauche embarque dans
    // ChatWorkspaceView (showBackButton: false, pas de "retour" au sens
    // pile puisqu'il n'y a rien en dessous). selectedConversationId permet
    // au panneau de gauche de surligner la conversation actuellement
    // affichee a droite -- essentiel en vue cote-a-cote ou l'utilisateur
    // doit voir en un coup d'oeil laquelle est active.
    property bool showBackButton: true
    property var selectedConversationId: null
    // Bascule les actions d'en-tete en icones seules (voir plus bas) --
    // active par defaut quand la vue est utilisee comme panneau de gauche
    // etroit dans ChatWorkspaceView.
    property bool compactActions: false

    // Police d'icones Font Awesome 4.7.0, memes glyphes que Home
    // (Components/DashboardCard.qml) - utilisee pour la loupe de recherche.
    FontLoader {
        id: iconFont
        source: "../Assets/fonts/fontawesome-webfont.ttf"
    }
    readonly property string iconFontFamily: iconFont.name

    signal backRequested()
    signal conversationSelected(var conversationId, string name)
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

                IconButton {
                    glyph: "\uf060"
                    variant: "ghost"
                    visible: root.showBackButton
                    onClicked: root.backRequested()
                }

                Label {
                    Layout.fillWidth: true
                    text: qsTr("Discussions")
                    font.pixelSize: Theme.fontSizeHeading
                    font.bold: true
                    font.family: Theme.fontFamily
                    color: Theme.text
                    elide: Text.ElideRight
                }

                // Bouton unique qui ouvre un modal pour choisir entre
                // nouvelle conversation et nouveau groupe
                IconButton {
                    glyph: "\uf067"
                    variant: "primary"
                    iconSize: Theme.fontSizeHeading
                    onClicked: actionMenu.visible = true
                }
            }
        }

        // Barre de recherche
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 75
            Layout.margins: 0

            TextField {
                id: searchField
                anchors.fill: parent
                anchors.margins: Theme.spacingMedium
                placeholderText: qsTr("Rechercher une conversation...")
                color: Theme.text
                font.pixelSize: Theme.fontSizeBody
                font.family: Theme.fontFamily
                leftPadding: 40
                selectByMouse: true

                background: Rectangle {
                    color: Theme.surfaceAlt
                    radius: Theme.radiusLarge
                    border.width: searchField.activeFocus ? 2 : 0
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
                        timestamp: item.timestamp ? Qt.formatDateTime(item.timestamp, "hh:mm") : "",
                        unreadCount: item.unreadCount || 0
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
                id: conversationDelegate
                readonly property bool isSelected: root.selectedConversationId !== null
                                                    && root.selectedConversationId !== undefined
                                                    && conversationId === root.selectedConversationId
                width: conversationsListView.width
                height: 76
                color: isSelected
                       ? Theme.selectionBackground
                       : (itemMouse.containsMouse ? Theme.surfaceHover : Theme.surface)
                radius: Theme.radiusMedium
                border.color: isSelected ? Theme.selectionBorder : Theme.border
                border.width: isSelected ? 2 : 1

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
                            // Non lu = plus contrasté, pour attirer l'oeil comme le badge.
                            color: unreadCount > 0 ? Theme.text : Theme.textSecondary
                            font.bold: unreadCount > 0
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }

                    ColumnLayout {
                        Layout.alignment: Qt.AlignTop
                        spacing: 6

                        Label {
                            Layout.alignment: Qt.AlignRight
                            text: timestamp
                            font.pixelSize: Theme.fontSizeCaption
                            font.family: Theme.fontFamily
                            color: unreadCount > 0 ? Theme.primary : Theme.textTertiary
                        }

                        // Badge de messages non lus (issue : is_read n'était jamais
                        // exploité côté UI, alors que le repository le gérait déjà).
                        Rectangle {
                            Layout.alignment: Qt.AlignRight
                            visible: unreadCount > 0
                            implicitWidth: Math.max(20, unreadCountLabel.implicitWidth + 12)
                            implicitHeight: 20
                            radius: 10
                            color: Theme.primary

                            Label {
                                id: unreadCountLabel
                                anchors.centerIn: parent
                                text: unreadCount > 99 ? "99+" : unreadCount
                                font.pixelSize: Theme.fontSizeCaption
                                font.bold: true
                                font.family: Theme.fontFamily
                                color: Theme.primaryText
                            }
                        }
                    }
                }

                MouseArea {
                    id: itemMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.conversationSelected(conversationId, name)
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

    // Modal de choix d'action
    Rectangle {
        id: actionMenu
        anchors.fill: parent
        visible: false
        color: "#40000000"

        MouseArea {
            anchors.fill: parent
            onClicked: actionMenu.visible = false
        }

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(320, parent.width - Theme.spacingXl * 2)
            height: actionColumn.implicitHeight + Theme.spacingLarge * 2
            radius: Theme.radiusLarge
            color: Theme.surface
            border.width: 1
            border.color: Theme.border

            ColumnLayout {
                id: actionColumn
                anchors.fill: parent
                anchors.margins: Theme.spacingLarge
                spacing: Theme.spacingMedium

                Label {
                    Layout.fillWidth: true
                    text: qsTr("Nouvelle action")
                    font.pixelSize: Theme.fontSizeSubheading
                    font.bold: true
                    font.family: Theme.fontFamily
                    color: Theme.text
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: Theme.border
                }

                AppButton {
                    Layout.fillWidth: true
                    variant: "ghost"
                    text: qsTr("Nouvelle conversation")
                    onClicked: {
                        actionMenu.visible = false
                        root.newConversationRequested()
                    }
                }

                AppButton {
                    Layout.fillWidth: true
                    variant: "ghost"
                    text: qsTr("Nouveau groupe")
                    onClicked: {
                        actionMenu.visible = false
                        root.createGroupRequested()
                    }
                }

                AppButton {
                    Layout.fillWidth: true
                    variant: "ghost"
                    text: qsTr("Annuler")
                    onClicked: actionMenu.visible = false
                }
            }
        }
    }
}
