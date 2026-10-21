import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Shapes
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

    // Fil d'Ariane de la barre superieure globale (AppShell) :
    // "Transferts / <correspondant ouvert>" ; un clic sur "Transferts"
    // referme le correspondant sans quitter l'ecran.
    readonly property string breadcrumbLeaf: root.currentGroup ? root.currentGroup.peerLabel : ""
    function breadcrumbRootClicked() { root.showAllExchanges("all") }
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
    signal conversationRequested(int conversationId)

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
        if (!root.election) return Theme.successColor
        if (root.election.roleLabel === "TEMP_SERVER") return Theme.warningColor
        return Theme.successColor
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
        case "failed": return root.stateOf(item) === "failed" || root.stateOf(item) === "interrupted"
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
        return root.matchesFilter(item)
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

    // true : vue « Tous les echanges » ; false : un dossier est ouvert (le
    // plus recent par defaut).
    property bool allSelected: false
    // Echange deplie (detail) dans le dossier ouvert.
    property string expandedKey: ""
    // Recherche dans la liste des dossiers.
    property string dossierSearch: ""

    function openDossier(key) {
        root.allSelected = false
        root.openedPeerKey = key
        root.activeFilter = "all"
        root.expandedKey = ""
    }
    function showAllExchanges(filter) {
        root.allSelected = true
        root.openedPeerKey = ""
        root.activeFilter = filter || "all"
        root.expandedKey = ""
    }
    function ensureDossier() {
        if (root.openedPeerKey.length > 0 && !root.currentGroup)
            root.openedPeerKey = ""
        if (!root.allSelected && root.openedPeerKey.length === 0 && root.peerGroups.length > 0)
            root.openedPeerKey = root.peerGroups[0].peerKey
    }
    onPeerGroupsChanged: root.ensureDossier()
    onDossierSearchChanged: Qt.callLater(root.rebuildModels)

    // ---- Chiffres du jour ----
    function isToday(iso) {
        if (!iso) return false
        const d = new Date(iso)
        const n = root.nowTick
        return d.getFullYear() === n.getFullYear() && d.getMonth() === n.getMonth() && d.getDate() === n.getDate()
    }
    readonly property var todayStats: {
        const s = { received: 0, receivedBytes: 0, sent: 0, sentBytes: 0, failed: 0, remaining: 0, running: 0, runningIn: null }
        for (let i = 0; i < root.allTransfers.length; i++) {
            const t = root.allTransfers[i]
            const st = root.stateOf(t)
            const inc = root.isIncomingItem(t)
            if (st === "failed" || st === "interrupted") s.failed++
            if (st === "in_progress") {
                s.running++
                s.remaining += Math.max(0, (t.totalBytes || 0) - (t.bytesTransferred || 0))
                if (inc && !s.runningIn) s.runningIn = t
            }
            if (!root.isToday(t.timestamp)) continue
            if (inc && st === "completed") { s.received++; s.receivedBytes += t.totalBytes || 0 }
            if (!inc && (st === "completed" || st === "in_progress")) { s.sent++; s.sentBytes += t.totalBytes || 0 }
        }
        return s
    }

    // Jour d'un echange : « Aujourd'hui », « Hier », sinon la date.
    function dayLabel(iso) {
        if (!iso) return ""
        const d = new Date(iso)
        if (isNaN(d.getTime())) return ""
        const n = root.nowTick
        const a = new Date(n.getFullYear(), n.getMonth(), n.getDate())
        const b = new Date(d.getFullYear(), d.getMonth(), d.getDate())
        const diff = Math.round((a - b) / 86400000)
        if (diff === 0) return qsTr("Aujourd'hui")
        if (diff === 1) return qsTr("Hier")
        const s = d.toLocaleDateString(Qt.locale(), "dddd d MMMM")
        return s.charAt(0).toUpperCase() + s.slice(1)
    }
    function timeOf(iso) {
        if (!iso) return ""
        const d = new Date(iso)
        return isNaN(d.getTime()) ? "" : Qt.formatTime(d, "HH:mm")
    }

    // Conversation avec la personne d'un dossier (meme logique que HomeView).
    function openConversationWith(group) {
        if (!group || typeof messagingContext === "undefined" || !messagingContext || !group.peerUserUuid) {
            root.chatRequested()
            return
        }
        const users = messagingContext.availableUsers() || []
        for (let i = 0; i < users.length; i++) {
            if (users[i].userUuid === group.peerUserUuid) {
                const id = messagingContext.startConversationWith(users[i].userId)
                if (id > 0) {
                    root.conversationRequested(id)
                    return
                }
            }
        }
        root.chatRequested()
    }

    // ---- modeles de liste (synchronises en place) ----
    ListModel { id: peerModel }
    ListModel { id: fileModel }

    function peerRow(g) {
        const last = g.items.length > 0 ? g.items[0] : null
        let active = 0, failed = 0, received = 0, volume = 0
        for (let i = 0; i < g.items.length; i++) {
            const st = root.stateOf(g.items[i])
            if (st === "in_progress") active++
            if (st === "failed" || st === "interrupted") failed++
            if (root.isIncomingItem(g.items[i])) received++
            volume += st === "completed" ? (g.items[i].totalBytes || 0) : (g.items[i].bytesTransferred || 0)
        }
        return {
            peerKey: g.peerKey,
            peerLabel: g.peerLabel,
            isUser: g.peerUserName.length > 0,
            machineName: last ? (last.peerName || g.peerAddress) : g.peerAddress,
            peerAddress: g.peerAddress,
            visibleCount: root.filteredCountFor(g),
            totalCount: g.items.length,
            receivedCount: received,
            sentCount: g.items.length - received,
            volume: volume,
            failedCount: failed,
            lastIncoming: last ? root.isIncomingItem(last) : false,
            lastPercent: last ? Math.round(last.percent || 0) : 0,
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
            timestamp: it.timestamp || "",
            dayLabel: root.dayLabel(it.timestamp),
            time: root.timeOf(it.timestamp)
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
        const q = root.dossierSearch.trim().toLowerCase()
        const groups = root.peerGroups.filter(function(g) {
            return q.length === 0 || g.peerLabel.toLowerCase().indexOf(q) >= 0
                   || (g.peerAddress || "").indexOf(q) >= 0
        })
        root.syncModel(peerModel, groups.map(function(g) { return root.peerRow(g) }), "peerKey")
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
        enabled: root.visible && (root.panelOpen || root.expandedKey.length > 0)
        onActivated: {
            if (root.panelOpen) root.closePanel()
            else root.expandedKey = ""
        }
    }

    // ======================================================================
    // Mise en page Ligne claire : dossiers par correspondant
    //
    //   [surtitre · phrase-titre · actions ............ 4 chiffres serif]
    //   [Dossiers (liste)  ][Dossier ouvert : en-tete, bilan, depot,
    //   [                  ] filtres, correspondance recus | envoyes   ]
    // ======================================================================
    readonly property real pageW: width - 2 * Theme.pagePadding
    readonly property bool heroWide: pageW > 1180
    readonly property bool foldersWide: pageW > 900
    readonly property real listWidth: pageW > 1240 ? 320 : 284

    function esc(t) {
        return String(t === undefined || t === null ? "" : t)
               .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    }
    function initials(label) {
        const w = (label || "?").split(/[\s-]+/).filter(function(x) { return x.length > 0 })
        return ((w[0] || "?").charAt(0) + (w.length > 1 ? w[1].charAt(0) : "")).toUpperCase()
    }
    function presenceKind(s) {
        s = (s || "").toLowerCase()
        if (s === "away" || s === "busy") return s
        return s.length === 0 || s === "offline" ? "offline" : "online"
    }
    function presenceWord(s) {
        switch (root.presenceKind(s)) {
        case "away": return qsTr("Absent")
        case "busy": return qsTr("Occupé")
        case "offline": return qsTr("Hors ligne")
        }
        return qsTr("En ligne")
    }
    function lastLine(row) {
        if (!row.lastFileName) return ""
        const st = row.lastState === "in_progress" ? row.lastPercent + " %"
                 : row.lastState === "completed" ? qsTr("terminé")
                 : row.lastState === "cancelled" ? qsTr("annulé")
                 : row.lastState === "interrupted" ? qsTr("interrompu") : qsTr("échec")
        return (row.lastIncoming ? "↓ " + qsTr("reçu") : "↑ " + qsTr("envoyé")) + " · " + row.lastFileName + " · " + st
    }
    function whenShort(iso) {
        if (!iso) return ""
        return root.isToday(iso) ? root.timeOf(iso) : root.dayLabel(iso).split(" ")[0].toLowerCase()
    }

    readonly property string currentPresence: root.currentGroup
                                              ? root.presenceFor(root.currentGroup.peerMachineId, root.currentGroup.peerAddress) : ""
    readonly property var currentRow: {
        if (!root.currentGroup) return null
        for (let i = 0; i < peerModel.count; i++)
            if (peerModel.get(i).peerKey === root.currentGroup.peerKey)
                return peerModel.get(i)
        return root.peerRow(root.currentGroup)
    }
    readonly property string firstName: root.currentGroup ? root.currentGroup.peerLabel.split(" ")[0] : ""
    readonly property bool laneLayout: !root.allSelected && dossierCol.width > 560

    // Onglet de filtre (souligne d'encre).
    component FilterTab: AbstractButton {
        id: ft
        property string key: "all"
        property int count: 0
        property bool danger: false
        readonly property bool current: root.activeFilter === ft.key
        hoverEnabled: true
        focusPolicy: Qt.StrongFocus
        padding: 0
        implicitHeight: 30
        implicitWidth: ftRow.implicitWidth
        Accessible.role: Accessible.PageTab
        Accessible.name: ft.text
        onClicked: { root.activeFilter = ft.key; root.expandedKey = "" }
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        background: Item {
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 2
                color: ft.current ? Theme.ruleInk : "transparent"
            }
            Rectangle {
                anchors.fill: parent
                anchors.margins: -3
                color: "transparent"
                radius: Theme.radiusSheet
                border.width: ft.visualFocus ? 2 : 0
                border.color: Theme.focusRing
            }
        }
        contentItem: Item {
            Row {
                id: ftRow
                spacing: 6
                anchors.top: parent.top
                anchors.topMargin: 3
                Text {
                    text: ft.text
                    color: ft.current || ft.hovered ? Theme.ink : Theme.ink3
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(12.5)
                    font.weight: ft.current ? Theme.weightSemibold : Theme.weightMedium
                }
                Text {
                    visible: ft.count > 0
                    text: ft.count
                    color: ft.danger ? Theme.dangerInk : Theme.ink3
                    font.family: Theme.fontFamilySerif
                    font.pixelSize: Theme.fs(12)
                    font.weight: Theme.weightBold
                }
            }
        }
    }

    // Monogramme d'un dossier : initiales sur disque d'encre (personne) ou
    // icone de poste (pas de compte), pastille de presence.
    component Monogram: Item {
        id: mg
        property string label: ""
        property bool isUser: true
        property string presence: ""
        property real size: 40
        implicitWidth: size
        implicitHeight: size
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: mg.isUser ? Theme.ink : "transparent"
            border.width: mg.isUser ? 0 : 1
            border.color: Theme.lineStrong
            Text {
                visible: mg.isUser
                anchors.centerIn: parent
                text: root.initials(mg.label)
                color: Theme.inkOnInk
                font.family: Theme.fontFamilySerif
                font.pixelSize: Math.round(mg.size * 0.35)
                font.weight: Theme.weightBold
            }
            LineIcon {
                visible: !mg.isUser
                anchors.centerIn: parent
                path: Icons.monitor
                size: Math.round(mg.size * 0.44)
                strokeWidth: 1.6
                color: Theme.ink2
            }
        }
        Rectangle {
            x: mg.width - width + 2
            y: mg.height - height + 2
            width: 14
            height: 14
            radius: 7
            color: Theme.bg
            StateGlyph { anchors.centerIn: parent; kind: root.presenceKind(mg.presence); size: 10 }
        }
    }

    Item {
        id: page
        anchors.fill: parent
        readonly property bool narrow: width < 720

        Rectangle { anchors.fill: parent; color: Theme.bg }

        // Depot de fichiers n'importe ou sur la page : ouvre le volet, avec
        // le correspondant du dossier ouvert comme destinataire.
        DropArea {
            id: pageDrop
            anchors.fill: parent
            onDropped: function(drop) {
                if (drop.hasUrls && drop.urls.length > 0)
                    root.acceptDroppedUrls(drop.urls)
            }
        }

        Flickable {
            id: pageScroll
            anchors.fill: parent
            contentWidth: width
            contentHeight: pageColumn.y + pageColumn.implicitHeight + 24
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            ColumnLayout {
                id: pageColumn
                x: Theme.pagePadding
                y: Theme.compact ? 16 : 20
                width: pageScroll.width - 2 * Theme.pagePadding
                spacing: 20

                // ---- En-tete --------------------------------------------
                GridLayout {
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
                            text: {
                                const d = root.nowTick.toLocaleDateString(Qt.locale(), "dddd d MMMM yyyy")
                                return d + ((typeof settingsModel !== "undefined" && settingsModel && settingsModel.machineName.length > 0)
                                            ? " · " + settingsModel.machineName : "")
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: root.totalFileCount === 0 ? qsTr("Aucun échange pour l'instant.")
                                  : root.todayStats.running === 0 ? qsTr("Aucun échange en cours.")
                                  : root.todayStats.running === 1 ? qsTr("<b>1</b> échange en cours.")
                                  : qsTr("<b>%1</b> échanges en cours.").arg(root.todayStats.running)
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
                                width: Math.min(implicitWidth, parent.width)
                                height: Math.max(implicitHeight, heroActions.implicitHeight)
                                verticalAlignment: Text.AlignVCenter
                                textFormat: Text.StyledText
                                wrapMode: Text.WordWrap
                                color: Theme.ink2
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(14.5)
                                text: {
                                    const s = root.todayStats
                                    if (root.totalFileCount === 0)
                                        return qsTr("Envoyez un premier fichier : chaque personne avec qui vous échangez aura son dossier, envois et réceptions réunis.")
                                    let t = ""
                                    if (s.runningIn)
                                        t += qsTr("<b>%1</b> vous envoie %2. ").arg(root.esc(s.runningIn.peerUserName || s.runningIn.peerName || s.runningIn.peerAddress))
                                                                                .arg(root.esc(s.runningIn.fileName))
                                    if (s.running > 0)
                                        t += qsTr("Il reste %1 à transférer. ").arg(root.formatBytes(s.remaining))
                                    if (s.failed > 0)
                                        t += "<b><font color=\"" + Theme.dangerInk + "\">"
                                             + (s.failed > 1 ? qsTr("%1 échanges à reprendre.").arg(s.failed) : qsTr("1 échange à reprendre."))
                                             + "</font></b>"
                                    return t.length > 0 ? t : qsTr("Tout est à jour.")
                                }
                            }
                            Row {
                                id: heroActions
                                spacing: 8
                                AppButton {
                                    variant: "ink"
                                    iconPath: "M12 19.5v-15 M5.5 11 12 4.5 18.5 11"
                                    text: qsTr("Nouveau transfert")
                                    onClicked: root.openPanel()
                                }
                                AppButton {
                                    variant: "line"
                                    iconPath: Icons.folder
                                    text: qsTr("Dossier de réception")
                                    onClicked: root.openDownloads()
                                }
                            }
                        }
                    }

                    // Quatre chiffres : ouvrent « Tous les echanges » filtre.
                    Item {
                        Layout.alignment: root.heroWide ? (Qt.AlignRight | Qt.AlignBottom) : Qt.AlignLeft
                        Layout.fillWidth: !root.heroWide
                        implicitWidth: figRow.implicitWidth
                        implicitHeight: figRow.implicitHeight + (root.heroWide ? 0 : 12)
                        Rectangle { visible: !root.heroWide; width: parent.width; height: 1; color: Theme.line }
                        Row {
                            id: figRow
                            y: root.heroWide ? 0 : 12
                            width: root.heroWide ? implicitWidth : parent.width
                            Repeater {
                                model: [
                                    { key: "all", label: qsTr("Dossiers"), value: root.peerGroups.length,
                                      ctx: root.peerGroups.length ? qsTr("personnes et postes") : qsTr("aucun") },
                                    { key: "received", label: qsTr("Reçus aujourd'hui"), value: root.todayStats.received,
                                      ctx: root.todayStats.received ? root.formatBytes(root.todayStats.receivedBytes) : qsTr("aucun") },
                                    { key: "sent", label: qsTr("Envoyés aujourd'hui"), value: root.todayStats.sent,
                                      ctx: root.todayStats.sent ? root.formatBytes(root.todayStats.sentBytes) : qsTr("aucun") },
                                    { key: "failed", label: qsTr("À reprendre"), value: root.todayStats.failed,
                                      ctx: root.todayStats.failed ? qsTr("échec ou interruption") : qsTr("aucun") }
                                ]
                                delegate: Item {
                                    id: fig
                                    required property var modelData
                                    required property int index
                                    width: root.heroWide ? sf.width + (index === 0 ? 0 : 22) + (index === 3 ? 0 : 22) : figRow.width / 4
                                    height: sf.implicitHeight
                                    Rectangle { visible: fig.index > 0; width: 1; height: parent.height; color: Theme.line }
                                    SerifFigure {
                                        id: sf
                                        x: fig.index === 0 ? 0 : (root.heroWide ? 22 : 18)
                                        width: Math.max(implicitWidth, 110)
                                        label: fig.modelData.label
                                        value: String(fig.modelData.value)
                                        context: fig.modelData.ctx
                                        attention: fig.modelData.key === "failed" && fig.modelData.value > 0
                                        valueSize: root.heroWide && root.height >= 720 ? Theme.fontSizeFigure : Theme.fs(32)
                                        onClicked: root.showAllExchanges(fig.modelData.key)
                                    }
                                }
                            }
                        }
                    }
                }

                // ---- Dossiers | dossier ouvert ----------------------------
                Rectangle { Layout.fillWidth: true; Layout.topMargin: -4; Layout.preferredHeight: 2; color: Theme.ruleInk }

                GridLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: -20
                    columns: root.foldersWide ? 2 : 1
                    columnSpacing: 0
                    rowSpacing: 0

                    // -- Liste des dossiers --------------------------------
                    ColumnLayout {
                        id: dossierList
                        Layout.preferredWidth: root.foldersWide ? root.listWidth : -1
                        Layout.fillWidth: !root.foldersWide
                        Layout.alignment: Qt.AlignTop
                        Layout.topMargin: 14
                        Layout.rightMargin: root.foldersWide ? 18 : 0
                        spacing: 2

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.bottomMargin: 8
                            CapsLabel { text: qsTr("Dossiers"); Layout.fillWidth: true }
                            Text {
                                text: root.peerGroups.length || ""
                                color: Theme.ink3
                                font.family: Theme.fontFamilySerif
                                font.pixelSize: Theme.fs(16)
                                font.weight: Theme.weightBold
                            }
                        }
                        Rectangle {
                            visible: root.peerGroups.length > 0
                            Layout.fillWidth: true
                            Layout.preferredHeight: 32
                            Layout.bottomMargin: 6
                            radius: Theme.radiusSheet
                            color: "transparent"
                            border.width: 1
                            border.color: dossierFind.activeFocus ? Theme.ink : Theme.line
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 8
                                spacing: 7
                                LineIcon { path: Icons.search; size: 14; strokeWidth: 1.8; color: Theme.ink3 }
                                TextField {
                                    id: dossierFind
                                    Layout.fillWidth: true
                                    placeholderText: qsTr("Personne ou poste…")
                                    placeholderTextColor: Theme.ink3
                                    color: Theme.ink
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(12.5)
                                    background: Item {}
                                    leftPadding: 0
                                    rightPadding: 0
                                    selectByMouse: true
                                    Accessible.name: qsTr("Rechercher un dossier")
                                    onTextChanged: root.dossierSearch = text
                                }
                            }
                        }
                        Text {
                            visible: root.peerGroups.length === 0
                            Layout.fillWidth: true
                            text: qsTr("Chaque personne avec qui vous échangez aura ici son dossier, envois et réceptions réunis.")
                            color: Theme.ink3
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(12.5)
                            wrapMode: Text.WordWrap
                        }

                        GridLayout {
                            Layout.fillWidth: true
                            columns: root.foldersWide || page.narrow ? 1 : 2
                            columnSpacing: 12
                            rowSpacing: 2

                            // « Tous les echanges »
                            AbstractButton {
                                id: allEntry
                                visible: root.peerGroups.length > 0
                                Layout.fillWidth: true
                                Layout.columnSpan: parent.columns
                                Layout.bottomMargin: 4
                                implicitHeight: 60
                                hoverEnabled: true
                                focusPolicy: Qt.TabFocus
                                Accessible.name: qsTr("Tous les échanges")
                                onClicked: root.showAllExchanges("all")
                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                                background: Rectangle {
                                    radius: Theme.radiusSheet
                                    color: root.allSelected ? Theme.surface0 : (allEntry.hovered ? Theme.selectWash : "transparent")
                                    border.width: root.allSelected ? 1 : (allEntry.visualFocus ? 2 : 0)
                                    border.color: allEntry.visualFocus ? Theme.focusRing : Theme.line
                                    Rectangle { visible: root.allSelected; x: -1; y: 8; width: 3; height: parent.height - 16; color: Theme.ruleInk }
                                }
                                contentItem: RowLayout {
                                    spacing: 12
                                    Rectangle {
                                        Layout.leftMargin: 10
                                        Layout.preferredWidth: 40
                                        Layout.preferredHeight: 40
                                        radius: 20
                                        color: "transparent"
                                        border.width: 1
                                        border.color: Theme.lineStrong
                                        LineIcon { anchors.centerIn: parent; path: Icons.exchange; size: 17; strokeWidth: 1.6; color: Theme.ink2 }
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 1
                                        Text { Layout.fillWidth: true; text: qsTr("Tous les échanges"); color: Theme.ink; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13.5); font.weight: Theme.weightSemibold }
                                        Text {
                                            Layout.fillWidth: true
                                            text: qsTr("%1 échanges · %2 dossiers").arg(root.totalFileCount).arg(root.peerGroups.length)
                                            color: Theme.ink3
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fs(12)
                                        }
                                    }
                                }
                            }

                            Repeater {
                                model: peerModel
                                delegate: AbstractButton {
                                    id: dos
                                    required property int index
                                    required property var model
                                    readonly property bool on: !root.allSelected && dos.model.peerKey === root.openedPeerKey
                                    Layout.fillWidth: true
                                    implicitHeight: dosRow.implicitHeight + 20
                                    hoverEnabled: true
                                    focusPolicy: Qt.TabFocus
                                    Accessible.role: Accessible.Button
                                    Accessible.name: qsTr("Dossier de %1, %2 échange(s)").arg(dos.model.peerLabel).arg(dos.model.totalCount)
                                    onClicked: root.openDossier(dos.model.peerKey)
                                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                                    background: Rectangle {
                                        radius: Theme.radiusSheet
                                        color: dos.on ? Theme.surface0 : (dos.hovered ? Theme.selectWash : "transparent")
                                        border.width: dos.on ? 1 : (dos.visualFocus ? 2 : 0)
                                        border.color: dos.visualFocus ? Theme.focusRing : Theme.line
                                        Rectangle { visible: dos.on; x: -1; y: 8; width: 3; height: parent.height - 16; color: Theme.ruleInk }
                                    }
                                    contentItem: RowLayout {
                                        id: dosRow
                                        spacing: 12
                                        Monogram {
                                            Layout.leftMargin: 10
                                            label: dos.model.peerLabel
                                            isUser: dos.model.isUser
                                            presence: dos.model.presenceStatus
                                        }
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.rightMargin: 10
                                            spacing: 1
                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 8
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: dos.model.peerLabel
                                                    color: Theme.ink
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: Theme.fs(13.5)
                                                    font.weight: Theme.weightSemibold
                                                    elide: Text.ElideRight
                                                }
                                                Text {
                                                    text: root.whenShort(dos.model.lastTimestamp)
                                                    color: Theme.ink3
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: Theme.fs(11.5)
                                                    font.features: ({ "tnum": 1 })
                                                }
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                text: root.lastLine(dos.model)
                                                color: Theme.ink3
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.fs(12)
                                                elide: Text.ElideRight
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                textFormat: Text.StyledText
                                                text: (dos.model.totalCount > 1 ? qsTr("%1 échanges").arg(dos.model.totalCount) : qsTr("1 échange"))
                                                      + (dos.model.activeCount > 0 ? " · <b><font color=\"" + Theme.navActiveInk + "\">"
                                                                                     + qsTr("%1 en cours").arg(dos.model.activeCount) + "</font></b>" : "")
                                                      + (dos.model.failedCount > 0 ? " · <b><font color=\"" + Theme.dangerInk + "\">"
                                                                                     + qsTr("%1 à reprendre").arg(dos.model.failedCount) + "</font></b>" : "")
                                                color: Theme.ink3
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.fs(11.5)
                                                elide: Text.ElideRight
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Dossier de reception
                        Rectangle { Layout.fillWidth: true; Layout.topMargin: 12; Layout.preferredHeight: 1; color: Theme.line }
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: 8
                            Text {
                                Layout.fillWidth: true
                                text: qsTr("Fichiers reçus")
                                color: Theme.ink3
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(12)
                            }
                            TextLink { text: qsTr("Ouvrir le dossier"); fontSize: Theme.fs(12); onClicked: root.openDownloads() }
                        }
                    }

                    // -- Dossier ouvert / tous les echanges ----------------------
                    Item {
                        id: dossierCol
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignTop
                        Layout.minimumHeight: Math.max(dossierList.implicitHeight, root.totalFileCount > 0 ? 420 : 160)
                        implicitHeight: dossierInner.implicitHeight + 18

                        // Filet vertical entre la liste et le dossier.
                        Rectangle {
                            visible: root.foldersWide
                            width: 1
                            height: Math.max(parent.height, dossierList.height)
                            color: Theme.line
                        }
                        Rectangle {
                            visible: !root.foldersWide
                            width: parent.width
                            height: 1
                            y: 4
                            color: Theme.line
                        }

                        ColumnLayout {
                            id: dossierInner
                            x: root.foldersWide ? (root.pageW > 1240 ? 28 : 22) : 0
                            y: root.foldersWide ? 16 : 20
                            width: parent.width - x
                            spacing: 0

                            // Etat vide general
                            ColumnLayout {
                                visible: root.totalFileCount === 0
                                Layout.fillWidth: true
                                Layout.topMargin: 24
                                spacing: 6
                                Text {
                                    text: qsTr("Aucun dossier pour l'instant.")
                                    color: Theme.ink
                                    font.family: Theme.fontFamilySerif
                                    font.pixelSize: Theme.fs(26)
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: qsTr("Dès votre premier envoi ou votre première réception, un dossier sera créé pour la personne concernée.")
                                    color: Theme.ink3
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(13)
                                    wrapMode: Text.WordWrap
                                }
                            }

                            // En-tete du dossier (ou de « Tous les echanges »)
                            GridLayout {
                                visible: root.totalFileCount > 0 && (root.allSelected || root.currentGroup !== null)
                                Layout.fillWidth: true
                                columns: dossierCol.width > 640 ? 2 : 1
                                columnSpacing: 20
                                rowSpacing: 12

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 16
                                    Monogram {
                                        visible: !root.allSelected && root.currentGroup !== null
                                        size: 56
                                        label: root.currentGroup ? root.currentGroup.peerLabel : ""
                                        isUser: !!root.currentGroup && root.currentGroup.peerUserName.length > 0
                                        presence: root.currentPresence
                                    }
                                    Rectangle {
                                        visible: root.allSelected
                                        Layout.preferredWidth: 56
                                        Layout.preferredHeight: 56
                                        radius: 28
                                        color: "transparent"
                                        border.width: 1
                                        border.color: Theme.lineStrong
                                        LineIcon { anchors.centerIn: parent; path: Icons.exchange; size: 22; strokeWidth: 1.6; color: Theme.ink2 }
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2
                                        CapsLabel { visible: !root.allSelected; text: qsTr("Dossier de correspondance") }
                                        Text {
                                            Layout.fillWidth: true
                                            text: root.allSelected ? qsTr("Tous les échanges") : (root.currentGroup ? root.currentGroup.peerLabel : "")
                                            color: Theme.ink
                                            font.family: Theme.fontFamilySerif
                                            font.pixelSize: Theme.fs(28)
                                            font.weight: Theme.weightBold
                                            elide: Text.ElideRight
                                            Accessible.role: Accessible.Heading
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            textFormat: Text.StyledText
                                            color: Theme.ink2
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fs(13)
                                            elide: Text.ElideRight
                                            text: {
                                                if (root.allSelected)
                                                    return qsTr("%1 dossiers · %2 reçus · %3 envoyés").arg(root.peerGroups.length)
                                                           .arg(root.filterCounts.received).arg(root.filterCounts.sent)
                                                const r = root.currentRow
                                                if (!r) return ""
                                                const machine = r.isUser && r.machineName && r.machineName !== r.peerLabel ? r.machineName + " · " : ""
                                                return machine + (r.peerAddress || "") + " · " + root.presenceWord(root.currentPresence)
                                            }
                                        }
                                    }
                                }
                                Row {
                                    Layout.alignment: dossierCol.width > 640 ? (Qt.AlignRight | Qt.AlignBottom) : Qt.AlignLeft
                                    spacing: 8
                                    AppButton {
                                        variant: "ink"
                                        iconPath: "M12 19.5v-15 M5.5 11 12 4.5 18.5 11"
                                        text: root.allSelected ? qsTr("Nouveau transfert") : qsTr("Envoyer à %1").arg(root.firstName)
                                        enabled: root.allSelected || root.presenceKind(root.currentPresence) !== "offline"
                                        tooltip: enabled ? "" : qsTr("Ce poste est hors ligne")
                                        onClicked: root.openPanel()
                                    }
                                    AppButton {
                                        visible: !root.allSelected && !!root.currentGroup && root.currentGroup.peerUserName.length > 0
                                        variant: "line"
                                        iconPath: Icons.messageCircle
                                        text: qsTr("Message")
                                        onClicked: root.openConversationWith(root.currentGroup)
                                    }
                                }
                            }

                            // Bilan du dossier
                            Rectangle {
                                visible: !root.allSelected && root.currentRow !== null && root.totalFileCount > 0
                                Layout.fillWidth: true
                                Layout.topMargin: 14
                                implicitHeight: figs.implicitHeight + 20
                                color: "transparent"
                                Rectangle { width: parent.width; height: 1; color: Theme.line }
                                Rectangle { width: parent.width; height: 1; y: parent.height - 1; color: Theme.line }
                                Flow {
                                    id: figs
                                    y: 10
                                    width: parent.width
                                    spacing: 22
                                    Repeater {
                                        model: root.currentRow ? [
                                            { v: root.currentRow.totalCount, k: qsTr("échanges"), c: Theme.ink },
                                            { v: root.currentRow.receivedCount, k: qsTr("reçus"), c: Theme.ink },
                                            { v: root.currentRow.sentCount, k: qsTr("envoyés"), c: Theme.ink },
                                            { v: root.formatBytes(root.currentRow.volume), k: qsTr("transférés"), c: Theme.ink },
                                            { v: root.currentRow.activeCount, k: qsTr("en cours"), c: Theme.navActiveInk, hide: root.currentRow.activeCount === 0 },
                                            { v: root.currentRow.failedCount, k: qsTr("à reprendre"), c: Theme.dangerInk, hide: root.currentRow.failedCount === 0 }
                                        ] : []
                                        delegate: Row {
                                            required property var modelData
                                            visible: !modelData.hide
                                            spacing: 5
                                            Text {
                                                anchors.baseline: parent.children[1].baseline
                                                text: modelData.v
                                                color: modelData.c
                                                font.family: Theme.fontFamilySerif
                                                font.pixelSize: Theme.fs(17)
                                                font.weight: Theme.weightBold
                                                font.features: ({ "tnum": 1 })
                                            }
                                            Text {
                                                text: modelData.k
                                                color: Theme.ink3
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.fs(12.5)
                                            }
                                        }
                                    }
                                }
                            }

                            // Depot propre au dossier
                            Rectangle {
                                id: dropBand
                                visible: !root.allSelected && root.currentGroup !== null && root.totalFileCount > 0
                                Layout.fillWidth: true
                                Layout.topMargin: 14
                                implicitHeight: 42
                                radius: Theme.radiusSheet
                                color: dropHover.hovered ? Theme.selectWash : "transparent"
                                // Bordure en tirets : une zone de depot, pas un bouton.
                                Shape {
                                    anchors.fill: parent
                                    preferredRendererType: Shape.CurveRenderer
                                    ShapePath {
                                        fillColor: "transparent"
                                        strokeColor: dropHover.hovered ? Theme.ink3 : Theme.lineStrong
                                        strokeWidth: 1.5
                                        strokeStyle: ShapePath.DashLine
                                        dashPattern: [3, 2.5]
                                        startX: 1; startY: 1
                                        PathLine { x: dropBand.width - 1; y: 1 }
                                        PathLine { x: dropBand.width - 1; y: dropBand.height - 1 }
                                        PathLine { x: 1; y: dropBand.height - 1 }
                                        PathLine { x: 1; y: 1 }
                                    }
                                }
                                HoverHandler { id: dropHover; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: { root.openPanel(); fileDialog.open() } }
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 14
                                    anchors.rightMargin: 14
                                    spacing: 10
                                    LineIcon { path: "M12 19.5v-15 M5.5 11 12 4.5 18.5 11"; size: 17; strokeWidth: 1.7; color: Theme.ink2 }
                                    Text {
                                        Layout.fillWidth: true
                                        textFormat: Text.StyledText
                                        text: qsTr("Déposez des fichiers dans ce dossier pour les envoyer à <b>%1</b>.")
                                              .arg(root.esc(root.currentGroup ? root.currentGroup.peerLabel : ""))
                                        color: Theme.ink3
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fs(12.5)
                                        elide: Text.ElideRight
                                    }
                                }
                            }

                            // Filtres
                            Item {
                                visible: root.totalFileCount > 0
                                Layout.fillWidth: true
                                Layout.topMargin: 14
                                implicitHeight: 31
                                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
                                Row {
                                    spacing: 18
                                    readonly property var items: root.allSelected ? root.allTransfers : (root.currentGroup ? root.currentGroup.items : [])
                                    FilterTab { key: "all"; text: qsTr("Tout"); count: parent.items.length }
                                    FilterTab { key: "received"; text: qsTr("Reçus"); count: parent.items.filter(function(t) { return root.isIncomingItem(t) }).length }
                                    FilterTab { key: "sent"; text: qsTr("Envoyés"); count: parent.items.filter(function(t) { return !root.isIncomingItem(t) }).length }
                                    FilterTab {
                                        key: "failed"; text: qsTr("À reprendre"); danger: true
                                        count: parent.items.filter(function(t) { const s = root.stateOf(t); return s === "failed" || s === "interrupted" }).length
                                    }
                                    FilterTab { key: "active"; text: qsTr("En cours"); count: parent.items.filter(function(t) { return root.stateOf(t) === "in_progress" }).length; visible: count > 0 }
                                }
                            }

                            // Sens des colonnes (fil a deux colonnes)
                            RowLayout {
                                visible: root.laneLayout && fileModel.count > 0
                                Layout.fillWidth: true
                                Layout.topMargin: 10
                                Row {
                                    Layout.fillWidth: true
                                    spacing: 6
                                    LineIcon { anchors.verticalCenter: parent.verticalCenter; path: "M12 4.5v15 M18.5 13 12 19.5 5.5 13"; size: 13; strokeWidth: 2; color: Theme.ink3 }
                                    CapsLabel { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Reçus de %1").arg(root.firstName) }
                                }
                                Row {
                                    spacing: 6
                                    CapsLabel { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Envoyés par vous") }
                                    LineIcon { anchors.verticalCenter: parent.verticalCenter; path: "M12 19.5v-15 M5.5 11 12 4.5 18.5 11"; size: 13; strokeWidth: 2; color: Theme.ink3 }
                                }
                            }

                            Text {
                                visible: root.totalFileCount > 0 && fileModel.count === 0
                                Layout.topMargin: 16
                                text: qsTr("Aucun échange ne correspond.")
                                color: Theme.ink3
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(12.5)
                            }

                            // La correspondance : recus a gauche, envoyes a droite, par jour.
                            Item {
                                Layout.fillWidth: true
                                Layout.topMargin: 4
                                implicitHeight: exchanges.implicitHeight

                                Rectangle {
                                    visible: root.laneLayout && fileModel.count > 0
                                    x: Math.round(parent.width / 2)
                                    width: 1
                                    height: parent.height
                                    color: Theme.line
                                }

                                Column {
                                    id: exchanges
                                    width: parent.width
                                    spacing: 8

                                    Repeater {
                                        model: fileModel
                                        delegate: Column {
                                            id: exRow
                                            required property int index
                                            required property var model
                                            // Le modele peut etre vide pendant sa reconstruction.
                                            readonly property bool newDay: {
                                                const prev = index > 0 && index - 1 < fileModel.count ? fileModel.get(index - 1) : null
                                                return !prev || prev.dayLabel !== model.dayLabel
                                            }
                                            width: exchanges.width
                                            spacing: 8

                                            // Separateur de jour
                                            Item {
                                                visible: exRow.newDay
                                                width: parent.width
                                                height: 30
                                                Rectangle {
                                                    anchors.centerIn: root.laneLayout ? parent : undefined
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: dayText.implicitWidth + (root.laneLayout ? 20 : 0)
                                                    height: 20
                                                    radius: 10
                                                    color: Theme.bg
                                                    border.width: root.laneLayout ? 1 : 0
                                                    border.color: Theme.line
                                                    CapsLabel {
                                                        id: dayText
                                                        anchors.centerIn: parent
                                                        text: exRow.model.dayLabel
                                                        color: Theme.ink2
                                                    }
                                                }
                                            }

                                            Item {
                                                width: parent.width
                                                height: card.height
                                                TransferExchange {
                                                    id: card
                                                    readonly property real laneW: (parent.width - 28) / 2
                                                    width: root.laneLayout ? laneW : parent.width
                                                    x: root.laneLayout && !exRow.model.incoming ? parent.width - width : 0
                                                    row: exRow.model
                                                    laneLayout: root.laneLayout
                                                    showPeer: root.allSelected
                                                    timeText: exRow.model.time
                                                    dateText: exRow.model.dayLabel + ", " + exRow.model.time
                                                    expanded: root.expandedKey === exRow.model.transferKey
                                                    onToggled: root.expandedKey = (root.expandedKey === exRow.model.transferKey ? "" : exRow.model.transferKey)
                                                    onRetryRequested: root.retryTransfer(exRow.model.transferKey)
                                                    onOpenLocationRequested: root.openLocation(exRow.model.filePath)
                                                    onResendRequested: root.openPanel()
                                                }
                                                // Liaison au fil central
                                                Rectangle {
                                                    visible: root.laneLayout
                                                    y: 18
                                                    x: exRow.model.incoming ? card.width : parent.width - card.width - 14
                                                    width: 14
                                                    height: 1
                                                    color: Theme.lineStrong
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
            z: 35
            color: Theme.alpha(Theme.bg, 0.88)
            Rectangle {
                anchors.centerIn: parent
                width: Math.min(560, parent.width * 0.8)
                height: dropCol.implicitHeight + 80
                radius: Theme.radiusSheet
                color: Theme.surface0
                border.width: 2
                border.color: Theme.ruleInk
                Column {
                    id: dropCol
                    anchors.centerIn: parent
                    width: parent.width - 48
                    spacing: 8
                    LineIcon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        size: 38
                        strokeWidth: 1.3
                        color: Theme.ink
                        path: "M12 19.5v-15 M5.5 11 12 4.5 18.5 11"
                    }
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: root.currentGroup && !root.allSelected
                              ? qsTr("Déposez pour envoyer à %1").arg(root.currentGroup.peerLabel)
                              : qsTr("Déposez pour envoyer")
                        color: Theme.ink
                        font.family: Theme.fontFamilySerif
                        font.pixelSize: Theme.fs(26)
                        wrapMode: Text.WordWrap
                    }
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: qsTr("Vous confirmerez les destinataires avant l'envoi.")
                        color: Theme.ink3
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(13)
                    }
                }
            }
        }

        // ---- volet « Nouveau transfert » (voile + volet lateral) ----
        Item {
            id: panelHost
            anchors.fill: parent
            z: 30
            visible: root.panelOpen || panel.x < panelHost.width

            Rectangle {
                anchors.fill: parent
                color: Theme.scrim
                opacity: root.panelOpen ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 160 } }
                MouseArea {
                    anchors.fill: parent
                    enabled: root.panelOpen
                    onClicked: root.closePanel()
                }
            }

            TransferComposer {
                id: panel
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: page.narrow ? panelHost.width : Math.min(460, panelHost.width - 48)
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
