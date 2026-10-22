import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import "../Components"
import "../Home"
import "../Chat"
import "../FileTransfer"
import "../SharedFolder"
import "../Call"
import "../Users"
import "../Admin"
import "../Settings"
import "../About"
import "../Login"

/*
 * AppShell - cadre unique de l'application connectee (refonte 2026).
 *
 * Avant : seuls Vue d'ensemble et Transferts avaient la navigation
 * laterale ; les autres ecrans etaient pousses plein ecran avec leur propre
 * en-tete et un bouton retour - deux experiences de navigation
 * concurrentes. Desormais la navigation laterale et la barre superieure
 * sont instanciees UNE fois ici, et chaque section s'affiche dans la pile
 * `pages` :
 *   - navigate(route)  remplace la section courante (sections soeurs) ;
 *   - pushPage(comp)   empile une sous-page (nouvelle conversation...) ;
 *   - backRequested()  d'une page depile, ou revient a la vue d'ensemble.
 *
 * Badges et notifications : uniquement des donnees reelles (conversations
 * non lues, transferts en cours, postes en attente, appel en cours,
 * evenements de NotificationManager recus pendant la session).
 */
Item {
    id: shell

    property string username: ""
    signal logoutRequested()

    // Propriete de contexte C++ capturee ici : dans les pages, une liaison
    // `messagingContext: messagingContext` se lierait a elle-meme.
    readonly property var messaging: (typeof messagingContext !== "undefined") ? messagingContext : null

    readonly property bool isAdmin: (typeof userManager !== "undefined" && userManager)
                                    ? userManager.currentUserIsAdmin : false

    // ---- Navigation ------------------------------------------------------
    property string currentRoute: ""

    readonly property var routeLabels: ({
        "home": qsTr("Vue d'ensemble"),
        "chat": qsTr("Discussions"),
        "transfer": qsTr("Transferts"),
        "folder": qsTr("Dossiers partagés"),
        "call": qsTr("Appels"),
        "peers": qsTr("Postes"),
        "journal": qsTr("Journal d'audit"),
        "admin": qsTr("Administration"),
        "settings": qsTr("Paramètres"),
        "about": qsTr("À propos")
    })

    function componentFor(route) {
        switch (route) {
        case "home": return homeComponent
        case "chat": return chatComponent
        case "transfer": return transferComponent
        case "folder": return folderComponent
        case "call": return callComponent
        case "peers": return peersComponent
        case "journal": return journalComponent
        case "admin": return adminComponent
        case "settings": return settingsComponent
        case "about": return aboutComponent
        }
        return null
    }

    function navigate(route, props) {
        shell.navOverlay = false
        // Les sections d'administration ne sont proposees qu'aux comptes
        // administrateurs (le controle reel reste cote metier).
        if ((route === "journal" || route === "admin") && !shell.isAdmin)
            route = "home"
        const comp = componentFor(route)
        if (!comp)
            return
        let properties = props || {}
        if (route === "admin" && properties.currentTab === undefined)
            properties.currentTab = 1
        if (route === shell.currentRoute && pages.depth === 1 && !props)
            return
        shell.currentRoute = route
        pages.replace(null, comp, properties)
        shell.refreshBadges()
    }

    function pushPage(comp, props) {
        pages.push(comp, props || {})
    }

    function goBack() {
        if (pages.depth > 1)
            pages.pop()
        else if (shell.currentRoute !== "home")
            shell.navigate("home")
    }

    function openConversation(conversationId) {
        if (conversationId <= 0)
            return
        if (shell.currentRoute !== "chat" || pages.depth > 1)
            shell.navigate("chat")
        if (pages.currentItem && pages.currentItem.openConversation)
            pages.currentItem.openConversation(conversationId, "")
    }

    // Fenetre etroite : rail d'icones impose (Ligne claire A2 : sous 1180 px).
    readonly property bool narrowWindow: shell.width < Theme.bpMetricsWrap
    // Barre repliee en rail (preference ou fenetre etroite)...
    readonly property bool railMode: Theme.sidebarCollapsed || shell.narrowWindow
    // ... et depliee temporairement par-dessus le contenu.
    property bool navOverlay: false
    onRailModeChanged: if (!railMode) shell.navOverlay = false

    // ---- Badges reels ----------------------------------------------------
    property int unreadMessages: 0
    property int activeTransfers: 0
    property int pendingAdmin: 0
    property int peersCount: 0
    property int folderConflicts: 0
    readonly property bool callActive: (typeof callContext !== "undefined" && callContext)
                                       ? (callContext.callState !== "" && callContext.callState !== "idle")
                                       : false

    readonly property bool callBarShown: (typeof callContext !== "undefined" && callContext)
                                         ? (callContext.callState === "connected" || callContext.callState === "ending") : false

    function refreshBadges() {
        // Messages non lus : somme des unreadCount de chaque conversation.
        let unread = 0
        if (typeof messagingContext !== "undefined" && messagingContext) {
            const convs = messagingContext.conversationsList() || []
            for (let i = 0; i < convs.length; i++)
                unread += convs[i].unreadCount || 0
        }
        shell.unreadMessages = unread

        let running = 0
        if (typeof transferContext !== "undefined" && transferContext) {
            const all = transferContext.activeTransfers || []
            for (let j = 0; j < all.length; j++)
                if (all[j] && all[j].state === "in_progress")
                    running++
        }
        shell.activeTransfers = running

        let pending = 0
        if (shell.isAdmin && typeof authorizedMachineModel !== "undefined" && authorizedMachineModel) {
            const total = authorizedMachineModel.rowCount ? authorizedMachineModel.rowCount() : 0
            for (let k = 0; k < total; k++) {
                const idx = authorizedMachineModel.index(k, 0)
                const authorized = authorizedMachineModel.data(idx, authorizedMachineModel.AuthorizedRole)
                const status = authorizedMachineModel.data(idx, authorizedMachineModel.StatusRole) || ""
                // Seules les demandes en attente comptent (une machine revoquee
                // n'est pas autorisee non plus, mais ce n'est pas une demande).
                if (status === "pending" || (!status && !authorized))
                    pending++
            }
        }
        shell.pendingAdmin = pending

        shell.peersCount = (typeof peersModel !== "undefined" && peersModel) ? peersModel.count : 0

        // Conflits de synchronisation (SharedFolderModel : HasConflictRole = UserRole + 9).
        let conflicts = 0
        const folders = (typeof sharedFolderContext !== "undefined" && sharedFolderContext)
                        ? sharedFolderContext.folderModel : null
        if (folders) {
            const total = folders.rowCount()
            for (let f = 0; f < total; f++)
                if (folders.data(folders.index(f, 0), 257 + 8))
                    conflicts++
        }
        shell.folderConflicts = conflicts
    }

    // Poste choisi dans la recherche : selectionne sur l'accueil si celui-ci
    // sait le faire, sinon ouvre la liste des postes.
    function showPeer(peerId) {
        if (shell.currentRoute !== "home" || pages.depth > 1)
            shell.navigate("home")
        const page = pages.currentItem
        if (page && typeof page.selectPeer === "function")
            page.selectPeer(peerId)
        else
            shell.navigate("peers")
    }

    // Les non-lus changent a la reception d'un message ou a la lecture
    // d'une conversation : on relit periodiquement (lecture locale en base,
    // peu couteuse) en plus des declencheurs evenementiels.
    Timer {
        interval: 5000
        running: shell.visible
        repeat: true
        onTriggered: shell.refreshBadges()
    }

    Connections {
        target: (typeof transferContext !== "undefined") ? transferContext : null
        function onActiveTransfersChanged() { shell.refreshBadges() }
    }
    Connections {
        target: (typeof authorizedMachineModel !== "undefined") ? authorizedMachineModel : null
        function onModelReset() { shell.refreshBadges() }
        function onDataChanged() { shell.refreshBadges() }
    }

    // ---- Notifications de session ------------------------------------------
    property var notifications: []
    property int unreadNotifications: 0

    Connections {
        target: (typeof notificationManager !== "undefined") ? notificationManager : null
        function onNotificationRequested(title, message, category, conversationId) {
            const list = shell.notifications.slice(0, 39)
            list.unshift({ title: title, message: message, category: category,
                           conversationId: conversationId, time: new Date() })
            shell.notifications = list
            shell.unreadNotifications = Math.min(99, shell.unreadNotifications + 1)
            shell.refreshBadges()
        }
    }

    function activateNotification(index) {
        const n = shell.notifications[index]
        if (!n)
            return
        if (n.category === "message" && n.conversationId > 0) {
            shell.openConversation(n.conversationId)
            return
        }
        switch (n.category) {
        case "transfer": shell.navigate("transfer"); break
        case "folder": shell.navigate("folder"); break
        case "connection":
        case "disconnection": shell.navigate("peers"); break
        // "Vous avez ete ajoute au groupe..." : groupe de discussion.
        case "group": shell.navigate("chat"); break
        case "call": shell.navigate("call"); break
        }
    }

    // ---- Etat reseau -------------------------------------------------------
    readonly property var election: (typeof electionService !== "undefined") ? electionService : null
    readonly property string networkLabel: {
        if (!shell.election) return qsTr("Réseau local")
        if (shell.election.roleLabel === "TEMP_SERVER") return qsTr("Serveur de secours")
        if (shell.election.roleLabel === "SERVER") return qsTr("Ce poste est serveur")
        return qsTr("Connecté au serveur")
    }
    readonly property string networkState: {
        if (!shell.election) return "client"
        if (shell.election.roleLabel === "TEMP_SERVER") return "backup"
        if (shell.election.roleLabel === "SERVER") return "server"
        return "client"
    }
    readonly property color networkColor: (shell.election && shell.election.roleLabel === "TEMP_SERVER")
                                          ? Theme.warningColor : Theme.successColor

    // ---- Mise en page ------------------------------------------------------
    Rectangle {
        anchors.fill: parent
        color: Theme.bg
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // Emplacement de la barre laterale : en surimpression, la page garde
        // la largeur du rail et la barre depliee passe par-dessus.
        Item {
            id: navSlot
            Layout.fillHeight: true
            Layout.preferredWidth: shell.navOverlay ? Theme.sidebarWidthCollapsed : sidebar.width
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            DashboardHeader {
                id: topbar
                Layout.fillWidth: true
                Layout.preferredHeight: Theme.topbarHeight
                isAdmin: shell.isAdmin
                networkLabel: shell.networkLabel
                networkColor: shell.networkColor
                networkState: shell.networkState
                showMenuButton: shell.railMode
                menuOpen: shell.navOverlay
                notifications: shell.notifications
                notificationCount: shell.unreadNotifications
                breadcrumb: {
                    const section = shell.routeLabels[shell.currentRoute] || ""
                    const page = pages.currentItem
                    const leaf = (page && page.breadcrumbLeaf !== undefined) ? page.breadcrumbLeaf : ""
                    return leaf && leaf.length > 0 ? section + " / " + leaf : section
                }

                onNavigateRequested: function(route) { shell.navigate(route) }
                onMenuRequested: shell.navOverlay = !shell.navOverlay
                onPeerRequested: function(peerId, peerName) { shell.showPeer(peerId) }
                onConversationRequested: function(conversationId) { shell.openConversation(conversationId) }
                onNotificationActivated: function(index) { shell.activateNotification(index) }
                onMarkAllRead: shell.unreadNotifications = 0
                onClearNotifications: {
                    shell.notifications = []
                    shell.unreadNotifications = 0
                }
                onSegmentClicked: function(index, label) {
                    // Section cliquee alors qu'un element est ouvert : la page
                    // revient a son niveau racine si elle sait le faire.
                    const page = pages.currentItem
                    if (pages.depth > 1)
                        pages.pop(null)
                    else if (page && typeof page.breadcrumbRootClicked === "function")
                        page.breadcrumbRootClicked()
                }
            }

            StackView {
                id: pages
                Layout.fillWidth: true
                Layout.fillHeight: true
                // Place laissee a la bande d'appel etabli (CallOverlay).
                Layout.bottomMargin: shell.callBarShown ? 76 : 0
                clip: true

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
                popEnter: Transition {
                    NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.durationNormal }
                }
                popExit: Transition {
                    NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Theme.durationFast }
                }
            }
        }
    }

    // Barre depliee en surimpression : voile cliquable, Echap pour fermer.
    Rectangle {
        anchors.fill: parent
        z: 30
        visible: shell.navOverlay
        color: Theme.scrim

        MouseArea {
            anchors.fill: parent
            onClicked: shell.navOverlay = false
        }
    }

    Shortcut {
        sequences: ["Escape"]
        enabled: shell.navOverlay
        onActivated: shell.navOverlay = false
    }

    DashboardSidebar {
        id: sidebar
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        z: 31
        isCompact: shell.railMode && !shell.navOverlay
        compactForced: shell.narrowWindow
        overlay: shell.navOverlay
        username: shell.username
        isAdmin: shell.isAdmin
        activeRoute: shell.currentRoute
        unreadMessages: shell.unreadMessages
        activeTransfers: shell.activeTransfers
        pendingAdmin: shell.pendingAdmin
        peersCount: shell.peersCount
        folderConflicts: shell.folderConflicts
        callActive: shell.callActive

        onHomeRequested: shell.navigate("home")
        onChatRequested: shell.navigate("chat")
        onTransferRequested: shell.navigate("transfer")
        onFoldersRequested: shell.navigate("folder")
        onCallRequested: shell.navigate("call")
        onPeersRequested: shell.navigate("peers")
        onJournalRequested: shell.navigate("journal")
        onAdminRequested: shell.navigate("admin")
        onSettingsRequested: shell.navigate("settings")
        onAboutRequested: shell.navigate("about")
        onLogoutRequested: shell.logoutRequested()
    }


    Component.onCompleted: shell.navigate("home")

    // ======================================================================
    // Pages
    // ======================================================================
    Component {
        id: homeComponent
        HomeView {
            objectName: "homeView"
            username: shell.username
            onUsersRequested: shell.navigate("peers")
            onChatRequested: shell.navigate("chat")
            onNewConversationRequested: shell.navigate("chat", { startPanel: "person" })
            onFileTransferRequested: function(openNewTransfer, peer) {
                shell.navigate("transfer", { autoOpenPanel: openNewTransfer === true,
                                             preselectedPeer: peer || null })
            }
            onCallRequested: shell.navigate("call")
            onAdminRequested: shell.navigate("admin")
            onAdminSectionRequested: function(tab) {
                if (tab === 0)
                    shell.navigate("journal")
                else
                    shell.navigate("admin", { currentTab: tab })
            }
            onSettingsRequested: shell.navigate("settings")
            onSharedFoldersRequested: shell.navigate("folder")
            onAboutRequested: shell.navigate("about")
            onLogoutRequested: shell.logoutRequested()
        }
    }

    Component {
        id: chatComponent
        ChatWorkspaceView {
            objectName: "chatWorkspaceView"
            messagingContext: shell.messaging
            onBackRequested: shell.goBack()
            onFileTransferRequested: function(peer) {
                shell.navigate("transfer", { autoOpenPanel: true, preselectedPeer: peer })
            }
            onExchangesRequested: function(peerKey) {
                shell.navigate("transfer", { openedPeerKey: peerKey })
            }
        }
    }

    Component {
        id: transferComponent
        FileTransferView {
            onBackRequested: shell.goBack()
            onChatRequested: shell.navigate("chat")
            onFoldersRequested: shell.navigate("folder")
            onCallRequested: shell.navigate("call")
            onPeersRequested: shell.navigate("peers")
            onAdminRequested: shell.navigate("admin")
            onSettingsRequested: shell.navigate("settings")
            onLogoutRequested: shell.logoutRequested()
            onConversationRequested: function(conversationId) { shell.openConversation(conversationId) }
        }
    }

    Component {
        id: folderComponent
        SharedFolderView {
            onBackRequested: shell.goBack()
            onSettingsRequested: shell.navigate("settings")
        }
    }

    Component {
        id: callComponent
        CallView {
            objectName: "callView"
            onBackRequested: shell.goBack()
        }
    }

    Component {
        id: peersComponent
        UsersView {
            onBackRequested: shell.goBack()
            onAdminRequested: shell.navigate("admin")
            onFileTransferRequested: function(peer) {
                shell.navigate("transfer", { autoOpenPanel: true, preselectedPeer: peer })
            }
            onConversationRequested: function(conversationId) { shell.openConversation(conversationId) }
            onExchangesRequested: function(peerKey) { shell.navigate("transfer", { openedPeerKey: peerKey }) }
        }
    }

    Component {
        id: journalComponent
        AuditJournalView {
            onBackRequested: shell.goBack()
            onPeerRequested: function(peerId) { shell.navigate("peers", { selectedKey: peerId }) }
            onConversationRequested: function(conversationId) { shell.openConversation(conversationId) }
            onAuthorizationsRequested: shell.navigate("admin", { currentTab: 1 })
            onTransfersRequested: shell.navigate("transfer")
        }
    }

    Component {
        id: adminComponent
        AdminView {
            onBackRequested: shell.goBack()
            onPeerRequested: function(peerId) { shell.navigate("peers", { selectedKey: peerId }) }
            onJournalRequested: function(search) { shell.navigate("journal", { search: search }) }
            // « Poids de priorité » : la priorité de secours est dans Paramètres > Réseau.
            onSettingsRequested: shell.navigate("settings", { category: "network" })
        }
    }

    Component {
        id: settingsComponent
        SettingsView {
            onBackRequested: shell.goBack()
            onLogoutRequested: shell.logoutRequested()
            onHistoryRequested: shell.navigate("admin", { currentTab: 3 })
            onServerTrustRequested: { shell.dismissedServer = ""; serverTrust.open = true }
        }
    }

    Component {
        id: aboutComponent
        AboutView {
            onBackRequested: shell.goBack()
            onNavigationRequested: function(route) { shell.navigate(route) }
        }
    }

    // Serveur inconnu pendant la session (serveur de secours, retour du serveur
    // officiel, poste deja connecte ou reconnecte automatiquement) : sans cette
    // fenetre, la demande n'apparaissait que sur l'ecran de connexion et le
    // poste restait isole sans le savoir.
    // Un serveur ecarte (« Annuler ») n'est plus propose pendant la session : la
    // connexion est retentee a chaque battement et la fenetre se rouvrirait sinon.
    property string dismissedServer: ""
    ServerTrustSheet {
        id: serverTrust
        open: false
        onCloseRequested: { shell.dismissedServer = application.pendingServerFingerprint; serverTrust.open = false }
        onApproved: serverTrust.open = false
    }
    Connections {
        target: (typeof application !== "undefined") ? application : null
        ignoreUnknownSignals: true
        function onPendingServerChanged() {
            const fp = application.pendingServerFingerprint
            serverTrust.open = fp.length > 0 && fp !== shell.dismissedServer
        }
    }
}
