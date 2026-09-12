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
import "Settings"
import "About"
import "SharedFolder"
import "Components"

/*
 * Main - fenetre racine de LocaLink.
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
    title: qsTr("LocaLink")
    color: Theme.background
    property bool allowApplicationQuit: false
    property bool backgroundModeAvailable: false

    onClosing: function(close) {
        if (!window.allowApplicationQuit && window.backgroundModeAvailable) {
            close.accepted = false
            window.hide()
        }
    }

    // Chargement global de la police Inter (issue design) : chargee une
    // seule fois ici plutot que localement dans chaque vue, pour que
    // Theme.fontFamily corresponde a une police reellement embarquee.
    FontLoader {
        id: interRegular
        source: "qrc:/ui/Assets/fonts/Inter-Regular.ttf"
    }
    FontLoader {
        id: interMedium
        source: "qrc:/ui/Assets/fonts/Inter-Medium.ttf"
    }
    FontLoader {
        id: interSemiBold
        source: "qrc:/ui/Assets/fonts/Inter-SemiBold.ttf"
    }
    FontLoader {
        id: interBold
        source: "qrc:/ui/Assets/fonts/Inter-Bold.ttf"
    }

    // Police par defaut de toute l'application : tous les Text/Label/Button
    // enfants heritent de font.family sauf override explicite.
    font.family: interRegular.status === FontLoader.Ready ? interRegular.name : Theme.fontFamilyFallback

    // Référence à la propriété globale messagingContext pour l'utiliser dans les Components
    property var globalMessagingContext: messagingContext

    Component.onCompleted: {
        window.visible = true
    }

    StackView {
        id: stackView
        anchors.fill: parent

        initialItem: startupLoadingViewComponent

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
    // ServerStatusIndicator {
    //     anchors.top: parent.top
    //     anchors.right: parent.right
    //     anchors.margins: Theme.spacingMedium
    //     visible: (typeof electionService !== "undefined" && electionService !== null)
    //              && !(stackView.currentItem
    //                   && (stackView.currentItem.objectName === "loginView"
    //                       || stackView.currentItem.objectName === "homeView"))
    // }

    // Superposition globale des toasts (issue #58) : place en dernier
    // pour rester au-dessus du StackView quelle que soit la vue active.
    ToastHost {
        id: toastHost
        anchors.fill: parent
        onConversationRequested: function(conversationId) {
            if (conversationId <= 0)
                return
            if (stackView.currentItem && stackView.currentItem.objectName === "chatWorkspaceView") {
                stackView.currentItem.openConversation(conversationId, "")
                return
            }
            stackView.push(chatWorkspaceComponent)
            if (stackView.currentItem && stackView.currentItem.objectName === "chatWorkspaceView")
                stackView.currentItem.openConversation(conversationId, "")
        }
        // Redirection pour les notifications non-message (clic sur la
        // carte ou son lien d'action) : chaque categorie ouvre l'ecran ou
        // se trouve l'information correspondante.
        onActionRequested: function(category) {
            switch (category) {
            case "transfer":
                stackView.push(fileTransferViewComponent)
                break
            case "folder":
                stackView.push(sharedFolderViewComponent)
                break
            case "connection":
            case "disconnection":
                stackView.push(usersViewComponent)
                break
            case "group":
                stackView.push(usersViewComponent)
                break
            }
        }
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
        id: startupLoadingViewComponent

        StartupLoadingView {
            property bool sessionRestored: false
            property bool startupChecked: false

            // Timer pour garantir un minimum de 3 secondes d'affichage de l'ecran de chargement, meme si l'auto-login est instantane (issue #6).
            Timer {
                id: minimumStartupTimer
                interval: 3000
                repeat: false
                onTriggered: {
                    if (startupChecked) {
                        if (sessionRestored) {
                            stackView.replace(homeViewComponent, { username: settingsModel.rememberedUsername })
                        } else {
                            stackView.replace(loginViewComponent)
                        }
                    }
                }
            }

            Component.onCompleted: {
                // L'écran de chargement est le seul point d'entrée visible.
                // L'auto-login est synchrone : on choisit la destination avant
                // de rendre LoginView ou HomeView visible.
                const hasRememberedSession = (typeof settingsModel !== "undefined" && settingsModel)
                        && settingsModel.rememberedUsername.length > 0
                        && settingsModel.rememberedSessionToken.length > 0
                if (hasRememberedSession) {
                    sessionRestored = userManager.loginWithRememberedToken(
                                settingsModel.rememberedUsername,
                                settingsModel.rememberedSessionToken)
                    if (!sessionRestored) {
                        settingsModel.rememberedUsername = ""
                        settingsModel.rememberedSessionToken = ""
                        settingsModel.save()
                    }
                }
                startupChecked = true
                minimumStartupTimer.start()
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
                // Après une restauration automatique, Home est la racine de
                // la pile : pop(null) ne peut plus revenir au login.
                // Déconnecter explicitement la session puis remplacer la vue.
                userManager.logout()
                stackView.replace(loginViewComponent)
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
            onSettingsRequested: {
                stackView.push(settingsViewComponent)
            }
            onSharedFoldersRequested: {
                stackView.push(sharedFolderViewComponent)
            }
            onAboutRequested: {
                stackView.push(aboutViewComponent)
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
        id: settingsViewComponent

        SettingsView {
            onBackRequested: {
                stackView.pop()
            }
        }
    }

    Component {
        id: aboutViewComponent

        AboutView {
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
