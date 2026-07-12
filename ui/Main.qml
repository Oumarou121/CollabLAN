import QtQuick
import QtQuick.Controls
import Themes
import "Login"
import "Home"
import "Users"
import "Chat"
import "FileTransfer"
import "Call"
import "Admin"
import "Components"

/*
 * Main - fenetre racine de CollabLAN.
 * Gere la navigation de base entre les ecrans via un StackView :
 *   Login -> Home (issue #6)
 * Applique le theme global (issue #7) via le singleton Themes.Theme.
 */
ApplicationWindow {
    id: window

    width: 1024
    height: 720
    minimumWidth: 640
    minimumHeight: 480
    visible: true
    title: qsTr("CollabLAN")
    color: Theme.background

    // Référence à la propriété globale messagingContext pour l'utiliser dans les Components
    property var globalMessagingContext: messagingContext

    StackView {
        id: stackView
        anchors.fill: parent

        initialItem: loginViewComponent

        // Transitions simples (fondu) entre les ecrans
        pushEnter: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 150 }
        }
        pushExit: Transition {
            NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 150 }
        }
        popEnter: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 150 }
        }
        popExit: Transition {
            NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 150 }
        }
    }

    // Indicateur discret de bascule automatique de serveur (issue UI section
    // 9 etape 5) : place comme ToastHost, au-dessus du StackView, visible
    // quel que soit l'ecran actif.
    ServerStatusIndicator {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: Theme.spacingMedium
    }

    // Superposition globale des toasts (issue #58) : place en dernier
    // pour rester au-dessus du StackView quelle que soit la vue active.
    ToastHost {
        anchors.fill: parent
    }

    // Navigation automatique vers CallView pour un appel entrant (issue #64bis) :
    // callContext est global et ecoute meme quand l'utilisateur est sur un
    // autre ecran (Home/Chat/...). Sans ce hook, "ringing" ne se voit que si
    // CallView est deja ouvert, d'ou les tentatives ignorees cote appelant.
    Connections {
        target: callContext
        function onCallStateChanged() {
            if (callContext.callState === "ringing"
                    && stackView.currentItem
                    && stackView.currentItem.objectName !== "callView") {
                stackView.push(callViewComponent)
            }
        }
    }

    Component {
        id: loginViewComponent

        LoginView {
            onLoginSucceeded: function(username) {
                stackView.push(homeViewComponent, { username: username })
            }
        }
    }

    Component {
        id: homeViewComponent

        HomeView {
            onLogoutRequested: {
                stackView.pop(null) // revient a l'ecran Login (racine de la pile)
            }
            onUsersRequested: {
                stackView.push(usersViewComponent)
            }
            onChatRequested: {
                stackView.push(conversationsViewComponent)
            }
            onFileTransferRequested: {
                stackView.push(fileTransferViewComponent)
            }
            onCallRequested: {
                stackView.push(callViewComponent)
            }
            onCallHistoryRequested: {
                stackView.push(callHistoryViewComponent)
            }
            onAdminRequested: {
                stackView.push(adminViewComponent)
            }
        }
    }

    Component {
        id: callViewComponent

        CallView {
            objectName: "callView"
            onBackRequested: {
                stackView.pop()
            }
        }
    }

    Component {
        id: callHistoryViewComponent

        CallHistoryView {
            onBackRequested: {
                stackView.pop()
            }
        }
    }

    Component {
        id: adminViewComponent

        AdminView {
            onBackRequested: {
                stackView.pop()
            }
        }
    }

    Component {
        id: fileTransferViewComponent

        FileTransferView {
            onBackRequested: {
                stackView.pop()
            }
        }
    }

    Component {
        id: usersViewComponent

        UsersView {
            onBackRequested: {
                stackView.pop()
            }
        }
    }

    Component {
        id: conversationsViewComponent

        ConversationsView {
            messagingContext: globalMessagingContext
            onBackRequested: {
                stackView.pop()
            }
            onConversationSelected: function(conversationId) {
                stackView.push(chatViewComponent, { conversationId: conversationId })
            }
            onCreateGroupRequested: {
                stackView.push(createGroupViewComponent)
            }
            onNewConversationRequested: {
                stackView.push(newConversationViewComponent)
            }
        }
    }

    Component {
        id: newConversationViewComponent

        NewConversationView {
            messagingContext: globalMessagingContext
            onBackRequested: {
                stackView.pop()
            }
            onConversationStarted: function(conversationId) {
                stackView.pop()
                stackView.push(chatViewComponent, { conversationId: conversationId })
            }
        }
    }

    Component {
        id: createGroupViewComponent

        CreateGroupView {
            messagingContext: globalMessagingContext
            onBackRequested: {
                stackView.pop()
            }
            onGroupCreated: function(groupId) {
                stackView.pop()
                // MessagingContext.createGroup() a deja appele setConversation()
                // en interne : le messageModel pointe donc deja sur la bonne
                // conversation de groupe.
                if (globalMessagingContext && globalMessagingContext.messageModel.conversationId > 0) {
                    stackView.push(chatViewComponent, { conversationId: globalMessagingContext.messageModel.conversationId })
                }
            }
        }
    }

    Component {
        id: chatViewComponent

        ChatView {
            messagingContext: globalMessagingContext
            onBackRequested: {
                stackView.pop()
            }
        }
    }
}
