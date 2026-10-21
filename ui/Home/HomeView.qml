import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import "../Components"
import "../Dashboard"
import "../Dashboard/transferFormat.js" as Fmt

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
        // Etat initial de la carte reseau : la vue Liste prend le relais
        // sous 900 px (onListFallbackChanged ne couvre que les changements).
        networkWorkspace.viewMode = root.listFallback ? "list" : "map"
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

    onListFallbackChanged: networkWorkspace.viewMode = root.listFallback ? "list" : "map"

    // ---- Donnees du role "utilisateur" -----------------------------------
    property int unreadTotal: 0
    property var recentConversations: []
    property int folderCount: 0
    property int folderConflictCount: 0

    function refreshConversations() {
        if (typeof messagingContext === "undefined" || !messagingContext) {
            root.unreadTotal = 0
            root.recentConversations = []
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
            networkWorkspace.viewMode = "map"
            networkWorkspace.selectedId = item.peerId
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

    // ---- Selection de la carte ------------------------------------------
    property var hiddenStatuses: []
    property bool selectionInitialized: false

    readonly property var selectedPeer: networkWorkspace.selectedId.length > 0
                                        ? networkWorkspace.peerById(networkWorkspace.selectedId) : null

    // Premiere selection automatique (poste en activite de preference),
    // puis nettoyage si le poste selectionne disparait.
    function ensureSelection() {
        const present = networkWorkspace.presentPeers
        if (networkWorkspace.selectedId.length > 0) {
            if (!networkWorkspace.peerById(networkWorkspace.selectedId))
                networkWorkspace.selectedId = ""
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
        networkWorkspace.selectedId = pick.id
        root.selectionInitialized = true
    }

    Connections {
        target: networkWorkspace
        function onPresentPeersChanged() { root.ensureSelection() }
        function onOfflinePeersPositionedChanged() { root.ensureSelection() }
    }

    function toggleStatus(key) {
        const list = root.hiddenStatuses.slice()
        const i = list.indexOf(key)
        if (i >= 0) list.splice(i, 1)
        else list.push(key)
        root.hiddenStatuses = list
    }

    function countStatus(key) {
        if (key === "offline")
            return networkWorkspace.offlinePeersPositioned.length
        return networkWorkspace.presentPeers.filter(function(p) { return p.status === key }).length
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

    // Puce de filtre d'etat (carte reseau).
    component FilterChip: AbstractButton {
        id: chip
        property string label: ""
        property int count: 0
        property color dotColor: Theme.successColor
        property bool hollow: false
        property bool active: true

        implicitHeight: 26
        implicitWidth: chipRow.implicitWidth + 20
        hoverEnabled: true
        focusPolicy: Qt.TabFocus
        checkable: false
        opacity: chip.active ? 1 : 0.45
        Accessible.role: Accessible.CheckBox
        Accessible.checked: chip.active
        Accessible.name: qsTr("%1 : %2 poste(s), %3").arg(chip.label).arg(chip.count)
                            .arg(chip.active ? qsTr("affichés") : qsTr("masqués"))
        ToolTip.visible: chip.hovered
        ToolTip.delay: 600
        ToolTip.text: chip.active ? qsTr("Masquer les postes « %1 »").arg(chip.label)
                                  : qsTr("Afficher les postes « %1 »").arg(chip.label)

        HoverHandler { cursorShape: Qt.PointingHandCursor }

        background: Rectangle {
            radius: height / 2
            color: chip.hovered ? Theme.hover : Theme.surface0
            border.width: 1
            border.color: Theme.line

            Rectangle {
                anchors.fill: parent
                anchors.margins: -3
                radius: height / 2
                color: "transparent"
                border.width: 2
                border.color: Theme.focusRing
                visible: chip.visualFocus
            }
        }
        contentItem: Item {
            Row {
                id: chipRow
                anchors.centerIn: parent
                spacing: 6
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 7; height: 7; radius: 3.5
                    color: chip.hollow ? "transparent" : chip.dotColor
                    border.width: chip.hollow ? 1.5 : 0
                    border.color: Theme.nodeOfflineLine
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: chip.label
                    color: Theme.ink
                    font.pixelSize: Theme.fs(12)
                    font.weight: Theme.weightSemibold
                    font.family: Theme.fontFamily
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: chip.count
                    color: Theme.ink3
                    font.pixelSize: Theme.fs(12)
                    font.weight: Theme.weightMedium
                    font.family: Theme.fontFamily
                }
            }
        }
    }

    // En-tete de panneau : titre, compteur, lien.
    component PanelHeader: RowLayout {
        id: ph
        property string title: ""
        property int count: -1
        property string countTone: "neutral"
        property string linkText: ""
        signal linkClicked()

        Layout.fillWidth: true
        Layout.leftMargin: 16
        Layout.rightMargin: 10
        Layout.topMargin: 12
        Layout.bottomMargin: 6
        Layout.minimumHeight: 30
        spacing: 8

        Text {
            text: ph.title
            color: Theme.ink
            font.pixelSize: Theme.fs(14)
            font.weight: Theme.weightSemibold
            font.family: Theme.fontFamily
            Accessible.role: Accessible.Heading
        }
        StatusBadge {
            visible: ph.count >= 0
            text: ph.count > 99 ? "99+" : ph.count
            tone: ph.countTone
            showDot: false
            compact: true
        }
        Item { Layout.fillWidth: true }
        AppButton {
            visible: ph.linkText.length > 0
            text: ph.linkText
            variant: "ghost"
            size: "small"
            onClicked: ph.linkClicked()
        }
    }

    // ======================================================================
    Flickable {
        id: pageFlick
        objectName: "pageFlick"
        anchors.fill: parent
        clip: true
        contentWidth: width
        // Deduite de la seule hauteur implicite de la colonne, et non de sa
        // hauteur (elle-meme deduite de contentHeight) : formulation sans
        // dependance circulaire.
        contentHeight: Math.max(height, pageColumn.y + pageColumn.implicitHeight + Theme.pagePadding)
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        ColumnLayout {
            id: pageColumn
            x: Theme.pagePadding
            y: Theme.compact ? 18 : 22
            width: pageFlick.width - 2 * Theme.pagePadding
            // Au moins la hauteur visible (les panneaux s'etirent pour la remplir),
            // davantage si le contenu l'exige : la page defile alors.
            height: Math.max(implicitHeight, pageFlick.height - y - Theme.pagePadding)
            spacing: Theme.spacingGutter

            // ---- En-tete de supervision ----------------------------------
            // Indicateurs a droite du titre tant qu'ils tiennent (le sous-titre
            // passe alors a la ligne), dessous sinon.
            GridLayout {
                id: headerGrid
                readonly property bool sideBySide: pageColumn.width >= 900
                Layout.fillWidth: true
                columns: sideBySide ? 2 : 1
                columnSpacing: 16
                rowSpacing: 12

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 3
                    Text {
                        text: qsTr("Supervision du réseau")
                        color: Theme.ink
                        font.pixelSize: Theme.fs(20)
                        font.weight: Theme.weightBold
                        font.family: Theme.fontFamily
                        Accessible.role: Accessible.Heading
                    }
                    Text {
                        Layout.fillWidth: true
                        text: root.sessionContext
                        color: Theme.ink2
                        font.pixelSize: Theme.fs(12.5)
                        font.family: Theme.fontFamily
                        wrapMode: Text.WordWrap
                    }
                }

                Flow {
                    Layout.alignment: headerGrid.sideBySide ? (Qt.AlignRight | Qt.AlignVCenter) : Qt.AlignLeft
                    Layout.preferredWidth: headerGrid.sideBySide ? implicitWidth : pageColumn.width
                    Layout.fillWidth: !headerGrid.sideBySide
                    spacing: 8

                    StatPill {
                        glyph: ""
                        tone: root.peersCount > 0 ? "success" : "neutral"
                        value: root.isAdmin && root.authorizedMachineCount > 0
                               ? root.peersCount + "/" + root.authorizedMachineCount : String(root.peersCount)
                        label: qsTr("postes en ligne")
                        tooltip: qsTr("Ouvrir la liste des postes")
                        onClicked: root.usersRequested()
                    }
                    StatPill {
                        glyph: ""
                        tone: root.totalActiveTransferCount > 0 ? "accent" : "neutral"
                        value: String(root.totalActiveTransferCount)
                        label: root.totalActiveTransferCount > 1 ? qsTr("transferts actifs") : qsTr("transfert actif")
                        tooltip: qsTr("Ouvrir les transferts")
                        onClicked: root.fileTransferRequested(false, null)
                    }
                    StatPill {
                        glyph: root.isAdmin ? "" : ""
                        tone: root.isAdmin ? (root.pendingRequestCount > 0 ? "warning" : "neutral")
                                           : (root.unreadTotal > 0 ? "accent" : "neutral")
                        value: String(root.isAdmin ? root.pendingRequestCount : root.unreadTotal)
                        // "demandes a traiter" (decisions attendues : autorisations et refus)
                        // et non le total du panneau "Interventions requises", qui ajoute
                        // les transferts en echec et les postes hors ligne a surveiller.
                        label: root.isAdmin ? (root.pendingRequestCount > 1 ? qsTr("demandes à traiter")
                                                                           : qsTr("demande à traiter"))
                                            : (root.unreadTotal > 1 ? qsTr("messages non lus") : qsTr("message non lu"))
                        tooltip: root.isAdmin ? qsTr("Autorisations en attente et connexions refusées · ouvrir les machines autorisées")
                                              : qsTr("Ouvrir les discussions")
                        onClicked: root.isAdmin ? root.adminSectionRequested(1) : root.chatRequested()
                    }
                    StatPill {
                        glyph: root.isAdmin ? "" : ""
                        tone: !root.isAdmin && root.folderConflictCount > 0 ? "warning" : "neutral"
                        value: String(root.isAdmin ? root.auditEventCount : root.folderCount)
                        label: root.isAdmin ? qsTr("événements")
                                            : (root.folderCount > 1 ? qsTr("dossiers partagés") : qsTr("dossier partagé"))
                        tooltip: root.isAdmin ? qsTr("Ouvrir le journal d'audit") : qsTr("Ouvrir les dossiers partagés")
                        onClicked: root.isAdmin ? root.adminSectionRequested(0) : root.sharedFoldersRequested()
                    }
                }
            }

            // ---- Corps ----------------------------------------------------
            GridLayout {
                id: mainGrid
                Layout.fillWidth: true
                Layout.fillHeight: root.wideLayout
                columns: root.wideLayout ? 2 : 1
                columnSpacing: 16
                rowSpacing: 16

                // -- Carte reseau ------------------------------------------
                Rectangle {
                    id: mapCard
                    Layout.fillWidth: true
                    Layout.fillHeight: root.wideLayout
                    // Au moins 360 px de dessin sous l'en-tete (quelle que soit sa hauteur :
                    // filtres sur deux lignes, texte agrandi) : en dessous, les postes
                    // hors ligne n'ont plus de place libre autour du poste central.
                    // Hauteur reellement mise en page de l'en-tete (et non sa hauteur
                    // implicite, qui depend de la largeur laissee au Flow des filtres) :
                    // la zone de dessin conserve 360 px dans tous les cas.
                    Layout.minimumHeight: mapHeader.height + 24 + 360
                    Layout.preferredHeight: root.wideLayout ? 420 : mapHeader.height + 24 + 380
                    radius: Theme.radiusCard
                    color: Theme.surface0
                    border.width: 1
                    border.color: Theme.line

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 1
                        spacing: 0

                        // Titre, filtres et Carte/Liste sur une ligne ; carte etroite :
                        // filtres sur une seconde ligne pleine largeur (maquette).
                        GridLayout {
                            id: mapHeader
                            readonly property bool stackFilters: mapCard.width < 840
                            Layout.fillWidth: true
                            Layout.leftMargin: 15
                            Layout.rightMargin: 15
                            Layout.topMargin: 12
                            Layout.bottomMargin: 12
                            columns: 3
                            columnSpacing: 12
                            rowSpacing: 10

                            Text {
                                Layout.row: 0
                                Layout.column: 0
                                Layout.alignment: Qt.AlignTop
                                Layout.topMargin: 4
                                text: qsTr("Réseau local")
                                color: Theme.ink
                                font.pixelSize: Theme.fs(14)
                                font.weight: Theme.weightSemibold
                                font.family: Theme.fontFamily
                                Accessible.role: Accessible.Heading
                            }

                            Flow {
                                Layout.row: mapHeader.stackFilters ? 1 : 0
                                Layout.column: mapHeader.stackFilters ? 0 : 1
                                Layout.columnSpan: mapHeader.stackFilters ? 3 : 1
                                Layout.fillWidth: true
                                spacing: 6
                                visible: networkWorkspace.viewMode === "map"
                                Accessible.name: qsTr("Filtrer les postes par état")

                                Repeater {
                                    model: [
                                        { key: "online", label: qsTr("En ligne"), color: Theme.successColor },
                                        { key: "away", label: qsTr("Absent"), color: Theme.markAway },
                                        { key: "busy", label: qsTr("Occupé"), color: Theme.markAway, optional: true },
                                        { key: "transferring", label: qsTr("En transfert"), color: Theme.markTransfer },
                                        { key: "calling", label: qsTr("En appel"), color: Theme.callColor },
                                        { key: "offline", label: qsTr("Hors ligne"), color: Theme.nodeOfflineLine, hollow: true }
                                    ]
                                    delegate: FilterChip {
                                        required property var modelData
                                        visible: !modelData.optional || count > 0
                                        label: modelData.label
                                        dotColor: modelData.color
                                        hollow: modelData.hollow === true
                                        count: root.countStatus(modelData.key)
                                        active: root.hiddenStatuses.indexOf(modelData.key) < 0
                                        onClicked: root.toggleStatus(modelData.key)
                                    }
                                }
                            }
                            Item {
                                Layout.row: 0
                                Layout.column: 1
                                Layout.fillWidth: true
                                visible: mapHeader.stackFilters || networkWorkspace.viewMode !== "map"
                            }

                            AppSegmentedControl {
                                Layout.row: 0
                                Layout.column: 2
                                Layout.alignment: Qt.AlignTop
                                stretch: false
                                small: true
                                model: [ { label: qsTr("Carte"), glyph: "" },
                                         { label: qsTr("Liste"), glyph: "" } ]
                                currentIndex: networkWorkspace.viewMode === "list" ? 1 : 0
                                onActivated: function(index) { networkWorkspace.viewMode = index === 1 ? "list" : "map" }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 1
                            color: Theme.line
                        }

                        Item {
                            id: mapInner
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true

                            ScrollView {
                                id: networkScrollView
                                anchors.fill: parent
                                clip: true
                                contentWidth: Math.max(availableWidth, 600)
                                ScrollBar.vertical.policy: ScrollBar.AlwaysOff

                                NetworkWorkspace {
                                    id: networkWorkspace
                                    objectName: "networkWorkspace"
                                    width: Math.max(networkScrollView.availableWidth, 600)
                                    height: mapInner.height
                                    showChrome: false
                                    showLegend: false
                                    inlineDetails: false
                                    offlineSelectable: true
                                    preferTopOffline: true
                                    bottomReserve: 34
                                    maxScale: 1.2
                                    mapBackground: Theme.darkMode ? Theme.bg : Theme.surface1
                                    hiddenStatuses: root.hiddenStatuses
                                    leftRadius: 0
                                    rightRadius: 0
                                    cornerBottomLeftRadius: Theme.radiusCard - 1
                                    cornerBottomRightRadius: Theme.radiusCard - 1

                                    peers: root.networkPeers
                                    offlinePeers: root.networkOfflinePeers
                                    localPeerName: (typeof settingsModel !== "undefined" && settingsModel
                                                    && settingsModel.machineName.length > 0)
                                                   ? settingsModel.machineName : qsTr("Ce poste")
                                    localPeerStatusLabel: root.serverStatusLabel
                                    activeTransfers: (typeof transferContext !== "undefined" && transferContext)
                                                     ? transferContext.activeTransfers : []
                                    activeCalls: root.networkActiveCalls
                                    demoMode: root.demoMode

                                    onPeerClicked: function(peer) {
                                        if (peer && peer.id)
                                            networkWorkspace.selectedId = peer.id
                                    }
                                    onSendFileRequested: function(peer) { root.fileTransferRequested(true, peer) }
                                    onCallRequested: function(peer) { root.callPeer(peer) }
                                    onMessageRequested: function(peer) { root.openConversationWithPeer(peer) }
                                }
                            }

                            RowLayout {
                                visible: networkWorkspace.viewMode === "map"
                                anchors.left: parent.left
                                anchors.bottom: parent.bottom
                                anchors.leftMargin: 14
                                anchors.bottomMargin: 12
                                spacing: 6
                                FaIcon { glyph: ""; color: Theme.ink3; font.pixelSize: Theme.fs(11) }
                                Text {
                                    text: networkWorkspace.presentPeers.length + networkWorkspace.offlinePeersPositioned.length === 0
                                          ? qsTr("Aucun autre poste détecté pour l'instant · la découverte automatique est en cours")
                                          : qsTr("Cliquez sur un poste pour afficher ses détails · disposition indicative, pas une topologie")
                                    color: Theme.ink3
                                    font.pixelSize: Theme.fs(11.5)
                                    font.family: Theme.fontFamily
                                }
                            }
                        }
                    }
                }

                // -- Poste selectionne + interventions ---------------------
                GridLayout {
                    id: inspector
                    // Placement naturel, sans Layout.row/column explicites :
                    // large = carte | inspecteur sur deux rangees, puis les panneaux
                    // du bas ; etroit = carte, inspecteur, panneaux du bas.
                    Layout.rowSpan: root.wideLayout ? 2 : 1
                    Layout.fillWidth: !root.wideLayout
                    Layout.preferredWidth: root.wideLayout ? 340 : -1
                    Layout.fillHeight: true
                    columns: root.wideLayout ? 1 : 2
                    columnSpacing: 16
                    rowSpacing: 16

                    SelectedPeerPanel {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.alignment: Qt.AlignTop
                        peer: root.selectedPeer
                        userName: {
                            const p = root.selectedPeer
                            if (!p) return ""
                            return (p.userUuid && root.userNameByUuid[p.userUuid]) || p.userName || ""
                        }
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
                        callText: root.selectedPeer && root.selectedPeer.status === "calling"
                                  ? (typeof callContext !== "undefined" && callContext && callContext.callState === "connected"
                                     ? qsTr("Appel en cours") : qsTr("Appel en cours d'établissement"))
                                  : ""
                        onMessageRequested: root.openConversationWithPeer(root.selectedPeer)
                        onSendFileRequested: root.fileTransferRequested(true, root.selectedPeer)
                        onCallRequested: root.callPeer(root.selectedPeer)
                    }

                    Rectangle {
                        id: interventionsCard
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.fillHeight: root.wideLayout
                        Layout.alignment: Qt.AlignTop
                        Layout.minimumHeight: 160
                        Layout.preferredHeight: root.wideLayout ? -1 : interventionsColumn.implicitHeight
                        radius: Theme.radiusCard
                        color: Theme.surface0
                        border.width: 1
                        border.color: Theme.line
                        clip: true

                        ColumnLayout {
                            id: interventionsColumn
                            anchors.fill: parent
                            spacing: 0

                            PanelHeader {
                                title: root.isAdmin ? qsTr("Interventions requises") : qsTr("À surveiller")
                                count: root.interventions.length
                                countTone: root.interventions.length > 0 ? "warning" : "neutral"
                            }

                            EmptyState {
                                visible: root.interventions.length === 0
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                compact: true
                                iconName: "check"
                                tone: "success"
                                title: qsTr("Aucune intervention requise")
                                description: root.isAdmin
                                             ? qsTr("Les demandes d'autorisation, refus de connexion et échecs apparaîtront ici.")
                                             : qsTr("Les transferts en échec et conflits de dossiers apparaîtront ici.")
                            }

                            ListView {
                                visible: root.interventions.length > 0
                                Layout.fillWidth: true
                                Layout.fillHeight: root.wideLayout
                                Layout.preferredHeight: root.wideLayout ? -1 : contentHeight
                                Layout.leftMargin: 16
                                Layout.rightMargin: 16
                                Layout.bottomMargin: 8
                                clip: true
                                interactive: contentHeight > height
                                boundsBehavior: Flickable.StopAtBounds
                                model: root.interventions
                                delegate: SupervisionRow {
                                    required property var modelData
                                    required property int index
                                    width: ListView.view.width
                                    showDivider: index > 0
                                    glyph: modelData.glyph
                                    tone: modelData.tone
                                    title: modelData.title
                                    meta: modelData.meta
                                    actionText: modelData.action
                                    actionTooltip: modelData.tip
                                    onActionTriggered: root.runIntervention(modelData)
                                }
                            }
                        }
                    }
                }

                // -- Echanges + evenements ---------------------------------
                GridLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 208
                    Layout.minimumHeight: 208
                    Layout.maximumHeight: 208
                    columns: 2
                    columnSpacing: 16

                    // Echanges en cours
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredWidth: 1
                        radius: Theme.radiusCard
                        color: Theme.surface0
                        border.width: 1
                        border.color: Theme.line
                        clip: true

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 0
                            PanelHeader {
                                title: qsTr("Échanges en cours")
                                count: root.totalActiveTransferCount
                                countTone: root.totalActiveTransferCount > 0 ? "accent" : "neutral"
                                linkText: qsTr("Transferts")
                                onLinkClicked: root.fileTransferRequested(false, null)
                            }
                            EmptyState {
                                visible: root.runningTransferRows.length === 0
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                compact: true
                                iconName: "transfer"
                                title: qsTr("Aucun échange en cours")
                                description: qsTr("Les envois et réceptions de fichiers s'afficheront ici.")
                            }
                            ListView {
                                visible: root.runningTransferRows.length > 0
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.leftMargin: 16
                                Layout.rightMargin: 16
                                Layout.bottomMargin: 6
                                clip: true
                                interactive: contentHeight > height
                                boundsBehavior: Flickable.StopAtBounds
                                model: root.runningTransferRows
                                delegate: SupervisionRow {
                                    required property var modelData
                                    required property int index
                                    readonly property var vis: root.transferVisual(modelData)
                                    width: ListView.view.width
                                    showDivider: index > 0
                                    glyph: ""
                                    tone: vis.tone
                                    title: modelData.fileName
                                    metaGlyph: modelData.isIncoming ? "" : ""
                                    meta: (modelData.isIncoming ? qsTr("Réception de %1") : qsTr("Envoi vers %1"))
                                              .arg(modelData.peerName || modelData.address)
                                          + (modelData.total > 0
                                             ? " · " + (modelData.state === "in_progress"
                                                        ? Fmt.formatBytesPrecise(modelData.transferred) + " / " + Fmt.formatBytesPrecise(modelData.total)
                                                        : Fmt.formatBytes(modelData.total))
                                             : "")
                                    progress: modelData.state === "in_progress" ? modelData.progress : -1
                                    badgeText: vis.badge
                                    badgeTone: vis.badgeTone
                                    timeText: vis.time
                                }
                            }
                        }
                    }

                    // Evenements recents (admin) / Appels recents (utilisateur)
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredWidth: 1
                        radius: Theme.radiusCard
                        color: Theme.surface0
                        border.width: 1
                        border.color: Theme.line
                        clip: true

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 0
                            PanelHeader {
                                title: root.isAdmin ? qsTr("Événements récents") : qsTr("Appels récents")
                                linkText: root.isAdmin ? qsTr("Journal") : qsTr("Appels")
                                onLinkClicked: root.isAdmin ? root.adminSectionRequested(0) : root.callRequested()
                            }
                            EmptyState {
                                visible: (root.isAdmin ? root.activityItems.length : root.recentCalls.length) === 0
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                compact: true
                                iconName: root.isAdmin ? "log" : "call"
                                title: root.isAdmin ? qsTr("Aucun événement récent") : qsTr("Aucun appel récent")
                                description: root.isAdmin ? qsTr("Les connexions, transferts et refus seront journalisés ici.")
                                                          : qsTr("Vos appels émis et reçus apparaîtront ici.")
                            }
                            ListView {
                                visible: root.isAdmin && root.activityItems.length > 0
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.leftMargin: 16
                                Layout.rightMargin: 16
                                Layout.bottomMargin: 6
                                clip: true
                                interactive: contentHeight > height
                                boundsBehavior: Flickable.StopAtBounds
                                model: root.isAdmin ? root.activityItems : []
                                delegate: SupervisionRow {
                                    required property var modelData
                                    required property int index
                                    readonly property var vis: root.eventVisual(modelData.event)
                                    width: ListView.view.width
                                    showDivider: index > 0
                                    glyph: vis.glyph
                                    tone: vis.tone
                                    title: modelData.actor || qsTr("Système")
                                    meta: modelData.message
                                    timeText: root.timeOf(modelData.timestamp)
                                }
                            }
                            ListView {
                                visible: !root.isAdmin && root.recentCalls.length > 0
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.leftMargin: 16
                                Layout.rightMargin: 16
                                Layout.bottomMargin: 6
                                clip: true
                                interactive: contentHeight > height
                                boundsBehavior: Flickable.StopAtBounds
                                model: root.isAdmin ? [] : root.recentCalls
                                delegate: SupervisionRow {
                                    required property var modelData
                                    required property int index
                                    width: ListView.view.width
                                    showDivider: index > 0
                                    glyph: ""
                                    tone: modelData.missed ? "danger" : "call"
                                    title: modelData.who
                                    meta: modelData.what
                                    timeText: root.timeOf(modelData.startedAt)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
