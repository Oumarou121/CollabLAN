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
import "SharedFolder"
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
    // Reste invisible tant que la tentative d'auto-login (voir
    // Component.onCompleted ci-dessous) n'a pas tranche entre Login et
    // Home : evite que l'utilisateur voie l'ecran Login clignoter une
    // fraction de seconde avant d'etre remplace par Home ("Se souvenir de
    // moi", migration #026).
    visible: false
    title: qsTr("CollabLAN")
    color: Theme.background

    // Référence à la propriété globale messagingContext pour l'utiliser dans les Components
    property var globalMessagingContext: messagingContext

    // Tentative d'auto-login silencieuse a partir du jeton persiste
    // localement (core::SettingsModel.rememberedSessionToken, jamais en
    // base - voir migration #026). userManager.loginWithRememberedToken()
    // est un appel C++ synchrone : au moment ou la fenetre devient visible,
    // on sait deja si on doit afficher Home ou Login, donc pas de flash de
    // l'ecran Login. Un jeton absent/expire/invalide echoue silencieusement
    // (pas de loginFailed) et laisse simplement l'ecran Login initial en place.
    Component.onCompleted: {
        const hasRememberedSession = (typeof settingsModel !== "undefined" && settingsModel)
                && settingsModel.rememberedUsername.length > 0
                && settingsModel.rememberedSessionToken.length > 0

        console.log("[Main.qml] rememberedUsername=" + (settingsModel ? settingsModel.rememberedUsername : "<settingsModel indisponible>")
                     + " tokenPresent=" + (settingsModel ? (settingsModel.rememberedSessionToken.length > 0) : false)
                     + " hasRememberedSession=" + hasRememberedSession)

        if (hasRememberedSession) {
            const restored = userManager.loginWithRememberedToken(
                        settingsModel.rememberedUsername,
                        settingsModel.rememberedSessionToken)
            console.log("[Main.qml] loginWithRememberedToken -> " + restored)
            if (restored) {
                stackView.push(homeViewComponent, { username: settingsModel.rememberedUsername })
            } else {
                // Jeton perime/invalide : on efface la trace locale pour ne
                // pas retenter a chaque demarrage (le hash en base a deja
                // ete nettoye cote C++ si expire).
                settingsModel.rememberedUsername = ""
                settingsModel.rememberedSessionToken = ""
                settingsModel.save()
            }
        }

        window.visible = true
    }

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
    // sur tous les ecrans SAUF Login/Home, qui integrent desormais leur
    // propre badge de statut dans l'en-tete (evite un double affichage /
    // chevauchement avec le bouton de theme et le profil).
    ServerStatusIndicator {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: Theme.spacingMedium
        visible: (typeof electionService !== "undefined" && electionService !== null)
                 && !(stackView.currentItem
                      && (stackView.currentItem.objectName === "loginView"
                          || stackView.currentItem.objectName === "homeView"))
    }

    // Superposition globale des toasts (issue #58) : place en dernier
    // pour rester au-dessus du StackView quelle que soit la vue active.
    ToastHost {
        anchors.fill: parent
    }

    // Barre(s) de progression globale(s) pour le partage de dossiers :
    // remplace le flot de notifications repetitives (une par fichier) par
    // une seule progression par rafale de synchronisation, suivie de la
    // notification finale existante (voir ToastHost ci-dessus) plutot que
    // par un toast par fichier transfere.
    FolderTransferProgressHost {
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
            objectName: "loginView"
            onLoginSucceeded: function(username) {
                stackView.push(homeViewComponent, { username: username })
            }
        }
    }

    Component {
        id: homeViewComponent

        HomeView {
            objectName: "homeView"
            onLogoutRequested: {
                stackView.pop(null) // revient a l'ecran Login (racine de la pile)
            }
            onUsersRequested: {
                stackView.push(usersViewComponent)
            }
            onChatRequested: {
                stackView.push(chatWorkspaceComponent)
            }
            onFileTransferRequested: {
                stackView.push(fileTransferViewComponent)
            }
            onCallRequested: {
                stackView.push(callViewComponent)
            }
            onAdminRequested: {
                stackView.push(adminViewComponent)
            }
            onSharedFoldersRequested: {
                stackView.push(sharedFolderViewComponent)
            }
        }
    }

    Component {
        id: sharedFolderViewComponent

        SharedFolderView {
            onBackRequested: {
                stackView.pop()
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
        id: chatWorkspaceComponent

        ChatWorkspaceView {
            objectName: "chatWorkspaceView"
            messagingContext: globalMessagingContext
            onBackRequested: {
                stackView.pop()
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
                // Le workspace (ChatWorkspaceView) est l'ecran qui redevient
                // actif apres ce pop : on lui demande d'ouvrir directement
                // la conversation fraichement creee dans le panneau de
                // droite, plutot que de pousser un ChatView plein ecran
                // par-dessus (ancien comportement, incompatible avec le
                // split-view).
                if (stackView.currentItem && stackView.currentItem.objectName === "chatWorkspaceView") {
                    stackView.currentItem.openConversation(conversationId, "")
                }
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
                if (stackView.currentItem && stackView.currentItem.objectName === "chatWorkspaceView"
                        && globalMessagingContext && globalMessagingContext.messageModel.conversationId > 0) {
                    stackView.currentItem.openConversation(globalMessagingContext.messageModel.conversationId, "")
                }
            }
        }
    }
}
