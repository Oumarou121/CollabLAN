import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import Core
import "../Components"

/*
 * ChatWorkspaceView - Espace de discussion type "WhatsApp Web" pour desktop.
 *
 * Remplace l'ancienne navigation plein ecran (ConversationsView -> push ->
 * ChatView -> pop pour revenir) par une disposition maitre/detail : la liste
 * des conversations reste visible en permanence dans un panneau de gauche
 * (largeur proportionnelle a la fenetre, entre 280 et 400px - cf.
 * conversationsPanelWidth), et la conversation active s'affiche a droite
 * dans le reste de l'espace. Basculer d'une conversation a l'autre ne
 * recharge donc plus l'ecran entier -- seul le panneau de droite change.
 *
 * ConversationsView et ChatView sont reutilisees telles quelles (avec les
 * proprietes showBackButton / compactActions / selectedConversationId
 * ajoutees pour ce mode) plutot que dupliquees : ca evite deux versions du
 * meme code a maintenir.
 */
Item {
    id: root

    property var messagingContext: null

    // Conversation actuellement affichee dans le panneau de droite.
    // null/0 = aucune selection -> etat vide.
    property var currentConversationId: null
    property string currentConversationName: ""

    signal backRequested()
    signal newConversationRequested()
    signal createGroupRequested()

    // Permet a Main.qml de rediriger vers une conversation fraichement
    // creee (nouvelle discussion / nouveau groupe) sans repasser par la
    // liste : ces ecrans restent des etapes separees dans le StackView,
    // mais une fois termines on revient sur ce workspace et on veut
    // ouvrir directement la conversation resultante a droite.
    function openConversation(conversationId, name) {
        root.currentConversationId = conversationId
        root.currentConversationName = name || ""
    }

    // Largeur du panneau de gauche : proportionnelle a la largeur de la
    // fenetre plutot que figee, pour rester confortable aussi bien en
    // fenetre partagee (proche du minimum) que sur un grand ecran desktop
    // (plafonnee pour ne pas empieter sur l'espace de lecture a droite).
    readonly property int conversationsPanelWidth: Math.max(280, Math.min(400, Math.round(root.width * 0.26)))

    // Police d'icones Font Awesome 4.7.0, meme jeu de glyphes que Home
    // (Components/DashboardCard.qml) - utilisee pour l'icone decorative
    // de l'etat vide (aucune conversation selectionnee).
    FontLoader {
        id: iconFont
        source: "../Assets/fonts/fontawesome-webfont.ttf"
    }
    readonly property string iconFontFamily: iconFont.name

    Rectangle {
        anchors.fill: parent
        color: Theme.background
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // Panneau de gauche : liste des conversations, toujours visible.
        ConversationsView {
            id: conversationsPanel
            Layout.preferredWidth: root.conversationsPanelWidth
            Layout.minimumWidth: 280
            Layout.fillHeight: true

            messagingContext: root.messagingContext
            showBackButton: true
            compactActions: true
            selectedConversationId: root.currentConversationId

            onBackRequested: root.backRequested()

            onConversationSelected: function(conversationId, name) {
                root.openConversation(conversationId, name)
            }

            onNewConversationRequested: root.newConversationRequested()
            onCreateGroupRequested: root.createGroupRequested()
        }

        // Separateur vertical entre les deux panneaux -- ombre douce plutot
        // qu'un filet 1px plein, pour rester coherent avec le reste du
        // module chat (header/zone de saisie/cartes de conversation).
        Item {
            Layout.preferredWidth: 8
            Layout.fillHeight: true

            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: Theme.shadowSoft }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }
        }

        // Panneau de droite : conversation active, ou etat vide si rien
        // n'est encore selectionne (premiere ouverture du workspace).
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ChatView {
                id: chatPanel
                anchors.fill: parent
                visible: root.currentConversationId !== null
                         && root.currentConversationId !== undefined
                         && root.currentConversationId !== 0

                messagingContext: root.messagingContext
                conversationId: root.currentConversationId || 0
                name: root.currentConversationName
                showBackButton: false
            }

            // Etat vide : invite a choisir une conversation, plutot qu'un
            // panneau de droite completement vide et silencieux au premier
            // lancement du workspace.
            ColumnLayout {
                anchors.centerIn: parent
                width: parent.width * 0.6
                spacing: Theme.spacingMedium
                visible: !chatPanel.visible

                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    width: 88
                    height: 88
                    radius: 44
                    color: Theme.primaryMuted

                    Text {
                        anchors.centerIn: parent
                        text: "\uf0e0"
                        font.family: root.iconFontFamily
                        font.pixelSize: 36
                        color: Theme.primary
                    }
                }

                Label {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignHCenter
                    horizontalAlignment: Text.AlignHCenter
                    text: qsTr("Selectionnez une conversation")
                    font.pixelSize: Theme.fontSizeHeading
                    font.bold: true
                    font.family: Theme.fontFamily
                    color: Theme.text
                }

                Label {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignHCenter
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: qsTr("Choisissez une discussion dans la liste de gauche, ou demarrez-en une nouvelle pour commencer a echanger.")
                    font.pixelSize: Theme.fontSizeBody
                    font.family: Theme.fontFamily
                    color: Theme.textSecondary
                }
            }
        }
    }
}
