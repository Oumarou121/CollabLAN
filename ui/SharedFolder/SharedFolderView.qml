import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Shapes
import QtQuick.Dialogs
import Themes
import "../Components"
import "../Components/icons.js" as Icons
import "../Dashboard/transferFormat.js" as Fmt

/*
 * SharedFolderView - ecran « Dossiers partages » en Ligne claire, meme
 * squelette que Transferts :
 *
 *   [surtitre · phrase-titre · action ................. 4 chiffres serif]
 *   [Dossiers (liste) ][Dossier ouvert : en-tete, bilan, membres,
 *   [                 ] synchronisation, conflits, Fichiers | Historique ]
 *
 * Partager un dossier indexe son contenu sur ce poste (SharedFolderManager)
 * puis FolderSyncService le tient a jour chez les membres. Les fenetres
 * (acces, exclusions, emplacement, invitation, arret du partage) et le volet
 * de creation sont des feuilles posees au-dessus de la page.
 */
Item {
    id: root

    property var context: (typeof sharedFolderContext !== "undefined") ? sharedFolderContext : null

    signal backRequested()
    signal settingsRequested()

    // Fil d'Ariane global (AppShell) : "Dossiers partages / <dossier ouvert>".
    readonly property string breadcrumbLeaf: root.currentFolder ? root.currentFolder.name : ""
    function breadcrumbRootClicked() { root.browsedRelativePath = ""; root.rebuildFileBrowser() }

    // ---- dossier ouvert ----
    property var openedFolderId: -1
    property string openedFolderUuid: ""
    // Dossier a ouvrir a l'arrivee (bandeau de synchronisation « Voir le dossier »).
    property string initialFolderUuid: ""
    property var currentFiles: []
    property var browserItems: []
    // Affichage par tranches : un dossier de milliers de fichiers creait
    // toutes ses lignes d un coup (l ecran se figeait a l ouverture).
    readonly property int browserPage: 200
    property int browserLimit: browserPage
    readonly property var shownBrowserItems: root.browserItems.length > root.browserLimit
                                             ? root.browserItems.slice(0, root.browserLimit) : root.browserItems
    property string browsedRelativePath: ""
    property var currentSyncHistory: []
    property var currentAccess: []
    property var currentExcludes: []
    property string tab: "files"              // "files" | "history"
    property string searchText: ""
    property string viewMode: "list"          // "list" | "grid"

    // Dossiers en cours d'indexation en arriere-plan (indexingStarted ->
    // folderReindexed) : indicateur dans la liste et dans le dossier.
    property var indexingFolderIds: []

    // Conflits du dossier ouvert. Cle : relativePath ; valeur : chemin de la
    // copie mise de cote.
    property var conflictedFiles: ({})

    // Rafales de synchronisation en cours (folderTransferProgress), par uuid.
    property var syncBatches: ({})

    // Invitations recues (dossiers distants sans emplacement), presentees une
    // par une.
    property var pendingShareConfirmations: []

    // ---- liste des dossiers ----
    property var folderRows: []
    property string activeFilter: "all"       // "all" | "mine" | "received" | "todo"
    property string listSearch: ""

    // Feuille ouverte : "" | "access" | "exclusions" | "location" | "remove"
    property string sheet: ""
    property bool composerOpen: false
    property bool composerDone: false
    property string composerError: ""
    property string composerPath: ""
    property var composerUsers: []

    // ======================================================================
    // Utilitaires
    // ======================================================================
    function esc(t) {
        return String(t === undefined || t === null ? "" : t)
               .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    }
    function initials(label) {
        const w = (label || "?").split(/[\s-]+/).filter(function(x) { return x.length > 0 })
        return ((w[0] || "?").charAt(0) + (w.length > 1 ? w[1].charAt(0) : "")).toUpperCase()
    }
    function plural(n, one, many) { return n + " " + (n > 1 ? many : one) }
    function formatBytes(b) { return Fmt.formatBytes(b) }
    function formatCount(n) { return Number(n).toLocaleString(Qt.locale(), "f", 0) }
    function extOf(name) {
        const i = (name || "").lastIndexOf(".")
        return i > 0 ? name.slice(i + 1, i + 5).toUpperCase() : ""
    }
    function dateOf(iso) {
        if (!iso) return null
        const d = new Date(iso)
        return isNaN(d.getTime()) ? null : d
    }
    function dayKey(d) { return d.getFullYear() + "-" + d.getMonth() + "-" + d.getDate() }
    function isSameDay(a, b) { return a && b && root.dayKey(a) === root.dayKey(b) }
    function isYesterday(d) {
        const y = new Date(); y.setDate(y.getDate() - 1)
        return root.isSameDay(d, y)
    }
    // « 14:21 », « hier », « 18 oct. »
    function whenShort(iso) {
        const d = root.dateOf(iso)
        if (!d) return ""
        if (root.isSameDay(d, new Date())) return d.toLocaleTimeString(Qt.locale(), "HH:mm")
        if (root.isYesterday(d)) return qsTr("hier")
        return d.toLocaleDateString(Qt.locale(), d.getFullYear() === new Date().getFullYear() ? "d MMM" : "d MMM yyyy")
    }
    function dayLabel(iso) {
        const d = root.dateOf(iso)
        if (!d) return ""
        if (root.isSameDay(d, new Date())) return qsTr("Aujourd'hui")
        if (root.isYesterday(d)) return qsTr("Hier")
        return d.toLocaleDateString(Qt.locale(), "dddd d MMMM")
    }
    function timeOf(iso) {
        const d = root.dateOf(iso)
        return d ? d.toLocaleTimeString(Qt.locale(), "HH:mm") : ""
    }
    function splitPatterns(text) {
        return (text || "").split(",").map(function(p) { return p.trim() }).filter(function(p) { return p.length > 0 })
    }
    function cleanUrl(url) {
        // "file:///C:/..." (Windows) ou "file:///home/..." : on retire le
        // schema, puis la barre en trop devant une lettre de lecteur.
        let path = decodeURIComponent(url.toString()).replace(/^file:\/\//, "")
        if (/^\/[A-Za-z]:/.test(path))
            path = path.substring(1)
        return path
    }
    readonly property string defaultSharedPath: (typeof settingsModel !== "undefined" && settingsModel && settingsModel.defaultSharedFolderPath)
                                                ? settingsModel.defaultSharedFolderPath : ""

    // ======================================================================
    // Dossiers : lecture du modele, chiffres de l'en-tete
    // ======================================================================
    Instantiator {
        id: folderSource
        model: root.context ? root.context.folderModel : null
        delegate: QtObject {
            required property var folderId
            required property string uuid
            required property string name
            required property string localPath
            required property var ownerId
            required property int fileCount
            required property bool isLocalOrigin
            required property bool hasConflict
            onFileCountChanged: root.scheduleRebuild()
            onHasConflictChanged: root.scheduleRebuild()
            onLocalPathChanged: root.scheduleRebuild()
            onNameChanged: root.scheduleRebuild()
        }
        onObjectAdded: root.scheduleRebuild()
        onObjectRemoved: root.scheduleRebuild()
    }

    property bool rebuildPending: false
    function scheduleRebuild() {
        if (root.rebuildPending) return
        root.rebuildPending = true
        // Premier affichage tout de suite ; ensuite, une rafale de signaux
        // (un par fichier recu) ne reconstruit la liste qu une fois par
        // fenetre de 150 ms.
        if (root.folderRows.length === 0) Qt.callLater(root.rebuildFolders)
        else rebuildTimer.start()
    }
    Timer { id: rebuildTimer; interval: 150; onTriggered: root.rebuildFolders() }

    // Fichiers et historique du dossier ouvert relus au plus une fois par
    // 250 ms pendant une synchronisation (auparavant a chaque fichier recu :
    // tout le dossier etait relu et retrie pour chacun).
    Timer {
        id: openedRefreshTimer
        interval: 250
        onTriggered: { root.refreshFiles(); root.refreshHistory() }
    }
    function scheduleOpenedRefresh() { if (!openedRefreshTimer.running) openedRefreshTimer.start() }

    function rebuildFolders() {
        root.rebuildPending = false
        const ctx = root.context
        const names = {}
        if (ctx) {
            const users = ctx.availableUsers()
            for (let u = 0; u < users.length; u++)
                names[users[u].userId] = users[u].username
        }
        const rows = []
        for (let i = 0; i < folderSource.count; i++) {
            const o = folderSource.objectAt(i)
            if (!o) continue
            const hist = ctx ? ctx.syncHistoryForFolder(o.folderId, 1) : []
            const access = ctx && o.isLocalOrigin ? ctx.accessForFolder(o.folderId) : []
            const conflicts = ctx && o.hasConflict ? ctx.getConflicts(o.folderId).length : 0
            rows.push({
                folderId: o.folderId, uuid: o.uuid, name: o.name, localPath: o.localPath || "",
                ownerId: o.ownerId, ownerName: names[o.ownerId] || "",
                fileCount: o.fileCount, isLocalOrigin: o.isLocalOrigin, hasConflict: o.hasConflict,
                conflictCount: o.hasConflict ? Math.max(1, conflicts) : 0,
                members: access.map(function(a) { return a.userId }),
                lastActivity: hist.length > 0 ? hist[0].createdAt : ""
            })
        }
        rows.sort(function(a, b) {
            if (a.lastActivity !== b.lastActivity) return a.lastActivity < b.lastActivity ? 1 : -1
            return a.name.localeCompare(b.name)
        })
        root.folderRows = rows
        root.ensureFolder()
    }

    function rowFor(folderId) {
        for (let i = 0; i < root.folderRows.length; i++)
            if (root.folderRows[i].folderId === folderId) return root.folderRows[i]
        return null
    }
    readonly property var currentFolder: root.rowFor(root.openedFolderId)
    readonly property bool currentReceived: !!root.currentFolder && !root.currentFolder.isLocalOrigin
    readonly property bool currentNoPath: root.currentReceived && root.currentFolder.localPath.length === 0

    function needsAction(r) { return r.hasConflict || (!r.isLocalOrigin && r.localPath.length === 0) }

    readonly property var stats: {
        const rows = root.folderRows
        const members = {}
        let mine = 0, files = 0, conflicts = 0, noPath = 0
        for (let i = 0; i < rows.length; i++) {
            const r = rows[i]
            if (r.isLocalOrigin) {
                mine++
                r.members.forEach(function(id) { members[id] = true })
            } else if (r.localPath.length === 0) {
                noPath++
            }
            files += r.fileCount
            conflicts += r.conflictCount
        }
        let syncing = 0
        for (const k in root.syncBatches) syncing++
        return { total: rows.length, mine: mine, received: rows.length - mine, files: files,
                 conflicts: conflicts, noPath: noPath, members: Object.keys(members).length, syncing: syncing }
    }

    readonly property var visibleRows: {
        const q = root.listSearch.trim().toLowerCase()
        return root.folderRows.filter(function(r) {
            const f = root.activeFilter === "mine" ? r.isLocalOrigin
                    : root.activeFilter === "received" ? !r.isLocalOrigin
                    : root.activeFilter === "todo" ? root.needsAction(r) : true
            return f && (q.length === 0 || r.name.toLowerCase().indexOf(q) !== -1)
        })
    }

    function batchFor(uuid) { return root.syncBatches[uuid + "|in"] || root.syncBatches[uuid + "|out"] || null }

    // ======================================================================
    // Dossier ouvert : fichiers, historique, acces
    // ======================================================================
    function openFolder(folderId) {
        const r = root.rowFor(folderId)
        if (!r) return
        root.openedFolderId = r.folderId
        root.openedFolderUuid = r.uuid
        root.tab = "files"
        root.searchText = ""
        root.browsedRelativePath = ""
        root.browserLimit = root.browserPage
        root.conflictedFiles = {}
        root.refreshFiles()
        root.refreshHistory()
        root.refreshAccess()
    }

    // Garde un dossier ouvert : le plus recent si aucun (ou s'il a disparu).
    function ensureFolder() {
        if (root.initialFolderUuid.length > 0) {
            const wanted = root.folderRows.filter(function(r) { return r.uuid === root.initialFolderUuid })[0]
            if (wanted) {
                root.initialFolderUuid = ""
                root.openFolder(wanted.folderId)
                return
            }
        }
        if (root.rowFor(root.openedFolderId)) return
        if (root.folderRows.length > 0) root.openFolder(root.folderRows[0].folderId)
        else root.openedFolderId = -1
    }

    function refreshFiles() {
        if (root.context && root.openedFolderId >= 0) {
            root.currentFiles = root.context.filesForFolder(root.openedFolderId)
            const conflicts = root.context.getConflicts(root.openedFolderId)
            const map = {}
            for (let i = 0; i < conflicts.length; i++)
                map[conflicts[i].relativePath] = conflicts[i].conflictPath
            root.conflictedFiles = map
        } else {
            root.currentFiles = []
            root.conflictedFiles = {}
        }
        root.rebuildFileBrowser()
    }

    function refreshHistory() {
        root.currentSyncHistory = (root.context && root.openedFolderId >= 0)
                                  ? root.context.syncHistoryForFolder(root.openedFolderId, 100) : []
    }

    function refreshAccess() {
        if (root.context && root.openedFolderId >= 0 && root.currentFolder && root.currentFolder.isLocalOrigin) {
            root.currentAccess = root.context.accessForFolder(root.openedFolderId)
            root.currentExcludes = root.splitPatterns(root.context.excludePatternsForFolder(root.openedFolderId))
        } else {
            root.currentAccess = []
            root.currentExcludes = []
        }
    }

    function refreshAll() {
        if (root.context) root.context.refresh()
        root.refreshFiles()
        root.refreshHistory()
        root.refreshAccess()
        root.scheduleRebuild()
    }

    // Bilan du dossier ouvert : volume et sous-dossiers (derives des fichiers).
    readonly property var currentTotals: {
        const dirs = {}
        let bytes = 0
        for (let i = 0; i < root.currentFiles.length; i++) {
            const f = root.currentFiles[i]
            bytes += f.size || 0
            const parts = f.relativePath.split("/")
            for (let k = 1; k < parts.length; k++) dirs[parts.slice(0, k).join("/")] = true
        }
        return { bytes: bytes, dirs: Object.keys(dirs).length }
    }

    function rebuildFileBrowser() {
        const folders = {}
        const files = []
        const prefix = root.browsedRelativePath.length > 0 ? root.browsedRelativePath + "/" : ""
        const q = root.searchText.trim().toLowerCase()
        const copies = {}
        for (const k in root.conflictedFiles) copies[root.conflictedFiles[k]] = true

        for (let i = 0; i < root.currentFiles.length; ++i) {
            const file = root.currentFiles[i]
            if (!file.relativePath.startsWith(prefix)) continue
            const rest = file.relativePath.slice(prefix.length)
            const sep = rest.indexOf("/")
            if (sep >= 0) {
                const name = rest.slice(0, sep)
                const path = prefix + name
                if (q.length === 0 || name.toLowerCase().indexOf(q) !== -1) {
                    if (!folders[path])
                        folders[path] = { kind: "folder", name: name, path: path, count: 0, lastModified: "" }
                    folders[path].count++
                    if ((file.lastModified || "") > folders[path].lastModified)
                        folders[path].lastModified = file.lastModified
                }
            } else if (q.length === 0 || rest.toLowerCase().indexOf(q) !== -1) {
                files.push({ kind: "file", name: rest, relativePath: file.relativePath, path: "",
                             size: file.size, version: file.version, lastModified: file.lastModified || "",
                             conflict: root.conflictedFiles.hasOwnProperty(file.relativePath),
                             conflictCopy: copies[file.relativePath] === true })
            }
        }
        const folderItems = Object.keys(folders).map(function(p) { return folders[p] })
        folderItems.sort(function(a, b) { return a.name.localeCompare(b.name) })
        files.sort(function(a, b) { return a.name.localeCompare(b.name) })
        root.browserItems = folderItems.concat(files)
    }

    function openBrowserFolder(path) {
        root.browsedRelativePath = path
        root.browserLimit = root.browserPage
        root.rebuildFileBrowser()
    }

    function resolveConflictFor(relativePath, conflictPath, resolution) {
        if (!root.context || root.openedFolderId < 0) return
        if (root.context.resolveConflict(root.openedFolderId, relativePath, conflictPath, resolution)) {
            root.refreshFiles()
            root.refreshHistory()
            root.scheduleRebuild()
        }
    }

    // Historique groupe par jour.
    readonly property var historyRows: {
        const out = []
        let day = ""
        for (let i = 0; i < root.currentSyncHistory.length; i++) {
            const e = root.currentSyncHistory[i]
            const d = root.dayLabel(e.createdAt)
            out.push({ newDay: d !== day, day: d, time: root.timeOf(e.createdAt), type: e.type,
                       relativePath: e.relativePath, oldRelativePath: e.oldRelativePath || "", version: e.version })
            day = d
        }
        return out
    }
    // Comptes par jour calcules une fois par liste : dayCount() refiltrait
    // toute la liste pour chaque ligne (cout quadratique sur un long historique).
    readonly property var dayTotals: {
        const m = {}
        for (let i = 0; i < root.historyRows.length; i++) m[root.historyRows[i].day] = (m[root.historyRows[i].day] || 0) + 1
        return m
    }
    function dayCount(day) { return root.dayTotals[day] || 0 }

    // ======================================================================
    // Invitations, avis
    // ======================================================================
    function showNextShareConfirmation() {
        if (inviteSheet.open || root.pendingShareConfirmations.length === 0) return
        const queue = root.pendingShareConfirmations.slice()
        const next = queue.shift()
        root.pendingShareConfirmations = queue
        inviteSheet.queueTotal = Math.max(inviteSheet.queueTotal, queue.length + 1)
        inviteSheet.queueIndex = inviteSheet.queueTotal - queue.length
        inviteSheet.folderId = next.folderId
        inviteSheet.folderName = next.folderName
        inviteSheet.ownerName = next.ownerName
        inviteSheet.suggestedPath = next.suggestedPath
        inviteSheet.allowWrite = next.allowWrite
        inviteSheet.open = true
    }

    property string noticeKind: ""            // "" | "conflict" | "error"
    property string noticeText: ""
    property string noticeFolderUuid: ""
    function showNotice(kind, text, uuid) {
        root.noticeKind = kind
        root.noticeText = text
        root.noticeFolderUuid = uuid || ""
        noticeTimer.restart()
    }
    Timer { id: noticeTimer; interval: 8000; onTriggered: root.noticeKind = "" }

    Connections {
        target: root.context
        function onFolderReindexed(folderId, changeCount) {
            const idx = root.indexingFolderIds.indexOf(folderId)
            if (idx !== -1) {
                const still = root.indexingFolderIds.slice()
                still.splice(idx, 1)
                root.indexingFolderIds = still
            }
            if (folderId === root.openedFolderId)
                root.scheduleOpenedRefresh()
            root.scheduleRebuild()
        }
        function onIndexingStarted(folderId) {
            if (root.indexingFolderIds.indexOf(folderId) === -1)
                root.indexingFolderIds = root.indexingFolderIds.concat([folderId])
        }
        function onFileReceived(folderUuid, relativePath) {
            if (folderUuid === root.openedFolderUuid)
                root.scheduleOpenedRefresh()
            root.scheduleRebuild()
        }
        function onFolderShareConfirmationRequested(folderId, folderName, ownerName, suggestedPath, allowWrite) {
            root.pendingShareConfirmations = root.pendingShareConfirmations.concat([{
                folderId: folderId, folderName: folderName, ownerName: ownerName,
                suggestedPath: suggestedPath, allowWrite: allowWrite
            }])
            root.showNextShareConfirmation()
        }
        function onErrorOccurred(message) {
            root.showNotice("error", message, "")
        }
        function onConflictDetected(folderUuid, relativePath, conflictPath) {
            if (folderUuid === root.openedFolderUuid) {
                const updated = Object.assign({}, root.conflictedFiles)
                updated[relativePath] = conflictPath
                root.conflictedFiles = updated
                root.rebuildFileBrowser()
            }
            let name = ""
            for (let i = 0; i < root.folderRows.length; i++)
                if (root.folderRows[i].uuid === folderUuid) name = root.folderRows[i].name
            root.showNotice("conflict", qsTr("<b>Conflit dans %1.</b> « %2 » a changé ici et ailleurs en même temps ; l'autre version est gardée dans « %3 ».")
                                        .arg(root.esc(name)).arg(root.esc(relativePath)).arg(root.esc(conflictPath)), folderUuid)
            root.scheduleRebuild()
        }
        function onSyncNotice(folderUuid, relativePath, kind) {
            let name = ""
            for (let i = 0; i < root.folderRows.length; i++)
                if (root.folderRows[i].uuid === folderUuid) name = root.folderRows[i].name
            if (kind === "kept-after-delete")
                root.showNotice("info", qsTr("<b>%1 :</b> « %2 » a été supprimé sur un autre poste, mais vous l'aviez modifié ici. Il est gardé et renvoyé aux autres membres.")
                                            .arg(root.esc(name)).arg(root.esc(relativePath)), folderUuid)
            else if (kind === "case-collision")
                root.showNotice("conflict", qsTr("<b>%1 :</b> « %2 » n'a pas été reçu : un autre fichier porte déjà ce nom à la casse près sur ce poste. Renommez l'un des deux.")
                                         .arg(root.esc(name)).arg(root.esc(relativePath)), folderUuid)
            root.scheduleRebuild()
        }
        function onFolderTransferProgress(folderUuid, folderName, incoming, filesCompleted, filesTotal, bytesTransferred, bytesTotal) {
            const b = Object.assign({}, root.syncBatches)
            b[folderUuid + (incoming ? "|in" : "|out")] = { incoming: incoming, done: filesCompleted, total: filesTotal,
                                                            bytes: bytesTransferred, bytesTotal: bytesTotal }
            root.syncBatches = b
        }
        function onFolderTransferComplete(folderUuid, folderName, incoming, fileCount) {
            const b = Object.assign({}, root.syncBatches)
            delete b[folderUuid + (incoming ? "|in" : "|out")]
            root.syncBatches = b
            if (folderUuid === root.openedFolderUuid) {
                root.refreshFiles()
                root.refreshHistory()
            }
            root.scheduleRebuild()
        }
    }

    Component.onCompleted: {
        if (root.context) root.context.refresh()
        root.scheduleRebuild()
    }
    onSearchTextChanged: root.rebuildFileBrowser()

    // ======================================================================
    // Actions
    // ======================================================================
    function openSheet(name) { moreMenu.close(); root.sheet = name }
    function openComposer() {
        root.composerDone = false
        root.composerError = ""
        root.composerPath = ""
        root.composerUsers = root.context ? root.context.availableUsers() : []
        composer.reset()
        root.composerOpen = true
    }
    function reindexCurrent() {
        if (root.context && root.openedFolderId >= 0) {
            root.context.shareFolder(root.openedFolderId)
            root.refreshFiles()
            root.refreshHistory()
        }
    }
    function openInExplorer() {
        if (root.context && root.openedFolderId >= 0 && !root.context.openFolderLocation(root.openedFolderId))
            root.showNotice("error", qsTr("<b>Impossible d'ouvrir l'emplacement du dossier.</b> Il a peut-être été déplacé ou renommé sur le disque."), "")
    }

    FolderDialog {
        id: composerPicker
        title: qsTr("Choisir un dossier local à partager")
        currentFolder: root.composerPath.length > 0 ? "file:///" + root.composerPath : (root.defaultSharedPath.length ? "file:///" + root.defaultSharedPath : "")
        onAccepted: root.composerPath = root.cleanUrl(selectedFolder)
    }
    FolderDialog {
        id: locationPicker
        title: qsTr("Choisir le dossier local")
        currentFolder: root.defaultSharedPath.length ? "file:///" + root.defaultSharedPath : ""
        onAccepted: locationSheet.localPath = root.cleanUrl(selectedFolder)
    }

    // ======================================================================
    // Composants de mise en page
    // ======================================================================
    readonly property real pageW: width - 2 * Theme.pagePadding
    readonly property bool heroWide: pageW > 1180
    readonly property bool foldersWide: pageW > 860
    readonly property real listWidth: pageW > 1240 ? 330 : 290

    // Onglet souligne d'encre (filtres de la liste, Fichiers / Historique).
    component InkTab: AbstractButton {
        id: it
        property bool current: false
        property string count: ""
        property bool danger: false
        property real textSize: Theme.fs(12.5)
        hoverEnabled: true
        focusPolicy: Qt.StrongFocus
        padding: 0
        implicitHeight: 30
        implicitWidth: itRow.implicitWidth
        Accessible.role: Accessible.PageTab
        Accessible.name: it.text
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        background: Item {
            Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: 2; color: it.current ? Theme.ruleInk : "transparent" }
            Rectangle { anchors.fill: parent; anchors.margins: -3; color: "transparent"; radius: Theme.radiusSheet; border.width: it.visualFocus ? 2 : 0; border.color: Theme.focusRing }
        }
        contentItem: Item {
            Row {
                id: itRow
                spacing: 6
                anchors.top: parent.top
                anchors.topMargin: 3
                Text {
                    text: it.text
                    color: it.current || it.hovered ? Theme.ink : Theme.ink3
                    font.family: Theme.fontFamily
                    font.pixelSize: it.textSize
                    font.weight: it.current ? Theme.weightSemibold : Theme.weightMedium
                }
                Text {
                    visible: it.count.length > 0
                    text: it.count
                    color: it.danger ? Theme.dangerInk : Theme.ink3
                    font.family: Theme.fontFamilySerif
                    font.pixelSize: Theme.fs(12)
                    font.weight: Theme.weightBold
                }
            }
        }
    }

    // Petit bouton carre a filet (remonter, bascule liste / vignettes).
    component SquareButton: AbstractButton {
        id: sq
        property string iconPath: ""
        property bool pressedState: false
        property string tip: ""
        hoverEnabled: true
        focusPolicy: Qt.StrongFocus
        implicitWidth: 30
        implicitHeight: 28
        Accessible.name: sq.tip
        ToolTip.visible: sq.tip.length > 0 && sq.hovered
        ToolTip.text: sq.tip
        ToolTip.delay: 400
        HoverHandler { cursorShape: sq.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
        background: Rectangle {
            radius: Theme.radiusSheet
            color: sq.pressedState ? Theme.ink : (sq.hovered && sq.enabled ? Theme.selectWash : "transparent")
            border.width: sq.visualFocus ? 2 : 1
            border.color: sq.visualFocus ? Theme.focusRing : Theme.lineStrong
        }
        contentItem: Item {
            LineIcon {
                anchors.centerIn: parent
                path: sq.iconPath
                size: 15
                strokeWidth: 1.8
                color: sq.pressedState ? Theme.inkOnInk : (sq.enabled ? Theme.ink2 : Theme.inkDisabled)
            }
        }
    }

    // Zone de depot en tirets (choisir ou glisser un dossier).
    component DashedDrop: Item {
        id: dd
        property string title: ""
        property string subtitle: ""
        property string buttonText: ""
        property string iconPath: Icons.folderPlus
        signal activated()
        signal pathDropped(string path)
        implicitHeight: ddRow.implicitHeight + 36
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: ddHover.hovered || ddDrop.containsDrag ? Theme.selectWash : "transparent"
                strokeColor: ddHover.hovered || ddDrop.containsDrag ? Theme.ink3 : Theme.lineStrong
                strokeWidth: 1.5
                strokeStyle: ShapePath.DashLine
                dashPattern: [3, 2.5]
                startX: 1; startY: 1
                PathLine { x: dd.width - 1; y: 1 }
                PathLine { x: dd.width - 1; y: dd.height - 1 }
                PathLine { x: 1; y: dd.height - 1 }
                PathLine { x: 1; y: 1 }
            }
        }
        HoverHandler { id: ddHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: dd.activated() }
        DropArea {
            id: ddDrop
            anchors.fill: parent
            onDropped: function(drop) { if (drop.hasUrls && drop.urls.length > 0) dd.pathDropped(root.cleanUrl(drop.urls[0])) }
        }
        RowLayout {
            id: ddRow
            anchors.verticalCenter: parent.verticalCenter
            x: 20
            width: parent.width - 40
            spacing: 14
            LineIcon { path: dd.iconPath; size: 26; strokeWidth: 1.4; color: Theme.ink2 }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Text { Layout.fillWidth: true; text: dd.title; color: Theme.ink; font.family: Theme.fontFamilySerif; font.pixelSize: Theme.fs(15); font.weight: Theme.weightBold; wrapMode: Text.WordWrap }
                Text { Layout.fillWidth: true; visible: dd.subtitle.length > 0; text: dd.subtitle; color: Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12.5); wrapMode: Text.WrapAnywhere }
            }
            AppButton { variant: "ink"; size: "small"; text: dd.buttonText; onClicked: dd.activated() }
        }
    }

    // Entree du menu « Plus » (icone, libelle, indication a droite).
    component SheetItem: MenuItem {
        id: mi
        property string iconPath: ""
        property string hint: ""
        property bool danger: false
        height: visible ? 36 : 0
        hoverEnabled: true
        background: Rectangle { color: mi.highlighted ? Theme.selectWash : "transparent" }
        contentItem: RowLayout {
            spacing: 10
            LineIcon { Layout.leftMargin: 8; path: mi.iconPath; size: 15; strokeWidth: 1.8; color: mi.danger ? Theme.dangerInk : Theme.ink3 }
            Text { Layout.fillWidth: true; text: mi.text; color: mi.danger ? Theme.dangerInk : Theme.ink; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13) }
            Text { Layout.rightMargin: 8; visible: mi.hint.length > 0; text: mi.hint; color: Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(11.5) }
        }
    }

    // Chiffre du bilan (« 408 fichiers »).
    component Fig: Row {
        property string value: ""
        property string label: ""
        property color tone: Theme.ink
        spacing: 5
        Text {
            id: figValue
            text: parent.value
            color: parent.tone
            font.family: Theme.fontFamilySerif
            font.pixelSize: Theme.fs(17)
            font.weight: Theme.weightBold
            font.features: ({ "tnum": 1 })
        }
        Text {
            anchors.baseline: figValue.baseline
            text: parent.label
            color: Theme.ink3
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fs(12.5)
        }
    }

    // ======================================================================
    // Page
    // ======================================================================
    Item {
        id: page
        anchors.fill: parent
        readonly property bool narrow: width < 720

        Rectangle { anchors.fill: parent; color: Theme.bg }

        Flickable {
            id: pageScroll
            objectName: "pageFlick"
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

                // ---- Avis (conflit recu, erreur) ---------------------------
                Rectangle {
                    visible: root.noticeKind.length > 0
                    Layout.fillWidth: true
                    implicitHeight: noticeRow.implicitHeight + 20
                    color: Theme.surface0
                    border.width: 1
                    border.color: Theme.line
                    Rectangle { width: 3; height: parent.height; color: Theme.dangerColor }
                    RowLayout {
                        id: noticeRow
                        anchors.verticalCenter: parent.verticalCenter
                        x: 16
                        width: parent.width - 26
                        spacing: 12
                        LineIcon { path: Icons.alertTriangle; size: 16; strokeWidth: 1.8; color: Theme.dangerInk }
                        Text {
                            Layout.fillWidth: true
                            text: root.noticeText
                            textFormat: Text.StyledText
                            wrapMode: Text.WordWrap
                            color: Theme.ink
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(13)
                        }
                        TextLink {
                            visible: root.noticeKind === "conflict"
                            text: qsTr("Régler")
                            onClicked: {
                                for (let i = 0; i < root.folderRows.length; i++)
                                    if (root.folderRows[i].uuid === root.noticeFolderUuid) root.openFolder(root.folderRows[i].folderId)
                                root.noticeKind = ""
                            }
                        }
                        AbstractButton {
                            id: noticeClose
                            Layout.preferredWidth: 28
                            Layout.preferredHeight: 28
                            hoverEnabled: true
                            Accessible.name: qsTr("Fermer")
                            onClicked: root.noticeKind = ""
                            background: Rectangle { radius: 14; color: noticeClose.hovered ? Theme.selectWash : "transparent" }
                            contentItem: Item { LineIcon { anchors.centerIn: parent; path: Icons.close; size: 14; strokeWidth: 1.8; color: Theme.ink2 } }
                        }
                    }
                }

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
                                const d = new Date().toLocaleDateString(Qt.locale(), "dddd d MMMM yyyy")
                                return d + ((typeof settingsModel !== "undefined" && settingsModel && settingsModel.machineName && settingsModel.machineName.length > 0)
                                            ? " · " + settingsModel.machineName : "")
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: root.stats.total === 0 ? qsTr("Aucun dossier partagé.")
                                  : root.stats.total === 1 ? qsTr("<b>1</b> dossier partagé.")
                                  : qsTr("<b>%1</b> dossiers partagés.").arg(root.stats.total)
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
                                width: Math.min(implicitWidth, parent.width, 640)
                                height: Math.max(implicitHeight, heroActions.implicitHeight)
                                verticalAlignment: Text.AlignVCenter
                                textFormat: Text.StyledText
                                wrapMode: Text.WordWrap
                                color: Theme.ink2
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(14.5)
                                text: {
                                    const s = root.stats
                                    if (s.total === 0)
                                        return qsTr("Partagez un dossier de ce poste : ses fichiers restent à jour chez les personnes que vous choisissez, sur le réseau local.")
                                    let t = qsTr("Vous en partagez <b>%1</b> et en recevez <b>%2</b>.").arg(s.mine).arg(s.received)
                                    for (let i = 0; i < root.folderRows.length; i++) {
                                        const r = root.folderRows[i]
                                        const b = root.batchFor(r.uuid)
                                        if (b)
                                            t += " " + qsTr("<b>%1</b> se synchronise : %2.").arg(root.esc(r.name))
                                                 .arg("<font color=\"" + Theme.navActiveInk + "\"><b>" + qsTr("%1 fichiers sur %2").arg(b.done).arg(b.total) + "</b></font>")
                                    }
                                    const todo = []
                                    if (s.conflicts > 0)
                                        todo.push("<b><font color=\"" + Theme.dangerInk + "\">" + root.plural(s.conflicts, qsTr("conflit"), qsTr("conflits")) + "</font></b> " + qsTr("à régler"))
                                    if (s.noPath > 0)
                                        todo.push("<b><font color=\"" + Theme.warningInk + "\">" + root.plural(s.noPath, qsTr("dossier reçu"), qsTr("dossiers reçus")) + "</font></b> " + qsTr("sans emplacement"))
                                    if (todo.length > 0)
                                        t += " " + todo.join(", ") + "."
                                    return t
                                }
                            }
                            Row {
                                id: heroActions
                                spacing: 8
                                AppButton {
                                    variant: "ink"
                                    iconPath: Icons.folderPlus
                                    text: qsTr("Nouveau dossier partagé")
                                    onClicked: root.openComposer()
                                }
                            }
                        }
                    }

                    // Quatre chiffres : filtrent la liste.
                    Item {
                        visible: root.stats.total > 0
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
                                model: {
                                    const s = root.stats
                                    const todo = s.conflicts + s.noPath
                                    const ctx = []
                                    if (s.conflicts) ctx.push(root.plural(s.conflicts, qsTr("conflit"), qsTr("conflits")))
                                    if (s.noPath) ctx.push(root.plural(s.noPath, qsTr("emplacement"), qsTr("emplacements")))
                                    return [
                                        { key: "mine", label: qsTr("Partagés par vous"), value: s.mine, ctx: root.plural(s.members, qsTr("membre"), qsTr("membres")) },
                                        { key: "received", label: qsTr("Reçus"), value: s.received, ctx: s.syncing ? qsTr("%1 en synchronisation").arg(s.syncing) : qsTr("à jour") },
                                        { key: "all", label: qsTr("Fichiers"), value: root.formatCount(s.files), ctx: qsTr("indexés sur ce poste") },
                                        { key: "todo", label: qsTr("À régler"), value: todo, ctx: todo ? ctx.join(" · ") : qsTr("rien"), attention: todo > 0 }
                                    ]
                                }
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
                                        attention: !!fig.modelData.attention
                                        valueSize: root.heroWide && root.height >= 720 ? Theme.fontSizeFigure : Theme.fs(32)
                                        onClicked: root.activeFilter = (root.activeFilter === fig.modelData.key ? "all" : fig.modelData.key)
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
                        id: folderList
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
                                text: root.folderRows.length
                                color: Theme.ink3
                                font.family: Theme.fontFamilySerif
                                font.pixelSize: Theme.fs(16)
                                font.weight: Theme.weightBold
                            }
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 32
                            Layout.bottomMargin: 8
                            radius: Theme.radiusSheet
                            color: "transparent"
                            border.width: 1
                            border.color: listFind.activeFocus ? Theme.ink : Theme.line
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 8
                                spacing: 7
                                LineIcon { path: Icons.search; size: 14; strokeWidth: 1.8; color: Theme.ink3 }
                                TextField {
                                    id: listFind
                                    Layout.fillWidth: true
                                    placeholderText: qsTr("Nom du dossier…")
                                    placeholderTextColor: Theme.ink3
                                    color: Theme.ink
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(12.5)
                                    background: Item {}
                                    leftPadding: 0
                                    rightPadding: 0
                                    selectByMouse: true
                                    Accessible.name: qsTr("Rechercher un dossier")
                                    onTextChanged: root.listSearch = text
                                }
                            }
                        }
                        Row {
                            Layout.bottomMargin: 6
                            spacing: 16
                            InkTab { text: qsTr("Tous"); count: String(root.stats.total); current: root.activeFilter === "all" || root.activeFilter === "todo"; onClicked: root.activeFilter = "all" }
                            InkTab { text: qsTr("Partagés"); count: String(root.stats.mine); current: root.activeFilter === "mine"; onClicked: root.activeFilter = "mine" }
                            InkTab { text: qsTr("Reçus"); count: String(root.stats.received); current: root.activeFilter === "received"; onClicked: root.activeFilter = "received" }
                        }
                        Text {
                            visible: root.visibleRows.length === 0
                            Layout.fillWidth: true
                            Layout.topMargin: 8
                            text: root.folderRows.length === 0 ? qsTr("Les dossiers que vous partagez ou recevez apparaîtront ici.")
                                                                : qsTr("Aucun dossier ne correspond.")
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

                            Repeater {
                                model: root.visibleRows
                                delegate: AbstractButton {
                                    id: dos
                                    required property var modelData
                                    readonly property var r: modelData
                                    readonly property bool on: dos.r.folderId === root.openedFolderId
                                    readonly property bool noPath: !dos.r.isLocalOrigin && dos.r.localPath.length === 0
                                    readonly property var batch: root.batchFor(dos.r.uuid)
                                    readonly property bool indexing: root.indexingFolderIds.indexOf(dos.r.folderId) !== -1
                                    Layout.fillWidth: true
                                    implicitHeight: dosRow.implicitHeight + 20
                                    hoverEnabled: true
                                    focusPolicy: Qt.TabFocus
                                    Accessible.role: Accessible.Button
                                    Accessible.name: dos.r.name
                                    onClicked: root.openFolder(dos.r.folderId)
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
                                        FolderMark {
                                            Layout.leftMargin: 10
                                            received: !dos.r.isLocalOrigin
                                            noPath: dos.noPath
                                            pip: dos.r.hasConflict ? "conflict" : dos.batch ? "sync" : dos.indexing ? "indexing" : dos.noPath ? "away" : ""
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
                                                    text: dos.r.name
                                                    color: Theme.ink
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: Theme.fs(13.5)
                                                    font.weight: Theme.weightSemibold
                                                    elide: Text.ElideRight
                                                }
                                                Text {
                                                    text: root.whenShort(dos.r.lastActivity)
                                                    color: Theme.ink3
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: Theme.fs(11.5)
                                                    font.features: ({ "tnum": 1 })
                                                }
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                text: dos.r.isLocalOrigin
                                                      ? (dos.r.members.length ? qsTr("Partagé par vous · %1").arg(root.plural(dos.r.members.length, qsTr("membre"), qsTr("membres")))
                                                                              : qsTr("Partagé par vous · aucun membre"))
                                                      : (dos.r.ownerName.length ? qsTr("Reçu de %1").arg(dos.r.ownerName) : qsTr("Reçu d'un autre poste"))
                                                color: Theme.ink3
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.fs(12)
                                                elide: Text.ElideRight
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                textFormat: Text.StyledText
                                                text: {
                                                    if (dos.noPath)
                                                        return "<b><font color=\"" + Theme.warningInk + "\">" + qsTr("Emplacement à choisir") + "</font></b>"
                                                    let t = root.plural(dos.r.fileCount, qsTr("fichier"), qsTr("fichiers"))
                                                    if (dos.r.conflictCount > 0)
                                                        t += " · <b><font color=\"" + Theme.dangerInk + "\">" + root.plural(dos.r.conflictCount, qsTr("conflit"), qsTr("conflits")) + "</font></b>"
                                                    if (dos.batch)
                                                        t += " · <b><font color=\"" + Theme.navActiveInk + "\">" + (dos.batch.incoming ? qsTr("réception") : qsTr("envoi"))
                                                             + " " + dos.batch.done + "/" + dos.batch.total + "</font></b>"
                                                    if (dos.indexing)
                                                        t += " · <b><font color=\"" + Theme.navActiveInk + "\">" + qsTr("indexation…") + "</font></b>"
                                                    return t
                                                }
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

                        // Emplacement par defaut des dossiers recus
                        Rectangle { visible: root.defaultSharedPath.length > 0; Layout.fillWidth: true; Layout.topMargin: 12; Layout.preferredHeight: 1; color: Theme.line }
                        ColumnLayout {
                            visible: root.defaultSharedPath.length > 0
                            Layout.fillWidth: true
                            Layout.topMargin: 8
                            spacing: 3
                            Text { text: qsTr("Emplacement des dossiers reçus"); color: Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12) }
                            Text { Layout.fillWidth: true; text: root.defaultSharedPath; color: Theme.ink2; font.family: "Cascadia Mono"; font.pixelSize: Theme.fs(11.5); elide: Text.ElideMiddle }
                            TextLink { text: qsTr("Modifier dans les paramètres"); fontSize: Theme.fs(12); onClicked: root.settingsRequested() }
                        }
                    }

                    // -- Dossier ouvert ------------------------------------
                    Item {
                        id: folderCol
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignTop
                        Layout.minimumHeight: Math.max(folderList.implicitHeight, 420)
                        implicitHeight: folderInner.implicitHeight + 18
                        readonly property bool wide: width > 700

                        Rectangle { visible: root.foldersWide; width: 1; height: Math.max(parent.height, folderList.height); color: Theme.line }
                        Rectangle { visible: !root.foldersWide; width: parent.width; height: 1; y: 4; color: Theme.line }

                        ColumnLayout {
                            id: folderInner
                            x: root.foldersWide ? (root.pageW > 1240 ? 28 : 22) : 0
                            y: root.foldersWide ? 16 : 20
                            width: parent.width - x
                            spacing: 0

                            // Aucun dossier : premier partage
                            ColumnLayout {
                                visible: root.folderRows.length === 0
                                Layout.fillWidth: true
                                Layout.maximumWidth: 640
                                Layout.topMargin: 14
                                spacing: 6
                                CapsLabel { text: qsTr("Pour commencer") }
                                Text { text: qsTr("Partagez un premier dossier."); color: Theme.ink; font.family: Theme.fontFamilySerif; font.pixelSize: Theme.fs(26) }
                                Text {
                                    Layout.fillWidth: true
                                    Layout.bottomMargin: 10
                                    text: qsTr("Choisissez un dossier de ce poste, puis les personnes qui le recevront. Ses fichiers sont indexés ici ; les modifications se propagent ensuite sur le réseau local, sans passer par Internet.")
                                    color: Theme.ink3
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(13)
                                    wrapMode: Text.WordWrap
                                }
                                DashedDrop {
                                    Layout.fillWidth: true
                                    title: qsTr("Déposez un dossier ici")
                                    subtitle: qsTr("ou cliquez pour le choisir dans l'explorateur")
                                    buttonText: qsTr("Choisir un dossier")
                                    onActivated: { root.openComposer(); composerPicker.open() }
                                    onPathDropped: function(path) { root.openComposer(); root.composerPath = path }
                                }
                            }

                            // En-tete du dossier
                            GridLayout {
                                visible: root.currentFolder !== null
                                Layout.fillWidth: true
                                columns: folderCol.width > 520 ? 2 : 1
                                columnSpacing: 20
                                rowSpacing: 12

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 16
                                    FolderMark {
                                        size: 56
                                        received: root.currentReceived
                                        noPath: root.currentNoPath
                                        pip: !root.currentFolder ? "" : root.currentFolder.hasConflict ? "conflict"
                                             : root.batchFor(root.currentFolder.uuid) ? "sync" : root.currentNoPath ? "away" : ""
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2
                                        CapsLabel {
                                            Layout.fillWidth: true
                                            text: !root.currentFolder ? "" : root.currentReceived
                                                  ? (root.currentFolder.ownerName.length ? qsTr("Dossier reçu de %1").arg(root.currentFolder.ownerName) : qsTr("Dossier reçu"))
                                                  : qsTr("Dossier partagé par vous")
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: root.currentFolder ? root.currentFolder.name : ""
                                            color: Theme.ink
                                            font.family: Theme.fontFamilySerif
                                            font.pixelSize: Theme.fs(28)
                                            font.weight: Theme.weightBold
                                            elide: Text.ElideRight
                                            Accessible.role: Accessible.Heading
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: !root.currentFolder ? "" : root.currentNoPath
                                                  ? qsTr("Pas encore d'emplacement sur ce poste") : root.currentFolder.localPath
                                            color: root.currentNoPath ? Theme.warningInk : Theme.ink2
                                            font.family: root.currentNoPath ? Theme.fontFamily : "Cascadia Mono"
                                            font.pixelSize: Theme.fs(12.5)
                                            font.weight: root.currentNoPath ? Theme.weightSemibold : Theme.weightRegular
                                            elide: Text.ElideMiddle
                                        }
                                    }
                                }
                                Row {
                                    Layout.alignment: folderCol.width > 520 ? (Qt.AlignRight | Qt.AlignBottom) : Qt.AlignLeft
                                    spacing: 8
                                    readonly property bool iconsOnly: folderCol.width < 820
                                    AppButton {
                                        visible: !root.currentReceived
                                        variant: "ink"
                                        iconPath: Icons.users
                                        text: parent.iconsOnly ? "" : qsTr("Gérer les accès")
                                        tooltip: parent.iconsOnly ? qsTr("Gérer les accès") : ""
                                        onClicked: root.openSheet("access")
                                    }
                                    AppButton {
                                        visible: !root.currentNoPath
                                        variant: "line"
                                        iconPath: Icons.external
                                        text: parent.iconsOnly ? "" : qsTr("Ouvrir dans l'explorateur")
                                        tooltip: parent.iconsOnly ? qsTr("Ouvrir dans l'explorateur") : ""
                                        onClicked: root.openInExplorer()
                                    }
                                    AppButton {
                                        id: moreBtn
                                        variant: "line"
                                        iconPath: Icons.more
                                        tooltip: qsTr("Plus d'actions")
                                        onClicked: moreMenu.opened ? moreMenu.close() : moreMenu.open()

                                        Menu {
                                            id: moreMenu
                                            y: moreBtn.height + 6
                                            x: moreBtn.width - width
                                            width: 250
                                            padding: 6
                                            background: Rectangle {
                                                color: Theme.surface0
                                                radius: Theme.radiusSheet
                                                border.width: 1
                                                border.color: Theme.ruleInk
                                            }
                                            SheetItem { text: qsTr("Réindexer maintenant"); iconPath: Icons.refresh; visible: !root.currentNoPath; onTriggered: root.reindexCurrent() }
                                            SheetItem { text: qsTr("Changer l'emplacement…"); iconPath: Icons.folderIn; visible: root.currentReceived; onTriggered: root.openSheet("location") }
                                            SheetItem {
                                                text: qsTr("Exclusions…"); iconPath: Icons.ban; visible: !root.currentReceived
                                                hint: root.currentExcludes.length ? String(root.currentExcludes.length) : qsTr("aucune")
                                                onTriggered: root.openSheet("exclusions")
                                            }
                                            SheetItem { text: qsTr("Gérer les accès…"); iconPath: Icons.users; visible: !root.currentReceived; onTriggered: root.openSheet("access") }
                                            MenuSeparator {
                                                contentItem: Rectangle { implicitHeight: 1; color: Theme.line }
                                            }
                                            SheetItem {
                                                text: root.currentReceived ? qsTr("Retirer de ce poste…") : qsTr("Arrêter le partage…")
                                                iconPath: Icons.trash
                                                danger: true
                                                onTriggered: root.openSheet("remove")
                                            }
                                        }
                                    }
                                }
                            }

                            // Dossier recu sans emplacement : mise en place
                            ColumnLayout {
                                visible: root.currentNoPath
                                Layout.fillWidth: true
                                Layout.maximumWidth: 640
                                Layout.topMargin: 26
                                spacing: 6
                                CapsLabel { text: qsTr("Avant d'ouvrir ce dossier") }
                                Text { text: qsTr("Choisissez où le recevoir sur ce poste."); color: Theme.ink; font.family: Theme.fontFamilySerif; font.pixelSize: Theme.fs(26); Layout.fillWidth: true; wrapMode: Text.WordWrap }
                                Text {
                                    Layout.fillWidth: true
                                    Layout.bottomMargin: 10
                                    text: root.currentFolder
                                          ? qsTr("%1 partage « %2 » avec vous. Ses fichiers seront copiés puis tenus à jour dans le dossier que vous indiquez.")
                                            .arg(root.currentFolder.ownerName.length ? root.currentFolder.ownerName : qsTr("Un autre poste")).arg(root.currentFolder.name)
                                          : ""
                                    color: Theme.ink3
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(13)
                                    wrapMode: Text.WordWrap
                                }
                                DashedDrop {
                                    Layout.fillWidth: true
                                    iconPath: Icons.folderIn
                                    title: qsTr("Déposez le dossier de destination ici")
                                    subtitle: root.defaultSharedPath.length && root.currentFolder
                                              ? qsTr("ou cliquez pour le choisir · proposé : %1/%2").arg(root.defaultSharedPath).arg(root.currentFolder.name)
                                              : qsTr("ou cliquez pour le choisir")
                                    buttonText: qsTr("Choisir l'emplacement")
                                    onActivated: root.openSheet("location")
                                    onPathDropped: function(path) { locationSheet.localPath = path; root.openSheet("location") }
                                }
                            }

                            // Bilan
                            Rectangle {
                                visible: root.currentFolder !== null && !root.currentNoPath
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
                                    Fig { value: root.formatCount(root.currentFiles.length); label: root.currentFiles.length > 1 ? qsTr("fichiers") : qsTr("fichier") }
                                    Fig { value: String(root.currentTotals.dirs); label: root.currentTotals.dirs > 1 ? qsTr("sous-dossiers") : qsTr("sous-dossier") }
                                    Fig { value: root.formatBytes(root.currentTotals.bytes); label: qsTr("sur ce poste") }
                                    Fig { visible: !root.currentReceived; value: String(root.currentAccess.length); label: root.currentAccess.length > 1 ? qsTr("membres") : qsTr("membre") }
                                    Fig { visible: root.currentExcludes.length > 0; value: String(root.currentExcludes.length); label: root.currentExcludes.length > 1 ? qsTr("exclusions") : qsTr("exclusion") }
                                    Fig {
                                        readonly property int n: Object.keys(root.conflictedFiles).length
                                        visible: n > 0
                                        value: String(n)
                                        label: n > 1 ? qsTr("conflits") : qsTr("conflit")
                                        tone: Theme.dangerInk
                                    }
                                }
                            }

                            // Membres
                            Item {
                                visible: root.currentFolder !== null && !root.currentReceived
                                Layout.fillWidth: true
                                implicitHeight: memRow.implicitHeight + 22
                                Rectangle { width: parent.width; height: 1; y: parent.height - 1; color: Theme.line }
                                RowLayout {
                                    id: memRow
                                    y: 11
                                    width: parent.width
                                    spacing: 14
                                    CapsLabel { Layout.alignment: Qt.AlignVCenter; text: qsTr("Membres") }
                                    Flow {
                                        Layout.fillWidth: true
                                        spacing: 14
                                        Repeater {
                                            model: root.currentAccess
                                            delegate: Row {
                                                required property var modelData
                                                spacing: 8
                                                Rectangle {
                                                    width: 24; height: 24; radius: 12
                                                    color: Theme.ink
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    Text { anchors.centerIn: parent; text: root.initials(modelData.username); color: Theme.inkOnInk; font.family: Theme.fontFamilySerif; font.pixelSize: Theme.fs(10); font.weight: Theme.weightBold }
                                                }
                                                Text { anchors.verticalCenter: parent.verticalCenter; text: modelData.username; color: Theme.ink; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12.5) }
                                                Text {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: modelData.permission === "Write" ? qsTr("modifie") : qsTr("consulte")
                                                    color: Theme.ink3
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: Theme.fs(11.5)
                                                }
                                            }
                                        }
                                        Text {
                                            visible: root.currentAccess.length === 0
                                            text: qsTr("Personne d'autre n'a accès à ce dossier.")
                                            color: Theme.ink3
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fs(12.5)
                                        }
                                    }
                                    TextLink { Layout.alignment: Qt.AlignVCenter; text: qsTr("Ajouter"); arrow: false; onClicked: root.openSheet("access") }
                                }
                            }

                            // Synchronisation en cours
                            Item {
                                id: syncLine
                                readonly property var batch: root.currentFolder ? root.batchFor(root.currentFolder.uuid) : null
                                readonly property real pct: batch && batch.bytesTotal > 0 ? Math.round(batch.bytes / batch.bytesTotal * 100) : 0
                                visible: batch !== null && !root.currentNoPath
                                Layout.fillWidth: true
                                implicitHeight: 52
                                Rectangle { width: parent.width; height: 1; y: parent.height - 1; color: Theme.line }
                                RowLayout {
                                    y: 11
                                    width: parent.width
                                    spacing: 10
                                    LineIcon { path: syncLine.batch && !syncLine.batch.incoming ? Icons.arrowUp : Icons.arrowDown; size: 16; strokeWidth: 1.8; color: Theme.navActiveInk }
                                    Text {
                                        Layout.fillWidth: true
                                        textFormat: Text.StyledText
                                        elide: Text.ElideRight
                                        text: !syncLine.batch ? "" : "<b>" + (syncLine.batch.incoming ? qsTr("Réception en cours") : qsTr("Envoi en cours")) + "</b> · "
                                              + qsTr("%1 fichiers sur %2").arg(syncLine.batch.done).arg(syncLine.batch.total) + " · "
                                              + qsTr("%1 sur %2").arg(root.formatBytes(syncLine.batch.bytes)).arg(root.formatBytes(syncLine.batch.bytesTotal))
                                        color: Theme.ink2
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fs(12.5)
                                    }
                                    Text { text: syncLine.pct + " %"; color: Theme.ink; font.family: Theme.fontFamilySerif; font.pixelSize: Theme.fs(18); font.weight: Theme.weightBold }
                                }
                                Rectangle {
                                    x: 26; y: 38
                                    width: parent.width - 26
                                    height: 2
                                    color: Theme.line
                                    Rectangle { y: -1; height: 4; width: parent.width * syncLine.pct / 100; color: Theme.markTransfer }
                                }
                            }

                            // Indexation en cours
                            Item {
                                visible: root.currentFolder !== null && root.indexingFolderIds.indexOf(root.openedFolderId) !== -1
                                Layout.fillWidth: true
                                implicitHeight: 42
                                Rectangle { width: parent.width; height: 1; y: parent.height - 1; color: Theme.line }
                                RowLayout {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width
                                    spacing: 10
                                    Spinner { width: 14; height: 14; running: parent.visible; lineWidth: 2 }
                                    Text {
                                        Layout.fillWidth: true
                                        textFormat: Text.StyledText
                                        text: "<b>" + qsTr("Indexation en cours") + "</b> · " + qsTr("les nouveaux fichiers apparaîtront au fur et à mesure ; l'application reste utilisable.")
                                        color: Theme.ink2
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fs(12.5)
                                        elide: Text.ElideRight
                                    }
                                }
                            }

                            // Conflits a regler
                            Rectangle {
                                id: conflictBox
                                readonly property var keys: Object.keys(root.conflictedFiles)
                                visible: keys.length > 0 && !root.currentNoPath
                                Layout.fillWidth: true
                                Layout.topMargin: 14
                                implicitHeight: conflictCol.implicitHeight + 26
                                color: Theme.surface0
                                border.width: 1
                                border.color: Theme.line
                                Rectangle { width: 3; height: parent.height; color: Theme.dangerColor }
                                ColumnLayout {
                                    id: conflictCol
                                    x: 18
                                    y: 12
                                    width: parent.width - 34
                                    spacing: 10
                                    Row {
                                        spacing: 6
                                        StateGlyph { anchors.verticalCenter: parent.verticalCenter; kind: "error"; size: 11 }
                                        CapsLabel {
                                            text: conflictBox.keys.length > 1 ? qsTr("%1 conflits à régler").arg(conflictBox.keys.length) : qsTr("1 conflit à régler")
                                            color: Theme.dangerInk
                                        }
                                    }
                                    Repeater {
                                        model: conflictBox.keys
                                        delegate: GridLayout {
                                            id: cf
                                            required property var modelData
                                            required property int index
                                            readonly property string copyPath: root.conflictedFiles[modelData] || ""
                                            Layout.fillWidth: true
                                            columns: folderCol.width > 760 ? 2 : 1
                                            columnSpacing: 18
                                            rowSpacing: 6
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 2
                                                Text { Layout.fillWidth: true; text: cf.modelData; color: Theme.ink; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13.5); font.weight: Theme.weightSemibold; wrapMode: Text.WrapAnywhere }
                                                Text {
                                                    Layout.fillWidth: true
                                                    textFormat: Text.StyledText
                                                    wrapMode: Text.WordWrap
                                                    text: qsTr("Le fichier a changé ici et ailleurs en même temps. L'autre version est gardée sous « %1 ».")
                                                          .arg(root.esc(cf.copyPath.split("/").pop()))
                                                    color: Theme.ink3
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: Theme.fs(12.5)
                                                }
                                            }
                                            // Trois choix d'un seul tenant
                                            Rectangle {
                                                Layout.alignment: Qt.AlignVCenter
                                                implicitWidth: choiceRow.implicitWidth + 2
                                                implicitHeight: 34
                                                radius: Theme.radiusSheet
                                                color: "transparent"
                                                border.width: 1
                                                border.color: Theme.lineStrong
                                                Row {
                                                    id: choiceRow
                                                    x: 1; y: 1
                                                    Repeater {
                                                        model: [
                                                            { t: qsTr("Garder l'original"), r: "keep_local" },
                                                            { t: qsTr("Garder la copie"), r: "keep_remote" },
                                                            { t: qsTr("Garder les deux"), r: "keep_both" }
                                                        ]
                                                        delegate: AbstractButton {
                                                            id: ch
                                                            required property var modelData
                                                            required property int index
                                                            hoverEnabled: true
                                                            implicitHeight: 32
                                                            implicitWidth: chText.implicitWidth + 24
                                                            Accessible.name: ch.modelData.t
                                                            onClicked: root.resolveConflictFor(cf.modelData, cf.copyPath, ch.modelData.r)
                                                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                                                            background: Rectangle {
                                                                color: ch.hovered ? Theme.ink : "transparent"
                                                                Rectangle { visible: ch.index > 0; width: 1; height: parent.height; color: Theme.lineStrong }
                                                            }
                                                            contentItem: Text {
                                                                id: chText
                                                                text: ch.modelData.t
                                                                horizontalAlignment: Text.AlignHCenter
                                                                verticalAlignment: Text.AlignVCenter
                                                                color: ch.hovered ? Theme.inkOnInk : Theme.ink
                                                                font.family: Theme.fontFamily
                                                                font.pixelSize: Theme.fs(12.5)
                                                                font.weight: Theme.weightSemibold
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // Onglets + outils
                            Item {
                                visible: root.currentFolder !== null && !root.currentNoPath
                                Layout.fillWidth: true
                                Layout.topMargin: 18
                                implicitHeight: 36
                                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
                                Row {
                                    anchors.bottom: parent.bottom
                                    spacing: 18
                                    InkTab { text: qsTr("Fichiers"); count: root.formatCount(root.currentFiles.length); current: root.tab === "files"; onClicked: root.tab = "files" }
                                    InkTab { text: qsTr("Historique"); count: String(root.currentSyncHistory.length); current: root.tab === "history"; onClicked: root.tab = "history" }
                                }
                                Row {
                                    visible: root.tab === "files"
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    spacing: 10
                                    Rectangle {
                                        visible: folderCol.width > 560
                                        width: folderCol.width > 900 ? 220 : 170
                                        height: 30
                                        radius: Theme.radiusSheet
                                        color: "transparent"
                                        border.width: 1
                                        border.color: inFind.activeFocus ? Theme.ink : Theme.line
                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 10
                                            anchors.rightMargin: 8
                                            spacing: 7
                                            LineIcon { path: Icons.search; size: 14; strokeWidth: 1.8; color: Theme.ink3 }
                                            TextField {
                                                id: inFind
                                                Layout.fillWidth: true
                                                placeholderText: qsTr("Dans ce dossier…")
                                                placeholderTextColor: Theme.ink3
                                                color: Theme.ink
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.fs(12.5)
                                                background: Item {}
                                                leftPadding: 0
                                                rightPadding: 0
                                                selectByMouse: true
                                                text: root.searchText
                                                Accessible.name: qsTr("Rechercher dans ce dossier")
                                                onTextChanged: root.searchText = text
                                            }
                                        }
                                    }
                                    Row {
                                        SquareButton { iconPath: Icons.list; tip: qsTr("Liste"); pressedState: root.viewMode === "list"; onClicked: root.viewMode = "list" }
                                        SquareButton { iconPath: Icons.grid; tip: qsTr("Vignettes"); pressedState: root.viewMode === "grid"; onClicked: root.viewMode = "grid" }
                                    }
                                }
                            }

                            // Fil du chemin
                            RowLayout {
                                visible: root.currentFolder !== null && !root.currentNoPath && root.tab === "files"
                                Layout.fillWidth: true
                                Layout.topMargin: 10
                                Layout.bottomMargin: 4
                                spacing: 8
                                SquareButton {
                                    iconPath: Icons.arrowUp
                                    tip: qsTr("Dossier parent")
                                    enabled: root.browsedRelativePath.length > 0
                                    onClicked: {
                                        const i = root.browsedRelativePath.lastIndexOf("/")
                                        root.openBrowserFolder(i >= 0 ? root.browsedRelativePath.slice(0, i) : "")
                                    }
                                }
                                Flow {
                                    Layout.fillWidth: true
                                    spacing: 6
                                    Repeater {
                                        model: {
                                            const segs = root.browsedRelativePath.length ? root.browsedRelativePath.split("/") : []
                                            const out = [{ label: root.currentFolder ? root.currentFolder.name : "", path: "", current: segs.length === 0 }]
                                            for (let i = 0; i < segs.length; i++)
                                                out.push({ label: segs[i], path: segs.slice(0, i + 1).join("/"), current: i === segs.length - 1 })
                                            return out
                                        }
                                        delegate: Row {
                                            required property var modelData
                                            required property int index
                                            spacing: 6
                                            Text { visible: index > 0; text: "/"; color: Theme.inkDisabled; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13) }
                                            Text {
                                                text: modelData.label
                                                color: modelData.current ? Theme.ink : (segHover.hovered ? Theme.ink : Theme.ink3)
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.fs(13)
                                                font.weight: modelData.current ? Theme.weightSemibold : Theme.weightRegular
                                                font.underline: segHover.hovered && !modelData.current
                                                HoverHandler { id: segHover; cursorShape: modelData.current ? Qt.ArrowCursor : Qt.PointingHandCursor }
                                                TapHandler { enabled: !modelData.current; onTapped: root.openBrowserFolder(modelData.path) }
                                            }
                                        }
                                    }
                                }
                                Text {
                                    text: root.plural(root.browserItems.length, qsTr("élément"), qsTr("éléments"))
                                    color: Theme.ink3
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(12)
                                }
                            }

                            // Table des fichiers
                            ColumnLayout {
                                id: fileTable
                                visible: root.currentFolder !== null && !root.currentNoPath && root.tab === "files" && root.viewMode === "list"
                                Layout.fillWidth: true
                                spacing: 0
                                readonly property bool showVersion: folderCol.width > 640
                                readonly property real sizeW: folderCol.width > 900 ? 96 : 84
                                readonly property real whenW: folderCol.width > 900 ? 120 : 96

                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 28
                                    spacing: 12
                                    Item { Layout.preferredWidth: 30 }
                                    CapsLabel { Layout.fillWidth: true; text: qsTr("Nom"); font.pixelSize: Theme.fs(10) }
                                    CapsLabel { Layout.preferredWidth: fileTable.sizeW; horizontalAlignment: Text.AlignRight; text: qsTr("Taille"); font.pixelSize: Theme.fs(10) }
                                    CapsLabel { visible: fileTable.showVersion; Layout.preferredWidth: 66; horizontalAlignment: Text.AlignRight; text: qsTr("Version"); font.pixelSize: Theme.fs(10) }
                                    CapsLabel { Layout.preferredWidth: fileTable.whenW; Layout.rightMargin: 8; horizontalAlignment: Text.AlignRight; text: qsTr("Modifié"); font.pixelSize: Theme.fs(10) }
                                }
                                Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.ruleInk }

                                Repeater {
                                    // Vue masquee : aucune ligne creee.
                                    model: fileTable.visible ? root.shownBrowserItems : []
                                    delegate: AbstractButton {
                                        id: fr
                                        required property var modelData
                                        readonly property bool isFolder: modelData.kind === "folder"
                                        Layout.fillWidth: true
                                        implicitHeight: 42
                                        hoverEnabled: true
                                        focusPolicy: fr.isFolder ? Qt.TabFocus : Qt.NoFocus
                                        Accessible.name: modelData.name
                                        onClicked: if (fr.isFolder) root.openBrowserFolder(modelData.path)
                                        HoverHandler { cursorShape: fr.isFolder ? Qt.PointingHandCursor : Qt.ArrowCursor }
                                        background: Rectangle {
                                            color: fr.modelData.conflict ? Theme.dangerSoft : (fr.hovered ? Theme.selectWash : "transparent")
                                            border.width: fr.visualFocus ? 2 : 0
                                            border.color: Theme.focusRing
                                            Rectangle { width: parent.width; height: 1; y: parent.height - 1; color: Theme.line }
                                        }
                                        contentItem: RowLayout {
                                            spacing: 12
                                            Item {
                                                Layout.preferredWidth: 30
                                                Layout.fillHeight: true
                                                LineIcon { visible: fr.isFolder; anchors.centerIn: parent; path: Icons.folder; size: 17; strokeWidth: 1.6; color: Theme.ink2 }
                                                Text {
                                                    visible: !fr.isFolder
                                                    anchors.centerIn: parent
                                                    text: root.extOf(fr.modelData.name)
                                                    color: Theme.ink3
                                                    font.family: Theme.fontFamilySerif
                                                    font.pixelSize: Theme.fs(10)
                                                    font.weight: Theme.weightBold
                                                    font.letterSpacing: 0.6
                                                }
                                            }
                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 8
                                                Text {
                                                    Layout.fillWidth: true
                                                    Layout.maximumWidth: implicitWidth
                                                    text: fr.modelData.name
                                                    color: fr.modelData.conflict ? Theme.dangerInk : Theme.ink
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: Theme.fs(13)
                                                    font.weight: fr.isFolder ? Theme.weightSemibold : Theme.weightMedium
                                                    elide: Text.ElideMiddle
                                                }
                                                LineIcon { visible: fr.isFolder; path: Icons.chevronRight; size: 14; strokeWidth: 1.8; color: Theme.inkDisabled }
                                                Row {
                                                    visible: fr.modelData.conflict === true
                                                    spacing: 4
                                                    StateGlyph { anchors.verticalCenter: parent.verticalCenter; kind: "error"; size: 10 }
                                                    Text { text: qsTr("en conflit"); color: Theme.dangerInk; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(11.5); font.weight: Theme.weightSemibold }
                                                }
                                                Text {
                                                    visible: fr.modelData.conflictCopy === true
                                                    text: qsTr("copie mise de côté")
                                                    color: Theme.ink3
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: Theme.fs(11.5)
                                                }
                                                Item { Layout.fillWidth: true }
                                            }
                                            Text {
                                                Layout.preferredWidth: fileTable.sizeW
                                                horizontalAlignment: Text.AlignRight
                                                text: fr.isFolder ? root.plural(fr.modelData.count, qsTr("fichier"), qsTr("fichiers")) : root.formatBytes(fr.modelData.size)
                                                color: Theme.ink2
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.fs(12.5)
                                                font.features: ({ "tnum": 1 })
                                            }
                                            Text {
                                                visible: fileTable.showVersion
                                                Layout.preferredWidth: 66
                                                horizontalAlignment: Text.AlignRight
                                                text: fr.isFolder ? "" : "v" + fr.modelData.version
                                                color: Theme.ink3
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.fs(12.5)
                                            }
                                            Text {
                                                Layout.preferredWidth: fileTable.whenW
                                                Layout.rightMargin: 8
                                                horizontalAlignment: Text.AlignRight
                                                text: root.whenShort(fr.modelData.lastModified)
                                                color: Theme.ink2
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.fs(12.5)
                                                font.features: ({ "tnum": 1 })
                                            }
                                        }
                                    }
                                }
                            }

                            // Vignettes
                            Flow {
                                id: fileGrid
                                visible: root.currentFolder !== null && !root.currentNoPath && root.tab === "files" && root.viewMode === "grid"
                                Layout.fillWidth: true
                                Layout.topMargin: 8
                                spacing: 10
                                readonly property real tileW: {
                                    const n = Math.max(1, Math.floor((width + 10) / 186))
                                    return (width - (n - 1) * 10) / n
                                }
                                Repeater {
                                    model: fileGrid.visible ? root.shownBrowserItems : []
                                    delegate: AbstractButton {
                                        id: tl
                                        required property var modelData
                                        readonly property bool isFolder: modelData.kind === "folder"
                                        width: parent.tileW
                                        implicitHeight: tlCol.implicitHeight + 24
                                        padding: 12
                                        hoverEnabled: true
                                        Accessible.name: modelData.name
                                        onClicked: if (tl.isFolder) root.openBrowserFolder(modelData.path)
                                        HoverHandler { cursorShape: tl.isFolder ? Qt.PointingHandCursor : Qt.ArrowCursor }
                                        background: Rectangle {
                                            radius: Theme.radiusSheet
                                            color: tl.modelData.conflict ? Theme.dangerSoft : (tl.hovered ? Theme.surface1 : Theme.surface0)
                                            border.width: 1
                                            border.color: tl.modelData.conflict ? Theme.dangerColor : Theme.line
                                        }
                                        contentItem: ColumnLayout {
                                            id: tlCol
                                            spacing: 6
                                            RowLayout {
                                                Layout.fillWidth: true
                                                LineIcon { visible: tl.isFolder; path: Icons.folder; size: 20; strokeWidth: 1.6; color: Theme.ink2 }
                                                Text {
                                                    visible: !tl.isFolder
                                                    text: root.extOf(tl.modelData.name)
                                                    color: Theme.ink3
                                                    font.family: Theme.fontFamilySerif
                                                    font.pixelSize: Theme.fs(11)
                                                    font.weight: Theme.weightBold
                                                    font.letterSpacing: 0.8
                                                }
                                                Item { Layout.fillWidth: true }
                                                Text {
                                                    text: tl.isFolder ? tl.modelData.count : "v" + tl.modelData.version
                                                    color: Theme.ink3
                                                    font.family: Theme.fontFamilySerif
                                                    font.pixelSize: Theme.fs(11)
                                                    font.weight: Theme.weightBold
                                                }
                                            }
                                            Text { Layout.fillWidth: true; text: tl.modelData.name; color: Theme.ink; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13); font.weight: Theme.weightSemibold; elide: Text.ElideMiddle }
                                            Text {
                                                Layout.fillWidth: true
                                                text: tl.isFolder ? root.plural(tl.modelData.count, qsTr("fichier"), qsTr("fichiers"))
                                                                  : root.formatBytes(tl.modelData.size) + " · " + root.whenShort(tl.modelData.lastModified)
                                                color: Theme.ink3
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.fs(12)
                                                elide: Text.ElideRight
                                            }
                                            Text {
                                                visible: tl.modelData.conflict === true || tl.modelData.conflictCopy === true
                                                text: tl.modelData.conflict ? qsTr("× en conflit") : qsTr("copie mise de côté")
                                                color: tl.modelData.conflict ? Theme.dangerInk : Theme.ink3
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.fs(11.5)
                                                font.weight: Theme.weightSemibold
                                            }
                                        }
                                    }
                                }
                            }

                            TextLink {
                                visible: root.currentFolder !== null && !root.currentNoPath && root.tab === "files"
                                         && root.browserItems.length > root.browserLimit
                                Layout.topMargin: 12
                                text: qsTr("Afficher %1 de plus (%2 restants)")
                                      .arg(Math.min(root.browserPage, root.browserItems.length - root.browserLimit))
                                      .arg(root.browserItems.length - root.browserLimit)
                                arrow: false
                                fontSize: Theme.fs(12.5)
                                onClicked: root.browserLimit += root.browserPage
                            }

                            Text {
                                visible: root.currentFolder !== null && !root.currentNoPath && root.tab === "files" && root.browserItems.length === 0
                                Layout.topMargin: 14
                                text: root.searchText.length ? qsTr("Aucun élément ne correspond.") : qsTr("Ce dossier ne contient aucun fichier indexé.")
                                color: Theme.ink3
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(12.5)
                            }

                            // Historique
                            ColumnLayout {
                                visible: root.currentFolder !== null && !root.currentNoPath && root.tab === "history"
                                Layout.fillWidth: true
                                spacing: 0
                                Repeater {
                                    model: root.historyRows
                                    delegate: ColumnLayout {
                                        id: hr
                                        required property var modelData
                                        Layout.fillWidth: true
                                        spacing: 0
                                        readonly property var op: {
                                            switch (modelData.type) {
                                            case "Create": return { g: "+", w: qsTr("Créé"), c: Theme.successInk }
                                            case "Update": return { g: "~", w: qsTr("Modifié"), c: Theme.navActiveInk }
                                            case "Delete": return { g: "−", w: qsTr("Supprimé"), c: Theme.dangerInk }
                                            case "Rename": return { g: "→", w: qsTr("Renommé"), c: Theme.ink2 }
                                            }
                                            return { g: "·", w: modelData.type, c: Theme.ink2 }
                                        }
                                        RowLayout {
                                            visible: hr.modelData.newDay
                                            Layout.fillWidth: true
                                            Layout.topMargin: 16
                                            Layout.bottomMargin: 6
                                            spacing: 10
                                            CapsLabel { text: hr.modelData.day; color: Theme.ink2 }
                                            Text {
                                                text: root.plural(root.dayCount(hr.modelData.day), qsTr("opération"), qsTr("opérations"))
                                                color: Theme.ink3
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.fs(11.5)
                                            }
                                        }
                                        Rectangle { visible: hr.modelData.newDay; Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.ruleInk }
                                        RowLayout {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: hr.modelData.type === "Rename" ? 50 : 40
                                            spacing: 12
                                            Text { Layout.preferredWidth: 44; text: hr.modelData.time; color: Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12); font.features: ({ "tnum": 1 }) }
                                            Row {
                                                Layout.preferredWidth: 104
                                                spacing: 7
                                                Rectangle {
                                                    width: 18; height: 18; radius: 9
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    color: "transparent"
                                                    border.width: 1
                                                    border.color: Theme.lineStrong
                                                    Text { anchors.centerIn: parent; text: hr.op.g; color: hr.op.c; font.family: Theme.fontFamilySerif; font.pixelSize: Theme.fs(12); font.weight: Theme.weightBold }
                                                }
                                                Text { anchors.verticalCenter: parent.verticalCenter; text: hr.op.w; color: hr.op.c; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12.5); font.weight: Theme.weightSemibold }
                                            }
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 1
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: hr.modelData.relativePath
                                                    color: hr.modelData.type === "Delete" ? Theme.ink3 : Theme.ink
                                                    font.strikeout: hr.modelData.type === "Delete"
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: Theme.fs(13)
                                                    elide: Text.ElideMiddle
                                                }
                                                Text {
                                                    visible: hr.modelData.type === "Rename" && hr.modelData.oldRelativePath.length > 0
                                                    Layout.fillWidth: true
                                                    text: qsTr("ancien nom : %1").arg(hr.modelData.oldRelativePath)
                                                    color: Theme.ink3
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: Theme.fs(11.5)
                                                    elide: Text.ElideMiddle
                                                }
                                            }
                                            Text { Layout.preferredWidth: 40; horizontalAlignment: Text.AlignRight; text: "v" + hr.modelData.version; color: Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12) }
                                        }
                                        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.line }
                                    }
                                }
                                Text {
                                    Layout.topMargin: 12
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                    text: root.historyRows.length === 0
                                          ? qsTr("Aucune opération enregistrée pour ce dossier. Réindexez-le pour commencer le journal.")
                                          : qsTr("Les 100 dernières opérations de ce dossier, sur ce poste.")
                                    color: Theme.ink3
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(12)
                                }
                            }
                        }
                    }
                }
            }
        }

        // ---- volet « Nouveau dossier partage » ----
        Item {
            id: composerHost
            anchors.fill: parent
            z: 30
            visible: root.composerOpen || composer.x < composerHost.width

            Rectangle {
                anchors.fill: parent
                color: Theme.scrim
                opacity: root.composerOpen ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 160 } }
                MouseArea { anchors.fill: parent; enabled: root.composerOpen; onClicked: root.composerOpen = false }
            }

            FolderComposer {
                id: composer
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: page.narrow ? composerHost.width : Math.min(460, composerHost.width - 48)
                x: root.composerOpen ? composerHost.width - width : composerHost.width
                Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                users: root.composerUsers
                localPath: root.composerPath
                done: root.composerDone
                errorText: root.composerError
                builtinExcludes: root.context ? root.context.builtinExcludePatterns() : []

                onCloseRequested: root.composerOpen = false
                onBrowseRequested: composerPicker.open()
                onPathDropped: function(path) { root.composerPath = path }
                onErrorDismissed: root.composerError = ""
                onCreateRequested: function(name, path, userIds, allowWrite, excludes) {
                    if (!root.context) return
                    if (root.context.createFolder(name, path, userIds, allowWrite, excludes)) {
                        root.composerDone = true
                        root.scheduleRebuild()
                    } else {
                        root.composerError = root.context.lastErrorString || qsTr("Le dossier n'a pas pu être partagé.")
                    }
                }
            }
        }

        // ---- fenetres ----
        FolderAccessSheet {
            id: accessSheet
            open: root.sheet === "access"
            context: root.context
            folderId: root.openedFolderId
            folderName: root.currentFolder ? root.currentFolder.name : ""
            onCloseRequested: root.sheet = ""
            onAccessChanged: { root.refreshAccess(); root.scheduleRebuild() }
        }
        FolderExclusionsSheet {
            id: exclusionsSheet
            open: root.sheet === "exclusions"
            context: root.context
            folderId: root.openedFolderId
            folderName: root.currentFolder ? root.currentFolder.name : ""
            onCloseRequested: root.sheet = ""
            onSaved: { root.sheet = ""; root.refreshFiles(); root.refreshHistory(); root.refreshAccess(); root.scheduleRebuild() }
        }
        FolderLocationSheet {
            id: locationSheet
            open: root.sheet === "location"
            folderName: root.currentFolder ? root.currentFolder.name : ""
            ownerName: root.currentFolder ? root.currentFolder.ownerName : ""
            hasPath: !root.currentNoPath
            suggestedPath: root.defaultSharedPath.length && root.currentFolder ? root.defaultSharedPath + "/" + root.currentFolder.name : ""
            onCloseRequested: { root.sheet = ""; locationSheet.localPath = "" }
            onBrowseRequested: locationPicker.open()
            onConfirmed: {
                if (root.context && root.openedFolderId >= 0 && root.context.setFolderLocalPath(root.openedFolderId, locationSheet.localPath)) {
                    root.sheet = ""
                    locationSheet.localPath = ""
                    root.refreshAll()
                }
            }
        }
        FolderRemoveSheet {
            open: root.sheet === "remove"
            folderName: root.currentFolder ? root.currentFolder.name : ""
            received: root.currentReceived
            ownerName: root.currentFolder ? root.currentFolder.ownerName : ""
            localPath: root.currentFolder ? root.currentFolder.localPath : ""
            memberCount: root.currentAccess.length
            onCloseRequested: root.sheet = ""
            onConfirmed: {
                const id = root.openedFolderId
                root.sheet = ""
                if (root.context && id >= 0) {
                    root.openedFolderId = -1
                    root.context.removeFolder(id)
                    root.scheduleRebuild()
                }
            }
        }
        FolderInviteSheet {
            id: inviteSheet
            onAccepted: {
                if (root.context && inviteSheet.folderId >= 0) root.context.acceptFolderShare(inviteSheet.folderId)
                inviteSheet.open = false
                root.scheduleRebuild()
                Qt.callLater(root.showNextShareConfirmation)
            }
            onPostponed: {
                if (root.context && inviteSheet.folderId >= 0) root.context.declineFolderShare(inviteSheet.folderId)
                inviteSheet.open = false
                root.scheduleRebuild()
                Qt.callLater(root.showNextShareConfirmation)
            }
            onOpenChanged: if (!inviteSheet.open && root.pendingShareConfirmations.length === 0) { inviteSheet.queueTotal = 0; inviteSheet.queueIndex = 0 }
        }
    }
}
