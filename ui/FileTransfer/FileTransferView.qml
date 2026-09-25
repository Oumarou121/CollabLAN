import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import Themes
import "../Components"
import "../Components/icons.js" as Icons
import "../Dashboard"
import "../Dashboard/transferFormat.js" as Fmt

/*
 * FileTransferView - ecran "Transfert de fichiers" (Dashboard V2.1).
 *
 * Refonte visuelle complete, alignee sur le Dashboard (DashboardShell :
 * meme Sidebar et Header, jetons Theme.dashboardXxx, memes boutons, badges
 * et icones filaires). La logique metier n'a pas change : transferContext
 * (activeTransfers, sendFile, sendFolder, retryTransfer, openFileLocation,
 * openDownloadsFolder, transferRejected), regroupement par correspondant
 * (buildPeerGroups -> peerGroups), filtres, recherche.
 *
 * Composition :
 *   Page defilante (Flickable), comme la maquette (.scroll) :
 *   Titre + [+ Nouveau transfert]  (+ bloc d'echec sous le filtre "Echoues")
 *   Barre d'outils : filtres | recherche, liste/grille, actualiser, dossier de reception
 *   Correspondants : grille de cartes 4/3/2/1 colonnes (clic = selection, re-clic = tous)
 *   Transferts     : UNE surface, lignes plates (liste) ou tuiles (grille)
 *   Volet lateral "Nouveau transfert" : fichier -> destinataires -> resume -> envoi
 *
 * Choix : le correspondant selectionne FILTRE la liste au lieu de la
 * remplacer ; activeTransfers est emis a chaque bloc transfere, donc les
 * groupes sont recalcules au plus toutes les 150 ms et les listes
 * synchronisees en place (ListModel) pour garder defilement et survol.
 */
