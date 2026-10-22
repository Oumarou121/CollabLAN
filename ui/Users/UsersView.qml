import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import "../Components"
import "../Chat"
import "../Components/icons.js" as Icons
import "../Call/callPeople.js" as People

/*
 * UsersView - ecran « Postes » en Ligne claire, meme squelette que
 * Transferts et Dossiers partages :
 *
 *   [surtitre · phrase-titre · demande en attente ........ 4 chiffres serif]
 *   [Registre (en ligne / hors ligne / a l'ecart)  | fiche du poste choisi  ]
 *
 * Donnees : peersModel (postes detectes, temps reel), authorizedMachineModel
 * (administrateur : postes autorises absents, demandes, acces retires,
 * empreinte, date d'autorisation), messagingContext (personne derriere un
 * poste, via userUuid). Un poste hors ligne n'est connu que par son
 * autorisation : aucune date de derniere connexion n'est inventee.
 *
 * Actions : envoyer un fichier, appeler, ecrire, ouvrir le dossier
 * d'echanges ; administrateur : autoriser, refuser, revoquer (toujours
 * confirme).
 */
Item {
    id: root

    property var model: (typeof peersModel !== "undefined") ? peersModel : null
    property var machines: (typeof authorizedMachineModel !== "undefined") ? authorizedMachineModel : null
    property var messaging: (typeof messagingContext !== "undefined") ? messagingContext : null
    readonly property bool isAdmin: (typeof userManager !== "undefined" && userManager)
                                    ? userManager.currentUserIsAdmin : false

    signal backRequested()
    signal fileTransferRequested(var peer)
    signal adminRequested()
    signal conversationRequested(int conversationId)
    signal exchangesRequested(string peerKey)

    // Fil d'Ariane global (AppShell) : "Postes / <poste choisi>".
    readonly property string breadcrumbLeaf: root.selected ? root.selected.machine : ""
    function breadcrumbRootClicked() { root.selectedKey = "" }

    // ======================================================================
    // Donnees
    // ======================================================================
    property var rows: []
    property var users: ({})                 // userUuid -> { userId, username }

    function readUsers() {
        const map = {}
        if (root.messaging && root.messaging.availableUsers) {
            const list = root.messaging.availableUsers() || []
            for (let i = 0; i < list.length; i++)
                if (list[i].userUuid) map[list[i].userUuid] = { userId: list[i].userId, username: list[i].username }
        }
        return map
    }

    // Autorisations (administrateur). Les roles sans propriete exposee
    // (AddedBy, AddedAt) sont lus par leur valeur d'enum (UserRole + 10/11).
    function readMachines() {
        const out = []
        const m = root.machines
        if (!root.isAdmin || !m) return out
        const total = m.rowCount ? m.rowCount() : 0
        for (let i = 0; i < total; i++) {
            const idx = m.index(i, 0)
            const status = m.data(idx, m.StatusRole) || ""
            const authorized = m.data(idx, m.AuthorizedRole)
            out.push({
                rowId: m.data(idx, m.IdRole),
                ip: m.data(idx, m.IpAddressRole) || "",
                machineId: m.data(idx, m.MachineIdRole) || "",
                host: m.data(idx, m.HostnameRole) || "",
                fingerprint: m.data(idx, m.CertificateFingerprintRole) || "",
                addedBy: m.data(idx, m.AddedByRole || 266),
                addedAt: m.data(idx, m.AddedAtRole || 267) || "",
                trust: status === "revoked" ? "revoked" : (authorized ? "authorized" : "pending")
            })
        }
        return out
    }

    function refresh() {
        root.users = root.readUsers()
        const peers = People.readPeers(root.model)
        const auth = root.readMachines()
        const used = {}
        const out = []
        // Postes detectes, relies a leur autorisation par identifiant puis adresse.
        for (let i = 0; i < peers.length; i++) {
            const p = peers[i]
            let a = null
            for (let j = 0; j < auth.length && !a; j++)
                if (!used[j] && auth[j].machineId.length && auth[j].machineId === p.id) { a = auth[j]; used[j] = true }
            for (let j = 0; j < auth.length && !a; j++)
                if (!used[j] && auth[j].ip.length && auth[j].ip === p.address) { a = auth[j]; used[j] = true }
            const lastSeen = root.model ? (root.model.data(root.model.index(i, 0), 265) || 0) : 0
            out.push(root.makeRow(p.machine || p.address, p.address, p, a, lastSeen))
        }
        // Autorisations sans poste detecte : hors ligne, demandes, acces retires.
        for (let j = 0; j < auth.length; j++)
            if (!used[j]) out.push(root.makeRow(auth[j].host || auth[j].ip || auth[j].machineId, auth[j].ip, null, auth[j], 0))
        root.rows = out
        if (root.selectedKey.length && !root.rowByKey(root.selectedKey)) root.selectedKey = ""
        if (!root.selectedKey.length && out.length) root.selectedKey = root.sortedVisible()[0] ? root.sortedVisible()[0].key : out[0].key
    }

    function makeRow(machine, address, peer, auth, lastSeen) {
        const person = peer && peer.userUuid && root.users[peer.userUuid] ? root.users[peer.userUuid] : null
        const status = peer ? People.presenceKind(peer.status) : "offline"
        const trust = auth ? auth.trust : (peer ? "" : "authorized")
        const st = trust === "pending" ? "pending" : trust === "revoked" ? "revoked" : (peer ? status : "off")
        return {
            key: (peer && peer.id) || (auth && auth.machineId) || address || machine,
            machine: machine, address: address,
            port: peer ? root.portOf(peer.id) : 0,
            online: !!peer, st: st, trust: trust,
            person: person ? person.username : "", userId: person ? person.userId : -1,
            userUuid: peer ? peer.userUuid : "",
            peerId: peer ? peer.id : "", signalingPort: peer ? peer.signalingPort : 0,
            lastSeenMs: lastSeen,
            rowId: auth ? auth.rowId : -1, fingerprint: auth ? auth.fingerprint : "",
            addedAt: auth ? auth.addedAt : "", addedBy: auth ? auth.addedBy : -1,
            group: st === "pending" || st === "revoked" ? "aside" : (peer ? "online" : "off")
        }
    }
    function portOf(id) {
        if (!root.model) return 0
        const n = root.model.rowCount ? root.model.rowCount() : (root.model.count || 0)
        for (let i = 0; i < n; i++) {
            const idx = root.model.index(i, 0)
            if ((root.model.data(idx, 257) || "") === id) return root.model.data(idx, 262) || 0
        }
        return 0
    }

    Component.onCompleted: root.refresh()
    Connections {
        target: root.model
        ignoreUnknownSignals: true
        function onCountChanged() { root.refresh() }
        function onDataChanged() { root.refresh() }
        function onModelReset() { root.refresh() }
        function onRowsInserted() { root.refresh() }
        function onRowsRemoved() { root.refresh() }
    }
    Connections {
        target: root.machines
        ignoreUnknownSignals: true
        function onModelReset() { root.refresh() }
        function onDataChanged() { root.refresh() }
        function onRowsInserted() { root.refresh() }
        function onRowsRemoved() { root.refresh() }
    }
    Connections {
        target: root.messaging
        ignoreUnknownSignals: true
        function onAvailableUsersChanged() { root.refresh() }
        function onPresenceChanged() { root.refresh() }
    }
    // « Vu il y a… » vieillit avec le temps.
    Timer { interval: 30000; running: root.visible; repeat: true; onTriggered: root.refresh() }

    // ======================================================================
    // Filtres, selection
    // ======================================================================
    property string filter: "all"            // "all" | "online" | "off" | "aside"
    property string searchText: ""
    property string selectedKey: ""

    function labelOf(r) { return r.person.length ? r.person : r.machine }
    function sortedVisible() {
        const q = root.searchText.trim().toLowerCase()
        const rank = { online: 0, busy: 1, away: 2 }
        return root.rows.filter(function(r) {
            if (root.filter !== "all" && r.group !== root.filter) return false
            return q.length === 0 || root.labelOf(r).toLowerCase().indexOf(q) !== -1
                   || r.machine.toLowerCase().indexOf(q) !== -1 || r.address.indexOf(q) !== -1
        }).sort(function(a, b) {
            const ga = ["online", "off", "aside"].indexOf(a.group), gb = ["online", "off", "aside"].indexOf(b.group)
            if (ga !== gb) return ga - gb
            if (a.group === "aside" && a.st !== b.st) return a.st === "pending" ? -1 : 1
            return root.labelOf(a).localeCompare(root.labelOf(b))
        })
    }
    readonly property var visibleRows: { root.rows; root.filter; root.searchText; return root.sortedVisible() }
    function rowByKey(k) {
        for (let i = 0; i < root.rows.length; i++) if (root.rows[i].key === k) return root.rows[i]
        return null
    }
    readonly property var selected: root.rowByKey(root.selectedKey)

    readonly property var stats: {
        const s = { online: 0, off: 0, pending: 0, people: 0, authorized: 0 }
        for (let i = 0; i < root.rows.length; i++) {
            const r = root.rows[i]
            if (r.group === "online") s.online++
            if (r.group === "off") s.off++
            if (r.st === "pending") s.pending++
            if (r.group === "online" && r.person.length) s.people++
            if (r.trust === "authorized" || (r.online && r.trust === "")) s.authorized++
        }
        return s
    }
    readonly property var firstPending: {
        for (let i = 0; i < root.rows.length; i++) if (root.rows[i].st === "pending") return root.rows[i]
        return null
    }

    // ======================================================================
    // Outils
    // ======================================================================
    function stateWord(st) {
        switch (st) {
        case "online": return qsTr("En ligne")
        case "away": return qsTr("Absent")
        case "busy": return qsTr("Occupé")
        case "pending": return qsTr("En attente")
        case "revoked": return qsTr("Révoqué")
        }
        return qsTr("Hors ligne")
    }
    function stateGlyph(st) {
        switch (st) {
        case "online": case "away": case "busy": return st
        case "pending": return "decision"
        case "revoked": return "error"
        case "ok": return "ok"
        }
        return "offline"
    }
    function stateInk(st) {
        switch (st) {
        case "online": return Theme.successInk
        case "away": case "busy": case "pending": return Theme.warningInk
        case "revoked": return Theme.dangerInk
        }
        return Theme.ink3       // "off", "ok" (autorise)
    }
    function seenLabel(ms) {
        if (!ms || ms < 1e12) return ""
        const seconds = Math.max(0, Math.round((Date.now() - ms) / 1000))
        if (seconds < 60) return qsTr("à l'instant")
        if (seconds < 3600) return qsTr("il y a %1 min").arg(Math.max(1, Math.round(seconds / 60)))
        return new Date(ms).toLocaleTimeString(Qt.locale(), "HH:mm")
    }
    function dateLabel(iso) {
        const d = new Date(iso)
        return isNaN(d.getTime()) ? "" : d.toLocaleDateString(Qt.locale(), "d MMM yyyy")
    }
    function nameOfUser(id) {
        return id !== undefined && id >= 0 && root.messaging && root.messaging.userName ? root.messaging.userName(id) : ""
    }
    function shortPrint(fp) {
        return fp && fp.length ? (fp.length > 11 ? fp.slice(0, 11) + "…" : fp) : "—"
    }
    function esc(t) { return String(t === undefined || t === null ? "" : t).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;") }

    // ======================================================================
    // Actions
    // ======================================================================
    property string notice: ""
    function showNotice(t) { root.notice = t; noticeTimer.restart() }
    Timer { id: noticeTimer; interval: 6000; onTriggered: root.notice = "" }

    function sendTo(r) {
        if (r && r.online) root.fileTransferRequested({ id: r.peerId, name: r.machine, address: r.address, status: r.st, userUuid: r.userUuid })
    }
    function callTo(r) {
        if (!r || !r.online || typeof callContext === "undefined" || !callContext) return
        if (!callContext.call(r.address, r.signalingPort || 0))
            root.showNotice(qsTr("Impossible d'appeler %1.").arg(root.labelOf(r)))
    }
    function writeTo(r) {
        if (!r || r.userId < 0 || !root.messaging) return
        const id = root.messaging.startConversationWith(r.userId)
        if (id > 0) root.conversationRequested(id)
        else root.showNotice(qsTr("La discussion n'a pas pu être ouverte."))
    }
    function exchangesOf(r) {
        if (!r) return
        root.exchangesRequested(r.userUuid.length ? "user:" + r.userUuid : (r.peerId.length ? "uuid:" + r.peerId : r.address))
    }

    property string confirm: ""              // "" | "allow" | "deny" | "revoke"
    function applyConfirm() {
        const r = root.selected, m = root.machines
        if (!r || !m || r.rowId === undefined || r.rowId < 0) { root.confirm = ""; return }
        let ok = false
        if (root.confirm === "allow") ok = m.authorizeMachine(r.rowId, "Autorisé par admin")
        else if (root.confirm === "deny") ok = m.revokeMachine(r.rowId, "Refusé par admin")
        else if (root.confirm === "revoke") ok = m.revokeMachine(r.rowId, "Révoqué par admin")
        if (!ok) root.showNotice(root.confirm === "allow" ? qsTr("Le poste n'a pas pu être autorisé.") : qsTr("L'accès n'a pas pu être retiré."))
        root.confirm = ""
        if (m.refresh) m.refresh()
        root.refresh()
    }

    // ======================================================================
    // Composants
    // ======================================================================
    readonly property real pageW: width - 2 * Theme.pagePadding
    readonly property bool heroWide: pageW > 1180
    readonly property bool ficheDocked: pageW > 980
    readonly property bool showAddress: pageW > 1240 || (!root.ficheDocked && pageW > 760)
    readonly property bool showSeen: pageW > 980

    // Marque d'un poste : personne (initiales), poste sans compte, absent,
    // demande (ambre), acces retire (rouge).
    component PosteMark: Item {
        id: pm
        property var r: null
        property real size: 36
        implicitWidth: size
        implicitHeight: size
        readonly property string st: pm.r ? pm.r.st : "off"
        ChatMonogram {
            visible: pm.r !== null && pm.r.online && pm.st !== "pending" && pm.st !== "revoked"
            size: pm.size
            label: pm.r ? root.labelOf(pm.r) : ""
            machine: pm.r !== null && pm.r.person.length === 0
            status: pm.r ? pm.st : ""
        }
        Rectangle {
            visible: !(pm.r !== null && pm.r.online && pm.st !== "pending" && pm.st !== "revoked")
            anchors.fill: parent
            radius: width / 2
            color: pm.st === "pending" ? Theme.warningSoft : pm.st === "revoked" ? Theme.dangerSoft : "transparent"
            border.width: 1
            border.color: pm.st === "pending" ? Theme.warningColor : pm.st === "revoked" ? Theme.dangerColor : Theme.line
            LineIcon {
                anchors.centerIn: parent
                path: pm.st === "revoked" ? Icons.ban : Icons.monitor
                size: Math.round(pm.size * 0.45)
                strokeWidth: 1.6
                color: pm.st === "pending" ? Theme.warningInk : pm.st === "revoked" ? Theme.dangerInk : Theme.ink3
            }
        }
    }

    component InkTab: AbstractButton {
        id: it
        property bool current: false
        property string count: ""
        property bool danger: false
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
                Text { text: it.text; color: it.current || it.hovered ? Theme.ink : Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12.5); font.weight: it.current ? Theme.weightSemibold : Theme.weightMedium }
                Text { text: it.count; color: it.danger && it.count !== "0" ? Theme.dangerInk : Theme.ink3; font.family: Theme.fontFamilySerif; font.pixelSize: Theme.fs(12); font.weight: Theme.weightBold }
            }
        }
    }

    component StateLine: Row {
        property string st: "off"
        property string word: ""
        spacing: 7
        StateGlyph { anchors.verticalCenter: parent.verticalCenter; kind: root.stateGlyph(parent.st); size: 11 }
        Text { anchors.verticalCenter: parent.verticalCenter; text: parent.word.length ? parent.word : root.stateWord(parent.st); color: root.stateInk(parent.st); font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12.5); font.weight: parent.st === "off" || parent.st === "ok" ? Theme.weightMedium : Theme.weightSemibold }
    }

    component FicheAction: AbstractButton {
        id: fa
        property string iconPath: ""
        property string hint: ""
        property bool first: false
        Layout.fillWidth: true
        implicitHeight: 40
        hoverEnabled: true
        focusPolicy: Qt.StrongFocus
        Accessible.name: fa.text
        HoverHandler { cursorShape: fa.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
        background: Rectangle {
            color: fa.hovered && fa.enabled ? Theme.ink : "transparent"
            border.width: fa.visualFocus ? 2 : 0
            border.color: Theme.focusRing
            Rectangle { visible: !fa.first; width: parent.width; height: 1; color: Theme.lineStrong }
        }
        contentItem: RowLayout {
            spacing: 10
            LineIcon { Layout.leftMargin: 12; path: fa.iconPath; size: 15; strokeWidth: 1.8; color: !fa.enabled ? Theme.inkDisabled : fa.hovered ? Theme.inkOnInk : Theme.ink3 }
            Text { Layout.fillWidth: true; text: fa.text; color: !fa.enabled ? Theme.inkDisabled : fa.hovered ? Theme.inkOnInk : Theme.ink; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13); font.weight: Theme.weightSemibold }
            Text { Layout.rightMargin: 12; visible: fa.hint.length > 0; text: fa.hint; color: fa.hovered && fa.enabled ? Theme.inkOnInk : Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(11.5) }
        }
    }

    component Fact: RowLayout {
        property string key: ""
        property string value: ""
        property bool mono: false
        Layout.fillWidth: true
        Text { text: parent.key; color: Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13) }
        Text { Layout.fillWidth: true; horizontalAlignment: Text.AlignRight; text: parent.value; color: Theme.ink; font.family: parent.mono ? "Cascadia Mono" : Theme.fontFamily; font.pixelSize: parent.mono ? Theme.fs(12) : Theme.fs(13); elide: Text.ElideMiddle }
    }

    // ======================================================================
    // Page
    // ======================================================================
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

            // ---- Avis --------------------------------------------------------
            Rectangle {
                visible: root.notice.length > 0
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
                    Text { Layout.fillWidth: true; text: root.notice; wrapMode: Text.WordWrap; color: Theme.ink; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13) }
                    TextLink { text: qsTr("OK"); arrow: false; onClicked: root.notice = "" }
                }
            }

            // ---- En-tete -----------------------------------------------------
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
                        textFormat: Text.StyledText
                        text: root.rows.length === 0 ? qsTr("Aucun autre poste détecté.")
                              : root.stats.online === 1 ? qsTr("<b>1</b> poste en ligne.")
                              : qsTr("<b>%1</b> postes en ligne.").arg(root.stats.online)
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
                            width: Math.min(implicitWidth, parent.width, 600)
                            height: Math.max(implicitHeight, heroActions.implicitHeight)
                            verticalAlignment: Text.AlignVCenter
                            textFormat: Text.StyledText
                            wrapMode: Text.WordWrap
                            color: Theme.ink2
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(14.5)
                            text: {
                                if (root.rows.length === 0)
                                    return qsTr("Les postes qui lancent LocaLink sur le même réseau local apparaissent ici automatiquement.")
                                let t = root.isAdmin
                                        ? qsTr("Sur <b>%1</b> postes autorisés ; %2 personne(s) connectée(s).").arg(root.stats.online + root.stats.off).arg(root.stats.people)
                                        : qsTr("%1 personne(s) connectée(s) sur le réseau local.").arg(root.stats.people)
                                if (root.firstPending) {
                                    const who = root.stats.pending > 1 ? qsTr("%1 postes demandent").arg(root.stats.pending)
                                                                       : qsTr("%1 demande").arg(root.esc(root.firstPending.machine))
                                    t += " " + "<b><font color=\"" + Theme.warningInk + "\">" + who + "</font></b> " + qsTr("à rejoindre le réseau.")
                                }
                                return t
                            }
                        }
                        Row {
                            id: heroActions
                            spacing: 8
                            AppButton {
                                visible: root.isAdmin
                                variant: "line"
                                iconPath: Icons.shield
                                text: qsTr("Gérer les autorisations")
                                onClicked: root.adminRequested()
                            }
                        }
                    }
                }

                Item {
                    visible: root.rows.length > 0
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
                            model: root.isAdmin ? [
                                { key: "online", label: qsTr("En ligne"), value: root.stats.online, ctx: qsTr("détectés à l'instant") },
                                { key: "off", label: qsTr("Hors ligne"), value: root.stats.off, ctx: qsTr("autorisés, absents") },
                                { key: "aside", label: qsTr("En attente"), value: root.stats.pending, ctx: root.stats.pending ? qsTr("à autoriser") : qsTr("aucune demande"), attention: root.stats.pending > 0 },
                                { key: "", label: qsTr("Personnes"), value: root.stats.people, ctx: qsTr("comptes connectés") }
                            ] : [
                                { key: "online", label: qsTr("En ligne"), value: root.stats.online, ctx: qsTr("postes du réseau") },
                                { key: "", label: qsTr("Personnes"), value: root.stats.people, ctx: qsTr("comptes connectés") }
                            ]
                            delegate: Item {
                                id: fig
                                required property var modelData
                                required property int index
                                readonly property int n: root.isAdmin ? 4 : 2
                                width: root.heroWide ? sf.width + (index === 0 ? 0 : 22) + (index === n - 1 ? 0 : 22) : figRow.width / n
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
                                    onClicked: if (fig.modelData.key.length) root.filter = root.filter === fig.modelData.key ? "all" : fig.modelData.key
                                }
                            }
                        }
                    }
                }
            }

            // ---- Registre | fiche --------------------------------------------
            Rectangle { Layout.fillWidth: true; Layout.topMargin: -4; Layout.preferredHeight: 2; color: Theme.ruleInk }

            GridLayout {
                Layout.fillWidth: true
                Layout.topMargin: -20
                columns: root.ficheDocked ? 2 : 1
                columnSpacing: 0
                rowSpacing: 0

                // -- Registre -------------------------------------------------
                ColumnLayout {
                    id: reg
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    Layout.topMargin: 14
                    Layout.rightMargin: root.ficheDocked ? 24 : 0
                    spacing: 0

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.bottomMargin: 8
                        CapsLabel { text: qsTr("Registre des postes"); Layout.fillWidth: true }
                        Text { text: root.rows.length; color: Theme.ink3; font.family: Theme.fontFamilySerif; font.pixelSize: Theme.fs(16); font.weight: Theme.weightBold }
                    }
                    Item {
                        Layout.fillWidth: true
                        implicitHeight: 38
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
                        Row {
                            anchors.bottom: parent.bottom
                            spacing: 18
                            InkTab { text: qsTr("Tous"); count: String(root.rows.length); current: root.filter === "all"; onClicked: root.filter = "all" }
                            InkTab { text: qsTr("En ligne"); count: String(root.stats.online); current: root.filter === "online"; onClicked: root.filter = "online" }
                            InkTab { visible: root.isAdmin; text: qsTr("Hors ligne"); count: String(root.stats.off); current: root.filter === "off"; onClicked: root.filter = "off" }
                            InkTab {
                                visible: root.isAdmin
                                text: qsTr("À l'écart")
                                danger: true
                                count: String(root.rows.filter(function(r) { return r.group === "aside" }).length)
                                current: root.filter === "aside"
                                onClicked: root.filter = "aside"
                            }
                        }
                        Rectangle {
                            visible: root.rows.length > 0
                            anchors.right: parent.right
                            anchors.top: parent.top
                            width: Math.min(240, parent.width * 0.4)
                            height: 30
                            radius: Theme.radiusSheet
                            color: "transparent"
                            border.width: 1
                            border.color: regFind.activeFocus ? Theme.ink : Theme.line
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 8
                                spacing: 7
                                LineIcon { path: Icons.search; size: 14; strokeWidth: 1.8; color: Theme.ink3 }
                                TextField {
                                    id: regFind
                                    Layout.fillWidth: true
                                    placeholderText: qsTr("Personne, poste ou adresse…")
                                    placeholderTextColor: Theme.ink3
                                    color: Theme.ink
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(12.5)
                                    background: Item {}
                                    leftPadding: 0
                                    rightPadding: 0
                                    selectByMouse: true
                                    Accessible.name: qsTr("Rechercher un poste")
                                    onTextChanged: root.searchText = text
                                }
                            }
                        }
                    }

                    Text {
                        visible: root.rows.length === 0
                        Layout.fillWidth: true
                        Layout.topMargin: 14
                        text: qsTr("Aucun poste pour l'instant. Vérifiez que les autres postes lancent LocaLink sur le même réseau local.")
                        color: Theme.ink3
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(12.5)
                        wrapMode: Text.WordWrap
                    }
                    Text {
                        visible: root.rows.length > 0 && root.visibleRows.length === 0
                        Layout.topMargin: 14
                        text: qsTr("Aucun poste ne correspond.")
                        color: Theme.ink3
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(12.5)
                    }

                    // En-tetes de colonnes
                    RowLayout {
                        visible: root.visibleRows.length > 0
                        Layout.fillWidth: true
                        Layout.topMargin: 10
                        Layout.leftMargin: 8
                        Layout.rightMargin: 8
                        spacing: 14
                        CapsLabel { Layout.fillWidth: true; text: qsTr("Poste"); font.pixelSize: Theme.fs(10) }
                        CapsLabel { Layout.preferredWidth: 120; text: qsTr("Disponibilité"); font.pixelSize: Theme.fs(10) }
                        CapsLabel { visible: root.isAdmin; Layout.preferredWidth: 104; text: qsTr("Confiance"); font.pixelSize: Theme.fs(10) }
                        CapsLabel { visible: root.showAddress; Layout.preferredWidth: 150; text: qsTr("Adresse"); font.pixelSize: Theme.fs(10) }
                        CapsLabel { visible: root.showSeen; Layout.preferredWidth: 90; horizontalAlignment: Text.AlignRight; text: qsTr("Vu"); font.pixelSize: Theme.fs(10) }
                    }
                    Rectangle { visible: root.visibleRows.length > 0; Layout.fillWidth: true; Layout.topMargin: 6; Layout.preferredHeight: 1; color: Theme.ruleInk }

                    Repeater {
                        model: root.visibleRows
                        delegate: ColumnLayout {
                            id: pr
                            required property var modelData
                            required property int index
                            readonly property var r: modelData
                            readonly property var prev: index > 0 ? root.visibleRows[index - 1] : null
                            readonly property bool newGroup: !prev || prev.group !== r.group
                            readonly property bool on: r.key === root.selectedKey
                            Layout.fillWidth: true
                            spacing: 0

                            RowLayout {
                                visible: pr.newGroup
                                Layout.fillWidth: true
                                Layout.leftMargin: 8
                                Layout.topMargin: 14
                                Layout.bottomMargin: 6
                                spacing: 10
                                CapsLabel {
                                    text: pr.r.group === "online" ? qsTr("En ligne") : pr.r.group === "off" ? qsTr("Hors ligne · autorisés") : qsTr("À l'écart · demandes et accès retirés")
                                    color: Theme.ink2
                                }
                                Text {
                                    text: root.visibleRows.filter(function(x) { return x.group === pr.r.group }).length
                                    color: Theme.ink3
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(11.5)
                                }
                            }

                            AbstractButton {
                                id: rowBtn
                                Layout.fillWidth: true
                                implicitHeight: 54
                                hoverEnabled: true
                                focusPolicy: Qt.TabFocus
                                Accessible.name: root.labelOf(pr.r) + ", " + root.stateWord(pr.r.st)
                                onClicked: root.selectedKey = pr.r.key
                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                                background: Rectangle {
                                    color: pr.on ? Theme.surface0 : (rowBtn.hovered ? Theme.selectWash : "transparent")
                                    border.width: pr.on ? 1 : (rowBtn.visualFocus ? 2 : 0)
                                    border.color: rowBtn.visualFocus ? Theme.focusRing : Theme.line
                                    Rectangle { visible: pr.on; width: 3; height: parent.height; color: Theme.ruleInk }
                                    Rectangle { visible: !pr.on; anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
                                }
                                contentItem: RowLayout {
                                    spacing: 14
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Layout.leftMargin: 8
                                        spacing: 12
                                        PosteMark { r: pr.r }
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 1
                                            Text {
                                                Layout.fillWidth: true
                                                text: root.labelOf(pr.r)
                                                color: pr.r.online ? Theme.ink : Theme.ink3
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.fs(13.5)
                                                font.weight: Theme.weightSemibold
                                                elide: Text.ElideRight
                                            }
                                            Text {
                                                visible: pr.r.person.length > 0
                                                Layout.fillWidth: true
                                                text: pr.r.machine
                                                color: Theme.ink3
                                                font.family: "Cascadia Mono"
                                                font.pixelSize: Theme.fs(11.5)
                                                elide: Text.ElideRight
                                            }
                                        }
                                    }
                                    StateLine { Layout.preferredWidth: 120; st: pr.r.st }
                                    StateLine {
                                        visible: root.isAdmin
                                        Layout.preferredWidth: 104
                                        st: pr.r.st === "pending" ? "pending" : pr.r.st === "revoked" ? "revoked" : "ok"
                                        word: pr.r.st === "pending" ? qsTr("À autoriser") : pr.r.st === "revoked" ? qsTr("Révoqué") : qsTr("Autorisé")
                                    }
                                    Text {
                                        visible: root.showAddress
                                        Layout.preferredWidth: 150
                                        text: pr.r.address + (pr.r.online && pr.r.port ? ":" + pr.r.port : "")
                                        color: Theme.ink2
                                        font.family: "Cascadia Mono"
                                        font.pixelSize: Theme.fs(12)
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        visible: root.showSeen
                                        Layout.preferredWidth: 90
                                        Layout.rightMargin: 8
                                        horizontalAlignment: Text.AlignRight
                                        text: root.seenLabel(pr.r.lastSeenMs) || "—"
                                        color: Theme.ink3
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fs(12)
                                    }
                                }
                            }
                        }
                    }
                }

                // -- Fiche ------------------------------------------------------
                Item {
                    id: ficheCol
                    visible: root.selected !== null
                    Layout.preferredWidth: root.ficheDocked ? (root.pageW > 1240 ? 340 : 300) : -1
                    Layout.fillWidth: !root.ficheDocked
                    Layout.alignment: Qt.AlignTop
                    implicitHeight: fiche.implicitHeight + 34
                    Rectangle { visible: root.ficheDocked; width: 1; height: Math.max(parent.height, reg.height + 14); color: Theme.line }
                    Rectangle { visible: !root.ficheDocked; width: parent.width; height: 1; y: 10; color: Theme.line }

                    ColumnLayout {
                        id: fiche
                        readonly property var r: root.selected
                        x: root.ficheDocked ? 24 : 0
                        y: root.ficheDocked ? 16 : 26
                        width: parent.width - x
                        spacing: 0

                        CapsLabel { text: fiche.r && fiche.r.st === "pending" ? qsTr("Demande d'accès") : qsTr("Poste") }
                        PosteMark { Layout.topMargin: 10; r: fiche.r; size: 64 }
                        Text {
                            Layout.fillWidth: true
                            Layout.topMargin: 10
                            text: fiche.r ? root.labelOf(fiche.r) : ""
                            color: Theme.ink
                            font.family: Theme.fontFamilySerif
                            font.pixelSize: Theme.fs(22)
                            font.weight: Theme.weightBold
                            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                            Accessible.role: Accessible.Heading
                        }
                        Text {
                            visible: !!fiche.r && fiche.r.person.length > 0
                            Layout.fillWidth: true
                            Layout.topMargin: 2
                            text: fiche.r ? fiche.r.machine : ""
                            color: Theme.ink2
                            font.family: "Cascadia Mono"
                            font.pixelSize: Theme.fs(12.5)
                            wrapMode: Text.WrapAnywhere
                        }
                        StateLine {
                            Layout.topMargin: 8
                            st: fiche.r ? fiche.r.st : "off"
                            word: fiche.r ? root.stateWord(fiche.r.st) + (root.seenLabel(fiche.r.lastSeenMs).length ? " · " + qsTr("vu %1").arg(root.seenLabel(fiche.r.lastSeenMs)) : "") : ""
                        }

                        Rectangle { Layout.fillWidth: true; Layout.topMargin: 14; Layout.bottomMargin: 10; Layout.preferredHeight: 1; color: Theme.line }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 7
                            Fact { key: qsTr("Adresse"); value: fiche.r ? fiche.r.address : ""; mono: true }
                            Fact { visible: !!fiche.r && fiche.r.online && fiche.r.port > 0; key: qsTr("Port"); value: fiche.r ? String(fiche.r.port) : ""; mono: true }
                            Fact { key: qsTr("Compte"); value: fiche.r && fiche.r.person.length ? fiche.r.person : (fiche.r && fiche.r.online ? qsTr("aucun connecté") : "—") }
                            Fact { visible: root.isAdmin; key: qsTr("Empreinte"); value: fiche.r ? root.shortPrint(fiche.r.fingerprint) : ""; mono: true }
                        }

                        // Demande d'acces
                        Rectangle {
                            visible: root.isAdmin && !!fiche.r && fiche.r.st === "pending"
                            Layout.fillWidth: true
                            Layout.topMargin: 14
                            implicitHeight: pendCol.implicitHeight + 24
                            color: Theme.warningSoft
                            Rectangle { width: 3; height: parent.height; color: Theme.warningColor }
                            ColumnLayout {
                                id: pendCol
                                x: 15
                                y: 12
                                width: parent.width - 28
                                spacing: 6
                                Text { Layout.fillWidth: true; text: qsTr("Ce poste demande à rejoindre le réseau."); color: Theme.ink; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13); font.weight: Theme.weightSemibold; wrapMode: Text.WordWrap }
                                Text { Layout.fillWidth: true; text: qsTr("Vérifiez son nom et son empreinte avec la personne qui l'utilise avant d'autoriser."); color: Theme.ink2; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12.5); wrapMode: Text.WordWrap }
                                Row {
                                    Layout.topMargin: 6
                                    spacing: 8
                                    AppButton { variant: "line"; size: "small"; text: qsTr("Refuser"); onClicked: root.confirm = "deny" }
                                    AppButton { variant: "ink"; size: "small"; iconPath: Icons.check; text: qsTr("Autoriser"); onClicked: root.confirm = "allow" }
                                }
                            }
                        }

                        // Actions
                        Rectangle {
                            visible: !!fiche.r && fiche.r.st !== "pending" && fiche.r.st !== "revoked"
                            Layout.fillWidth: true
                            Layout.topMargin: 16
                            implicitHeight: actions.implicitHeight + 2
                            radius: Theme.radiusSheet
                            color: "transparent"
                            border.width: 1
                            border.color: Theme.lineStrong
                            clip: true
                            ColumnLayout {
                                id: actions
                                x: 1; y: 1
                                width: parent.width - 2
                                spacing: 0
                                FicheAction {
                                    first: true
                                    text: qsTr("Envoyer un fichier")
                                    iconPath: Icons.arrowUp
                                    enabled: !!fiche.r && fiche.r.online
                                    hint: enabled ? "" : qsTr("hors ligne")
                                    onClicked: root.sendTo(fiche.r)
                                }
                                FicheAction {
                                    text: qsTr("Appeler")
                                    iconPath: Icons.phoneLine
                                    enabled: !!fiche.r && fiche.r.online && typeof callContext !== "undefined" && callContext !== null
                                    onClicked: root.callTo(fiche.r)
                                }
                                FicheAction {
                                    text: qsTr("Message")
                                    iconPath: Icons.messageCircle
                                    enabled: !!fiche.r && fiche.r.userId >= 0
                                    hint: enabled ? "" : qsTr("pas de compte")
                                    onClicked: root.writeTo(fiche.r)
                                }
                                FicheAction {
                                    text: qsTr("Dossier d'échanges")
                                    iconPath: Icons.folder
                                    hint: qsTr("Transferts")
                                    onClicked: root.exchangesOf(fiche.r)
                                }
                            }
                        }

                        // Autorisation (administrateur)
                        ColumnLayout {
                            visible: root.isAdmin && !!fiche.r && fiche.r.st !== "pending" && fiche.r.rowId >= 0
                            Layout.fillWidth: true
                            Layout.topMargin: 18
                            spacing: 8
                            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 2; color: Theme.ruleInk }
                            CapsLabel { Layout.topMargin: 4; text: qsTr("Autorisation") }
                            Text {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                text: {
                                    const r = fiche.r
                                    if (!r) return ""
                                    const when = root.dateLabel(r.addedAt)
                                    const by = root.nameOfUser(r.addedBy)
                                    if (r.st === "revoked")
                                        return qsTr("Accès retiré%1. Ce poste ne peut plus rejoindre le réseau.").arg(when.length ? " — " + qsTr("enregistré le %1").arg(when) : "")
                                    return when.length ? (by.length ? qsTr("Autorisé le %1 par %2.").arg(when).arg(by) : qsTr("Autorisé le %1.").arg(when)) : qsTr("Poste autorisé.")
                                }
                                color: Theme.ink2
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(12.5)
                            }
                            AppButton {
                                visible: !!fiche.r && fiche.r.st === "revoked"
                                variant: "line"
                                size: "small"
                                text: qsTr("Autoriser de nouveau")
                                onClicked: root.confirm = "allow"
                            }
                            AbstractButton {
                                id: revokeLink
                                visible: !!fiche.r && fiche.r.st !== "revoked"
                                hoverEnabled: true
                                Accessible.name: text
                                text: qsTr("Révoquer l'accès…")
                                onClicked: root.confirm = "revoke"
                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                                background: Item {}
                                contentItem: Row {
                                    spacing: 6
                                    LineIcon { anchors.verticalCenter: parent.verticalCenter; path: Icons.ban; size: 14; strokeWidth: 1.8; color: Theme.dangerInk }
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: revokeLink.text; color: Theme.dangerInk; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12.5); font.weight: Theme.weightSemibold; font.underline: revokeLink.hovered }
                                }
                            }
                        }
                        Text {
                            visible: !root.isAdmin
                            Layout.fillWidth: true
                            Layout.topMargin: 14
                            text: qsTr("Les autorisations sont gérées par l'administrateur du réseau.")
                            color: Theme.ink3
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(12)
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }
        }
    }

    // ======================================================================
    // Confirmations
    // ======================================================================
    SheetModal {
        id: confirmSheet
        readonly property var r: root.selected
        readonly property string machine: r ? r.machine.replace(/&/g, "&amp;").replace(/</g, "&lt;") : ""
        open: root.confirm.length > 0 && r !== null
        boldTitle: false
        sheetWidth: 470
        kicker: root.confirm === "allow" ? qsTr("Autoriser un poste") : root.confirm === "deny" ? qsTr("Refuser la demande") : qsTr("Révoquer l'accès")
        title: (root.confirm === "allow" ? qsTr("Autoriser") : root.confirm === "deny" ? qsTr("Refuser") : qsTr("Révoquer")) + " <b>" + confirmSheet.machine + "</b> ?"
        onCloseRequested: root.confirm = ""

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 10
            Text {
                visible: root.confirm === "allow"
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: qsTr("Ce poste pourra rejoindre le réseau local : échanger des fichiers, recevoir les dossiers partagés de ses membres et appeler.")
                color: Theme.ink2
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(13)
            }
            // Carte d'identite du poste
            Rectangle {
                visible: root.confirm !== "revoke"
                Layout.fillWidth: true
                implicitHeight: idCol.implicitHeight + 22
                radius: Theme.radiusSheet
                color: Theme.surface0
                border.width: 1
                border.color: Theme.line
                ColumnLayout {
                    id: idCol
                    x: 14
                    y: 11
                    width: parent.width - 28
                    spacing: 6
                    Fact { key: qsTr("Poste"); value: confirmSheet.r ? confirmSheet.r.machine : ""; mono: true }
                    Fact { key: qsTr("Adresse"); value: confirmSheet.r ? confirmSheet.r.address : ""; mono: true }
                    Fact { key: qsTr("Empreinte"); value: confirmSheet.r ? root.shortPrint(confirmSheet.r.fingerprint) : ""; mono: true }
                }
            }
            Text {
                visible: root.confirm !== "revoke"
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: root.confirm === "allow"
                      ? qsTr("Comparez l'empreinte avec celle affichée sur le poste avant de confirmer.")
                      : qsTr("Le poste ne pourra pas rejoindre le réseau. Sa demande reste visible ici ; vous pourrez l'autoriser plus tard.")
                color: Theme.ink2
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(13)
            }
            Rectangle {
                visible: root.confirm === "revoke"
                Layout.fillWidth: true
                implicitHeight: warnRow.implicitHeight + 24
                color: Theme.dangerSoft
                Rectangle { width: 2; height: parent.height; color: Theme.dangerColor }
                RowLayout {
                    id: warnRow
                    x: 14
                    y: 12
                    width: parent.width - 28
                    spacing: 12
                    LineIcon { Layout.alignment: Qt.AlignTop; path: Icons.alertTriangle; size: 18; strokeWidth: 1.8; color: Theme.dangerInk }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Text {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            text: (confirmSheet.r && confirmSheet.r.person.length ? qsTr("%1 ne pourra plus").arg(confirmSheet.r.person) : qsTr("Ce poste ne pourra plus"))
                                  + " " + qsTr("rejoindre le réseau : plus de transferts, d'appels ni de synchronisation.")
                            color: Theme.ink
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(13)
                        }
                        Text {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            text: qsTr("Ses fichiers déjà reçus restent sur son disque. Vous pourrez l'autoriser de nouveau depuis sa fiche.")
                            color: Theme.ink2
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(12.5)
                        }
                    }
                }
            }
        }

        footer: [
            AppButton { variant: "ghost"; text: qsTr("Annuler"); onClicked: root.confirm = "" },
            AppButton {
                variant: root.confirm === "allow" ? "ink" : "danger"
                iconPath: root.confirm === "allow" ? Icons.check : ""
                text: root.confirm === "allow" ? qsTr("Autoriser") : root.confirm === "deny" ? qsTr("Refuser") : qsTr("Révoquer l'accès")
                onClicked: root.applyConfirm()
            }
        ]
    }
}
