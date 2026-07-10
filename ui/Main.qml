import QtQuick
import QtQuick.Controls
import Themes
import "Login"
import "Home"
import "Users"
import "Chat"

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
            messagingContext: messagingContext
            onBackRequested: {
                stackView.pop()
            }
            onConversationSelected: function(conversationId) {
                stackView.push(chatViewComponent, { conversationId: conversationId })
            }
            onCreateGroupRequested: {
                stackView.push(createGroupViewComponent)
            }
        }
    }

    Component {
        id: createGroupViewComponent

        CreateGroupView {
            messagingContext: messagingContext
            onBackRequested: {
                stackView.pop()
            }
            onGroupCreated: function(groupId) {
                stackView.pop()
                // MessagingContext.createGroup() a deja appele setConversation()
                // en interne : le messageModel pointe donc deja sur la bonne
                // conversation de groupe.
                if (messagingContext && messagingContext.messageModel.conversationId > 0) {
                    stackView.push(chatViewComponent, { conversationId: messagingContext.messageModel.conversationId })
                }
            }
        }
    }

    Component {
        id: chatViewComponent

        ChatView {
            messagingContext: messagingContext
            onBackRequested: {
                stackView.pop()
            }
        }
    }
}
