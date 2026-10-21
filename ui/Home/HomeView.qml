import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Shapes
import Themes
import "../Components"
import "../Dashboard"
import "../Dashboard/transferFormat.js" as Fmt
import "../Components/icons.js" as Icons

/*
 * HomeView - Dashboard principal LocaLink selon la maquette V2.1
 *
 * Structure:
 * - Sidebar (navigation, profil)
 * - Header (breadcrumb, recherche)
 * - Zone titre (bonjour, état serveur)
 * - NetworkWorkspace (carte réseau)
 * - ActionRequiredPanel (à traiter)
 * - TransferList (transferts)
 * - ActivityList (activité)
 */
Item {
    id: root
    objectName: "homeView"

    property string username: ""

    signal logoutRequested()
    signal usersRequested()
    signal chatRequested()
    // openNewTransfer=true : la vue Transferts doit s'ouvrir directement sur
    // le volet "Nouveau transfert" (bouton dedie / etat vide), pas seulement
    // sur la liste (ex. clic sur "Transferts" dans la Sidebar).
    signal fileTransferRequested(bool openNewTransfer, var peer)
    signal callRequested()
    signal adminRequested()
    signal settingsRequested()
    signal sharedFoldersRequested()
    signal aboutRequested()
    // Emis par le bouton "Examiner" d'ActionRequiredPanel : ouvre l'Admin
    // directement sur l'onglet pertinent (0 = Journal d'audit,
    // 1 = Machines autorisées - voir AdminView.currentTab).
    signal adminSectionRequested(int tab)
    // « Nouvelle discussion » : AppShell ouvre la sous-page de creation.
    signal newConversationRequested()

    // Responsive breakpoints (selon maquette HTML)
    readonly property int width1440: 1440
    readonly property int width1200: 1200
    readonly property int width900: 900
    readonly property int width700: 700

    readonly property bool isCompact: root.width < width900
    readonly property bool isMobile: root.width < width700

    // Mode validation visuelle (activé pour test géométrie)
    property bool demoMode: false

    // Couleurs exactes selon maquette HTML
    readonly property color bg: Theme.dashboardBackground
    readonly property color surface: Theme.dashboardSurface
    readonly property color surface2: Theme.dashboardSurfaceAlt
    readonly property color line: Theme.dashboardLine
    readonly property color line2: Theme.dashboardLineStrong
    readonly property color ink: Theme.dashboardInk
    readonly property color ink2: Theme.dashboardInkSecondary
    readonly property color ink3: Theme.dashboardInkTertiary
    readonly property color primary: Theme.dashboardPrimary
    readonly property color primarySoft: Theme.dashboardPrimarySoft
    readonly property color primaryMuted: Theme.dashboardPrimaryMuted
    readonly property color ok: Theme.dashboardSuccess
    readonly property color okSoft: Theme.dashboardSuccessSoft
    readonly property color okText: Theme.dashboardSuccessText
    readonly property color warn: Theme.dashboardWarning
    readonly property color warnSoft: Theme.dashboardWarningSoft
    readonly property color warnText: Theme.dashboardWarningText
    readonly property color err: Theme.dashboardError
    readonly property color errSoft: Theme.dashboardErrorSoft
    readonly property color errText: Theme.dashboardErrorText
    readonly property color info: Theme.dashboardInfo
    readonly property color infoSoft: Theme.dashboardInfoSoft
    readonly property color infoText: Theme.dashboardInfoText
    readonly property color call: Theme.dashboardCall
    readonly property color callSoft: Theme.dashboardCallSoft
    readonly property color callText: Theme.dashboardCallText
    readonly property color track: Theme.dashboardSurfaceSunken

    readonly property bool isAdmin: (typeof userManager !== "undefined" && userManager)
                                    ? userManager.currentUserIsAdmin : false
    readonly property var election: (typeof electionService !== "undefined")
                                    ? electionService : null
    readonly property int peersCount: (typeof peersModel !== "undefined" && peersModel)
                                      ? peersModel.count : 0



    // État serveur
    readonly property string serverStatusLabel: {
        if (!root.election)
            return qsTr("Réseau local")
        if (root.election.roleLabel === "TEMP_SERVER")
            return qsTr("Mode secours")
        if (root.election.roleLabel === "SERVER")
            return qsTr("Serveur actif")
        return qsTr("Connecté au serveur")
    }
    readonly property color serverStatusColor: {
        if (!root.election)
            return Theme.dashboardSuccess
        if (root.election.roleLabel === "TEMP_SERVER")
            return Theme.dashboardWarning
        return Theme.dashboardSuccess
    }

    // Chargement : les listes affichent des squelettes tant que le contenu
    // n'est pas "installe" (evite un flash d'etat vide avant l'arrivee des
    // donnees). Passe a true des que des donnees arrivent, ou apres 600 ms.
    property bool contentSettled: false

    Timer {
        interval: 600
        running: true
        repeat: false
        onTriggered: root.contentSettled = true
    }

    // Données transferts
    property var transferItems: []
    // Nombre de transferts reellement actifs (in_progress) parmi
    // transferItems - distinct de transferItems.length des que des
    // transferts recents (termines/echoues/...) sont ajoutes pour
    // completer la liste (voir refreshTransfers()).
    property int activeTransferCount: 0

    // ---- Bandeau d'indicateurs (refonte 2026) ---------------------------
    // activeTransferCount est plafonne a 4 (la liste du dashboard n'affiche
    // que 4 lignes) : le bandeau a besoin des totaux reels.
    property int totalActiveTransferCount: 0
    property int activeSendCount: 0
    property int activeReceiveCount: 0
    // Progression (0..1) de chaque transfert en cours, pour les mini
    // barres de la tuile "Transferts actifs" - 6 au maximum.
    property var activeTransferProgress: []
    // Machines autorisees (administrateur uniquement, 0 sinon).
    property int authorizedMachineCount: 0
    // Nombre d'evenements charges dans le journal d'audit.
    readonly property int auditEventCount: (typeof auditLogModel !== "undefined" && auditLogModel)
                                           ? auditLogModel.count : 0

    function refreshAuthorizedMachineCount() {
        if (!root.isAdmin || typeof authorizedMachineModel === "undefined" || !authorizedMachineModel) {
            authorizedMachineCount = 0
            return
        }
        let total = authorizedMachineModel.rowCount ? authorizedMachineModel.rowCount() : 0
        let authorized = 0
        for (let i = 0; i < total; i++) {
            const idx = authorizedMachineModel.index(i, 0)
            if (authorizedMachineModel.data(idx, authorizedMachineModel.AuthorizedRole))
                authorized++
        }
        authorizedMachineCount = authorized
    }

    function refreshTransfers() {
        if (typeof transferContext === "undefined" || !transferContext) {
            transferItems = []
            activeTransferCount = 0
            totalActiveTransferCount = 0
            activeSendCount = 0
            activeReceiveCount = 0
            activeTransferProgress = []
            return
        }
        const all = transferContext.activeTransfers || []
        // state est la valeur technique non localisee ("in_progress"),
        // contrairement a statusText qui est traduit et donc fragile a
        // comparer ici (voir TransferContext::onTransferStarted()).
        const running = all.filter(function(item) {
            return item && item.state === "in_progress"
        })
        // Totaux reels (bandeau d'indicateurs), avant troncature a 4.
        totalActiveTransferCount = running.length
        let sends = 0
        let receives = 0
        const progress = []
        for (let k = 0; k < running.length; k++) {
            if (running[k].incoming)
                receives++
            else
                sends++
            if (progress.length < 6)
                progress.push(Math.max(0, Math.min(100, running[k].percent || 0)) / 100)
        }
        activeSendCount = sends
        activeReceiveCount = receives
        activeTransferProgress = progress

        const active = running.slice(-4).reverse()
        activeTransferCount = active.length

        // Complete avec les derniers transferts termines/echoues/annules
        // quand il n'y a pas (ou peu) de transfert en cours, pour eviter
        // que la section "Transferts" du dashboard soit vide en permanence :
        // meme logique que la sequence chronologique deja disponible dans
        // transferContext.activeTransfers (voir TransferContext::loadHistory()),
        // simplement filtree ici sur l'etat inverse.
        if (active.length < 4) {
            const recent = all.filter(function(item) {
                return item && item.state !== "in_progress"
            }).slice(-(4 - active.length)).reverse()
            transferItems = active.concat(recent)
        } else {
            transferItems = active
        }

        if (transferItems.length > 0)
            contentSettled = true
    }

    // Données activité
    property var activityItems: []

    // Traduit une entree brute auditLogModel.get(i) (cles : eventType,
    // actorLabel, description, timestamp - voir AuditLogModel::get()) vers
    // la forme attendue par ActivityRow (event/actor/message/resultBadge).
    function activityFromAuditEntry(item) {
        const resultBadgeByEvent = {
            "connection": "ok",
            "transfer": "xf",
            "call": "call",
            "access_denied": "err"
        }
        return {
            event: item.eventType || "activity",
            actor: item.actorLabel || "",
            message: item.description || "",
            result: "",
            resultBadge: resultBadgeByEvent[item.eventType] || "",
            timestamp: item.timestamp ? new Date(item.timestamp) : new Date()
        }
    }

    function refreshActivities() {
        if (typeof auditLogModel === "undefined" || !auditLogModel) {
            activityItems = []
            return
        }
        const all = []
        const total = Math.min(auditLogModel.count, 10)
        for (let i = 0; i < total; i++) {
            all.push(root.activityFromAuditEntry(auditLogModel.get(i)))
        }
        activityItems = all
        if (all.length > 0)
            contentSettled = true
    }

    // Données postes pour la carte réseau. L'angle (degrés) et la
    // dérivation transfert/appel sont calculés par NetworkWorkspace lui-même
    // (voir Dashboard/NetworkWorkspace.qml) à partir de activeTransfers/
    // activeCalls ci-dessous ; on ne fournit ici que les champs réellement
    // exposés par peersModel (doc étape 3, §38).
    property var networkPeers: []
    property var networkOfflinePeers: []
    property var networkActiveCalls: []

    function refreshNetworkPeers() {
        if (typeof peersModel === "undefined" || !peersModel) {
            networkPeers = []
            return
        }
        const peers = []
        const count = peersModel.count

        for (let i = 0; i < count; i++) {
            const index = peersModel.index(i, 0)
            const id = peersModel.data(index, peersModel.IdRole || 257) || ""
            const name = peersModel.data(index, peersModel.NameRole || 258) || ""
            const address = peersModel.data(index, peersModel.AddressRole || 261) || ""
            const status = peersModel.data(index, peersModel.StatusRole || 260) || "online"
            const userUuid = peersModel.data(index, peersModel.UserUuidRole || 259) || ""
            // PortRole = UserRole + 6, LastSeenMsRole = UserRole + 9 (PeersModel).
            const port = peersModel.data(index, 262) || 0
            const lastSeenMs = peersModel.data(index, 265) || 0

            peers.push({
                id: id,
                name: name || ("Poste " + (i + 1)),
                address: address,
                status: status,
                userUuid: userUuid,
                port: port,
                lastSeenMs: lastSeenMs
            })
        }
        networkPeers = peers
    }

    // Postes autorisés mais absents (authorizedMachineModel moins
    // peersModel) : uniquement visible côté administrateur pour l'instant,
    // à confirmer côté client standard (doc §38).
    function refreshNetworkOfflinePeers() {
        if (!root.isAdmin || typeof authorizedMachineModel === "undefined" || !authorizedMachineModel) {
            networkOfflinePeers = []
            return
        }
        const presentById = {}
        const presentByAddress = {}
        if (typeof peersModel !== "undefined" && peersModel) {
            for (let i = 0; i < peersModel.count; i++) {
                const idx = peersModel.index(i, 0)
                const id = peersModel.data(idx, peersModel.IdRole || 257) || ""
                const addr = peersModel.data(idx, peersModel.AddressRole || 261) || ""
                if (id) presentById[id] = true
                if (addr) presentByAddress[addr] = true
            }
        }
        const offline = []
        const total = authorizedMachineModel.rowCount ? authorizedMachineModel.rowCount() : 0
        for (let j = 0; j < total; j++) {
            const midx = authorizedMachineModel.index(j, 0)
            const authorized = authorizedMachineModel.data(midx, authorizedMachineModel.AuthorizedRole)
            const id = authorizedMachineModel.data(midx, authorizedMachineModel.MachineIdRole) || ""
            const ip = authorizedMachineModel.data(midx, authorizedMachineModel.IpAddressRole) || ""
            const host = authorizedMachineModel.data(midx, authorizedMachineModel.HostnameRole) || ""
            if (authorized) {
                // Vérifier par ID en priorité, puis par adresse en repli
                const isPresent = (id && presentById[id]) || (ip && presentByAddress[ip])
                if (!isPresent && (id || ip)) {
                    offline.push({ name: host || ip || id, address: ip || "", id: id || "" })
                }
            }
        }
        networkOfflinePeers = offline
    }

    // Appel en cours (callContext) sous la forme attendue par
    // NetworkWorkspace.activeCalls.
    function refreshNetworkActiveCalls() {
        if (typeof callContext === "undefined" || !callContext
                || !callContext.remoteAddress || callContext.callState === "idle") {
            networkActiveCalls = []
            return
        }
        networkActiveCalls = [{ remoteAddress: callContext.remoteAddress, callState: callContext.callState }]
    }

    // Données actions requises
    property var actionRequiredItems: []
    // Nombre de postes en attente d'autorisation, reutilise par le badge
    // "admin" de la sidebar (DashboardSidebar.pendingAdmin).
    property int pendingAuthorizationCount: 0

    function refreshActionRequired() {
        const items = []

        // 1. Postes en attente d'autorisation (pendingClientCount) - seul un
        // admin peut autoriser un poste (voir AdminView, onglet "Machines
        // autorisées"), donc réservé côté admin comme refreshNetworkOfflinePeers().
        if (root.isAdmin && typeof authorizedMachineModel !== "undefined" && authorizedMachineModel) {
            const total = authorizedMachineModel.rowCount ? authorizedMachineModel.rowCount() : 0
            let pendingCount = 0
            const pendingHosts = []

            for (let j = 0; j < total; j++) {
                const midx = authorizedMachineModel.index(j, 0)
                const authorized = authorizedMachineModel.data(midx, authorizedMachineModel.AuthorizedRole)
                const ip = authorizedMachineModel.data(midx, authorizedMachineModel.IpAddressRole) || ""
                const status = authorizedMachineModel.data(midx, authorizedMachineModel.StatusRole) || ""
                const host = authorizedMachineModel.data(midx, authorizedMachineModel.HostnameRole) || ""

                if ((status === "pending" || (!status && !authorized)) && ip) {
                    pendingCount++
                    pendingHosts.push(host || ip)
                }
            }

            if (pendingCount > 0) {
                items.push({
                    urgency: "medium",
                    title: pendingCount === 1 ? qsTr("1 poste demande une autorisation")
                                           : qsTr("%1 postes demandent une autorisation").arg(pendingCount),
                    description: pendingHosts.slice(0, 3).join(", ") + (pendingHosts.length > 3 ? "..." : ""),
                    type: "authorization"
                })
            }
            root.pendingAuthorizationCount = pendingCount
        }

        // 2. Connexions refusées récentes (auditLogModel)
        if (typeof auditLogModel !== "undefined" && auditLogModel) {
            const count = Math.min(auditLogModel.count, 10)
            let deniedCount = 0
            let lastDenied = null

            for (let i = 0; i < count; i++) {
                const item = auditLogModel.get(i)
                if (item && item.eventType === "access_denied") {
                    deniedCount++
                    if (!lastDenied) {
                        lastDenied = {
                            message: item.description || "",
                            timestamp: item.timestamp ? new Date(item.timestamp) : new Date()
                        }
                    }
                }
            }

            if (deniedCount > 0) {
                const timeStr = lastDenied.timestamp ? new Date(lastDenied.timestamp).toLocaleTimeString([], {hour: '2-digit', minute:'2-digit'}) : ""
                items.push({
                    urgency: "high",
                    title: deniedCount === 1 ? qsTr("1 connexion refusée")
                                          : qsTr("%1 connexions refusées").arg(deniedCount),
                    description: lastDenied.message || qsTr("Certificat inconnu") + (timeStr ? ", " + timeStr : ""),
                    type: "access_denied"
                })
            }
        }

        actionRequiredItems = items
    }

    Component.onCompleted: {
        refreshTransfers()
        refreshActivities()
        refreshNetworkPeers()
        refreshNetworkOfflinePeers()
        refreshNetworkActiveCalls()
        refreshActionRequired()
        refreshAuthorizedMachineCount()
        refreshNow()
        refreshUserDirectory()
        refreshInterventions()
        refreshRecentCalls()
        // Etat initial : le registre prend le relais sur une page tres etroite
        // (onListFallbackChanged ne couvre que les changements).
        root.networkView = root.listFallback ? "registre" : "hemicycle"
    }

    Connections {
        target: (typeof transferContext !== "undefined") ? transferContext : null
        function onActiveTransfersChanged() { root.refreshTransfers() }
    }

    Connections {
        target: (typeof peersModel !== "undefined") ? peersModel : null
        function onCountChanged() {
            root.refreshNetworkPeers()
            root.refreshNetworkOfflinePeers()
        }
        function onDataChanged() {
            root.refreshNetworkPeers()
        }
        function onRowsInserted() {
            root.refreshNetworkPeers()
            root.refreshNetworkOfflinePeers()
        }
        function onRowsRemoved() {
            root.refreshNetworkPeers()
            root.refreshNetworkOfflinePeers()
        }
        function onModelReset() {
            root.refreshNetworkPeers()
            root.refreshNetworkOfflinePeers()
        }
    }

    Connections {
        target: (typeof authorizedMachineModel !== "undefined") ? authorizedMachineModel : null
        function onModelReset() {
            root.refreshNetworkOfflinePeers()
            root.refreshActionRequired()
            root.refreshAuthorizedMachineCount()
        }
        function onDataChanged() {
            root.refreshNetworkOfflinePeers()
            root.refreshActionRequired()
            root.refreshAuthorizedMachineCount()
        }
    }

    Connections {
        target: (typeof callContext !== "undefined") ? callContext : null
        function onCallStateChanged() { root.refreshNetworkActiveCalls() }
        function onRemoteAddressChanged() { root.refreshNetworkActiveCalls() }
    }

    Connections {
        target: (typeof auditLogModel !== "undefined") ? auditLogModel : null
        function onModelReset() {
            root.refreshActivities()
            root.refreshActionRequired()
        }
        // Le compteur de la tuile Journal suit `count` : la liste d'activite
        // doit suivre aussi, quelle que soit la facon dont le modele change.
        function onCountChanged() {
            root.refreshActivities()
            root.refreshActionRequired()
        }
    }

    // Fond
    Rectangle {
        anchors.fill: parent
        color: Theme.dashboardBackground
    }

    // Bannière d'erreur pour les actions transferts (ouvrir l'emplacement,
    // réessayer) - même patron que FileTransferView.qml (errorBanner).
    Rectangle {
        id: errorBanner
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: errorLabel.implicitHeight + 16
        color: Theme.dashboardError
        visible: opacity > 0
        opacity: 0
        z: 10

        Label {
            id: errorLabel
            anchors.centerIn: parent
            width: parent.width - 32
            color: Theme.dashboardSurface
            font.pixelSize: Theme.fs(13)
            font.family: Theme.fontFamily
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }

        Behavior on opacity { NumberAnimation { duration: 150 } }

        Timer {
            id: errorTimer
            interval: 4000
            onTriggered: errorBanner.opacity = 0
        }

        function show(message) {
            errorLabel.text = message
            opacity = 1
            errorTimer.restart()
        }
    }

    // ======================================================================
    // Mise en page (refonte 2026)
    //
    // Meme grille pour tous les roles : 4 indicateurs, puis deux rangees
    // [panneau large | panneau lateral]. Seul le CONTENU des panneaux
    // depend des droits :
    //   administrateur : A traiter, Journal d'audit, Activite recente
    //   utilisateur    : Messages non lus, Dossiers partages, Conversations
    // ======================================================================
    signal conversationRequested(int conversationId)

    // Deux colonnes des que la page (hors navigation) le permet.
    readonly property bool twoColumns: root.width >= 900
    readonly property bool metricsWrapped: root.width < 1060
    // Sous 760 px de page, la carte radiale devient illisible : la vue
    // Liste prend le relais (l'utilisateur peut revenir a la carte).
    readonly property bool listFallback: root.width < 760

    onListFallbackChanged: root.networkView = root.listFallback ? "registre" : "hemicycle"

    // ---- Donnees du role "utilisateur" -----------------------------------
    property int unreadTotal: 0
    property var recentConversations: []
    // Toutes les conversations (la plus recente d'abord) : fiche du poste, discussions.
    property var allConversations: []
    property int folderCount: 0
    property int folderConflictCount: 0

    function refreshConversations() {
        if (typeof messagingContext === "undefined" || !messagingContext) {
            root.unreadTotal = 0
            root.recentConversations = []
            root.allConversations = []
            return
        }
        const convs = (messagingContext.conversationsList() || []).slice()
        let unread = 0
        for (let i = 0; i < convs.length; i++)
            unread += convs[i].unreadCount || 0
        convs.sort(function(a, b) {
            return new Date(b.timestamp || 0).getTime() - new Date(a.timestamp || 0).getTime()
        })
        root.unreadTotal = unread
        root.recentConversations = convs.slice(0, 5)
        root.allConversations = convs
    }

    readonly property var folderModel: (typeof sharedFolderContext !== "undefined" && sharedFolderContext)
                                       ? sharedFolderContext.folderModel : null

    function refreshFolders() {
        if (!root.folderModel) {
            root.folderCount = 0
            root.folderConflictCount = 0
            return
        }
        const total = root.folderModel.rowCount()
        let conflicts = 0
        // HasConflictRole = Qt.UserRole + 9 (voir SharedFolderModel).
        for (let i = 0; i < total; i++)
            if (root.folderModel.data(root.folderModel.index(i, 0), 257 + 8))
                conflicts++
        root.folderCount = total
        root.folderConflictCount = conflicts
    }

    Connections {
        target: root.folderModel
        function onModelReset() { root.refreshFolders() }
        function onRowsInserted() { root.refreshFolders() }
        function onRowsRemoved() { root.refreshFolders() }
        function onDataChanged() { root.refreshFolders() }
    }

    // Les non-lus evoluent a chaque message : lecture locale periodique.
    Timer {
        interval: 5000
        running: root.visible
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            root.refreshConversations()
            root.refreshFolders()
            root.refreshNow()
        }
    }

    // ---- Utilitaires d'affichage ----------------------------------------
    property string nowText: ""

    function refreshNow() {
        const now = new Date()
        const day = now.toLocaleDateString(Qt.locale(), "dddd d MMMM")
        root.nowText = day.charAt(0).toUpperCase() + day.slice(1)
    }

    function relativeTime(value) {
        if (!value)
            return ""
        const date = (value instanceof Date) ? value : new Date(value)
        if (isNaN(date.getTime()))
            return ""
        const seconds = Math.max(0, Math.round((Date.now() - date.getTime()) / 1000))
        if (seconds < 60) return qsTr("à l'instant")
        const minutes = Math.round(seconds / 60)
        if (minutes < 60) return qsTr("il y a %1 min").arg(minutes)
        const hours = Math.round(minutes / 60)
        if (hours < 24) return qsTr("il y a %1 h").arg(hours)
        return date.toLocaleDateString(Qt.locale(), "d MMM")
    }

    readonly property var actionChips: {
        let authorizations = 0
        let denied = 0
        for (let i = 0; i < root.actionRequiredItems.length; i++) {
            const item = root.actionRequiredItems[i]
            if (!item) continue
            if (item.type === "authorization") authorizations++
            else if (item.type === "access_denied") denied++
        }
        const chips = []
        if (authorizations > 0)
            chips.push({ text: authorizations > 1 ? qsTr("%1 autorisations").arg(authorizations)
                                                  : qsTr("1 autorisation"), tone: "warning" })
        if (denied > 0)
            chips.push({ text: denied > 1 ? qsTr("%1 refus").arg(denied) : qsTr("1 refus"), tone: "danger" })
        return chips
    }

    // transferItems vient de transferContext ; TransferList attend
    // progress 0..1, address, transferred/total, status, isIncoming.
    readonly property var transferRowItems: root.transferItems.map(function(item) {
        return {
            fileName: item.fileName || "",
            peerName: item.peerName || "",
            address: item.peerAddress || "",
            progress: Math.max(0, Math.min(100, item.percent || 0)) / 100,
            transferred: item.bytesTransferred || 0,
            total: item.totalBytes || 0,
            status: item.statusText || "",
            state: item.state || "",
            timestamp: item.timestamp || "",
            isIncoming: item.incoming === true,
            transferKey: item.transferKey || "",
            filePath: item.filePath || ""
        }
    })

    function retryTransfer(row) {
        if (!row || !row.transferKey || typeof transferContext === "undefined" || !transferContext)
            return
        if (!transferContext.retryTransfer(row.transferKey))
            errorBanner.show(qsTr("Impossible de relancer le transfert."))
    }

    function openTransferLocation(row) {
        if (!row || !row.filePath || typeof transferContext === "undefined" || !transferContext)
            return
        if (!transferContext.openFileLocation(row.filePath))
            errorBanner.show(qsTr("Impossible d'ouvrir l'emplacement du fichier."))
    }

    // ======================================================================
    // Supervision du reseau (maquette 2 retenue, design/dashboard-mockups)
    //
    //   [Titre + contexte .......................... 4 indicateurs compacts]
    //   [Carte reseau (filtres, Carte/Liste)  ][Poste selectionne         ]
    //   [                                     ][Interventions requises    ]
    //   [Echanges en cours ][Evenements recents]
    //
    // Sous 1000 px de page : carte pleine largeur, puis les panneaux par
    // paires (detail + interventions, echanges + evenements).
    // ======================================================================

    // ---- Donnees propres a la supervision -------------------------------
    // Annuaire uuid -> nom du compte (pour "Utilisateur" du poste selectionne).
    property var userNameByUuid: ({})

    function refreshUserDirectory() {
        if (typeof messagingContext === "undefined" || !messagingContext || !messagingContext.availableUsers) {
            root.userNameByUuid = {}
            return
        }
        const users = messagingContext.availableUsers() || []
        const map = {}
        for (let i = 0; i < users.length; i++)
            if (users[i].userUuid)
                map[users[i].userUuid] = users[i].username || ""
        root.userNameByUuid = map
    }

    // Etat de confiance d'une machine (administrateur uniquement).
    function machineTrust(id, address) {
        if (!root.isAdmin || typeof authorizedMachineModel === "undefined" || !authorizedMachineModel)
            return ""
        const total = authorizedMachineModel.rowCount ? authorizedMachineModel.rowCount() : 0
        for (let i = 0; i < total; i++) {
            const idx = authorizedMachineModel.index(i, 0)
            const mid = authorizedMachineModel.data(idx, authorizedMachineModel.MachineIdRole) || ""
            const ip = authorizedMachineModel.data(idx, authorizedMachineModel.IpAddressRole) || ""
            if ((id && mid === id) || (!id && address && ip === address)) {
                const status = authorizedMachineModel.data(idx, authorizedMachineModel.StatusRole) || ""
                if (status === "revoked") return qsTr("Révoqué")
                if (status === "pending") return qsTr("En attente d'autorisation")
                return authorizedMachineModel.data(idx, authorizedMachineModel.AuthorizedRole)
                       ? qsTr("Autorisé") : qsTr("Non autorisé")
            }
        }
        return qsTr("Non enregistré")
    }

    function networkPeerEntry(id) {
        for (let i = 0; i < root.networkPeers.length; i++)
            if (root.networkPeers[i].id === id)
                return root.networkPeers[i]
        return null
    }

    // Interventions : une ligne par element reel demandant une action.
    property var interventions: []
    property int pendingRequestCount: 0

    function refreshInterventions() {
        const items = []
        let requests = 0
        if (root.isAdmin && typeof authorizedMachineModel !== "undefined" && authorizedMachineModel) {
            const total = authorizedMachineModel.rowCount ? authorizedMachineModel.rowCount() : 0
            for (let j = 0; j < total; j++) {
                const midx = authorizedMachineModel.index(j, 0)
                const status = authorizedMachineModel.data(midx, authorizedMachineModel.StatusRole) || ""
                const authorized = authorizedMachineModel.data(midx, authorizedMachineModel.AuthorizedRole)
                if (!(status === "pending" || (!status && !authorized)))
                    continue
                const ip = authorizedMachineModel.data(midx, authorizedMachineModel.IpAddressRole) || ""
                const host = authorizedMachineModel.data(midx, authorizedMachineModel.HostnameRole) || ""
                requests++
                items.push({ kind: "authorization", glyph: "", tone: "warning",
                             title: host || ip, meta: qsTr("Demande d'autorisation") + (ip ? " · " + ip : ""),
                             action: qsTr("Examiner"), tip: qsTr("Ouvrir les machines autorisées") })
            }
        }
        if (root.isAdmin && typeof auditLogModel !== "undefined" && auditLogModel) {
            const count = Math.min(auditLogModel.count, 10)
            let shown = 0
            for (let i = 0; i < count && shown < 2; i++) {
                const e = auditLogModel.get(i)
                if (!e || e.eventType !== "access_denied")
                    continue
                requests++
                shown++
                items.push({ kind: "denied", glyph: "", tone: "danger",
                             title: e.actorLabel || qsTr("Connexion refusée"),
                             meta: e.description || qsTr("Connexion refusée"),
                             action: qsTr("Journal"), tip: qsTr("Ouvrir le journal d'audit") })
            }
        }
        if (typeof transferContext !== "undefined" && transferContext) {
            const all = (transferContext.activeTransfers || []).slice().reverse()
            let failed = 0
            for (let k = 0; k < all.length && failed < 2; k++) {
                const t = all[k]
                if (!t || (t.state !== "failed" && t.state !== "interrupted"))
                    continue
                failed++
                items.push({ kind: "transfer", glyph: "", tone: "danger", transferKey: t.transferKey || "",
                             title: t.fileName || qsTr("Transfert"),
                             meta: qsTr("Échec") + " · " + (t.errorString || t.statusText || t.peerName || ""),
                             action: qsTr("Réessayer"), tip: qsTr("Relancer le transfert") })
            }
        }
        if (!root.isAdmin && root.folderModel) {
            const total = root.folderModel.rowCount()
            for (let f = 0; f < total; f++) {
                const fidx = root.folderModel.index(f, 0)
                // HasConflictRole = UserRole + 9, NameRole = UserRole + 3 (SharedFolderModel).
                if (!root.folderModel.data(fidx, 257 + 8))
                    continue
                items.push({ kind: "conflict", glyph: "", tone: "warning",
                             title: root.folderModel.data(fidx, 257 + 2) || qsTr("Dossier partagé"),
                             meta: qsTr("Conflit de synchronisation"),
                             action: qsTr("Résoudre"), tip: qsTr("Ouvrir les dossiers partagés") })
            }
        }
        for (let o = 0; o < root.networkOfflinePeers.length && o < 3; o++) {
            const p = root.networkOfflinePeers[o]
            items.push({ kind: "offline", glyph: "", tone: "neutral", peerId: p.id || p.address,
                         title: p.name, meta: qsTr("Hors ligne") + (p.address ? " · " + p.address : ""),
                         action: qsTr("Détails"), tip: qsTr("Sélectionner ce poste sur la carte") })
        }
        root.interventions = items
        root.pendingRequestCount = requests
    }

    function runIntervention(item) {
        if (!item)
            return
        switch (item.kind) {
        case "authorization": root.adminSectionRequested(1); break
        case "denied": root.adminSectionRequested(0); break
        case "transfer": root.retryTransfer({ transferKey: item.transferKey }); break
        case "conflict": root.sharedFoldersRequested(); break
        case "offline":
            root.networkView = "hemicycle"
            root.selectPeer(item.peerId)
            break
        }
    }

    // Appels recents (utilisateur standard ; roles de CallHistoryModel :
    // UserRole+2 direction, +4 nom, +5 statut, +6 debut, +7 duree).
    property var recentCalls: []

    function refreshRecentCalls() {
        if (root.isAdmin || typeof callHistoryModel === "undefined" || !callHistoryModel) {
            root.recentCalls = []
            return
        }
        const out = []
        const total = Math.min(callHistoryModel.rowCount(), 5)
        for (let i = 0; i < total; i++) {
            const idx = callHistoryModel.index(i, 0)
            const direction = callHistoryModel.data(idx, 258) || "outgoing"
            const status = callHistoryModel.data(idx, 261) || ""
            const seconds = callHistoryModel.data(idx, 263) || 0
            const missed = status === "missed" || status === "rejected" || status === "failed"
            let what
            if (status === "missed") what = qsTr("Appel manqué")
            else if (status === "rejected") what = qsTr("Appel refusé")
            else if (status === "failed") what = qsTr("Appel échoué")
            else what = (direction === "incoming" ? qsTr("Appel entrant") : qsTr("Appel sortant"))
                        + (seconds > 0 ? " · " + qsTr("%1 min").arg(Math.max(1, Math.round(seconds / 60))) : "")
            out.push({ who: callHistoryModel.data(idx, 260) || callHistoryModel.data(idx, 259) || "",
                       what: what, missed: missed, startedAt: callHistoryModel.data(idx, 262) || "" })
        }
        root.recentCalls = out
    }

    Connections {
        target: (typeof callHistoryModel !== "undefined") ? callHistoryModel : null
        function onModelReset() { root.refreshRecentCalls() }
        function onCountChanged() { root.refreshRecentCalls() }
    }

    // Les interventions dependent des machines, du journal, des transferts,
    // des dossiers et des postes hors ligne : recalcul a chaque changement.
    onActionRequiredItemsChanged: root.refreshInterventions()
    onNetworkOfflinePeersChanged: root.refreshInterventions()
    onTransferItemsChanged: root.refreshInterventions()
    onFolderConflictCountChanged: root.refreshInterventions()
    onNetworkPeersChanged: root.refreshUserDirectory()

    // ---- Actions partagees (carte, liste, panneau de detail) ------------
    function openConversationWithPeer(peer) {
        // startConversationWith() attend l'identifiant numerique du compte
        // (et non l'UUID du poste) : on le retrouve via availableUsers(), puis
        // on ouvre la conversation. A defaut, on ouvre les Discussions.
        if (!peer || typeof messagingContext === "undefined" || !messagingContext || !peer.userUuid) {
            root.chatRequested()
            return
        }
        const users = messagingContext.availableUsers() || []
        let conversationId = 0
        for (let i = 0; i < users.length; i++) {
            if (users[i].userUuid === peer.userUuid) {
                conversationId = messagingContext.startConversationWith(users[i].userId)
                break
            }
        }
        if (conversationId > 0)
            root.conversationRequested(conversationId)
        else
            root.chatRequested()
    }

    function callPeer(peer) {
        if (!peer || !peer.address || typeof callContext === "undefined" || !callContext)
            return
        // Port de signalisation connu (PeersModel, UserRole + 8) : sinon le
        // port par defaut est choisi cote metier.
        const signalingPort = root.peerSignalingPort(peer.id)
        if (!callContext.call(peer.address, signalingPort))
            errorBanner.show(qsTr("Impossible d'appeler %1.").arg(peer.name || peer.address))
    }

    function peerSignalingPort(id) {
        if (typeof peersModel === "undefined" || !peersModel)
            return 0
        for (let i = 0; i < peersModel.count; i++) {
            const idx = peersModel.index(i, 0)
            if ((peersModel.data(idx, peersModel.IdRole || 257) || "") === id)
                return peersModel.data(idx, 264) || 0
        }
        return 0
    }

    // ---- Etat du reseau et selection (hemicycle / registre) --------------
    // Etat effectif de chaque poste, derive comme dans l'ancienne carte :
    // hors ligne > appel > transfert > occupe > absent > en ligne. La
    // selection est commune a l'hemicycle, au registre et a la fiche.
    property string networkView: "hemicycle"     // "hemicycle" | "registre"
    property string selectedId: ""
    property var hiddenStatuses: []
    property bool selectionInitialized: false

    readonly property var liveTransfers: (typeof transferContext !== "undefined" && transferContext)
                                         ? (transferContext.activeTransfers || []) : []
    readonly property string activeServerUuid: (root.election && root.election.activeServerUuid)
                                               ? root.election.activeServerUuid : ""

    function peerIdFor(p) {
        if (p.id && p.id.length > 0) return p.id
        return (p.address && p.address.length > 0) ? p.address : (p.name || "")
    }

    // Transfert EN COURS le plus recent avec ce poste (pas l'historique).
    function findTransferFor(p) {
        let latest = null
        for (let j = 0; j < root.liveTransfers.length; j++) {
            const t = root.liveTransfers[j]
            if (!t || t.state !== "in_progress") continue
            if (t.transferKey && t.transferKey.indexOf("history:") === 0) continue
            const matches = (p.id && t.peerMachineId && t.peerMachineId === p.id)
                            || (p.address && t.peerAddress === p.address)
                            || (p.name && t.peerName === p.name)
            if (matches && (!latest || (t.timestamp && t.timestamp > (latest.timestamp || ""))))
                latest = t
        }
        return latest
    }

    function findCallFor(p) {
        for (let k = 0; k < root.networkActiveCalls.length; k++) {
            const c = root.networkActiveCalls[k]
            if (!c) continue
            if ((p.id && c.remoteMachineId && c.remoteMachineId === p.id)
                    || (p.address && c.remoteAddress === p.address))
                return c
        }
        return null
    }

    readonly property var presentPeers: root.networkPeers.map(function(p) {
        const xfer = root.findTransferFor(p)
        const call = root.findCallFor(p)
        const status = call ? "calling" : xfer ? "transferring"
                     : (p.status === "busy" || p.status === "away") ? p.status : "online"
        return {
            id: root.peerIdFor(p), name: p.name || "", address: p.address || "",
            userUuid: p.userUuid || "",
            userName: (p.userUuid && root.userNameByUuid[p.userUuid]) || "",
            status: status, direction: xfer ? (xfer.incoming ? "in" : "out") : "",
            transfer: xfer, call: call,
            server: root.activeServerUuid.length > 0 && p.id === root.activeServerUuid
        }
    })
    readonly property var offlinePeersLive: root.networkOfflinePeers.map(function(o) {
        return { id: o.id || o.address || o.name, name: o.name || "", address: o.address || "",
                 userUuid: "", userName: "", status: "offline", direction: "",
                 transfer: null, call: null, server: false }
    })
    readonly property var allPeersLive: root.presentPeers.concat(root.offlinePeersLive)

    function peerById(id) {
        for (let i = 0; i < root.allPeersLive.length; i++)
            if (root.allPeersLive[i].id === id)
                return root.allPeersLive[i]
        return null
    }

    readonly property var selectedPeer: root.selectedId.length > 0 ? root.peerById(root.selectedId) : null

    // Selection depuis la recherche globale (AppShell.showPeer) ou une
    // intervention : le poste est rendu visible s'il etait filtre.
    function selectPeer(id) {
        const p = root.peerById(id)
        if (!p)
            return
        if (root.hiddenStatuses.indexOf(p.status) >= 0)
            root.toggleStatus(p.status)
        root.selectedId = id
        root.selectionInitialized = true
    }

    // Premiere selection automatique (poste en activite de preference),
    // puis nettoyage si le poste selectionne disparait.
    function ensureSelection() {
        const present = root.presentPeers
        if (root.selectedId.length > 0) {
            if (!root.peerById(root.selectedId))
                root.selectedId = ""
            return
        }
        if (root.selectionInitialized || present.length === 0)
            return
        let pick = present[0]
        for (let i = 0; i < present.length; i++) {
            if (present[i].status === "transferring" || present[i].status === "calling") {
                pick = present[i]
                break
            }
        }
        root.selectedId = pick.id
        root.selectionInitialized = true
    }
    onAllPeersLiveChanged: Qt.callLater(root.ensureSelection)

    function toggleStatus(key) {
        const list = root.hiddenStatuses.slice()
        const i = list.indexOf(key)
        if (i >= 0) list.splice(i, 1)
        else list.push(key)
        root.hiddenStatuses = list
    }

    function countStatus(key) {
        return root.allPeersLive.filter(function(p) { return p.status === key }).length
    }

    // Conversation individuelle avec la personne connectee sur ce poste
    // (rapprochement par nom d'utilisateur, faute d'identifiant expose).
    function conversationFor(peer) {
        if (!peer || !peer.userName)
            return null
        for (let i = 0; i < root.allConversations.length; i++)
            if (root.allConversations[i].name === peer.userName)
                return root.allConversations[i]
        return null
    }

    // Correspondant d'un echange -> poste de l'hemicycle (adresse puis nom).
    function selectPeerByEndpoint(address, name) {
        for (let i = 0; i < root.allPeersLive.length; i++) {
            const p = root.allPeersLive[i]
            if ((address && p.address === address) || (name && p.name === name)) {
                root.selectPeer(p.id)
                return
            }
        }
    }

    // Activite d'un poste pour le registre.
    function activityText(p) {
        if (!p) return ""
        if (p.status === "transferring" && p.transfer)
            return (p.transfer.incoming ? qsTr("Réception") : qsTr("Envoi")) + " · "
                   + Math.round(Math.max(0, Math.min(100, p.transfer.percent || 0))) + " %"
        if (p.status === "calling") return qsTr("En appel")
        if (p.status === "offline") return qsTr("Hors ligne")
        const e = root.networkPeerEntry(p.id)
        return e && e.lastSeenMs > 0 ? root.relativeTime(new Date(e.lastSeenMs)) : ""
    }

    // Nature d'un evenement du journal : glyphe et resultat (mot + couleur).
    function eventLook(type) {
        switch (type) {
        case "connection": return { glyph: "online", result: qsTr("Connecté"), ink: Theme.successInk }
        case "disconnection": return { glyph: "offline", result: qsTr("Déconnecté"), ink: Theme.ink3 }
        case "transfer": return { glyph: "brand", result: qsTr("Transfert"), ink: Theme.navActiveInk }
        case "access_denied": return { glyph: "error", result: qsTr("Refusée"), ink: Theme.dangerInk }
        case "call": return { glyph: "call", result: qsTr("Appel"), ink: Theme.callInk }
        case "message": return { glyph: "read", result: qsTr("Message"), ink: Theme.ink3 }
        }
        return { glyph: "watch", result: "", ink: Theme.ink3 }
    }

    function timeOf(value) {
        if (!value)
            return ""
        const d = (value instanceof Date) ? value : new Date(value)
        return isNaN(d.getTime()) ? "" : Qt.formatTime(d, "HH:mm")
    }

    function eventVisual(type) {
        switch (type) {
        case "transfer": return { glyph: "", tone: "transfer" }
        case "access_denied": return { glyph: "", tone: "danger" }
        case "connection": return { glyph: "", tone: "success" }
        case "disconnection": return { glyph: "", tone: "neutral" }
        case "call": return { glyph: "", tone: "call" }
        case "message": return { glyph: "", tone: "neutral" }
        default: return { glyph: "", tone: "neutral" }
        }
    }

    function transferVisual(row) {
        if (row.state === "in_progress")
            return { tone: "transfer", badge: Math.round(row.progress * 100) + " %", badgeTone: "accent",
                     time: qsTr("En cours") }
        if (row.state === "completed")
            return { tone: "success", badge: qsTr("Terminé"), badgeTone: "success", time: root.relativeTime(row.timestamp) }
        if (row.state === "cancelled")
            return { tone: "neutral", badge: qsTr("Annulé"), badgeTone: "neutral", time: root.relativeTime(row.timestamp) }
        return { tone: "danger", badge: qsTr("Échec"), badgeTone: "danger", time: root.relativeTime(row.timestamp) }
    }

    // Le role du poste (serveur/client) est deja annonce par la barre
    // superieure : le sous-titre ne le repete pas et tient sur une ligne.
    readonly property string sessionContext: {
        const parts = []
        if (root.username.length > 0)
            parts.push(qsTr("Bonjour %1").arg(root.username))
        if (root.nowText.length > 0)
            parts.push(root.nowText.charAt(0).toLowerCase() + root.nowText.slice(1))
        parts.push(root.peersCount === 0 ? qsTr("aucun autre poste détecté")
                   : root.peersCount === 1 ? qsTr("1 poste joignable")
                   : qsTr("%1 postes joignables").arg(root.peersCount))
        return parts.join(" · ")
    }

    // Seuil de mise en page sur la largeur utile de la page.
    // "Echanges en cours" : uniquement les transferts actifs (titre du panneau).
    readonly property var runningTransferRows: root.transferRowItems.filter(function(r) { return r.state === "in_progress" })

    readonly property bool wideLayout: (root.width - 2 * Theme.pagePadding) >= 1000

    // ======================================================================
    // Mise en page Ligne claire (A2)
    //
    //   [surtitre · salutation · phrase + actions ......... 4 chiffres serif]
    //   [Le reseau : hemicycle | registre + legende ][Poste selectionne    ]
    //   [Echanges            ][Journal / Appels     ][A traiter           ]
    //
    // Seuils sur la largeur utile de la page (equivalent des @container de
    // la maquette) : chiffres sous la salutation sous 1180 px ; colonne de
    // droite de 348 px au-dessus de 1260 px, 312 px jusqu'a 1000 px ; en
    // dessous, empilement (fiche et « A traiter » cote a cote).
    // ======================================================================
    readonly property real pageW: root.width - 2 * Theme.pagePadding
    readonly property bool heroWide: root.pageW > 1180
    readonly property bool mainWide: root.pageW > 1000
    readonly property bool lowerPaired: root.pageW > 760
    readonly property real sideWidth: root.pageW > 1260 ? 348 : 312

    function esc(t) {
        return String(t === undefined || t === null ? "" : t)
               .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    }

    readonly property string firstName: (root.username || "").trim().split(/\s+/)[0] || ""
    readonly property string localMachineName: (typeof settingsModel !== "undefined" && settingsModel
                                                && settingsModel.machineName.length > 0)
                                               ? settingsModel.machineName : qsTr("Ce poste")
    readonly property string localState: !root.election ? "client"
                                        : root.election.roleLabel === "TEMP_SERVER" ? "backup"
                                        : root.election.roleLabel === "SERVER" ? "server" : "client"

    // Demandes d'autorisation en attente (interventions « authorization »).
    readonly property var pendingAuthorizations: root.interventions.filter(function(i) { return i.kind === "authorization" })

    readonly property string ledeText: {
        if (root.allPeersLive.length === 0)
            return qsTr("Aucun autre poste n'est encore apparu sur le réseau. La découverte automatique se poursuit.")
        if (root.isAdmin) {
            const lead = root.localState === "backup"
                       ? qsTr("Ce poste assure le service en <b><font color=\"%1\">mode secours</font></b>. ").arg(Theme.warningInk)
                       : ""
            const n = root.pendingAuthorizations.length
            if (n > 1)
                return lead + qsTr("<b>%1 postes</b> demandent l'accès au réseau et attendent votre décision.").arg(n)
            if (n === 1)
                return lead + qsTr("<b>%1</b> demande l'accès au réseau et attend votre décision.")
                                  .arg(root.esc(root.pendingAuthorizations[0].title))
            return lead + (lead.length ? qsTr("Aucune décision ne vous attend.")
                                       : qsTr("Le réseau fonctionne normalement. Aucune décision ne vous attend."))
        }
        let text = ""
        const inbound = root.runningTransferRows.filter(function(r) { return r.isIncoming })
        if (inbound.length > 0) {
            // Nom de la personne connectee sur le poste emetteur, a defaut le poste.
            const sender = root.presentPeers.filter(function(p) {
                return p.address === inbound[0].address || p.name === inbound[0].peerName
            })[0]
            text = qsTr("<b>%1</b> vous envoie %2. ").arg(root.esc((sender && sender.userName) || inbound[0].peerName || inbound[0].address))
                                                    .arg(root.esc(inbound[0].fileName))
        }
        return text + (root.folderConflictCount > 0
                       ? qsTr("Un conflit est à résoudre dans vos dossiers partagés.")
                       : qsTr("Vos dossiers partagés sont synchronisés."))
    }

    function plural(n, one, many) { return n + " " + (n > 1 ? many : one) }

    readonly property string transferContextText: root.totalActiveTransferCount === 0
        ? qsTr("aucun en cours")
        : [root.activeSendCount > 0 ? root.plural(root.activeSendCount, qsTr("envoi"), qsTr("envois")) : "",
           root.activeReceiveCount > 0 ? root.plural(root.activeReceiveCount, qsTr("réception"), qsTr("réceptions")) : ""]
          .filter(function(x) { return x.length > 0 }).join(" · ")

    readonly property var figureModel: {
        if (root.isAdmin) {
            const denied = Math.max(0, root.pendingRequestCount - root.pendingAuthorizationCount)
            return [
                { key: "peers", label: qsTr("Postes en ligne"), value: String(root.peersCount),
                  suffix: root.authorizedMachineCount > 0 ? "/" + root.authorizedMachineCount : "",
                  context: root.networkOfflinePeers.length > 0
                           ? qsTr("%1 hors ligne").arg(root.networkOfflinePeers.length)
                           : (root.peersCount > 0 ? qsTr("tous joignables") : qsTr("découverte en cours")),
                  tip: qsTr("Ouvrir la liste des postes") },
                { key: "transfers", label: qsTr("Transferts actifs"), value: String(root.totalActiveTransferCount),
                  suffix: "", context: root.transferContextText, tip: qsTr("Ouvrir les transferts") },
                { key: "requests", label: qsTr("Demandes"), value: String(root.pendingRequestCount), suffix: "",
                  attention: root.pendingAuthorizationCount > 0,
                  context: root.pendingRequestCount === 0 ? qsTr("aucune en attente")
                           : [root.pendingAuthorizationCount > 0 ? root.plural(root.pendingAuthorizationCount, qsTr("autorisation"), qsTr("autorisations")) : "",
                              denied > 0 ? root.plural(denied, qsTr("refus"), qsTr("refus")) : ""]
                             .filter(function(x) { return x.length > 0 }).join(" · "),
                  tip: qsTr("Autorisations en attente et connexions refusées") },
                { key: "audit", label: qsTr("Journal"), value: String(root.auditEventCount), suffix: "",
                  context: root.activityItems.length > 0 ? qsTr("dernier à %1").arg(root.timeOf(root.activityItems[0].timestamp))
                                                         : qsTr("aucun événement"),
                  tip: qsTr("Ouvrir le journal d'audit") }
            ]
        }
        const unreadConvs = root.recentConversations.filter(function(c) { return (c.unreadCount || 0) > 0 }).length
        return [
            { key: "peers", label: qsTr("Postes accessibles"), value: String(root.peersCount), suffix: "",
              context: root.peersCount > 0 ? qsTr("serveur joignable") : qsTr("découverte en cours"),
              tip: qsTr("Ouvrir la liste des postes") },
            { key: "transfers", label: qsTr("Transferts"), value: String(root.totalActiveTransferCount), suffix: "",
              context: root.transferContextText, tip: qsTr("Ouvrir les transferts") },
            { key: "unread", label: qsTr("Non lus"), value: String(root.unreadTotal), suffix: "",
              context: root.unreadTotal > 0 ? qsTr("dans %1").arg(root.plural(unreadConvs, qsTr("conversation"), qsTr("conversations")))
                                            : qsTr("tout est lu"),
              tip: qsTr("Ouvrir les discussions") },
            { key: "folders", label: qsTr("Dossiers partagés"), value: String(root.folderCount), suffix: "",
              attention: root.folderConflictCount > 0,
              context: root.folderConflictCount > 0 ? root.plural(root.folderConflictCount, qsTr("conflit"), qsTr("conflits"))
                                                    : qsTr("synchronisés"),
              tip: qsTr("Ouvrir les dossiers partagés") }
        ]
    }

    function openFigure(key) {
        switch (key) {
        case "peers": root.usersRequested(); break
        case "transfers": root.fileTransferRequested(false, null); break
        case "requests": root.adminSectionRequested(1); break
        case "audit": root.adminSectionRequested(0); break
        case "unread": root.chatRequested(); break
        case "folders": root.sharedFoldersRequested(); break
        }
    }

    // Onglet Hemicycle / Registre : texte souligne d'un filet d'encre.
    component ViewTab: AbstractButton {
        id: tab
        property bool current: false
        property int count: -1
        hoverEnabled: true
        focusPolicy: Qt.StrongFocus
        padding: 0
        implicitHeight: 30
        implicitWidth: tabRow.implicitWidth
        Accessible.role: Accessible.PageTab
        Accessible.name: tab.text
        HoverHandler { cursorShape: Qt.PointingHandCursor }

        background: Item {
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 2
                color: tab.current ? Theme.ruleInk : "transparent"
            }
            Rectangle {
                anchors.fill: parent
                anchors.margins: -3
                color: "transparent"
                border.width: 2
                border.color: Theme.focusRing
                radius: Theme.radiusSheet
                visible: tab.visualFocus
            }
        }
        contentItem: Item {
            Row {
                id: tabRow
                anchors.top: parent.top
                anchors.topMargin: 2
                spacing: 6
                Text {
                    text: tab.text
                    color: tab.current || tab.hovered ? Theme.ink : Theme.ink3
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(12.5)
                    font.weight: tab.current ? Theme.weightSemibold : Theme.weightMedium
                }
                Text {
                    visible: tab.count > 0
                    text: tab.count
                    color: Theme.ink3
                    font.family: Theme.fontFamilySerif
                    font.pixelSize: Theme.fs(12)
                    font.weight: Theme.weightBold
                }
            }
        }
    }

    // Filtre d'etat de la legende : glyphe, libelle, compteur ; barre quand masque.
    component LegendFilter: AbstractButton {
        id: lf
        property string kind: "online"
        property int count: 0
        property bool shown: true
        hoverEnabled: true
        focusPolicy: Qt.TabFocus
        padding: 0
        implicitHeight: 24
        implicitWidth: lfRow.implicitWidth
        opacity: lf.shown ? 1 : 0.42
        Accessible.role: Accessible.CheckBox
        Accessible.checked: lf.shown
        Accessible.name: qsTr("%1 : %2 poste(s), %3").arg(lf.text).arg(lf.count)
                            .arg(lf.shown ? qsTr("affichés") : qsTr("masqués"))
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        ToolTip.visible: lf.hovered
        ToolTip.delay: 600
        ToolTip.text: (lf.shown ? qsTr("Masquer les postes « %1 »").arg(lf.text)
                                : qsTr("Afficher les postes « %1 »").arg(lf.text))
                      + (lf.kind === "offline" ? "
" + qsTr("Postes autorisés actuellement absents du réseau") : "")

        background: Rectangle {
            color: "transparent"
            border.width: lf.visualFocus ? 2 : 0
            border.color: Theme.focusRing
            radius: Theme.radiusSheet
        }
        contentItem: Item {
            Row {
                id: lfRow
                anchors.verticalCenter: parent.verticalCenter
                spacing: 7
                StateGlyph { anchors.verticalCenter: parent.verticalCenter; kind: lf.kind; size: 12 }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: lf.text
                    color: Theme.ink2
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(12)
                    font.strikeout: !lf.shown
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: lf.count
                    color: Theme.ink
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(12)
                    font.weight: Theme.weightSemibold
                    font.features: ({ "tnum": 1 })
                }
            }
        }
    }

    // ======================================================================
    Flickable {
        id: pageFlick
        objectName: "pageFlick"
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: Math.max(height, pageColumn.y + pageColumn.implicitHeight + 18)
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        ColumnLayout {
            id: pageColumn
            x: Theme.pagePadding
            y: Theme.compact ? 16 : 20
            width: pageFlick.width - 2 * Theme.pagePadding
            spacing: 20

            // ---- En-tete : salutation, phrase, actions, chiffres -----------
            GridLayout {
                id: hero
                Layout.fillWidth: true
                columns: root.heroWide ? 2 : 1
                columnSpacing: 32
                rowSpacing: 14

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignBottom
                    spacing: 6

                    CapsLabel {
                        Layout.fillWidth: true
                        text: root.nowText + " · " + root.localMachineName
                    }
                    Text {
                        Layout.fillWidth: true
                        text: qsTr("Bonjour <b>%1</b>.").arg(root.esc(root.firstName))
                        textFormat: Text.StyledText
                        color: Theme.ink
                        font.family: Theme.fontFamilySerif
                        font.pixelSize: root.height < 720 ? Theme.fs(30) : Theme.fontSizeGreeting
                        elide: Text.ElideRight
                        Accessible.role: Accessible.Heading
                    }
                    Flow {
                        Layout.fillWidth: true
                        Layout.topMargin: 2
                        spacing: 22

                        Text {
                            id: lede
                            // Pleine largeur si la phrase est longue : les actions passent dessous.
                            width: Math.min(implicitWidth, parent.width)
                            height: Math.max(implicitHeight, heroActions.implicitHeight)
                            verticalAlignment: Text.AlignVCenter
                            text: root.ledeText
                            textFormat: Text.StyledText
                            color: Theme.ink2
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(14.5)
                            wrapMode: Text.WordWrap
                        }
                        Row {
                            id: heroActions
                            spacing: 8
                            AppButton {
                                variant: "ink"
                                text: qsTr("Envoyer un fichier")
                                iconPath: "M12 19.5v-15 M5.5 11 12 4.5 18.5 11"
                                enabled: root.peersCount > 0
                                tooltip: root.peersCount > 0 ? "" : qsTr("Aucun poste joignable pour l'instant")
                                onClicked: root.fileTransferRequested(true, null)
                            }
                            AppButton {
                                variant: "line"
                                text: qsTr("Nouvelle discussion")
                                iconPath: Icons.messageCircle
                                onClicked: root.newConversationRequested()
                            }
                        }
                    }
                }

                // Quatre chiffres separes par des filets.
                Item {
                    Layout.alignment: root.heroWide ? (Qt.AlignRight | Qt.AlignBottom) : Qt.AlignLeft
                    Layout.fillWidth: !root.heroWide
                    implicitWidth: figuresRow.implicitWidth
                    implicitHeight: figuresRow.implicitHeight + (root.heroWide ? 0 : 12)

                    Rectangle {
                        visible: !root.heroWide
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        height: 1
                        color: Theme.line
                    }

                    Row {
                        id: figuresRow
                        y: root.heroWide ? 0 : 12
                        width: root.heroWide ? implicitWidth : parent.width

                        Repeater {
                            model: root.figureModel
                            delegate: Item {
                                id: fig
                                required property var modelData
                                required property int index
                                width: root.heroWide ? figure.implicitWidth + (index === 0 ? 0 : 22) + (index === 3 ? 0 : 22)
                                                     : figuresRow.width / 4
                                height: figure.implicitHeight

                                Rectangle {
                                    visible: fig.index > 0
                                    width: 1
                                    height: parent.height
                                    color: Theme.line
                                }
                                SerifFigure {
                                    id: figure
                                    x: fig.index === 0 ? 0 : (root.heroWide ? 22 : 18)
                                    width: Math.max(implicitWidth, 110)
                                    label: fig.modelData.label
                                    value: fig.modelData.value
                                    suffix: fig.modelData.suffix
                                    context: fig.modelData.context
                                    attention: fig.modelData.attention === true
                                    tooltip: fig.modelData.tip
                                    valueSize: root.heroWide && root.height >= 720 ? Theme.fontSizeFigure : Theme.fs(32)
                                    onClicked: root.openFigure(fig.modelData.key)
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: -4
                Layout.preferredHeight: 1
                color: Theme.line
            }

            // ---- Corps -------------------------------------------------------
            GridLayout {
                id: mainGrid
                Layout.fillWidth: true
                columns: root.mainWide ? 2 : 1
                columnSpacing: root.pageW > 1260 ? 28 : 24
                rowSpacing: 22

                // -- Feuille « Le reseau » -----------------------------------
                Rectangle {
                    id: sheet
                    Layout.row: 0
                    Layout.column: 0
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.mainWide
                        ? Math.max(384, Math.min(470, pageFlick.height - hero.height - 300))
                        : 420
                    color: Theme.surface0
                    border.width: 1
                    border.color: Theme.line
                    radius: Theme.radiusSheet

                    // Ombre portee tres discrete (papier pose sur la page).
                    Rectangle {
                        z: -1
                        anchors.fill: parent
                        anchors.topMargin: 6
                        anchors.bottomMargin: -6
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        radius: 12
                        color: Theme.shadowColor
                        opacity: 0.6
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 1
                        spacing: 0

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.leftMargin: 20
                            Layout.rightMargin: 20
                            Layout.topMargin: 15
                            spacing: 16

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 3
                                Text {
                                    text: qsTr("Le réseau")
                                    color: Theme.ink
                                    font.family: Theme.fontFamilySerif
                                    font.pixelSize: Theme.fontSizeSection
                                    font.weight: Theme.weightBold
                                    Accessible.role: Accessible.Heading
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: qsTr("Regroupés par état · disposition indicative, pas une topologie")
                                    color: Theme.ink3
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(12)
                                    elide: Text.ElideRight
                                }
                            }

                            Item {
                                Layout.alignment: Qt.AlignTop
                                implicitWidth: tabs.implicitWidth
                                implicitHeight: tabs.implicitHeight

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    height: 1
                                    color: Theme.line
                                }
                                Row {
                                    id: tabs
                                    spacing: 18
                                    ViewTab {
                                        text: qsTr("Hémicycle")
                                        current: root.networkView === "hemicycle"
                                        onClicked: root.networkView = "hemicycle"
                                    }
                                    ViewTab {
                                        text: qsTr("Registre")
                                        count: root.allPeersLive.length
                                        current: root.networkView === "registre"
                                        onClicked: root.networkView = "registre"
                                    }
                                }
                            }
                        }

                        Item {
                            id: sheetBody
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true

                            Hemicycle {
                                id: hemicycle
                                objectName: "hemicycle"
                                anchors.fill: parent
                                anchors.topMargin: 6
                                visible: root.networkView === "hemicycle" && root.allPeersLive.length > 0
                                peers: root.allPeersLive
                                selectedId: root.selectedId
                                hiddenStatuses: root.hiddenStatuses
                                localName: root.localMachineName
                                localState: root.localState
                                localLabel: root.serverStatusLabel
                                pendingTitle: root.pendingAuthorizations.length > 0 ? root.pendingAuthorizations[0].title : ""
                                pendingCount: root.pendingAuthorizations.length
                                onSeatActivated: function(peerId) { root.selectPeer(peerId) }
                                onDoorActivated: root.adminSectionRequested(1)
                            }

                            NetworkRegistry {
                                anchors.fill: parent
                                anchors.topMargin: 8
                                visible: root.networkView === "registre" && root.allPeersLive.length > 0
                                peers: root.allPeersLive
                                selectedId: root.selectedId
                                hiddenStatuses: root.hiddenStatuses
                                isAdmin: root.isAdmin
                                activityOf: function(p) { return root.activityText(p) }
                                trustOf: function(p) { return root.machineTrust(p.id, p.address) }
                                onPeerSelected: function(peerId) { root.selectPeer(peerId) }
                                onMessageRequested: function(peer) { root.openConversationWithPeer(peer) }
                                onFileRequested: function(peer) { root.fileTransferRequested(true, peer) }
                                onCallRequested: function(peer) { root.callPeer(peer) }
                            }

                            // Etat vide : aucun poste detecte.
                            Column {
                                visible: root.allPeersLive.length === 0
                                anchors.centerIn: parent
                                width: Math.min(parent.width - 48, 420)
                                spacing: 6

                                Item {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: 132
                                    height: 66
                                    Shape {
                                        anchors.fill: parent
                                        preferredRendererType: Shape.CurveRenderer
                                        ShapePath {
                                            fillColor: "transparent"
                                            strokeColor: Theme.lineStrong
                                            strokeWidth: 1.2
                                            PathAngleArc { centerX: 66; centerY: 64; radiusX: 60; radiusY: 60; startAngle: 180; sweepAngle: 180 }
                                        }
                                        ShapePath {
                                            fillColor: "transparent"
                                            strokeColor: Theme.lineStrong
                                            strokeWidth: 1.2
                                            PathAngleArc { centerX: 66; centerY: 64; radiusX: 36; radiusY: 36; startAngle: 180; sweepAngle: 180 }
                                        }
                                        ShapePath {
                                            id: sweepPath
                                            fillColor: "transparent"
                                            strokeColor: Theme.markTransfer
                                            strokeWidth: 1.6
                                            strokeStyle: ShapePath.DashLine
                                            dashPattern: [2.5, 3.5]
                                            startX: 66; startY: 64
                                            PathLine { x: 22; y: 26 }
                                        }
                                    }
                                    NumberAnimation {
                                        target: sweepPath
                                        property: "dashOffset"
                                        from: 0; to: -6
                                        duration: 1400
                                        loops: Animation.Infinite
                                        running: root.visible && root.allPeersLive.length === 0
                                    }
                                }
                                Text {
                                    width: parent.width
                                    horizontalAlignment: Text.AlignHCenter
                                    text: qsTr("L'hémicycle est encore vide.")
                                    color: Theme.ink
                                    font.family: Theme.fontFamilySerif
                                    font.pixelSize: Theme.fs(21)
                                }
                                Text {
                                    width: parent.width
                                    horizontalAlignment: Text.AlignHCenter
                                    text: qsTr("Les postes apparaîtront ici dès qu'ils seront détectés sur le réseau local. Vérifiez qu'ils sont allumés et que LocaLink y est ouvert.")
                                    color: Theme.ink3
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(13)
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }

                        // Legende : filtres d'etat + aide.
                        Rectangle {
                            visible: root.allPeersLive.length > 0
                            Layout.fillWidth: true
                            Layout.preferredHeight: 1
                            color: Theme.line
                        }
                        Flow {
                            visible: root.allPeersLive.length > 0
                            Layout.fillWidth: true
                            Layout.leftMargin: 20
                            Layout.rightMargin: 20
                            Layout.topMargin: 10
                            Layout.bottomMargin: 10
                            spacing: 18

                            Repeater {
                                model: [
                                    { key: "calling", label: qsTr("En appel") },
                                    { key: "transferring", label: qsTr("En transfert") },
                                    { key: "online", label: qsTr("En ligne") },
                                    { key: "busy", label: qsTr("Occupé") },
                                    { key: "away", label: qsTr("Absent") },
                                    { key: "offline", label: qsTr("Hors ligne") }
                                ]
                                delegate: LegendFilter {
                                    required property var modelData
                                    visible: count > 0
                                    kind: modelData.key
                                    text: modelData.label
                                    count: root.countStatus(modelData.key)
                                    shown: root.hiddenStatuses.indexOf(modelData.key) < 0
                                    onClicked: root.toggleStatus(modelData.key)
                                }
                            }

                            Row {
                                spacing: 8
                                height: 24
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root.networkView === "registre"
                                          ? qsTr("La sélection est commune aux deux vues")
                                          : (hemicycle.namesForAll
                                             ? qsTr("Survolez ou sélectionnez un siège")
                                             : qsTr("%1 postes : noms affichés pour l'activité et la sélection").arg(root.allPeersLive.length))
                                    color: Theme.ink3
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(11.5)
                                }
                                TextLink {
                                    visible: root.networkView === "hemicycle" && !hemicycle.namesForAll
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: qsTr("Parcourir le registre")
                                    fontSize: Theme.fs(11.5)
                                    onClicked: root.networkView = "registre"
                                }
                            }
                        }
                    }
                }

                // -- Colonne de lecture : poste selectionne + a traiter -------
                GridLayout {
                    id: side
                    Layout.row: root.mainWide ? 0 : 1
                    Layout.column: root.mainWide ? 1 : 0
                    Layout.rowSpan: root.mainWide ? 2 : 1
                    Layout.fillWidth: !root.mainWide
                    Layout.preferredWidth: root.mainWide ? root.sideWidth : -1
                    // Large : epouse la hauteur du reseau et des echanges sans
                    // l'imposer (« A traiter » defile a l'interieur).
                    Layout.fillHeight: root.mainWide
                    Layout.preferredHeight: root.mainWide ? 0 : -1
                    Layout.minimumHeight: 0
                    Layout.alignment: Qt.AlignTop
                    columns: root.mainWide || !root.lowerPaired ? 1 : 2
                    columnSpacing: 22
                    rowSpacing: 18

                    PeerFiche {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.alignment: Qt.AlignTop
                        peer: root.selectedPeer
                        anyPeer: root.allPeersLive.length > 0
                        isAdmin: root.isAdmin
                        addressText: {
                            const p = root.selectedPeer
                            if (!p || !p.address) return ""
                            const e = root.networkPeerEntry(p.id)
                            return e && e.port > 0 ? p.address + ":" + e.port : p.address
                        }
                        lastActivityText: {
                            const p = root.selectedPeer
                            if (!p) return ""
                            if (p.status === "offline") return qsTr("Hors ligne")
                            const e = root.networkPeerEntry(p.id)
                            return e && e.lastSeenMs > 0 ? root.relativeTime(new Date(e.lastSeenMs)) : ""
                        }
                        trustText: root.selectedPeer ? root.machineTrust(root.selectedPeer.id, root.selectedPeer.address) : ""
                        conversation: root.conversationFor(root.selectedPeer)
                        conversationTime: conversation ? root.timeOf(conversation.timestamp) : ""
                        onMessageRequested: root.openConversationWithPeer(root.selectedPeer)
                        onSendFileRequested: root.fileTransferRequested(true, root.selectedPeer)
                        onCallRequested: root.callPeer(root.selectedPeer)
                        onFollowTransferRequested: root.fileTransferRequested(false, null)
                        onOpenConversationRequested: function(conversationId) {
                            if (conversationId > 0) root.conversationRequested(conversationId)
                            else root.chatRequested()
                        }
                        onManageRequested: root.adminSectionRequested(1)
                    }

                    InterventionList {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.fillHeight: root.mainWide
                        Layout.minimumHeight: 0
                        Layout.maximumHeight: root.mainWide ? -1 : 360
                        Layout.alignment: Qt.AlignTop
                        items: root.interventions
                        isAdmin: root.isAdmin
                        onActivated: function(item) { root.runIntervention(item) }
                    }
                }

                // -- Echanges + journal (administrateur) ou discussions --------
                GridLayout {
                    id: lower
                    Layout.row: root.mainWide ? 1 : 2
                    Layout.column: 0
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    columns: root.lowerPaired ? 2 : 1
                    columnSpacing: root.pageW > 1260 ? 28 : 22
                    rowSpacing: 18

                    // Echanges : lignes a deux niveaux (fichier / correspondant).
                    ColumnLayout {
                        id: ledger
                        Layout.fillWidth: true
                        Layout.preferredWidth: 5
                        Layout.alignment: Qt.AlignTop
                        spacing: 0
                        readonly property bool compactRows: ledger.width < 470

                        SectionHeader {
                            Layout.fillWidth: true
                            title: qsTr("Échanges")
                            linkText: qsTr("Tous les transferts")
                            onLinkActivated: root.fileTransferRequested(false, null)
                        }
                        Text {
                            visible: root.transferRowItems.length === 0
                            Layout.fillWidth: true
                            Layout.topMargin: 12
                            text: qsTr("Aucun échange pour le moment.")
                            color: Theme.ink
                            font.family: Theme.fontFamilySerif
                            font.pixelSize: Theme.fs(17)
                        }
                        Text {
                            visible: root.transferRowItems.length === 0
                            Layout.fillWidth: true
                            Layout.topMargin: 2
                            text: qsTr("Les envois et réceptions de fichiers de ce poste s'inscriront ici.")
                            color: Theme.ink3
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(12.5)
                            wrapMode: Text.WordWrap
                        }

                        Repeater {
                            model: root.transferRowItems

                            delegate: Item {
                                id: xr
                                required property var modelData
                                required property int index
                                readonly property bool running: modelData.state === "in_progress"
                                readonly property color tone: modelData.state === "completed" ? Theme.successColor
                                                            : modelData.state === "failed" ? Theme.dangerColor
                                                            : modelData.state === "cancelled" ? Theme.nodeOfflineLine
                                                            : Theme.markTransfer
                                Layout.fillWidth: true
                                implicitHeight: 46

                                Rectangle {
                                    visible: xr.index > 0
                                    width: parent.width
                                    height: 1
                                    color: Theme.line
                                }
                                HoverHandler { id: xrHover; enabled: xr.running; cursorShape: Qt.PointingHandCursor }
                                TapHandler { enabled: xr.running; onTapped: root.fileTransferRequested(false, null) }

                                RowLayout {
                                    anchors.fill: parent
                                    spacing: 14

                                    // Sens : fleche dans un cercle.
                                    Rectangle {
                                        Layout.preferredWidth: 20
                                        Layout.preferredHeight: 20
                                        radius: 10
                                        color: "transparent"
                                        border.width: 1
                                        border.color: Theme.lineStrong
                                        LineIcon {
                                            anchors.centerIn: parent
                                            path: xr.modelData.isIncoming ? "M12 4.5v15 M18.5 13 12 19.5 5.5 13"
                                                                          : "M12 19.5v-15 M5.5 11 12 4.5 18.5 11"
                                            size: 11
                                            strokeWidth: 2.2
                                            color: Theme.ink2
                                        }
                                        Accessible.name: xr.modelData.isIncoming ? qsTr("Réception") : qsTr("Envoi")
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 1
                                        Text {
                                            Layout.fillWidth: true
                                            text: xr.modelData.fileName
                                            color: Theme.ink
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fs(13.5)
                                            font.weight: Theme.weightMedium
                                            font.underline: xrHover.hovered
                                            elide: Text.ElideMiddle
                                        }
                                        Row {
                                            Layout.fillWidth: true
                                            spacing: 4
                                            Text {
                                                text: xr.modelData.isIncoming ? qsTr("de") : qsTr("vers")
                                                color: Theme.ink3
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.fs(12)
                                            }
                                            Text {
                                                id: peerLink
                                                width: Math.min(implicitWidth, parent.width - 30)
                                                text: xr.modelData.peerName || xr.modelData.address
                                                color: peerHover.hovered ? Theme.ink : Theme.ink2
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.fs(12)
                                                font.underline: peerHover.hovered
                                                elide: Text.ElideRight
                                                HoverHandler { id: peerHover; cursorShape: Qt.PointingHandCursor }
                                                TapHandler { onTapped: root.selectPeerByEndpoint(xr.modelData.address, xr.modelData.peerName) }
                                            }
                                        }
                                    }
                                    // Avancement : filet de 2 px + pourcentage (ou taille).
                                    RowLayout {
                                        visible: !ledger.compactRows
                                        Layout.preferredWidth: 116
                                        spacing: 8
                                        Rectangle {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 2
                                            color: Theme.line
                                            Rectangle {
                                                y: -1
                                                height: 4
                                                width: parent.width * (xr.modelData.state === "cancelled" ? 0 : xr.modelData.progress)
                                                color: xr.tone
                                            }
                                        }
                                        Text {
                                            Layout.minimumWidth: 36
                                            horizontalAlignment: Text.AlignRight
                                            text: xr.modelData.state === "completed" ? Fmt.formatBytes(xr.modelData.total)
                                                                                     : Math.round(xr.modelData.progress * 100) + " %"
                                            color: Theme.ink2
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fs(12)
                                            font.features: ({ "tnum": 1 })
                                        }
                                    }
                                    // Etat (mot + couleur) et heure / volume.
                                    Column {
                                        Layout.preferredWidth: 104
                                        Text {
                                            width: parent.width
                                            horizontalAlignment: Text.AlignRight
                                            text: xr.running ? qsTr("En cours") : xr.modelData.state === "completed" ? qsTr("Terminé")
                                                  : xr.modelData.state === "cancelled" ? qsTr("Annulé") : qsTr("Échec")
                                            color: xr.running ? Theme.navActiveInk : xr.modelData.state === "completed" ? Theme.successInk
                                                   : xr.modelData.state === "cancelled" ? Theme.ink3 : Theme.dangerInk
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fs(12)
                                            font.weight: Theme.weightSemibold
                                        }
                                        Text {
                                            width: parent.width
                                            horizontalAlignment: Text.AlignRight
                                            text: xr.running ? (xr.modelData.total > 0 ? qsTr("sur %1").arg(Fmt.formatBytes(xr.modelData.total)) : "")
                                                             : root.relativeTime(xr.modelData.timestamp)
                                            color: Theme.ink3
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fs(12)
                                            font.features: ({ "tnum": 1 })
                                            elide: Text.ElideLeft
                                        }
                                    }
                                }
                            }
                        }
                        Text {
                            readonly property int others: Math.max(0, root.liveTransfers.length - root.transferRowItems.length)
                            visible: others > 0
                            Layout.topMargin: 6
                            text: others > 1 ? qsTr("+ %1 autres échanges dans Transferts").arg(others)
                                             : qsTr("+ 1 autre échange dans Transferts")
                            color: Theme.ink3
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(12)
                        }
                    }

                    // Journal (administrateur) ou discussions (utilisateur).
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 4
                        Layout.alignment: Qt.AlignTop
                        spacing: 0

                        SectionHeader {
                            Layout.fillWidth: true
                            title: root.isAdmin ? qsTr("Journal") : qsTr("Discussions")
                            linkText: root.isAdmin ? qsTr("Journal d'audit") : qsTr("Toutes les discussions")
                            onLinkActivated: root.isAdmin ? root.adminSectionRequested(0) : root.chatRequested()
                        }
                        Text {
                            visible: (root.isAdmin ? root.activityItems.length : root.allConversations.length) === 0
                            Layout.fillWidth: true
                            Layout.topMargin: 12
                            text: root.isAdmin ? qsTr("Journal vierge.") : qsTr("Aucune conversation.")
                            color: Theme.ink
                            font.family: Theme.fontFamilySerif
                            font.pixelSize: Theme.fs(17)
                        }
                        Text {
                            visible: (root.isAdmin ? root.activityItems.length : root.allConversations.length) === 0
                            Layout.fillWidth: true
                            Layout.topMargin: 2
                            text: root.isAdmin ? qsTr("Connexions, transferts et refus y seront consignés.")
                                               : qsTr("Vos échanges avec les collègues du réseau apparaîtront ici.")
                            color: Theme.ink3
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(12.5)
                            wrapMode: Text.WordWrap
                        }

                        Repeater {
                            model: root.isAdmin ? root.activityItems.slice(0, 5)
                                                : root.allConversations.slice().sort(function(a, b) {
                                                      return (b.unreadCount || 0) - (a.unreadCount || 0)
                                                  }).slice(0, 5)

                            delegate: Item {
                                id: ev
                                required property var modelData
                                required property int index
                                readonly property var look: root.isAdmin ? root.eventLook(modelData.event)
                                                                         : { glyph: (modelData.unreadCount || 0) > 0 ? "unread" : "read",
                                                                             result: "", ink: Theme.ink3 }
                                Layout.fillWidth: true
                                implicitHeight: 34

                                Rectangle {
                                    visible: ev.index > 0
                                    width: parent.width
                                    height: 1
                                    color: Theme.line
                                }
                                HoverHandler { id: evHover; enabled: !root.isAdmin; cursorShape: Qt.PointingHandCursor }
                                TapHandler {
                                    enabled: !root.isAdmin
                                    onTapped: if (ev.modelData.conversationId > 0) root.conversationRequested(ev.modelData.conversationId)
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    spacing: 10
                                    Text {
                                        Layout.preferredWidth: 40
                                        text: root.timeOf(root.isAdmin ? ev.modelData.timestamp : ev.modelData.timestamp)
                                        color: Theme.ink3
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fs(12)
                                        font.features: ({ "tnum": 1 })
                                    }
                                    StateGlyph { kind: ev.look.glyph; size: 10 }
                                    Text {
                                        Layout.fillWidth: true
                                        text: "<b>" + root.esc(root.isAdmin ? (ev.modelData.actor || qsTr("Système")) : ev.modelData.name)
                                              + "</b>&nbsp;&nbsp;<font color=\"" + Theme.ink2 + "\">"
                                              + root.esc(root.isAdmin ? ev.modelData.message : (ev.modelData.lastMessage || "")) + "</font>"
                                        textFormat: Text.StyledText
                                        color: Theme.ink
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fs(13)
                                        font.underline: evHover.hovered
                                        elide: Text.ElideRight
                                    }
                                    CapsLabel {
                                        visible: root.isAdmin && ev.look.result.length > 0
                                        text: ev.look.result
                                        color: ev.look.ink
                                        font.pixelSize: Theme.fs(10)
                                        font.weight: Theme.weightBold
                                    }
                                    Text {
                                        visible: !root.isAdmin && (ev.modelData.unreadCount || 0) > 0
                                        text: ev.modelData.unreadCount || ""
                                        color: Theme.navActiveInk
                                        font.family: Theme.fontFamilySerif
                                        font.pixelSize: Theme.fs(13)
                                        font.weight: Theme.weightBold
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