Item {
    id: root

    property var context: (typeof transferContext !== "undefined") ? transferContext : null

    property var selectedFilePaths: []
    property string selectedFolderPath: ""
    property var selectedRecipients: []

    function isRecipientSelected(machineId) {
        for (let i = 0; i < selectedRecipients.length; ++i) {
            if (selectedRecipients[i].machineId === machineId) return true
        }
        return false
    }

    function toggleRecipient(recipient) {
        const list = selectedRecipients.slice()
        const idx = list.findIndex(function(r) { return r.machineId === recipient.machineId })
        if (idx >= 0) {
            list.splice(idx, 1)
        } else {
            list.push(recipient)
        }
        selectedRecipients = list
    }

    readonly property bool compactList: root.width < 900

    signal backRequested()
    // Navigation Sidebar relayee comme dans HomeView (voir Main.qml).
    // "Vue d'ensemble" reutilise backRequested() : l'ecran est empile par-
    // dessus HomeView, y revenir est un simple pop().
    signal chatRequested()
    signal foldersRequested()
    signal callRequested()
    signal peersRequested()
    signal adminRequested()
    signal settingsRequested()
    signal logoutRequested()

    // ---- contexte Sidebar/Header (meme source que HomeView) ----
    readonly property bool isAdmin: (typeof userManager !== "undefined" && userManager)
                                     ? userManager.currentUserIsAdmin : false
    readonly property string currentUsername: (typeof userManager !== "undefined" && userManager)
                                     ? userManager.currentUsername : ""
    readonly property var election: (typeof electionService !== "undefined") ? electionService : null
    readonly property string serverStatusLabel: {
        if (!root.election) return qsTr("Réseau local")
        if (root.election.roleLabel === "TEMP_SERVER") return qsTr("Mode secours")
        if (root.election.roleLabel === "SERVER") return qsTr("Serveur actif")
        return qsTr("Connecté au serveur")
    }
    readonly property color serverStatusColorValue: {
        if (!root.election) return "#2E9A66"
        if (root.election.roleLabel === "TEMP_SERVER") return "#C27A0E"
        return "#2E9A66"
    }
    readonly property int activeTransferCount: {
        const all = root.context ? (root.context.activeTransfers || []) : []
        return all.filter(function(item) { return item && item.state === "in_progress" }).length
    }
    readonly property bool isCompactWidth: root.width < 1050

    // ---- utilitaires ----
    function fileNameFromPath(path) { return Fmt.fileNameFromPath(path) }
    function formatBytes(bytes) { return Fmt.formatBytes(bytes) }

    // "Aujourd'hui 14:31", "Hier 09:12" ou "24/09/2026 14:31".
    function formatRowDate(isoString, tick) {
        if (!isoString) return ""
        const d = new Date(isoString)
        if (isNaN(d.getTime())) return ""
        const now = tick ? tick : new Date()
        const startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate())
        const startOfDate = new Date(d.getFullYear(), d.getMonth(), d.getDate())
        const diffDays = Math.round((startOfToday - startOfDate) / 86400000)
        const time = d.toLocaleString(Qt.locale(), "HH:mm")
        if (diffDays === 0) return qsTr("Aujourd'hui %1").arg(time)
        if (diffDays === 1) return qsTr("Hier %1").arg(time)
        return d.toLocaleString(Qt.locale(), "dd/MM/yyyy HH:mm")
    }

    // Date relative courte ("il y a 2 min"). `tick` (nowTick) force la
    // reevaluation des liaisons quand le temps passe.
    function formatRelative(isoString, tick) {
        if (!isoString) return ""
        const d = new Date(isoString)
        if (isNaN(d.getTime())) return ""
        const now = tick ? tick : new Date()
        const mins = Math.floor((now.getTime() - d.getTime()) / 60000)
        if (mins < 1) return qsTr("à l'instant")
        if (mins < 60) return qsTr("il y a %1 min").arg(mins)

        const startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate())
        const startOfDate = new Date(d.getFullYear(), d.getMonth(), d.getDate())
        const diffDays = Math.round((startOfToday - startOfDate) / 86400000)
        if (diffDays <= 0) return qsTr("il y a %1 h").arg(Math.floor(mins / 60))
        if (diffDays === 1) return qsTr("hier")
        if (diffDays < 7) return qsTr("il y a %1 j").arg(diffDays)
        return d.toLocaleString(Qt.locale(), "dd/MM/yyyy")
    }

    function countLabel(n) {
        return n === 1 ? qsTr("1 transfert") : qsTr("%1 transferts").arg(n)
    }

    function normalizePeerAddress(address) {
        if (!address) return ""
        let a = address.trim().toLowerCase()
        const v4MappedPrefix = "::ffff:"
        if (a.indexOf(v4MappedPrefix) === 0) {
            a = a.substring(v4MappedPrefix.length)
        }
        return a
    }

    function buildPeerGroups(transfers) {
        const groupsByKey = {}
        const order = []

        for (let i = 0; i < transfers.length; i++) {
            const item = transfers[i]
            const rawAddress = item.peerAddress || ""
            const peerMachineId = item.peerMachineId || ""
            const peerUserUuid = item.peerUserUuid || ""
            const peerUserName = item.peerUserName || ""

            // Cle conversation : sender/recipient identifient le correspondant
            // utilisateur, quel que soit le sens du transfert. peerMachineId
            // reste le repli stable pour les pairs LAN sans compte utilisateur.
            const key = peerUserUuid.length > 0
                        ? "user:" + peerUserUuid
                        : (peerMachineId.length > 0
                        ? "uuid:" + peerMachineId
                        : (rawAddress.length > 0 ? root.normalizePeerAddress(rawAddress) : "__unknown__"))

            if (!groupsByKey[key]) {
                groupsByKey[key] = {
                    peerKey: key,
                    peerLabel: peerUserName.length > 0 ? peerUserName
                               : ((item.peerName && item.peerName.length > 0) ? item.peerName
                               : (rawAddress.length > 0 ? rawAddress
                               : qsTr("Correspondant inconnu"))),
                    peerAddress: rawAddress,
                    peerMachineId: peerMachineId,
                    peerUserUuid: peerUserUuid,
                    peerUserName: peerUserName,
                    items: [],
                    lastTimestampMs: 0
                }
                order.push(key)
            }

            const group = groupsByKey[key]
            // Mettre a jour peerLabel si un nom arrive plus tard (seulement si
            // le label actuel est l'adresse ou "Correspondant inconnu").
            if (peerUserName.length > 0) {
                group.peerLabel = peerUserName
            } else if (item.peerName && item.peerName.length > 0) {
                if (group.peerLabel === rawAddress || group.peerLabel === qsTr("Correspondant inconnu")) {
                    group.peerLabel = item.peerName
                }
            }
            if (rawAddress.length > 0 && group.peerAddress.toLowerCase().indexOf("::ffff:") === 0
                    && rawAddress.toLowerCase().indexOf("::ffff:") !== 0) {
                group.peerAddress = rawAddress
                if (!item.peerName || item.peerName.length === 0) {
                    group.peerLabel = rawAddress
                }
            }

            const ts = item.timestamp ? Date.parse(item.timestamp) : 0
            group.items.push(item)
            if (ts > group.lastTimestampMs) {
                group.lastTimestampMs = ts
            }
        }

        const groups = order.map(function(key) { return groupsByKey[key] })
        groups.sort(function(a, b) { return b.lastTimestampMs - a.lastTimestampMs })
        for (let g = 0; g < groups.length; g++) {
            groups[g].items.sort(function(a, b) {
                return Date.parse(b.timestamp || 0) - Date.parse(a.timestamp || 0)
            })
        }
        return groups
    }

    // ---- proprietes ----
    property var allTransfers: []
    property var peerGroups: []

    property string openedPeerKey: ""
    property string searchText: ""

    property string viewMode: "list"          // "list" | "grid"
    property string activeFilter: "all"       // "all" | "active" | "received" | "sent" | "failed"

    // Crochet d'affichage "squelette" : la liste est chargee de maniere
    // synchrone (loadHistory), il reste donc a false.
    property bool loading: false

    property date nowTick: new Date()

    // ---- etat du panneau "Nouveau transfert" ----
    property bool panelOpen: false
    property string panelMode: "form"         // "form" | "sending"
    property string panelError: ""
    property var recipients: []
    property var knownKeysBeforeSend: ({})

    function stateOf(item) {
        if (item.state && item.state.length > 0) return item.state
        switch (item.statusText) {
        case "Terminé": return "completed"
        case "Échoué": return "failed"
        case "Annulé": return "cancelled"
        case "Interrompu": return "interrupted"
        default: return "in_progress"
        }
    }

    function isIncomingItem(item) {
        if (item.incoming !== undefined) return !!item.incoming
        return item.direction === qsTr("Réception")
    }

    function matchesFilter(item) {
        switch (root.activeFilter) {
        case "received": return root.isIncomingItem(item)
        case "sent": return !root.isIncomingItem(item)
        case "failed": return root.stateOf(item) === "failed"
        case "active": return root.stateOf(item) === "in_progress"
        default: return true
        }
    }

    function matchesSearch(item, group) {
        const q = root.searchText.trim().toLowerCase()
        if (q.length === 0) return true
        return group.peerLabel.toLowerCase().indexOf(q) !== -1
               || (item.fileName || "").toLowerCase().indexOf(q) !== -1
    }

    function itemVisible(item, group) {
        return root.matchesFilter(item) && root.matchesSearch(item, group)
    }

    // Dernier envoi echoue (relancable) : alimente le bloc "Echec du transfert".
    readonly property var latestFailure: {
        let best = null
        let bestTs = -1
        for (let g = 0; g < root.peerGroups.length; g++) {
            const group = root.peerGroups[g]
            for (let i = 0; i < group.items.length; i++) {
                const it = group.items[i]
                if (root.stateOf(it) !== "failed" || root.isIncomingItem(it) || !it.transferKey) continue
                const ts = it.timestamp ? Date.parse(it.timestamp) : 0
                if (ts > bestTs) {
                    bestTs = ts
                    best = { key: it.transferKey, peer: group.peerLabel }
                }
            }
        }
        return best
    }

    readonly property var currentGroup: {
        for (let i = 0; i < root.peerGroups.length; i++) {
            if (root.peerGroups[i].peerKey === root.openedPeerKey)
                return root.peerGroups[i]
        }
        return null
    }

    readonly property var filteredPeerGroups: {
        return root.peerGroups.filter(function(g) {
            return g.items.some(function(it) { return root.itemVisible(it, g) })
        })
    }

    readonly property var filteredCurrentItems: {
        if (!root.currentGroup) return []
        const g = root.currentGroup
        return g.items.filter(function(it) { return root.itemVisible(it, g) })
    }

    // Transferts affiches : ceux du correspondant selectionne, sinon tous ;
    // en cours d'abord, puis du plus recent au plus ancien.
    readonly property var filteredTransfers: {
        const out = []
        const groups = root.currentGroup ? [root.currentGroup] : root.peerGroups
        for (let g = 0; g < groups.length; g++) {
            const items = groups[g].items
            for (let i = 0; i < items.length; i++) {
                if (root.itemVisible(items[i], groups[g]))
                    out.push({ item: items[i], group: groups[g] })
            }
        }
        out.sort(function(a, b) {
            const aa = root.stateOf(a.item) === "in_progress" ? 1 : 0
            const bb = root.stateOf(b.item) === "in_progress" ? 1 : 0
            if (aa !== bb) return bb - aa
            const ta = a.item.timestamp ? Date.parse(a.item.timestamp) : 0
            const tb = b.item.timestamp ? Date.parse(b.item.timestamp) : 0
            return tb - ta
        })
        return out
    }

    // Compteurs des filtres rapides (recherche appliquee, filtre ignore).
    readonly property var filterCounts: {
        const c = { all: 0, active: 0, received: 0, sent: 0, failed: 0 }
        for (let g = 0; g < root.peerGroups.length; g++) {
            const group = root.peerGroups[g]
            for (let i = 0; i < group.items.length; i++) {
                const it = group.items[i]
                if (!root.matchesSearch(it, group)) continue
                c.all++
                if (root.stateOf(it) === "in_progress") c.active++
                if (root.stateOf(it) === "failed") c.failed++
                if (root.isIncomingItem(it)) c.received++; else c.sent++
            }
        }
        return c
    }

    readonly property int totalFileCount: {
        let n = 0
        for (let i = 0; i < root.peerGroups.length; i++) n += root.peerGroups[i].items.length
        return n
    }

    readonly property real totalTransferredBytes: {
        let total = 0
        for (let i = 0; i < root.peerGroups.length; i++) {
            const items = root.peerGroups[i].items
            for (let j = 0; j < items.length; j++) {
                if (root.stateOf(items[j]) === "completed") total += (items[j].totalBytes || 0)
            }
        }
        return total
    }

    function filteredCountFor(group) {
        return group.items.filter(function(it) { return root.itemVisible(it, group) }).length
    }

    function hasActiveFilters() {
        return root.searchText.trim().length > 0 || root.activeFilter !== "all"
    }

    function resetFilters() {
        root.activeFilter = "all"
        root.searchText = ""
    }

    function refreshGroups() {
        const all = root.context ? (root.context.activeTransfers || []) : []
        root.allTransfers = all
        root.peerGroups = root.buildPeerGroups(all)
    }

    // Statut reseau (present/absent) des correspondants dont un transfert
    // existe, par machineId puis par adresse : source = peersModel (meme
    // que refreshRecipients()), pas l'historique des transferts qui ne dit
    // rien de la presence actuelle.
    function presenceFor(peerMachineId, peerAddress) {
        if (typeof peersModel === "undefined" || !peersModel) return ""
        for (let i = 0; i < peersModel.count; i++) {
            const idx = peersModel.index(i, 0)
            const id = peersModel.data(idx, peersModel.IdRole || 257) || ""
            const addr = peersModel.data(idx, peersModel.AddressRole || 261) || ""
            if ((peerMachineId && id === peerMachineId) || (peerAddress && addr === peerAddress)) {
                return (peersModel.data(idx, peersModel.StatusRole || 260) || "online").toLowerCase()
            }
        }
        return ""
    }

    onPeerGroupsChanged: {
        if (root.openedPeerKey.length > 0 && !root.currentGroup) {
            root.openedPeerKey = ""
        }
    }

    // ---- modeles de liste (synchronises en place) ----
    ListModel { id: peerModel }
    ListModel { id: fileModel }

    function peerRow(g) {
        const last = g.items.length > 0 ? g.items[0] : null
        let active = 0
        for (let i = 0; i < g.items.length; i++) {
            if (root.stateOf(g.items[i]) === "in_progress") active++
        }
        return {
            peerKey: g.peerKey,
            peerLabel: g.peerLabel,
            isUser: g.peerUserName.length > 0,
            visibleCount: root.filteredCountFor(g),
            activeCount: active,
            lastFileName: last ? (last.fileName || "") : "",
            lastState: last ? root.stateOf(last) : "",
            lastStatusText: last ? (last.statusText || "") : "",
            lastTimestamp: last ? (last.timestamp || "") : "",
            presenceStatus: root.presenceFor(g.peerMachineId, g.peerAddress)
        }
    }

    function fileRow(entry) {
        const it = entry.item
        return {
            transferKey: it.transferKey || "",
            fileName: it.fileName || "",
            peerLabel: entry.group.peerLabel,
            incoming: root.isIncomingItem(it),
            state: root.stateOf(it),
            statusText: it.statusText || "",
            errorString: it.errorString || "",
            percent: Math.round(it.percent || 0),
            bytesTransferred: it.bytesTransferred || 0,
            totalBytes: it.totalBytes || 0,
            filePath: it.filePath || "",
            timestamp: it.timestamp || ""
        }
    }

    // Met `model` a jour depuis `rows`. Meme suite de cles : mise a jour en
    // place (la progression ne fait ni sauter le defilement, ni perdre le
    // survol). Sinon : reconstruction. Retourne true si reconstruit.
    function syncModel(model, rows, keyName) {
        let same = model.count === rows.length
        for (let i = 0; same && i < rows.length; i++) {
            if (model.get(i)[keyName] !== rows[i][keyName]) same = false
        }
        if (same) {
            for (let r = 0; r < rows.length; r++) {
                const current = model.get(r)
                for (const k in rows[r]) {
                    if (current[k] !== rows[r][k]) model.setProperty(r, k, rows[r][k])
                }
            }
            return false
        }
        model.clear()
        for (let n = 0; n < rows.length; n++) model.append(rows[n])
        return true
    }

    function rebuildModels() {
        // Le defilement est celui de la page entiere (maquette .scroll) :
        // on le conserve si la liste est reconstruite.
        const py = pageScroll.contentY
        root.syncModel(peerModel, root.filteredPeerGroups.map(function(g) { return root.peerRow(g) }), "peerKey")
        if (root.syncModel(fileModel, root.filteredTransfers.map(function(e) { return root.fileRow(e) }), "transferKey")) {
            Qt.callLater(function() {
                pageScroll.contentY = Math.max(0, Math.min(py, pageScroll.contentHeight - pageScroll.height))
            })
        }
    }

    onFilteredPeerGroupsChanged: Qt.callLater(root.rebuildModels)
    onFilteredTransfersChanged: Qt.callLater(root.rebuildModels)

    // true quand la vue doit s'ouvrir directement sur le volet "Nouveau
    // transfert" (venant du bouton "Nouveau transfert" du Dashboard, ou de
    // son etat vide) plutot que sur la simple liste (ex. Sidebar).
    property bool autoOpenPanel: false

    // Poste à présélectionner comme destinataire à l'ouverture du volet
    // (venant d'un clic sur "Envoyer un fichier" depuis la carte réseau ou
    // la vue liste - Dashboard/NetworkWorkspace.qml / NetworkListView.qml).
    // Objet attendu : le peer tel qu'exposé par PeersModel/HomeView.networkPeers
    // ({ id, address, name, ... } - voir HomeView.refreshNetworkPeers()).
    // Consommé une seule fois par openPanel(), puis remis à null.
    property var preselectedPeer: null

    Component.onCompleted: {
        root.refreshGroups()
        root.rebuildModels()
        if (root.autoOpenPanel) root.openPanel()
    }

    Connections {
        target: root.context
        function onActiveTransfersChanged() {
            if (!refreshTimer.running) refreshTimer.start()
        }
        function onTransferRejected(reason) {
            if (root.panelOpen) root.panelError = reason
            else root.showError(reason)
        }
    }

    Timer {
        id: refreshTimer
        interval: 150
        repeat: false
        onTriggered: root.refreshGroups()
    }

    Timer {
        interval: 30000
        repeat: true
        running: root.visible
        onTriggered: root.nowTick = new Date()
    }

    // Postes autorises mais absents du reseau (authorizedMachineModel moins
    // availableRecipients()) : meme calcul que HomeView.refreshNetworkOfflinePeers(),
    // reserve aux administrateurs (authorizedMachineModel n'est peuple que
    // cote admin - voir PermissionManager::getAllMachines() ; root.isAdmin
    // deja defini plus haut, reutilise ici).
    property var offlineRecipients: []

    function refreshOfflineRecipients() {
        if (!root.isAdmin || typeof authorizedMachineModel === "undefined" || !authorizedMachineModel) {
            root.offlineRecipients = []
            return
        }
        const presentById = {}
        const presentByAddress = {}
        for (let i = 0; i < root.recipients.length; ++i) {
            const r = root.recipients[i]
            if (r.machineId) presentById[r.machineId] = true
            if (r.address) presentByAddress[r.address] = true
        }
        const offline = []
        const total = authorizedMachineModel.rowCount ? authorizedMachineModel.rowCount() : 0
        for (let j = 0; j < total; j++) {
            const midx = authorizedMachineModel.index(j, 0)
            const authorized = authorizedMachineModel.data(midx, authorizedMachineModel.AuthorizedRole)
            const id = authorizedMachineModel.data(midx, authorizedMachineModel.MachineIdRole) || ""
            const ip = authorizedMachineModel.data(midx, authorizedMachineModel.IpAddressRole) || ""
            const host = authorizedMachineModel.data(midx, authorizedMachineModel.HostnameRole) || ""
            if (!authorized || (!id && !ip)) continue
            const present = (id && presentById[id]) || (ip && presentByAddress[ip])
            if (!present) {
                offline.push({
                    name: host || ip || id,
                    label: (host || ip || id) + " (" + qsTr("hors ligne") + ")",
                    address: ip,
                    machineId: id,
                    status: "offline"
                })
            }
        }
        root.offlineRecipients = offline
    }

    // availableRecipients() est une methode sans signal de changement : on la
    // relit a l'ouverture du panneau, sur demande, puis toutes les 3 s tant
    // que le formulaire est affiche.
    function refreshRecipients() {
        const peers = root.context ? root.context.availableRecipients() : []
        const result = []
        for (let i = 0; i < peers.length; ++i) {
            result.push({
                name: peers[i].name,
                label: peers[i].name + " (" + peers[i].address + ")",
                address: peers[i].address,
                port: peers[i].port,
                // UUID du pair choisi, transmis a sendFile()/sendFolder() pour
                // que envoi et reception d'un meme correspondant se regroupent
                // (voir buildPeerGroups() et TransferManager::sendFile()).
                machineId: peers[i].id,
                // Statut declare du pair (online / away / busy), voir PeersModel.
                status: peers[i].status || ""
            })
        }
        if (JSON.stringify(result) !== JSON.stringify(root.recipients))
            root.recipients = result
        root.refreshOfflineRecipients()
    }

    Timer {
        interval: 3000
        repeat: true
        running: root.panelOpen && root.panelMode === "form"
        onTriggered: root.refreshRecipients()
    }

    // ---- actions ----
    function showError(message) {
        pageAlert.text = message
        pageAlert.visible = true
        pageAlertTimer.restart()
    }

    function openPanel() {
        root.panelError = ""
        root.panelMode = "form"
        root.refreshRecipients()

        // Poste transmis depuis la carte réseau / la liste (bouton "Envoyer
        // un fichier" sur un poste précis) : priorité sur le correspondant
        // courant, consommé une seule fois.
        if (root.preselectedPeer && root.selectedRecipients.length === 0) {
            const wanted = root.preselectedPeer
            const wantedId = wanted.machineId || wanted.id || ""
            for (let p = 0; p < root.recipients.length; ++p) {
                const candidate = root.recipients[p]
                if ((wantedId && candidate.machineId === wantedId)
                        || (wanted.address && candidate.address === wanted.address)) {
                    root.toggleRecipient(candidate)
                    break
                }
            }
            root.preselectedPeer = null
        } else if (root.currentGroup && root.selectedRecipients.length === 0 && root.currentGroup.peerMachineId.length > 0) {
            // Depuis un correspondant selectionne : on le propose comme destinataire.
            for (let i = 0; i < root.recipients.length; ++i) {
                if (root.recipients[i].machineId === root.currentGroup.peerMachineId) {
                    root.toggleRecipient(root.recipients[i])
                    break
                }
            }
        }
        root.panelOpen = true
    }

    function closePanel() {
        root.panelOpen = false
    }

    function clearSelection() {
        root.selectedFilePaths = []
        root.selectedFolderPath = ""
    }

    function acceptDroppedUrls(urls) {
        const paths = []
        for (let i = 0; i < urls.length; ++i) {
            paths.push(urls[i].toString())
        }
        if (paths.length === 0) return
        root.selectedFilePaths = paths
        root.selectedFolderPath = ""
        root.openPanel()
    }

    function retryTransfer(transferKey) {
        if (root.context && !root.context.retryTransfer(transferKey)) {
            root.showError(qsTr("Impossible de relancer le transfert."))
        }
    }

    // Donnees du transfert affiche dans TransferDetailsDialog (null =
    // ferme). Objet fileRow() existant : aucune donnee supplementaire.
    property var detailsItem: null

    function showDetails(row) {
        // Copie simple : le modele continue d'etre mis a jour en place
        // (progression), la fiche affiche donc l'etat au moment de l'ouverture.
        root.detailsItem = {
            fileName: row.fileName, peerLabel: row.peerLabel, incoming: row.incoming,
            state: row.state, statusText: row.statusText, errorString: row.errorString,
            percent: row.percent, bytesTransferred: row.bytesTransferred,
            totalBytes: row.totalBytes, filePath: row.filePath, timestamp: row.timestamp,
            transferKey: row.transferKey
        }
        detailsDialog.open()
    }

    function openLocation(filePath) {
        if (root.context && !root.context.openFileLocation(filePath)) {
            root.showError(qsTr("Impossible d'ouvrir l'emplacement du fichier."))
        }
    }

    function openDownloads() {
        if (root.context && !root.context.openDownloadsFolder()) {
            root.showError(qsTr("Impossible d'ouvrir le dossier de réception."))
        }
    }

    function sendSelected() {
        if (!root.context || root.selectedRecipients.length === 0) return
        root.panelError = ""

        // Transferts deja connus : isole ceux de cet envoi dans le suivi.
        const known = {}
        const before = root.context.activeTransfers || []
        for (let k = 0; k < before.length; ++k) known[before[k].transferKey] = true
        root.knownKeysBeforeSend = known

        // Boucle destinataires x (fichiers ou dossier) : chaque combinaison est
        // un appel sendFile()/sendFolder() distinct, mis en file cote
        // TransferService pour sa propre destination (aucun changement backend).
        let failedCount = 0
        let totalAttempts = 0

        for (let r = 0; r < root.selectedRecipients.length; ++r) {
            const recipient = root.selectedRecipients[r]

            if (root.selectedFolderPath.length > 0) {
                totalAttempts++
                const ok = root.context.sendFolder(root.selectedFolderPath, recipient.address, recipient.port, recipient.machineId)
                if (!ok) failedCount++
            } else {
                for (let i = 0; i < root.selectedFilePaths.length; ++i) {
                    totalAttempts++
                    const ok2 = root.context.sendFile(root.selectedFilePaths[i], recipient.address, recipient.port, recipient.machineId)
                    if (!ok2) failedCount++
                }
            }
        }

        if (failedCount === 0) {
            root.clearSelection()
            root.panelMode = "sending"
        } else if (failedCount === totalAttempts) {
            root.panelError = qsTr("Impossible d'envoyer le(s) fichier(s).")
        } else {
            root.panelError = qsTr("%1 envoi(s) sur %2 ont échoué.").arg(failedCount).arg(totalAttempts)
            root.clearSelection()
            root.panelMode = "sending"
        }
    }

    // Transferts lances par le dernier envoi (suivi du panneau).
    readonly property var batchItems: {
        if (root.panelMode !== "sending") return []
        return root.allTransfers.filter(function(t) {
            return !root.knownKeysBeforeSend[t.transferKey] && !root.isIncomingItem(t)
        }).map(function(t) {
            return {
                fileName: t.fileName || "",
                state: root.stateOf(t),
                statusText: t.statusText || "",
                percent: Math.round(t.percent || 0),
                bytesTransferred: t.bytesTransferred || 0,
                totalBytes: t.totalBytes || 0,
                peerName: t.peerName || "",
                peerUserName: t.peerUserName || "",
                peerAddress: t.peerAddress || ""
            }
        })
    }

    // ---- fiche "Detail" (maquette .acts, sans comportement dans la demo
    // HTML : n'affiche que des champs deja connus du transfert) ----
    TransferDetailsDialog {
        id: detailsDialog
        parent: root
        item: root.detailsItem
        canRetry: root.detailsItem !== null && root.detailsItem.state === "failed" && !root.detailsItem.incoming
        canOpen: root.detailsItem !== null && root.detailsItem.state === "completed"
        onClosed: root.detailsItem = null
        onRetryRequested: if (root.detailsItem) root.retryTransfer(root.detailsItem.transferKey)
        onOpenRequested: if (root.detailsItem) root.openLocation(root.detailsItem.filePath)
    }

    // ---- dialogues ----
    FileDialog {
        id: fileDialog
        title: qsTr("Choisir un ou plusieurs fichiers à envoyer")
        fileMode: FileDialog.OpenFiles
        onAccepted: {
            const paths = []
            for (let i = 0; i < selectedFiles.length; ++i) {
                paths.push(selectedFiles[i].toString())
            }
            root.selectedFilePaths = paths
            root.selectedFolderPath = ""
        }
    }

    FolderDialog {
        id: sendFolderDialog
        title: qsTr("Choisir un dossier à envoyer")
        onAccepted: {
            root.selectedFolderPath = selectedFolder.toString()
            root.selectedFilePaths = []
        }
    }

    Shortcut {
        sequence: "Escape"
        enabled: root.visible && (root.panelOpen || root.openedPeerKey.length > 0)
        onActivated: {
            if (root.panelOpen) root.closePanel()
            else root.openedPeerKey = ""
        }
    }

    // ---- Sidebar + Header partages du Dashboard ----
    DashboardShell {
        id: shell
        anchors.fill: parent

        activeRoute: "transfer"
        sidebarCompact: root.isCompactWidth
        username: root.currentUsername
        serverStatus: root.serverStatusLabel
        serverStatusColor: root.serverStatusColorValue
        activeTransfers: root.activeTransferCount
        isAdmin: root.isAdmin
        breadcrumb: root.currentGroup
                    ? qsTr("LocaLink / Transferts / ") + root.currentGroup.peerLabel
                    : qsTr("LocaLink / Transferts")

        onHomeRequested: root.backRequested()
        onChatRequested: root.chatRequested()
        onTransferRequested: { /* deja sur Transferts */ }
        onFoldersRequested: root.foldersRequested()
        onCallRequested: root.callRequested()
        onPeersRequested: root.peersRequested()
        onAdminRequested: root.adminRequested()
        onSettingsRequested: root.settingsRequested()
        onLogoutRequested: root.logoutRequested()
        // "LocaLink" -> retour a l'accueil ; "Transferts" (quand un
        // correspondant est ouvert) -> referme le filtre correspondant,
        // sans quitter l'ecran (arborescence : LocaLink / Transferts / X).
        onBreadcrumbSegmentClicked: function(index, label) {
            if (index === 0) root.backRequested()
            else root.openedPeerKey = ""
        }

        Item {
            id: page
            Layout.fillWidth: true
            Layout.fillHeight: true

            readonly property bool narrow: width < 720
            readonly property bool phone: root.width <= 720
            readonly property bool wideToolbar: width >= 940
            // Grille des correspondants (maquette) : 4 colonnes, 3 a <= 1200,
            // 2 a <= 900, 1 a <= 720 (largeur de fenetre).
            readonly property int peerColumns: root.width <= 720 ? 1 : (root.width <= 900 ? 2 : (root.width <= 1200 ? 3 : 4))
            readonly property int peerCardWidth: Math.max(120, Math.floor((width - 48 - (peerColumns - 1) * 12) / peerColumns))
            readonly property int peerCardHeight: root.width <= 720 ? 60 : 100

            Rectangle {
                anchors.fill: parent
                color: Theme.dashboardBackground
            }

            // Depot de fichiers n'importe ou sur la page : ouvre le panneau.
            DropArea {
                id: pageDrop
                anchors.fill: parent
                onDropped: function(drop) {
                    if (drop.hasUrls && drop.urls.length > 0) {
                        root.acceptDroppedUrls(drop.urls)
                    }
                }
            }

            // Page defilante (maquette .scroll : padding 8 24 24).
            Flickable {
                id: pageScroll
                anchors.fill: parent
                contentWidth: width
                contentHeight: pageColumn.implicitHeight + 24
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                ColumnLayout {
                id: pageColumn
                x: 24
                width: pageScroll.width - 48
                spacing: 0

                // ---- Titre de page (meme rythme que "Bonjour, ..." du Dashboard) ----
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 62
                    Layout.topMargin: 8

                    ColumnLayout {
                        anchors.left: parent.left
                        anchors.right: newTransferBtn.left
                        anchors.rightMargin: 16
                        anchors.bottom: parent.bottom
                        clip: true
                        spacing: 5

                        Label {
                            Layout.fillWidth: true
                            text: qsTr("Transfert de fichiers")
                            color: Theme.dashboardInk
                            font.pixelSize: 26
                            font.weight: Font.Bold
                            font.family: Theme.fontFamily
                            font.letterSpacing: -0.52
                            lineHeight: 32
                            lineHeightMode: Text.FixedHeight
                            elide: Text.ElideRight
                        }

                        Label {
                            Layout.fillWidth: true
                            text: qsTr("Envoyez et suivez vos fichiers sur votre réseau local.")
                            color: Theme.dashboardInkSecondary
                            font.pixelSize: 14
                            font.family: Theme.fontFamily
                            elide: Text.ElideRight
                        }
                    }

                    DashboardButton {
                        id: newTransferBtn
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        variant: "primary"
                        iconPath: Icons.plus
                        text: qsTr("Nouveau transfert")
                        onClicked: root.openPanel()
                    }
                }

                // ---- Bloc d'erreur (maquette .err) : filtre "Echoues" ----
                TransferErrorBanner {
                    visible: root.activeFilter === "failed" && root.latestFailure !== null
                    Layout.fillWidth: true
                    Layout.topMargin: 12
                    title: qsTr("Échec du transfert")
                    message: root.latestFailure
                             ? qsTr("Le fichier n'a pas pu être envoyé à %1.").arg(root.latestFailure.peer) : ""
                    onRetryRequested: {
                        if (root.latestFailure) root.retryTransfer(root.latestFailure.key)
                    }
                }

                // ---- Etat vide (maquette .empty : flex column, align-items
                // center, text-align center, padding 48px 16px) ----
                Rectangle {
                    visible: root.peerGroups.length === 0 && !root.loading
                    Layout.fillWidth: true
                    Layout.topMargin: 20
                    implicitHeight: emptyColumn.implicitHeight + 96
                    radius: Theme.radiusMedium
                    color: Theme.dashboardSurface
                    border.width: 1
                    border.color: Theme.dashboardLine

                    ColumnLayout {
                        id: emptyColumn
                        anchors.centerIn: parent
                        width: Math.min(parent.width - 32, 360)
                        spacing: 6

                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: 56
                            Layout.preferredHeight: 56
                            radius: 16
                            color: Theme.dashboardPrimarySoft
                            LineIcon {
                                anchors.centerIn: parent
                                size: 26
                                strokeWidth: 1.75
                                color: Theme.dashboardPrimary
                                path: "M7 4 3 8l4 4 M3 8h14 M17 20l4-4-4-4 M21 16H7"
                            }
                        }
                        Label {
                            Layout.fillWidth: true
                            Layout.topMargin: 4
                            horizontalAlignment: Text.AlignHCenter
                            text: qsTr("Aucun transfert")
                            color: Theme.dashboardInk
                            font.pixelSize: 14
                            font.weight: Font.Bold
                            font.family: Theme.fontFamily
                        }
                        Label {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            text: qsTr("Les fichiers envoyés et reçus apparaîtront ici.")
                            color: Theme.dashboardInkTertiary
                            font.pixelSize: 12
                            font.family: Theme.fontFamily
                        }
                        DashboardButton {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.topMargin: 4
                            variant: "soft"
                            controlHeight: 32
                            text: qsTr("Envoyer un fichier")
                            onClicked: root.openPanel()
                        }
                    }
                }

                // ---- Barre d'outils : filtres | recherche, affichage, actions ----
                GridLayout {
                    id: toolbar
                    visible: root.peerGroups.length > 0 || root.loading
                    Layout.fillWidth: true
                    Layout.topMargin: 16
                    columns: page.wideToolbar ? 2 : 1
                    columnSpacing: 16
                    rowSpacing: 8

                    Row {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 8

                        Repeater {
                            model: [
                                { key: "all",      label: qsTr("Tous") },
                                { key: "active",   label: qsTr("En cours") },
                                { key: "received", label: qsTr("Reçus") },
                                { key: "sent",     label: qsTr("Envoyés") },
                                { key: "failed",   label: qsTr("Échoués") }
                            ]

                            delegate: Rectangle {
                                id: chip
                                readonly property bool isActive: root.activeFilter === modelData.key
                                readonly property bool hovered: chipMouse.containsMouse
                                readonly property int count: root.filterCounts[modelData.key]
                                // Texte sur fond primaire (primaryText de la maquette, clair et sombre).
                                readonly property color activeText: Theme.darkMode ? Theme.dashboardBackground
                                                                                   : Theme.dashboardPrimaryText

                                height: 28
                                width: chipRow.implicitWidth + 24
                                radius: Theme.radiusPill
                                color: chip.isActive ? Theme.dashboardPrimary : Theme.dashboardSurface
                                border.width: 1
                                border.color: chip.isActive ? Theme.dashboardPrimary
                                              : (chip.hovered ? Theme.dashboardLineStrong : Theme.dashboardLine)
                                Behavior on color { ColorAnimation { duration: 100 } }

                                Accessible.role: Accessible.Button
                                Accessible.name: modelData.label

                                Row {
                                    id: chipRow
                                    anchors.centerIn: parent
                                    spacing: 6

                                    Label {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: modelData.label
                                        color: chip.isActive ? chip.activeText : Theme.dashboardInkSecondary
                                        font.pixelSize: 12
                                        font.weight: chip.isActive ? Font.DemiBold : Font.Medium
                                        font.family: Theme.fontFamily
                                    }
                                    Label {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: chip.count
                                        opacity: chip.isActive ? 0.75 : 1
                                        color: chip.isActive ? chip.activeText : Theme.dashboardInkTertiary
                                        font.pixelSize: 11
                                        font.family: Theme.fontFamily
                                    }
                                }

                                MouseArea {
                                    id: chipMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.activeFilter = modelData.key
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: !page.wideToolbar
                        Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                        spacing: 8

                        Rectangle {
                            Layout.fillWidth: !page.wideToolbar
                            Layout.preferredWidth: page.wideToolbar ? 250 : -1
                            Layout.preferredHeight: 32
                            radius: Theme.radiusSmall
                            color: Theme.dashboardSurface
                            border.width: searchField.activeFocus ? 2 : 1
                            border.color: searchField.activeFocus ? Theme.dashboardPrimary : Theme.dashboardLine

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 4
                                spacing: 8

                                LineIcon {
                                    size: 15
                                    strokeWidth: 2
                                    color: Theme.dashboardInkTertiary
                                    path: Icons.search
                                }

                                TextField {
                                    id: searchField
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    placeholderText: qsTr("Rechercher un transfert...")
                                    placeholderTextColor: Theme.dashboardInkTertiary
                                    text: root.searchText
                                    onTextChanged: root.searchText = text
                                    color: Theme.dashboardInk
                                    font.pixelSize: 12
                                    font.family: Theme.fontFamily
                                    selectByMouse: true
                                    leftPadding: 0
                                    rightPadding: 0
                                    background: Rectangle { color: "transparent" }
                                }

                                DashboardButton {
                                    visible: root.searchText.length > 0
                                    variant: "ghost"
                                    iconOnly: true
                                    controlHeight: 24
                                    iconPath: Icons.close
                                    tooltip: qsTr("Effacer la recherche")
                                    onClicked: root.searchText = ""
                                }
                            }
                        }

                        Row {
                            spacing: 6

                            DashboardButton {
                                variant: "ghost"
                                iconOnly: true
                                controlHeight: 32
                                iconPath: Icons.list
                                active: root.viewMode === "list"
                                tooltip: qsTr("Affichage en liste")
                                onClicked: root.viewMode = "list"
                            }
                            DashboardButton {
                                variant: "ghost"
                                iconOnly: true
                                controlHeight: 32
                                iconPath: Icons.grid
                                active: root.viewMode === "grid"
                                tooltip: qsTr("Affichage en grille")
                                onClicked: root.viewMode = "grid"
                            }
                        }

                        DashboardButton {
                            variant: "ghost"
                            iconOnly: true
                            controlHeight: 32
                            iconPath: Icons.folderOpen
                            tooltip: qsTr("Ouvrir le dossier de réception")
                            onClicked: root.openDownloads()
                        }
                    }
                }

                // ---- Correspondants ----
                RowLayout {
                    visible: toolbar.visible && (root.filteredPeerGroups.length > 0 || root.loading)
                    Layout.fillWidth: true
                    Layout.topMargin: 20
                    Layout.preferredHeight: 28
                    spacing: 8

                    Label {
                        text: qsTr("Correspondants")
                        color: Theme.dashboardInk
                        font.pixelSize: 15
                        font.weight: Font.Bold
                        font.family: Theme.fontFamily
                    }
                    Label {
                        text: root.filteredPeerGroups.length
                        color: Theme.dashboardInkTertiary
                        font.pixelSize: 12
                        font.family: Theme.fontFamily
                    }

                    Item { Layout.fillWidth: true }

                    DashboardButton {
                        visible: root.openedPeerKey.length > 0
                        variant: "ghost"
                        controlHeight: 28
                        text: qsTr("Afficher tous")
                        onClicked: root.openedPeerKey = ""
                    }
                }

                GridLayout {
                    id: peerGrid
                    visible: toolbar.visible && (root.filteredPeerGroups.length > 0 || root.loading)
                    Layout.fillWidth: true
                    Layout.topMargin: 8
                    columns: page.peerColumns
                    columnSpacing: 12
                    rowSpacing: 12

                    Repeater {
                        model: root.loading ? 0 : peerModel

                        delegate: TransferPeerCard {
                            Layout.preferredWidth: page.peerCardWidth
                            Layout.preferredHeight: page.peerCardHeight
                            showLastTransfer: !page.phone
                            peerLabel: model.peerLabel
                            isUser: model.isUser
                            metaText: {
                                const n = root.countLabel(model.visibleCount)
                                const rel = root.formatRelative(model.lastTimestamp, root.nowTick)
                                return rel.length > 0 ? n + " · " + rel : n
                            }
                            activeCount: model.activeCount
                            lastFileName: model.lastFileName
                            lastState: model.lastState
                            lastStatusText: model.lastStatusText
                            selected: model.peerKey === root.openedPeerKey
                            presenceStatus: model.presenceStatus
                            onClicked: root.openedPeerKey = (root.openedPeerKey === model.peerKey ? "" : model.peerKey)
                        }
                    }

                    // Chargement : cartes squelettes (4, comme la maquette).
                    Repeater {
                        model: root.loading ? 4 : 0

                        delegate: Rectangle {
                            Layout.preferredWidth: page.peerCardWidth
                            Layout.preferredHeight: page.peerCardHeight
                            radius: Theme.radiusMedium
                            color: Theme.dashboardSurface
                            border.width: 1
                            border.color: Theme.dashboardLine
                            SkeletonLine { x: 12; y: 12; width: 36; height: 36; radius: 18 }
                            SkeletonLine { x: 58; y: 16; width: (parent.width - 70) * 0.7 }
                            SkeletonLine { x: 58; y: 36; width: (parent.width - 70) * 0.45 }
                            SkeletonLine { visible: !page.phone; x: 12; y: 72; width: parent.width - 24 }
                        }
                    }
                }

                // ---- Transferts ----
                RowLayout {
                    visible: toolbar.visible
                    Layout.fillWidth: true
                    Layout.topMargin: 20
                    Layout.preferredHeight: 28
                    spacing: 8

                    Label {
                        text: qsTr("Transferts")
                        color: Theme.dashboardInk
                        font.pixelSize: 15
                        font.weight: Font.Bold
                        font.family: Theme.fontFamily
                    }
                    Label {
                        text: qsTr("%1 en cours").arg(root.activeTransferCount)
                        color: Theme.dashboardInkTertiary
                        font.pixelSize: 12
                        font.family: Theme.fontFamily
                    }

                    Rectangle {
                        visible: !!root.currentGroup
                        implicitWidth: selectedChipRow.implicitWidth + 18
                        implicitHeight: 24
                        radius: Theme.radiusPill
                        color: Theme.dashboardPrimarySoft

                        Row {
                            id: selectedChipRow
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: 10
                            spacing: 4

                            Label {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.currentGroup ? root.currentGroup.peerLabel : ""
                                color: Theme.dashboardPrimary
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                font.family: Theme.fontFamily
                                elide: Text.ElideRight
                                width: Math.min(implicitWidth, 200)
                            }
                            DashboardButton {
                                anchors.verticalCenter: parent.verticalCenter
                                variant: "ghost"
                                iconOnly: true
                                controlHeight: 20
                                iconPath: Icons.close
                                tooltip: qsTr("Afficher tous les correspondants")
                                onClicked: root.openedPeerKey = ""
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    Label {
                        visible: !page.narrow && root.totalTransferredBytes > 0
                        text: qsTr("%1 transférés").arg(root.formatBytes(root.totalTransferredBytes))
                        color: Theme.dashboardInkTertiary
                        font.pixelSize: 12
                        font.family: Theme.fontFamily
                    }
                }

                Rectangle {
                    id: tablePanel
                    visible: toolbar.visible
                    Layout.fillWidth: true
                    Layout.topMargin: 8
                    Layout.preferredHeight: panelColumn.implicitHeight + 2
                    radius: Theme.radiusMedium
                    color: Theme.dashboardSurface
                    border.width: 1
                    border.color: Theme.dashboardLine

                    readonly property bool showDateColumn: width >= 780
                    readonly property bool showSizeColumn: width >= 600
                    readonly property int sizeColumnWidth: 84
                    readonly property int statusColumnWidth: 124
                    readonly property int dateColumnWidth: 128
                    // Elargie pour accueillir le bouton texte "Details" en plus
                    // de Reessayer / Ouvrir l'emplacement (maquette .acts).
                    readonly property int actionsColumnWidth: 168
                    readonly property bool hasRows: fileModel.count > 0 && !root.loading

                    ColumnLayout {
                        id: panelColumn
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 1
                        spacing: 0

                        // En-tete des colonnes (liste)
                        RowLayout {
                            visible: root.viewMode === "list" && tablePanel.hasRows
                            Layout.fillWidth: true
                            Layout.preferredHeight: 34
                            Layout.leftMargin: 16
                            Layout.rightMargin: 16
                            spacing: 12

                            Label {
                                Layout.fillWidth: true
                                Layout.leftMargin: 44
                                text: qsTr("Nom")
                                color: Theme.dashboardInkTertiary
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                font.family: Theme.fontFamily
                            }
                            Label {
                                visible: tablePanel.showSizeColumn
                                Layout.preferredWidth: tablePanel.sizeColumnWidth
                                text: qsTr("Taille")
                                color: Theme.dashboardInkTertiary
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                font.family: Theme.fontFamily
                            }
                            Label {
                                Layout.preferredWidth: tablePanel.statusColumnWidth
                                text: qsTr("Statut")
                                color: Theme.dashboardInkTertiary
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                font.family: Theme.fontFamily
                            }
                            Label {
                                visible: tablePanel.showDateColumn
                                Layout.preferredWidth: tablePanel.dateColumnWidth
                                text: qsTr("Date")
                                color: Theme.dashboardInkTertiary
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                font.family: Theme.fontFamily
                            }
                            Item { Layout.preferredWidth: tablePanel.actionsColumnWidth }
                        }

                        // ---- Liste (le panneau prend la hauteur de son contenu,
                        // la page defile : comme la maquette) ----
                        Column {
                            id: listRows
                            visible: root.viewMode === "list" && tablePanel.hasRows
                            Layout.fillWidth: true
                            spacing: 0

                            Repeater {
                                model: fileModel

                                delegate: TransferFileRow {
                                    width: listRows.width
                                    showTopLine: true
                                    fileName: model.fileName
                                    peerLabel: model.peerLabel
                                    incoming: model.incoming
                                    transferState: model.state
                                    statusText: model.statusText
                                    errorString: model.errorString
                                    percent: model.percent
                                    sizeText: root.formatBytes(model.totalBytes)
                                    progressText: qsTr("%1 sur %2").arg(root.formatBytes(model.bytesTransferred)).arg(root.formatBytes(model.totalBytes))
                                    dateText: root.formatRowDate(model.timestamp, root.nowTick)
                                    showSizeColumn: tablePanel.showSizeColumn
                                    showDateColumn: tablePanel.showDateColumn
                                    sizeColumnWidth: tablePanel.sizeColumnWidth
                                    statusColumnWidth: tablePanel.statusColumnWidth
                                    dateColumnWidth: tablePanel.dateColumnWidth
                                    actionsColumnWidth: tablePanel.actionsColumnWidth
                                    canRetry: model.state === "failed" && !model.incoming
                                    canOpen: model.state === "completed"
                                    onRetryRequested: root.retryTransfer(model.transferKey)
                                    onOpenRequested: root.openLocation(model.filePath)
                                    onDetailsRequested: root.showDetails(model)
                                }
                            }
                        }

                        // ---- Grille : minmax(200px, 1fr), gap 12, padding 12 ----
                        GridLayout {
                            id: gridRows
                            visible: root.viewMode === "grid" && tablePanel.hasRows
                            Layout.fillWidth: true
                            Layout.margins: 12
                            readonly property real avail: tablePanel.width - 2 - 24
                            columns: Math.max(1, Math.floor((avail + 12) / 212))
                            columnSpacing: 12
                            rowSpacing: 12

                            Repeater {
                                model: fileModel

                                delegate: Rectangle {
                                    id: tile
                                    Layout.preferredWidth: Math.floor((gridRows.avail - (gridRows.columns - 1) * 12) / gridRows.columns)
                                    Layout.preferredHeight: 132
                                    Layout.alignment: Qt.AlignTop

                                    readonly property bool isActive: model.state === "in_progress"
                                    readonly property bool hovered: tileHover.hovered

                                    radius: Theme.radiusMedium
                                    color: tile.hovered ? Theme.dashboardSurfaceAlt : Theme.dashboardSurface
                                    border.width: 1
                                    border.color: tile.hovered ? Theme.dashboardLineStrong : Theme.dashboardLine

                                    HoverHandler { id: tileHover }

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: 12
                                        spacing: 6

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 8

                                            FileTypeIcon {
                                                fileName: model.fileName
                                                size: 32
                                            }
                                            Item { Layout.fillWidth: true }

                                            DashboardButton {
                                                visible: model.state === "failed" && !model.incoming
                                                variant: "soft"
                                                controlHeight: 28
                                                text: qsTr("Réessayer")
                                                onClicked: root.retryTransfer(model.transferKey)
                                            }
                                            DashboardButton {
                                                visible: model.state === "completed"
                                                variant: "ghost"
                                                iconOnly: true
                                                controlHeight: 28
                                                iconPath: Icons.folderOpen
                                                tooltip: qsTr("Ouvrir l'emplacement")
                                                opacity: tile.hovered || activeFocus ? 1 : 0
                                                Behavior on opacity { NumberAnimation { duration: 120 } }
                                                onClicked: root.openLocation(model.filePath)
                                            }
                                            DashboardButton {
                                                variant: "ghost"
                                                iconOnly: true
                                                controlHeight: 28
                                                iconPath: Icons.alertCircle
                                                tooltip: qsTr("Détails")
                                                opacity: tile.hovered || activeFocus ? 1 : 0
                                                Behavior on opacity { NumberAnimation { duration: 120 } }
                                                onClicked: root.showDetails(model)
                                            }
                                        }

                                        Label {
                                            Layout.fillWidth: true
                                            text: model.fileName
                                            color: Theme.dashboardInk
                                            font.pixelSize: 12
                                            font.weight: Font.Bold
                                            font.family: Theme.fontFamily
                                            elide: Text.ElideRight
                                            maximumLineCount: 1

                                            ToolTip.visible: truncated && tile.hovered
                                            ToolTip.text: model.fileName
                                            ToolTip.delay: 600
                                        }

                                        Label {
                                            Layout.fillWidth: true
                                            text: root.formatBytes(model.totalBytes) + " · " + model.peerLabel
                                            color: Theme.dashboardInkTertiary
                                            font.pixelSize: 11
                                            font.family: Theme.fontFamily
                                            elide: Text.ElideRight
                                            maximumLineCount: 1
                                        }

                                        Item { Layout.fillHeight: true }

                                        Rectangle {
                                            visible: tile.isActive
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 6
                                            radius: 3
                                            color: Theme.dashboardLine
                                            Rectangle {
                                                anchors.left: parent.left
                                                anchors.top: parent.top
                                                anchors.bottom: parent.bottom
                                                width: parent.width * Math.max(0, Math.min(100, model.percent)) / 100
                                                radius: 3
                                                color: Theme.dashboardPrimary
                                            }
                                        }
                                        TransferStatusBadge {
                                            visible: !tile.isActive
                                            transferState: model.state
                                            text: model.statusText
                                        }
                                    }
                                }
                            }
                        }

                        // ---- Aucun resultat (maquette .empty) ----
                        // Item englobant + largeur plafonnée centrée par ancrage,
                        // comme l'etat vide principal ci-dessus (Rectangle "Aucun
                        // transfert") - un ColumnLayout en Layout.fillWidth ne
                        // suffit pas a centrer ses enfants sur toute la largeur
                        // du panneau (Layout.alignment seul reste collé a gauche).
                        Item {
                            visible: fileModel.count === 0 && !root.loading
                            Layout.fillWidth: true
                            Layout.topMargin: 48
                            Layout.bottomMargin: 48
                            implicitHeight: noResultsColumn.implicitHeight

                            ColumnLayout {
                                id: noResultsColumn
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: Math.min(parent.width - 32, 360)
                                spacing: 6

                                Rectangle {
                                    Layout.alignment: Qt.AlignHCenter
                                    Layout.preferredWidth: 56
                                    Layout.preferredHeight: 56
                                    radius: 16
                                    color: Theme.dashboardPrimarySoft
                                    LineIcon {
                                        anchors.centerIn: parent
                                        size: 26
                                        strokeWidth: 1.9
                                        color: Theme.dashboardPrimary
                                        path: Icons.upload
                                    }
                                }
                                Label {
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignHCenter
                                    text: qsTr("Aucun transfert ne correspond")
                                    color: Theme.dashboardInk
                                    font.pixelSize: 14
                                    font.weight: Font.Bold
                                    font.family: Theme.fontFamily
                                }
                                Label {
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignHCenter
                                    wrapMode: Text.WordWrap
                                    text: qsTr("Modifiez la recherche ou les filtres.")
                                    color: Theme.dashboardInkTertiary
                                    font.pixelSize: 12
                                    font.family: Theme.fontFamily
                                }
                                DashboardButton {
                                    visible: root.hasActiveFilters()
                                    Layout.alignment: Qt.AlignHCenter
                                    Layout.topMargin: 4
                                    variant: "soft"
                                    controlHeight: 32
                                    text: qsTr("Réinitialiser les filtres")
                                    onClicked: root.resetFilters()
                                }
                            }
                        }

                        SkeletonRows {
                            visible: root.loading
                            Layout.fillWidth: true
                            Layout.leftMargin: 16
                            Layout.rightMargin: 16
                            variant: "transfer"
                            count: 4
                        }
                    }
                }
                }
            }

            // ---- alerte (retry / ouverture d'emplacement / rejet d'envoi) ----
            InlineAlert {
                id: pageAlert
                visible: false
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.topMargin: 12
                width: Math.min(560, parent.width - 48)
                z: 40
                onCloseRequested: pageAlert.visible = false

                Timer {
                    id: pageAlertTimer
                    interval: 6000
                    onTriggered: pageAlert.visible = false
                }
            }

            // ---- indication de depot ----
            Rectangle {
                visible: pageDrop.containsDrag
                anchors.fill: parent
                anchors.margins: 12
                z: 35
                radius: Theme.radiusMedium
                color: Qt.rgba(Theme.dashboardPrimarySoft.r, Theme.dashboardPrimarySoft.g, Theme.dashboardPrimarySoft.b, 0.92)
                border.width: 2
                border.color: Theme.dashboardPrimary

                Column {
                    anchors.centerIn: parent
                    spacing: 10

                    LineIcon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        size: 32
                        strokeWidth: 1.75
                        color: Theme.dashboardPrimary
                        path: Icons.upload
                    }
                    Label {
                        text: qsTr("Déposez vos fichiers pour les envoyer")
                        color: Theme.dashboardPrimary
                        font.pixelSize: 16
                        font.weight: Font.Bold
                        font.family: Theme.fontFamily
                    }
                }
            }

            // ---- panneau "Nouveau transfert" (voile + volet lateral) ----
            Item {
                id: panelHost
                anchors.fill: parent
                z: 30
                visible: root.panelOpen || panel.x < panelHost.width

                Rectangle {
                    anchors.fill: parent
                    color: Theme.overlay
                    opacity: root.panelOpen ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 160 } }

                    MouseArea {
                        anchors.fill: parent
                        enabled: root.panelOpen
                        onClicked: root.closePanel()
                    }
                }

                NewTransferPanel {
                    id: panel
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    // Volet lateral a partir de 720 px, tiroir pleine largeur en dessous.
                    width: page.narrow ? panelHost.width : Math.min(420, panelHost.width - 48)
                    x: root.panelOpen ? panelHost.width - width : panelHost.width
                    Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                    recipients: root.recipients
                    offlineRecipients: root.offlineRecipients
                    selectedFilePaths: root.selectedFilePaths
                    selectedFolderPath: root.selectedFolderPath
                    selectedRecipients: root.selectedRecipients
                    mode: root.panelMode
                    batchItems: root.batchItems
                    errorText: root.panelError

                    onCloseRequested: root.closePanel()
                    onBrowseFilesRequested: fileDialog.open()
                    onBrowseFolderRequested: sendFolderDialog.open()
                    onClearSelectionRequested: root.clearSelection()
                    onRecipientToggled: function(recipient) { root.toggleRecipient(recipient) }
                    onRefreshRecipientsRequested: root.refreshRecipients()
                    onSendRequested: root.sendSelected()
                    onNewTransferRequested: root.openPanel()
                    onErrorDismissed: root.panelError = ""
                }
            }
        }
    }
}
