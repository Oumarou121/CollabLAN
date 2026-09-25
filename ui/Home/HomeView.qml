import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import "../Components"
import "../Dashboard"

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
    readonly property color track: "#D9E2E0"

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

    function refreshTransfers() {
        if (typeof transferContext === "undefined" || !transferContext) {
            transferItems = []
            activeTransferCount = 0
            return
        }
        const all = transferContext.activeTransfers || []
        // state est la valeur technique non localisee ("in_progress"),
        // contrairement a statusText qui est traduit et donc fragile a
        // comparer ici (voir TransferContext::onTransferStarted()).
        const active = all.filter(function(item) {
            return item && item.state === "in_progress"
        }).slice(-4).reverse()
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

            peers.push({
                id: id,
                name: name || ("Poste " + (i + 1)),
                address: address,
                status: status,
                userUuid: userUuid
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
                const host = authorizedMachineModel.data(midx, authorizedMachineModel.HostnameRole) || ""

                if (!authorized && ip) {
                    pendingCount++
                    pendingHosts.push(host || ip)
                }
            }

            if (pendingCount > 0) {
                items.push({
                    urgency: "medium",
                    title: pendingCount + " " + qsTr("poste(s) demandent une autorisation"),
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
                    title: deniedCount + " " + qsTr("connexion(s) refusée(s)"),
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
        }
        function onDataChanged() {
            root.refreshNetworkOfflinePeers()
            root.refreshActionRequired()
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
            font.pixelSize: 13
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

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // Sidebar
        DashboardSidebar {
            id: sidebar
            Layout.fillHeight: true
            // Largeur réduite à 150px quand le panneau "À traiter" disparait (< 1050px)
            // Sinon 180px normal
            isCompact: root.isMobile || root.width < 1050
            username: root.username
            serverStatus: root.serverStatusLabel
            serverStatusColor: root.serverStatusColor
            activeTransfers: root.activeTransferCount
            pendingAdmin: root.isAdmin ? root.pendingAuthorizationCount : 0
            isAdmin: root.isAdmin

            onHomeRequested: { /* Déjà sur home */ }
            onChatRequested: root.chatRequested()
            onTransferRequested: root.fileTransferRequested(false, null)
            onFoldersRequested: root.sharedFoldersRequested()
            onCallRequested: root.callRequested()
            onPeersRequested: root.usersRequested()
            onAdminRequested: root.adminRequested()
            onSettingsRequested: root.settingsRequested()
            onLogoutRequested: root.logoutRequested()
        }

        // Zone principale
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // Header
            DashboardHeader {
                Layout.fillWidth: true
                // Même remarque que la sidebar : implicitHeight d'un Item nu
                // vaut 0, donc il faut fixer explicitement la hauteur ici.
                Layout.preferredHeight: 52
                breadcrumb: "LocaLink / Vue d'ensemble"

                onSearchRequested: function(query) {
                    console.log("Search requested:", query)
                }
                onNotificationsRequested: {
                    console.log("Notifications requested")
                }
            }

            // Contenu principal - padding exact selon maquette: 4px 24px 18px
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                // Zone titre - height 62px, align-items: flex-end selon maquette
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 62
                    Layout.leftMargin: 24
                    Layout.rightMargin: 24
                    Layout.topMargin: 8

                    // Ancrage explicite (au lieu d'un RowLayout + Layout.fillWidth
                    // sur la colonne de titre) : le bouton doit rester collé au
                    // bord droit de la zone, quelle que soit la largeur du texte
                    // "Bonjour, ..." / des compteurs. Avec fillWidth sur la
                    // colonne, le RowLayout ne pousse le bouton à droite que si
                    // la colonne réclame déjà tout l'espace restant ; ça
                    // provoquait un décalage visible par rapport au bord droit
                    // de la carte réseau / du panneau "À traiter" juste en
                    // dessous (qui, eux, sont ancrés sur toute la largeur).
                    ColumnLayout {
                        id: titleColumn
                        anchors.left: parent.left
                        anchors.right: newTransferBtn.left
                        anchors.rightMargin: 16
                        anchors.bottom: parent.bottom
                        // Permet à la colonne de se réduire (élision du texte)
                        // plutôt que de déborder et de repousser le bouton hors
                        // de la zone visible sur les fenêtres étroites.
                        clip: true
                        spacing: 5

                            // .gr h1 : 26px / 700 / line-height 32 / letter-spacing -0.02em
                            Label {
                                text: qsTr("Bonjour, ") + (root.username || "")
                                color: Theme.dashboardInk
                                font.pixelSize: 27
                                font.weight: Theme.weightSemibold
                                font.family: Theme.fontFamily
                                font.letterSpacing: -0.54
                                lineHeight: 32
                                lineHeightMode: Text.FixedHeight
                            }

                            // .stl : flex row, align-items center, gap 16,
                            // couleur par défaut ink2, texte en gras (b) en ink
                            RowLayout {
                                spacing: 16
                                Layout.alignment: Qt.AlignVCenter

                                // .sp1 : largeur auto (padding 9/11), pas de
                                // largeur fixe qui tronquerait un libellé long
                                // Statut serveur traité comme information contextuelle
                                // discrète (pastille + libellé), plus comme un badge
                                // "alerte" : poids medium au lieu de bold, fond très
                                // légèrement teinté.
                                RowLayout {
                                    spacing: 7
                                    Layout.alignment: Qt.AlignVCenter

                                    Rectangle {
                                        Layout.preferredWidth: 6
                                        Layout.preferredHeight: 6
                                        radius: 3
                                        color: Theme.dashboardSuccess
                                    }

                                    Label {
                                        text: root.serverStatusLabel
                                        color: Theme.dashboardInkSecondary
                                        font.pixelSize: 13
                                        font.weight: Theme.weightMedium
                                        font.family: Theme.fontFamily
                                    }
                                }

                                Rectangle {
                                    Layout.preferredWidth: 1
                                    Layout.preferredHeight: 12
                                    color: Theme.dashboardLine
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                // <span><b>N</b> postes en ligne</span>
                                // Valeur mise en avant par le poids (semibold) plutôt
                                // que par une taille plus grande, libellé en tertiaire :
                                // information contextuelle secondaire, pas un compteur
                                // "hero".
                                Row {
                                    spacing: 4
                                    Layout.alignment: Qt.AlignVCenter

                                    Label {
                                        text: root.peersCount
                                        color: Theme.dashboardInk
                                        font.pixelSize: 13
                                        font.weight: Theme.weightSemibold
                                        font.family: Theme.fontFamily
                                    }
                                    Label {
                                        text: qsTr("postes en ligne")
                                        color: Theme.dashboardInkTertiary
                                        font.pixelSize: 13
                                        font.family: Theme.fontFamily
                                    }
                                }

                                // <span><b>M</b> transferts en cours</span>
                                Row {
                                    spacing: 4
                                    Layout.alignment: Qt.AlignVCenter

                                    Label {
                                        text: root.activeTransferCount
                                        color: Theme.dashboardInk
                                        font.pixelSize: 13
                                        font.weight: Theme.weightSemibold
                                        font.family: Theme.fontFamily
                                    }
                                    Label {
                                        text: qsTr("transferts en cours")
                                        color: Theme.dashboardInkTertiary
                                        font.pixelSize: 13
                                        font.family: Theme.fontFamily
                                    }
                                }
                            }
                    }

                    // .btn.p : height 36, padding 0 14, radius 8, 600 14px,
                    // icône "+" avant le texte, gap 7. Ancré au bord droit de
                    // la zone (et non plus poussé par un RowLayout) pour
                    // rester collé à droite dans tous les cas, indépendamment
                    // du panneau "À traiter" et de la largeur du texte à gauche.
                    Button {
                        id: newTransferBtn
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 36
                            leftPadding: 14
                            rightPadding: 14
                            background: Rectangle {
                                color: newTransferBtn.hovered ? Theme.dashboardPrimaryHover : Theme.dashboardPrimary
                                radius: 8
                            }
                            contentItem: RowLayout {
                                spacing: 7
                                Label {
                                    text: "+"
                                    color: Theme.dashboardSurface
                                    font.pixelSize: 15
                                    font.bold: true
                                    font.family: Theme.fontFamily
                                    Layout.alignment: Qt.AlignVCenter
                                }
                                Label {
                                    text: qsTr("Nouveau transfert")
                                    color: Theme.dashboardSurface
                                    font.pixelSize: 14
                                    font.bold: true
                                    font.family: Theme.fontFamily
                                    verticalAlignment: Text.AlignVCenter
                                    Layout.alignment: Qt.AlignVCenter
                                }
                            }
                            onClicked: root.fileTransferRequested(true, null)
                    }
                }

                // Workspace - height 456px. Maquette : `.ws` = UNE seule surface
                // (bordure 1px, rayon 12) contenant la carte réseau (`.cv`, filet
                // droit 1px) et la colonne « À traiter » (`.atr`, fond surface2).
                // Colonne « À traiter » : 336px à 1440, jamais 1fr illimité ; la
                // carte prend tout le reste (au minimum 840px).
                Rectangle {
                    id: workspaceContainer
                    Layout.fillWidth: true
                    Layout.preferredHeight: 456
                    Layout.leftMargin: 24
                    Layout.rightMargin: 24
                    Layout.topMargin: 14
                    color: Theme.surfaceLevel2
                    border.width: 1
                    border.color: Theme.hairline
                    radius: 14

                    // Surface interne, inscrite DANS la bordure de 1px : les enfants
                    // ont ainsi un rayon de 11px (12 - 1), concentrique à la bordure.
                    // Plus aucune « rustine » ne recouvre la bordure du conteneur.
                    Item {
                        id: workspaceInner
                        anchors.fill: parent
                        anchors.margins: 1

                        readonly property real innerRadius: workspaceContainer.radius - workspaceContainer.border.width
                        readonly property real mapMinWidth: 840
                        readonly property real actionPanelMaxWidth: 336
                        // Visible uniquement si la largeur est suffisante (>= 1050px)
                        readonly property bool showActionPanel: workspaceContainer.width >= 1050
                        // 1fr plafonné : le panneau ne dépasse jamais 336px (le reste
                        // va à la carte). Il n'est réduit sous 336 que si la carte
                        // tomberait sous ses 840px.
                        readonly property real actionPanelWidth: showActionPanel
                                ? Math.min(actionPanelMaxWidth, Math.max(0, width - mapMinWidth - 1))
                                : 0

                        // ScrollView pour la carte réseau - défilement uniquement si
                        // la place manque (< 840px)
                        ScrollView {
                            id: networkScrollView
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            // -1 : filet de séparation vertical
                            width: parent.width - (workspaceInner.showActionPanel ? workspaceInner.actionPanelWidth + 1 : 0)
                            clip: true
                            contentWidth: networkWorkspace.width
                            contentHeight: networkWorkspace.height
                            ScrollBar.horizontal.policy: ScrollBar.AsNeeded
                            ScrollBar.vertical.policy: ScrollBar.AlwaysOff

                            // Carte réseau - au moins 840px, occupe toute la place
                            // laissée par « À traiter » ; centre recalculé (width/2).
                            NetworkWorkspace {
                                id: networkWorkspace
                                width: Math.max(workspaceInner.mapMinWidth, networkScrollView.width)
                                height: networkScrollView.height
                                // Coins arrondis uniquement sur les côtés qui touchent
                                // la bordure de la surface.
                                leftRadius: workspaceInner.innerRadius
                                rightRadius: workspaceInner.showActionPanel ? 0 : workspaceInner.innerRadius
                                peers: root.networkPeers
                                offlinePeers: root.networkOfflinePeers
                                localPeerName: root.username || qsTr("Ce poste")
                                localPeerStatusLabel: root.serverStatusLabel
                                activeTransfers: (typeof transferContext !== "undefined" && transferContext)
                                                 ? transferContext.activeTransfers : []
                                activeCalls: root.networkActiveCalls
                                demoMode: root.demoMode

                                onSendFileRequested: function(peer) {
                                    // Ouvre l'écran Transferts avec le volet "Nouveau
                                    // transfert" déjà déplié et ce poste (carte réseau,
                                    // vue carte ou liste) déjà sélectionné comme
                                    // destinataire - même mécanisme que le bouton
                                    // "Nouveau transfert" du Dashboard (autoOpenPanel),
                                    // avec le poste transmis en plus.
                                    root.fileTransferRequested(true, peer)
                                }
                                onCallRequested: function(peer) {
                                    if (typeof callContext !== "undefined" && callContext && peer.address)
                                        callContext.call(peer.address)
                                }
                                onMessageRequested: function(peer) {
                                    if (typeof messagingContext !== "undefined" && messagingContext && peer.userUuid)
                                        messagingContext.startConversationWith(peer.userUuid)
                                }
                            }
                        }

                        // Filet vertical carte | À traiter (maquette : `.cv` border-right 1px)
                        Rectangle {
                            id: workspaceDivider
                            visible: workspaceInner.showActionPanel
                            anchors.left: networkScrollView.right
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: 1
                            color: Theme.dashboardLine
                        }

                        // À traiter - colonne accolée à la carte (maquette : `.atr`,
                        // fond surface2, padding 14px 16px). Seuls les coins droits
                        // suivent l'arrondi de la surface.
                        Rectangle {
                            id: actionPanelSurface
                            visible: workspaceInner.showActionPanel
                            anchors.left: workspaceDivider.right
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            color: Theme.dashboardSurfaceAlt
                            topLeftRadius: 0
                            bottomLeftRadius: 0
                            topRightRadius: workspaceInner.innerRadius
                            bottomRightRadius: workspaceInner.innerRadius

                            ActionRequiredPanel {
                                anchors.fill: parent
                                anchors.leftMargin: 16
                                anchors.rightMargin: 16
                                anchors.topMargin: 14
                                anchors.bottomMargin: 14
                                actions: root.actionRequiredItems

                                onActionRequested: function(action, actionType) {
                                    if (actionType !== "examine")
                                        return
                                    // 1 = onglet "Machines autorisées" (item de type
                                    // "authorization"), 0 = "Journal d'audit" (tout le
                                    // reste, notamment "access_denied") - voir
                                    // AdminView.currentTab.
                                    root.adminSectionRequested(action.type === "authorization" ? 1 : 0)
                                }
                            }
                        }
                    }
                }

                // Zone inférieure - grid 1.22fr + 1fr, à plat sur le fond
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.leftMargin: 24
                    Layout.rightMargin: 24
                    Layout.topMargin: 14
                    Layout.bottomMargin: 18

                    RowLayout {
                        anchors.fill: parent
                        spacing: 0

                        // Transferts - 1.22fr
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.preferredWidth: parent.width * 1.22 / 2.22
                            Layout.rightMargin: 28
                            spacing: 0

                            // Header Transferts
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 30
                                spacing: 8

                                Label {
                                    text: qsTr("Transferts")
                                    color: Theme.dashboardInk
                                    font.pixelSize: 15
                                    font.bold: true
                                    font.family: Theme.fontFamily
                                }

                                Label {
                                    text: root.activeTransferCount > 0 ? (root.activeTransferCount + " en cours") : ""
                                    color: Theme.dashboardInkTertiary
                                    font.pixelSize: 12
                                    font.family: Theme.fontFamily
                                }

                                Item { Layout.fillWidth: true }

                                Button {
                                    text: qsTr("Tous les transferts")
                                    flat: true
                                    font.pixelSize: 12
                                    font.family: Theme.fontFamily
                                    background: Rectangle { color: "transparent" }
                                    contentItem: Label {
                                        text: parent.text
                                        color: Theme.dashboardPrimary
                                        font.pixelSize: 12
                                        font.family: Theme.fontFamily
                                    }
                                }
                            }

                            // Etat vide transferts
                            SkeletonRows {
                                visible: !root.contentSettled
                                variant: "transfer"
                                Layout.fillWidth: true
                            }

                            EmptyState {
                                visible: root.contentSettled && root.transferItems.length === 0
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                iconName: "transfer"
                                title: qsTr("Aucun transfert en cours")
                                description: qsTr("Les fichiers envoyés et reçus apparaîtront ici.")
                                actionText: qsTr("Envoyer un fichier")
                                onActionClicked: root.fileTransferRequested(true, null)
                            }

                            // Liste transferts à plat
                            ScrollView {
                                visible: root.contentSettled && root.transferItems.length > 0
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                clip: true

                                ColumnLayout {
                                    width: parent.width
                                    spacing: 10

                                    Repeater {
                                        model: root.transferItems
                                        delegate: TransferRow {
                                            Layout.fillWidth: true
                                            fileName: modelData.fileName || ""
                                            peerName: modelData.peerName || ""
                                            address: modelData.peerAddress || ""
                                            progress: (modelData.percent || 0) / 100
                                            transferred: modelData.bytesTransferred || 0
                                            total: modelData.totalBytes || 0
                                            status: modelData.statusText || "En cours"
                                            state: modelData.state || ""
                                            timestamp: modelData.timestamp || ""
                                            isIncoming: modelData.incoming || false

                                            onDetailsRequested: root.fileTransferRequested(false, null)
                                            onOpenLocationRequested: {
                                                if (typeof transferContext === "undefined" || !transferContext
                                                        || !transferContext.openFileLocation(modelData.filePath || "")) {
                                                    errorBanner.show(qsTr("Impossible d'ouvrir l'emplacement du fichier."))
                                                }
                                            }
                                            onRetryRequested: {
                                                if (typeof transferContext === "undefined" || !transferContext
                                                        || !transferContext.retryTransfer(modelData.transferKey || "")) {
                                                    errorBanner.show(qsTr("Impossible de relancer le transfert."))
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Séparateur vertical
                        Rectangle {
                            Layout.preferredWidth: 1
                            Layout.fillHeight: true
                            color: Theme.dashboardLine
                        }

                        // Activité - 1fr
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.leftMargin: 28
                            spacing: 0

                            // Header Activité
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 30
                                spacing: 8

                                Label {
                                    text: qsTr("Activité récente")
                                    color: Theme.dashboardInk
                                    font.pixelSize: 15
                                    font.bold: true
                                    font.family: Theme.fontFamily
                                }

                                Item { Layout.fillWidth: true }

                                Button {
                                    visible: root.contentSettled && root.activityItems.length > 0
                                    text: qsTr("Voir le journal")
                                    flat: true
                                    font.pixelSize: 12
                                    font.family: Theme.fontFamily
                                    background: Rectangle { color: "transparent" }
                                    contentItem: Label {
                                        text: parent.text
                                        color: Theme.dashboardPrimary
                                        font.pixelSize: 12
                                        font.family: Theme.fontFamily
                                    }
                                }
                            }

                            // Etat vide activité (pas de bouton : rien à ouvrir)
                            SkeletonRows {
                                visible: !root.contentSettled
                                variant: "activity"
                                Layout.fillWidth: true
                            }

                            EmptyState {
                                visible: root.contentSettled && root.activityItems.length === 0
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                iconName: "log"
                                title: qsTr("Aucune activité pour le moment")
                                description: qsTr("Les connexions, messages, transferts et appels apparaîtront ici.")
                            }

                            // Liste activité à plat
                            ScrollView {
                                visible: root.contentSettled && root.activityItems.length > 0
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                clip: true

                                ColumnLayout {
                                    width: parent.width
                                    spacing: 8

                                    Repeater {
                                        model: root.activityItems
                                        delegate: ActivityRow {
                                            Layout.fillWidth: true
                                            event: modelData.event || ""
                                            actor: modelData.actor || ""
                                            message: modelData.message || ""
                                            result: modelData.result || ""
                                            resultBadge: modelData.resultBadge || ""
                                            timestamp: modelData.timestamp || new Date()
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
}
