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
    signal fileTransferRequested()
    signal callRequested()
    signal adminRequested()
    signal settingsRequested()
    signal sharedFoldersRequested()
    signal aboutRequested()

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
    readonly property color bg: "#EEF2F1"
    readonly property color surface: "#FFFFFF"
    readonly property color surface2: "#F7F9F8"
    readonly property color line: "#DDE4E2"
    readonly property color line2: "#C8D2CF"
    readonly property color ink: "#15222B"
    readonly property color ink2: "#4A5961"
    readonly property color ink3: "#62717A"
    readonly property color primary: "#0B5C70"
    readonly property color primarySoft: "#E0EEF2"
    readonly property color primaryMuted: "#B9D8E0"
    readonly property color ok: "#2E9A66"
    readonly property color okSoft: "#E4F4EC"
    readonly property color okText: "#1B7048"
    readonly property color warn: "#C27A0E"
    readonly property color warnSoft: "#FCF1DC"
    readonly property color warnText: "#8E5A08"
    readonly property color err: "#C8453B"
    readonly property color errSoft: "#FBE9E7"
    readonly property color errText: "#9E2F27"
    readonly property color info: "#3A78B8"
    readonly property color infoSoft: "#E5EEF8"
    readonly property color infoText: "#28598C"
    readonly property color call: "#7A55B0"
    readonly property color callSoft: "#EEE8F7"
    readonly property color callText: "#5B3B8C"
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
            return "#2E9A66"
        if (root.election.roleLabel === "TEMP_SERVER")
            return "#C27A0E"
        return "#2E9A66"
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

    function refreshTransfers() {
        if (typeof transferContext === "undefined" || !transferContext) {
            transferItems = []
            return
        }
        const all = transferContext.activeTransfers || []
        transferItems = all.filter(function(item) {
            return item && item.statusText === qsTr("En cours")
        }).slice(-4).reverse()
        if (transferItems.length > 0)
            contentSettled = true
    }

    // Données activité
    property var activityItems: []

    function refreshActivities() {
        if (typeof auditLogModel === "undefined" || !auditLogModel) {
            activityItems = []
            return
        }
        const all = []
        for (let i = 0; i < Math.min(auditLogModel.count, 10); i++) {
            const item = auditLogModel.get(i)
            all.push({
                event: item.event || "activity",
                actor: item.actor || "",
                message: item.message || "",
                result: item.result || "",
                resultBadge: item.resultBadge || "",
                timestamp: item.timestamp || new Date()
            })
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

    function refreshActionRequired() {
        const items = []

        // 1. Postes en attente d'autorisation (pendingClientCount)
        if (typeof authorizedMachineModel !== "undefined" && authorizedMachineModel) {
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
        }

        // 2. Connexions refusées récentes (auditLogModel)
        if (typeof auditLogModel !== "undefined" && auditLogModel) {
            const count = Math.min(auditLogModel.count, 10)
            let deniedCount = 0
            let lastDenied = null

            for (let i = 0; i < count; i++) {
                const item = auditLogModel.get(i)
                if (item && item.event === "access_denied") {
                    deniedCount++
                    if (!lastDenied) {
                        lastDenied = {
                            message: item.message || "",
                            timestamp: item.timestamp || new Date()
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

        // Ajouter un item de démonstration si vide (pour tester l'affichage)
        if (items.length === 0) {
            items.push({
                urgency: "info",
                title: qsTr("Tout est en ordre"),
                description: qsTr("Aucune action requise pour le moment"),
                type: "demo"
            })
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
        color: "#EEF2F1"
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
            activeTransfers: root.transferItems.length
            pendingAdmin: 0 // TODO: Connecter aux vraies données
            isAdmin: root.isAdmin

            onHomeRequested: { /* Déjà sur home */ }
            onChatRequested: root.chatRequested()
            onTransferRequested: root.fileTransferRequested()
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
                                color: "#15222B"
                                font.pixelSize: 26
                                font.bold: true
                                font.weight: Font.Medium
                                font.family: Theme.fontFamily
                                font.letterSpacing: -0.52
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
                                Rectangle {
                                    Layout.preferredHeight: 26
                                    Layout.preferredWidth: sp1Row.implicitWidth + 20
                                    radius: 13
                                    color: "#E4F4EC"

                                    RowLayout {
                                        id: sp1Row
                                        anchors.centerIn: parent
                                        spacing: 7

                                        Rectangle {
                                            Layout.preferredWidth: 7
                                            Layout.preferredHeight: 7
                                            radius: 3.5
                                            color: "#2E9A66"
                                        }

                                        Label {
                                            text: root.serverStatusLabel
                                            color: "#1B7048"
                                            font.pixelSize: 12
                                            font.bold: true
                                            font.family: Theme.fontFamily
                                        }
                                    }
                                }

                                // <span><b>N</b> postes en ligne</span>
                                Label {
                                    text: "<b style=\"color:#15222B\">" + root.peersCount + "</b> " + qsTr("postes en ligne")
                                    textFormat: Text.RichText
                                    color: "#4A5961"
                                    font.pixelSize: 14
                                    font.family: Theme.fontFamily
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                // <span><b>M</b> transferts en cours</span>
                                Label {
                                    text: "<b style=\"color:#15222B\">" + root.transferItems.length + "</b> " + qsTr("transferts en cours")
                                    textFormat: Text.RichText
                                    color: "#4A5961"
                                    font.pixelSize: 14
                                    font.family: Theme.fontFamily
                                    Layout.alignment: Qt.AlignVCenter
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
                                color: newTransferBtn.hovered ? "#0A4E5F" : "#0B5C70"
                                radius: 8
                            }
                            contentItem: RowLayout {
                                spacing: 7
                                Label {
                                    text: "+"
                                    color: "#FFFFFF"
                                    font.pixelSize: 15
                                    font.bold: true
                                    font.family: Theme.fontFamily
                                    Layout.alignment: Qt.AlignVCenter
                                }
                                Label {
                                    text: qsTr("Nouveau transfert")
                                    color: "#FFFFFF"
                                    font.pixelSize: 14
                                    font.bold: true
                                    font.family: Theme.fontFamily
                                    verticalAlignment: Text.AlignVCenter
                                    Layout.alignment: Qt.AlignVCenter
                                }
                            }
                            onClicked: root.fileTransferRequested()
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
                    color: "#FFFFFF"
                    border.width: 1
                    border.color: "#DDE4E2"
                    radius: 12

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
                                    // Nécessite un sélecteur de fichier (doc §26) -
                                    // pas encore branché à cette étape (carte
                                    // réseau uniquement, doc §51).
                                    console.log("Envoyer un fichier vers", peer.name)
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
                            color: "#DDE4E2"
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
                            color: "#F7F9F8"
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
                                    console.log("Action requested:", action.title, actionType)
                                    // TODO: Implémenter les actions
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
                                    color: "#15222B"
                                    font.pixelSize: 15
                                    font.bold: true
                                    font.family: Theme.fontFamily
                                }

                                Label {
                                    text: root.transferItems.length > 0 ? (root.transferItems.length + " en cours") : ""
                                    color: "#62717A"
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
                                        color: "#0B5C70"
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
                                onActionClicked: root.fileTransferRequested()
                            }

                            // Liste transferts à plat
                            ScrollView {
                                visible: root.contentSettled && root.transferItems.length > 0
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                clip: true

                                ColumnLayout {
                                    width: parent.width
                                    spacing: 0

                                    Repeater {
                                        model: root.transferItems
                                        delegate: TransferRow {
                                            Layout.fillWidth: true
                                            fileName: modelData.fileName || ""
                                            peerName: modelData.recipientName || ""
                                            address: modelData.recipientAddress || ""
                                            progress: modelData.progress || 0
                                            transferred: modelData.transferred || 0
                                            total: modelData.total || 0
                                            status: modelData.statusText || "En cours"
                                            isIncoming: modelData.isIncoming || false

                                            onDetailsRequested: root.fileTransferRequested()
                                            onOpenLocationRequested: function(transfer) {
                                                console.log("Open location:", transfer.fileName)
                                            }
                                            onRetryRequested: function(transfer) {
                                                console.log("Retry transfer:", transfer.fileName)
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
                                    color: "#15222B"
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
                                        color: "#0B5C70"
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
                                    spacing: 0

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
