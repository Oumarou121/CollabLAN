import QtQuick
import QtQuick.Controls
import Themes
import "Login"
import "Dashboard"
import "Call"
import "Components"

/*
 * Main - fenetre racine de LocaLink.
 *
 * Pile racine a trois etats : chargement -> connexion -> application.
 * Une fois connecte, TOUTE la navigation se fait dans AppShell (barre
 * laterale + barre superieure uniques, sections dans une pile interne) :
 * plus d'ecrans pousses plein ecran avec leur propre en-tete.
 */
ApplicationWindow {
    id: window

    width: 1440
    height: 900
    minimumWidth: 900
    minimumHeight: 600
    // Reste invisible tant que la tentative d'auto-login (voir
    // startupLoadingViewComponent) n'a pas tranche entre connexion et
    // application : evite un clignotement de l'ecran de connexion.
    visible: false
    title: qsTr("LocaLink")
    color: Theme.bg
    property bool allowApplicationQuit: false
    property bool backgroundModeAvailable: false

    onClosing: function(close) {
        if (!window.allowApplicationQuit && window.backgroundModeAvailable) {
            close.accepted = false
            window.hide()
        }
    }

    // Police Inter embarquee, chargee une seule fois pour toute l'application.
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
    // PT Serif : titres et chiffres de Ligne claire (Theme.fontFamilySerif).
    FontLoader {
        id: serifRegular
        source: "qrc:/ui/Assets/fonts/PTSerif-Regular.ttf"
    }
    FontLoader {
        id: serifBold
        source: "qrc:/ui/Assets/fonts/PTSerif-Bold.ttf"
    }

    // Police par defaut : tous les Text/Label/Button en heritent sauf
    // surcharge explicite.
    font.family: interRegular.status === FontLoader.Ready ? interRegular.name : Theme.fontFamilyFallback

    // Conserve pour les composants qui la lisent (ToastHost...).
    property var globalMessagingContext: messagingContext

    Component.onCompleted: window.visible = true

    // Ecran actuellement connecte (null tant que l'on est sur la connexion).
    readonly property var appShell: (stackView.currentItem && stackView.currentItem.objectName === "appShell")
                                    ? stackView.currentItem : null

    StackView {
        id: stackView
        anchors.fill: parent
        initialItem: startupLoadingViewComponent

        replaceEnter: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.durationNormal }
        }
        replaceExit: Transition {
            NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Theme.durationFast }
        }
        pushEnter: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.durationNormal }
        }
        pushExit: Transition {
            NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Theme.durationFast }
        }
    }

    // Toasts globaux : au-dessus de la pile quel que soit l'ecran.
    ToastHost {
        id: toastHost
        anchors.fill: parent
        // Sous la barre de contexte une fois connecte ; au-dessus de la bande d'appel.
        topInset: window.appShell ? 70 : 16
        bottomInset: window.appShell && window.appShell.callBarShown ? 92 : 16
        onConversationRequested: function(conversationId) {
            if (window.appShell)
                window.appShell.openConversation(conversationId)
        }
        // Clic sur un toast non-message : ouvre la section correspondante.
        onActionRequested: function(category) {
            if (!window.appShell)
                return
            switch (category) {
            case "transfer": window.appShell.navigate("transfer"); break
            case "folder": window.appShell.navigate("folder"); break
            case "connection":
            case "disconnection": window.appShell.navigate("peers"); break
            // Ajout a un groupe de discussion : ouvre les Discussions.
            case "group": window.appShell.navigate("chat"); break
            }
        }
    }

    // Progression globale des synchronisations de dossiers partages.
    FolderTransferProgressHost {
        anchors.fill: parent
    }

    // Appel en cours (appelant comme appele), par-dessus l'ecran actif.
    CallOverlay {
        anchors.fill: parent
        z: 50
        // La bande d'appel s'aligne sur la page, a droite de la barre laterale.
        leftInset: window.appShell ? (window.appShell.railMode ? Theme.sidebarWidthCollapsed : Theme.sidebarWidth) : 0
    }

    Component {
        id: startupLoadingViewComponent

        StartupLoadingView {
            property bool sessionRestored: false
            property bool startupChecked: false

            // Duree minimale d'affichage de l'ecran de chargement (issue #6).
            Timer {
                id: minimumStartupTimer
                interval: 3000
                repeat: false
                onTriggered: {
                    if (startupChecked) {
                        if (sessionRestored)
                            stackView.replace(appShellComponent, { username: settingsModel.rememberedUsername })
                        else
                            stackView.replace(loginViewComponent)
                    }
                }
            }

            Component.onCompleted: {
                // L'auto-login est synchrone : la destination est choisie
                // avant de rendre la connexion ou l'application visible.
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
                stackView.replace(appShellComponent, { username: username })
            }
        }
    }

    Component {
        id: appShellComponent

        AppShell {
            objectName: "appShell"
            onLogoutRequested: {
                userManager.logout()
                stackView.replace(loginViewComponent)
            }
        }
    }
}
