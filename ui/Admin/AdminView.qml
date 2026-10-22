import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import "../Components"
import "../Chat"
import "../Components/icons.js" as Icons
import "../Call/callPeople.js" as People

/*
 * AdminView - ecran « Administration » en Ligne claire :
 *
 *   [surtitre · « N postes attendent votre décision. » · bilan ... 4 chiffres]
 *   [Machines | Comptes | Bascule serveur  (grands onglets serif)           ]
 *   [liste de la section                               | fiche              ]
 *
 * Le journal d'audit a son propre ecran (AuditJournalView). currentTab garde
 * la numerotation historique : 1 Machines, 2 Comptes, 3 Bascule serveur.
 *
 * Donnees : authorizedMachineModel (machines ; presence via peersModel),
 * discoveryService.machineCandidates() (ajout), userManagementModel (comptes),
 * electionService + application.electionHistory() (bascule). Les regles
 * metier (dernier administrateur...) restent appliquees cote C++ : l'ecran
 * les annonce d'avance et affiche un avis si une action est refusee.
 */
Item {
    id: root
    objectName: "adminView"

    property var machinesSource: (typeof authorizedMachineModel !== "undefined") ? authorizedMachineModel : null
    property var usersSource: (typeof userManagementModel !== "undefined") ? userManagementModel : null
    property var peersSource: (typeof peersModel !== "undefined") ? peersModel : null
    property var messaging: (typeof messagingContext !== "undefined") ? messagingContext : null
    property var election: (typeof electionService !== "undefined") ? electionService : null

    signal backRequested()
    signal peerRequested(string peerId)
    signal journalRequested(string search)
    signal settingsRequested()

    property int currentTab: 1                 // 1 Machines | 2 Comptes | 3 Bascule serveur
    readonly property int tab: root.currentTab >= 1 && root.currentTab <= 3 ? root.currentTab : 1
    property string machineFilter: "all"       // all | pending | authorized | revoked
    property string userFilter: "all"          // all | admin | user
    property string search: ""
    property string selectedMachine: ""        // cle : identifiant de ligne
    property var selectedUser: -1
    onCurrentTabChanged: { root.search = ""; if (root.tab === 3) root.reloadElection() }

    readonly property bool isAdmin: (typeof userManager !== "undefined" && userManager) ? userManager.currentUserIsAdmin : false
    readonly property string me: (typeof userManager !== "undefined" && userManager && userManager.currentUsername) ? userManager.currentUsername : ""
    readonly property string hereName: (typeof settingsModel !== "undefined" && settingsModel && settingsModel.machineName) ? settingsModel.machineName : ""

    // ======================================================================
    // Donnees
    // ======================================================================
    property var peers: []
    property var machines: []
    property var users: []
    property var history: []

    function cleanFp(f) { return String(f || "").replace(/[^0-9a-fA-F]/g, "").toUpperCase() }

    // Roles sans propriete exposee lus par leur valeur d'enum (Qt.UserRole + n).
    function readMachines() {
        const out = []
        const m = root.machinesSource
        if (!m) return out
        const total = m.rowCount ? m.rowCount() : 0
        for (let i = 0; i < total; i++) {
            const idx = m.index(i, 0)
            const status = m.data(idx, m.StatusRole) || ""
            const authorized = !!m.data(idx, m.AuthorizedRole)
            const ip = m.data(idx, m.IpAddressRole) || m.data(idx, m.LastIpAddressRole || 262) || ""
            const machineId = m.data(idx, m.MachineIdRole) || ""
            const peer = root.peerFor(machineId, ip)
            const host = m.data(idx, m.HostnameRole) || ""
            out.push({
                rowId: m.data(idx, m.IdRole),
                key: String(m.data(idx, m.IdRole)),
                ip: ip, machineId: machineId,
                host: host.length ? host : (ip.length ? ip : machineId),
                fingerprint: m.data(idx, m.CertificateFingerprintRole) || "",
                addedBy: m.data(idx, m.AddedByRole || 266),
                addedAt: m.data(idx, m.AddedAtRole || 267) || "",
                reason: m.data(idx, m.ReasonRole || 268) || "",
                status: status === "revoked" ? "revoked" : (authorized ? "authorized" : "pending"),
                peerId: peer ? peer.id : "",
                online: peer !== null,
                here: root.hereName.length > 0 && host === root.hereName
            })
        }
        return out
    }
    function peerFor(machineId, ip) {
        for (let i = 0; i < root.peers.length; i++)
            if (machineId.length && root.peers[i].id === machineId) return root.peers[i]
        for (let j = 0; j < root.peers.length; j++)
            if (ip.length && root.peers[j].address === ip) return root.peers[j]
        return null
    }

    Instantiator {
        id: userSource
        model: root.usersSource
        delegate: QtObject {
            readonly property var row: ({ id: model.id, name: model.name || "", uuid: model.uuid || "",
                                          isAdmin: !!model.isAdmin, createdAt: model.createdAt })
        }
        onObjectAdded: Qt.callLater(root.reload)
        onObjectRemoved: Qt.callLater(root.reload)
    }
    function readUsers() {
        const out = []
        for (let i = 0; i < userSource.count; i++) {
            const o = userSource.objectAt(i)
            if (!o) continue
            const u = Object.assign({}, o.row)
            let peer = null
            for (let k = 0; k < root.peers.length && !peer; k++)
                if (u.uuid.length && root.peers[k].userUuid === u.uuid) peer = root.peers[k]
            u.me = root.me.length > 0 && u.name === root.me
            u.presence = u.me ? "online" : (peer ? People.presenceKind(peer.status) : "offline")
            u.machine = u.me ? root.hereName : (peer ? peer.machine : "")
            out.push(u)
        }
        out.sort(function(a, b) { return (b.me ? 1 : 0) - (a.me ? 1 : 0) || a.name.localeCompare(b.name) })
        return out
    }

    function reload() {
        root.peers = People.readPeers(root.peersSource)
        root.machines = root.readMachines()
        root.users = root.readUsers()
        if (!root.machineByKey(root.selectedMachine)) {
            const p = root.machines.filter(function(m) { return m.status === "pending" })
            root.selectedMachine = p.length ? p[0].key : (root.machines.length ? root.machines[0].key : "")
        }
        if (!root.userById(root.selectedUser))
            root.selectedUser = root.users.length ? (root.users.length > 1 ? root.users[1].id : root.users[0].id) : -1
    }
    function reloadElection() {
        root.history = (typeof application !== "undefined" && application && application.electionHistory)
                       ? (application.electionHistory(100) || []) : []
    }
    Connections {
        target: root.machinesSource
        ignoreUnknownSignals: true
        function onModelReset() { Qt.callLater(root.reload) }
        function onRowsInserted() { Qt.callLater(root.reload) }
        function onRowsRemoved() { Qt.callLater(root.reload) }
        function onDataChanged() { Qt.callLater(root.reload) }
    }
    Connections {
        target: root.peersSource
        ignoreUnknownSignals: true
        function onCountChanged() { Qt.callLater(root.reload) }
        function onModelReset() { Qt.callLater(root.reload) }
    }
    Connections {
        target: root.usersSource
        ignoreUnknownSignals: true
        function onModelReset() { Qt.callLater(root.reload) }
        function onDataChanged() { Qt.callLater(root.reload) }
    }
    // Pas de signal de changement pour l'historique des bascules.
    Timer { interval: 5000; repeat: true; running: root.tab === 3 && root.visible; onTriggered: root.reloadElection() }

    Component.onCompleted: {
        if (root.machinesSource && root.machinesSource.refresh) root.machinesSource.refresh()
        if (root.usersSource && root.usersSource.refresh) root.usersSource.refresh()
        root.reload()
        root.reloadElection()
    }

    function machineByKey(k) { for (let i = 0; i < root.machines.length; i++) if (root.machines[i].key === k) return root.machines[i]; return null }
    function userById(id) { for (let i = 0; i < root.users.length; i++) if (root.users[i].id === id) return root.users[i]; return null }
    function nameOfUser(id) { const u = root.userById(id); return u ? u.name : "" }

    readonly property var pending: root.machines.filter(function(m) { return m.status === "pending" })
    readonly property var authorized: root.machines.filter(function(m) { return m.status === "authorized" })
    readonly property var revoked: root.machines.filter(function(m) { return m.status === "revoked" })
    readonly property var admins: root.users.filter(function(u) { return u.isAdmin })
    readonly property var selMachine: root.machineByKey(root.selectedMachine)
    readonly property var selUser: root.userById(root.selectedUser)

    // ---- Bascule ----------------------------------------------------------
    readonly property string roleLabel: root.election ? (root.election.roleLabel || "") : ""
    readonly property string roleKind: root.roleLabel === "SERVER" ? "server" : root.roleLabel === "TEMP_SERVER" ? "backup" : "client"
    readonly property int epoch: root.election && root.election.epoch !== undefined ? root.election.epoch : 0
    function machineName(uuid) {
        if (!uuid) return ""
        for (let i = 0; i < root.peers.length; i++) if (root.peers[i].id === uuid) return root.peers[i].machine || uuid
        for (let j = 0; j < root.machines.length; j++) if (root.machines[j].machineId === uuid) return root.machines[j].host
        return uuid
    }
    readonly property string activeServer: {
        const uuid = root.election ? (root.election.activeServerUuid || "") : ""
        if (root.roleKind !== "client" || !uuid.length) return root.hereName
        return root.machineName(uuid)
    }
    function toDate(v) { return v instanceof Date ? v : new Date(v) }
    // Episodes : de « ne repond plus » a la reconciliation, les plus recents en tete.
    readonly property var episodes: {
        const asc = root.history.slice().sort(function(a, b) { return root.toDate(a.createdAt) - root.toDate(b.createdAt) })
        const out = []
        let cur = null
        for (let i = 0; i < asc.length; i++) {
            if (asc[i].event === "HEARTBEAT_LOST" || !cur) { cur = []; out.push(cur) }
            cur.push(asc[i])
        }
        return out.reverse().map(function(evs) {
            const find = function(k) { for (let i = 0; i < evs.length; i++) if (evs[i].event === k) return evs[i]; return null }
            const lost = find("HEARTBEAT_LOST"), back = find("SERVER_RESTORED"), relay = find("TEMP_PROMOTED")
            let summary = ""
            if (lost && back) {
                const mins = Math.round((root.toDate(back.createdAt) - root.toDate(lost.createdAt)) / 60000)
                summary = mins >= 60 ? qsTr("coupure de %1 h %2").arg(Math.floor(mins / 60)).arg(String(mins % 60).padStart(2, "0"))
                                     : qsTr("coupure de %1 min").arg(Math.max(1, mins))
            } else if (lost) {
                summary = qsTr("coupure en cours")
            }
            if (relay) summary += (summary.length ? " · " : "") + qsTr("relais par %1").arg(root.machineName(relay.machineUuid))
            return { day: root.toDate(evs[0].createdAt).toLocaleDateString(Qt.locale(), "dddd d MMMM"), summary: summary, events: evs.slice().reverse() }
        })
    }
    readonly property int swaps30: root.history.filter(function(h) {
        return h.event === "TEMP_PROMOTED" && (Date.now() - root.toDate(h.createdAt).getTime()) <= 30 * 86400000
    }).length
    function eventLook(e) {
        const m = root.esc(root.machineName(e.machineUuid))
        switch (e.event) {
        case "HEARTBEAT_LOST": return { tone: "danger", icon: Icons.pulse, line: qsTr("<b>%1</b> ne répond plus").arg(m), sub: qsTr("Battement perdu : le serveur ne s'est pas manifesté à temps") }
        case "TEMP_PROMOTED": return { tone: "warning", icon: Icons.server, line: qsTr("<b>%1</b> prend le relais").arg(m), sub: qsTr("Serveur de secours pour le réseau") }
        case "SERVER_RESTORED": return { tone: "success", icon: Icons.server, line: qsTr("<b>%1</b> reprend la main").arg(m), sub: qsTr("Retour du serveur officiel") }
        case "SERVER_RECONCILED": return { tone: "success", icon: Icons.refresh, line: qsTr("Données réconciliées"), sub: qsTr("Ce qui s'est passé pendant le secours est repris par %1").arg(m) }
        }
        return { tone: "neutral", icon: Icons.server, line: root.esc(e.event), sub: "" }
    }
    function esc(t) { return String(t === undefined || t === null ? "" : t).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;") }

    // ---- Presentation -------------------------------------------------------
    function dateLabel(v) {
        if (!v) return ""
        const d = root.toDate(v)
        return isNaN(d.getTime()) ? String(v) : d.toLocaleDateString(Qt.locale(), "d MMM yyyy")
    }
    function timeLabel(v) { const d = root.toDate(v); return isNaN(d.getTime()) ? "" : d.toLocaleTimeString(Qt.locale(), "HH:mm") }
    function shortPrint(f) { const c = root.cleanFp(f); return c.length ? c.slice(0, 4) + " " + c.slice(4, 8) + " " + c.slice(8, 12) + " …" : "—" }
    function presenceWord(p) { return p === "away" ? qsTr("Absent") : p === "busy" ? qsTr("Occupé") : p === "offline" ? qsTr("Hors ligne") : qsTr("En ligne") }

    // ======================================================================
    // Actions
    // ======================================================================
    property string notice: ""
    property bool noticeError: true
    function showNotice(text, isError) { root.notice = text; root.noticeError = isError !== false; noticeTimer.restart() }
    Timer { id: noticeTimer; interval: 7000; onTriggered: root.notice = "" }

    property string confirm: ""                // allow | deny | revoke | remove | role | deluser
    function applyConfirm() {
        const m = root.selMachine, u = root.selUser, a = root.confirm
        root.confirm = ""
        let ok = true
        if ((a === "allow" || a === "deny" || a === "revoke" || a === "remove") && m && root.machinesSource) {
            if (a === "allow") ok = root.machinesSource.authorizeMachine(m.rowId, "Autorisé par admin")
            else if (a === "deny") ok = root.machinesSource.revokeMachine(m.rowId, "Refusé par admin")
            else if (a === "revoke") ok = root.machinesSource.revokeMachine(m.rowId, "Révoqué par admin")
            else ok = root.machinesSource.removeMachine(m.rowId)
            if (!ok)
                root.showNotice(a === "allow" ? qsTr("%1 n'a pas pu être autorisée.").arg(m.host)
                                : a === "remove" ? qsTr("%1 n'a pas pu être retirée de la liste.").arg(m.host)
                                : qsTr("L'accès de %1 n'a pas pu être retiré.").arg(m.host))
        } else if ((a === "role" || a === "deluser") && u && root.usersSource) {
            if (a === "role") {
                if (!root.usersSource.changeRole(u.id, !u.isAdmin))
                    root.showNotice(qsTr("Le rôle n'a pas été modifié : il doit toujours rester au moins un administrateur."))
            } else if (!root.usersSource.deleteUser(u.id)) {
                root.showNotice(qsTr("Le compte n'a pas été supprimé : il doit toujours rester au moins un administrateur."))
            }
        }
        Qt.callLater(root.reload)
    }

    TextEdit { id: clipboardHelper; visible: false }
    function copyText(t) { clipboardHelper.text = t; clipboardHelper.selectAll(); clipboardHelper.copy(); root.showNotice(qsTr("Empreinte copiée."), false) }

    // ======================================================================
    // Composants
    // ======================================================================
    readonly property real pageW: width - 2 * Theme.pagePadding
    readonly property bool heroWide: pageW > 1180
    readonly property bool ficheDocked: pageW > 980
    readonly property bool roomy: pageW > 1240

    component SectionTab: AbstractButton {
        id: st
        property bool current: false
        property string count: ""
        property bool warn: false
        hoverEnabled: true
        focusPolicy: Qt.StrongFocus
        padding: 0
        implicitHeight: 46
        implicitWidth: stRow.implicitWidth
        Accessible.role: Accessible.PageTab
        Accessible.name: st.text
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        background: Item {
            Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: 3; color: st.current ? Theme.ruleInk : "transparent" }
            Rectangle { anchors.fill: parent; anchors.margins: -3; color: "transparent"; radius: Theme.radiusSheet; border.width: st.visualFocus ? 2 : 0; border.color: Theme.focusRing }
        }
        contentItem: Item {
            Row {
                id: stRow
                spacing: 8
                anchors.verticalCenter: parent.verticalCenter
                Text { anchors.verticalCenter: parent.verticalCenter; text: st.text; color: st.current || st.hovered ? Theme.ink : Theme.ink3; font.family: Theme.fontFamilySerif; font.pixelSize: Theme.fs(19); font.weight: st.current ? Theme.weightBold : Theme.weightRegular }
                Text { visible: st.count.length > 0; anchors.verticalCenter: parent.verticalCenter; anchors.verticalCenterOffset: 1; text: st.count; color: st.warn ? Theme.warningInk : Theme.ink3; font.family: Theme.fontFamilySerif; font.pixelSize: Theme.fs(13); font.weight: Theme.weightBold }
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

    // Marque d'une machine : en ligne, absente, demande (ambre), revoquee (rouge), ce poste.
    component MachineMark: Rectangle {
        id: mm
        property var m: null
        property real size: 36
        readonly property string st: mm.m ? mm.m.status : "authorized"
        implicitWidth: size
        implicitHeight: size
        radius: size / 2
        color: mm.st === "pending" ? Theme.warningSoft : mm.st === "revoked" ? Theme.dangerSoft : "transparent"
        border.width: 1
        border.color: mm.st === "pending" ? Theme.warningColor : mm.st === "revoked" ? Theme.dangerColor : (mm.m && mm.m.online ? Theme.lineStrong : Theme.line)
        LineIcon {
            anchors.centerIn: parent
            path: mm.st === "revoked" ? Icons.ban : (mm.m && mm.m.here ? Icons.server : Icons.monitor)
            size: Math.round(mm.size * 0.46)
            strokeWidth: 1.6
            color: mm.st === "pending" ? Theme.warningInk : mm.st === "revoked" ? Theme.dangerInk : (mm.m && (mm.m.online || mm.m.here) ? Theme.ink2 : Theme.ink3)
        }
        Rectangle {
            visible: mm.st === "authorized" && !!mm.m && (mm.m.online || mm.m.here)
            x: parent.width - width + 2; y: parent.height - height + 2
            width: Math.round(mm.size * 0.38); height: width; radius: width / 2
            color: Theme.bg
            StateGlyph { anchors.centerIn: parent; kind: "online"; size: Math.round(mm.size * 0.26) }
        }
    }

    // Avatar d'un compte : initiales serif, bouclier pour un administrateur.
    component AccountMark: Item {
        id: am
        property var u: null
        property real size: 36
        implicitWidth: size
        implicitHeight: size
        ChatMonogram {
            anchors.fill: parent
            size: am.size
            label: am.u ? am.u.name : ""
            status: am.u && !am.u.isAdmin ? am.u.presence : ""
        }
        Rectangle {
            visible: !!am.u && am.u.isAdmin
            x: parent.width - width + 3; y: parent.height - height + 3
            width: Math.round(am.size * 0.44); height: width; radius: width / 2
            color: Theme.bg
            border.width: 1
            border.color: Theme.line
            LineIcon { anchors.centerIn: parent; path: Icons.shield; size: Math.round(am.size * 0.28); strokeWidth: 2; color: Theme.ink }
        }
    }

    component StateWord: Row {
        property string glyph: "ok"
        property string word: ""
        property string extra: ""
        property color ink: Theme.ink
        spacing: 7
        StateGlyph { anchors.verticalCenter: parent.verticalCenter; kind: parent.glyph; size: 11 }
        Text { anchors.verticalCenter: parent.verticalCenter; text: parent.word; color: parent.ink; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12.5); font.weight: Theme.weightSemibold }
        Text { visible: parent.extra.length > 0; anchors.verticalCenter: parent.verticalCenter; text: "· " + parent.extra; color: Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(11.5) }
    }

    component FicheAction: AbstractButton {
        id: fa
        property string iconPath: ""
        property string hint: ""
        property bool first: false
        property bool danger: false
        Layout.fillWidth: true
        implicitHeight: 40
        hoverEnabled: true
        focusPolicy: Qt.StrongFocus
        Accessible.name: fa.text
        HoverHandler { cursorShape: fa.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
        readonly property color fill: fa.danger ? Theme.dangerColor : Theme.ink
        background: Rectangle {
            color: fa.hovered && fa.enabled ? fa.fill : "transparent"
            border.width: fa.visualFocus ? 2 : 0
            border.color: Theme.focusRing
            Rectangle { visible: !fa.first; width: parent.width; height: 1; color: Theme.lineStrong }
        }
        contentItem: RowLayout {
            spacing: 10
            LineIcon { Layout.leftMargin: 12; path: fa.iconPath; size: 15; strokeWidth: 1.8; color: !fa.enabled ? Theme.inkDisabled : fa.hovered ? Theme.inkOnInk : fa.danger ? Theme.dangerInk : Theme.ink3 }
            Text { Layout.fillWidth: true; text: fa.text; elide: Text.ElideRight; color: !fa.enabled ? Theme.inkDisabled : fa.hovered ? Theme.inkOnInk : fa.danger ? Theme.dangerInk : Theme.ink; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13); font.weight: Theme.weightSemibold }
            Text { Layout.rightMargin: 12; Layout.maximumWidth: fa.width * 0.4; visible: fa.hint.length > 0; text: fa.hint; elide: Text.ElideRight; color: fa.hovered && fa.enabled ? Theme.inkOnInk : Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(11.5) }
        }
    }

    component Fact: RowLayout {
        property string key: ""
        property string value: ""
        property bool mono: false
        Layout.fillWidth: true
        spacing: 16
        Text { Layout.alignment: Qt.AlignTop; text: parent.key; color: Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13) }
        Text { Layout.fillWidth: true; horizontalAlignment: Text.AlignRight; text: parent.value; wrapMode: Text.WrapAtWordBoundaryOrAnywhere; color: Theme.ink; font.family: parent.mono ? "Cascadia Mono" : Theme.fontFamily; font.pixelSize: parent.mono ? Theme.fs(12) : Theme.fs(13); font.features: ({ "tnum": 1 }) }
    }

    component DangerLink: AbstractButton {
        id: dl
        property string iconPath: ""
        hoverEnabled: true
        focusPolicy: Qt.StrongFocus
        implicitHeight: 24
        implicitWidth: dlRow.implicitWidth
        Accessible.name: dl.text
        HoverHandler { cursorShape: dl.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
        background: Rectangle { color: "transparent"; radius: Theme.radiusSheet; border.width: dl.visualFocus ? 2 : 0; border.color: Theme.focusRing }
        contentItem: Item {
            Row {
                id: dlRow
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                LineIcon { anchors.verticalCenter: parent.verticalCenter; path: dl.iconPath; size: 14; strokeWidth: 1.8; color: dl.enabled ? Theme.dangerInk : Theme.inkDisabled }
                Text { anchors.verticalCenter: parent.verticalCenter; text: dl.text; color: dl.enabled ? Theme.dangerInk : Theme.inkDisabled; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12.5); font.weight: Theme.weightSemibold; font.underline: dl.hovered && dl.enabled }
            }
        }
    }

    component ColHead: CapsLabel { font.pixelSize: Theme.fs(10) }

    component FindBox: Rectangle {
        id: fb
        property string placeholder: ""
        implicitWidth: 240
        implicitHeight: 30
        radius: Theme.radiusSheet
        color: "transparent"
        border.width: 1
        border.color: fbField.activeFocus ? Theme.ink : Theme.line
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 6
            spacing: 7
            LineIcon { path: Icons.search; size: 14; strokeWidth: 1.8; color: Theme.ink3 }
            TextField {
                id: fbField
                Layout.fillWidth: true
                text: root.search
                placeholderText: fb.placeholder
                placeholderTextColor: Theme.ink3
                color: Theme.ink
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(12.5)
                background: Item {}
                leftPadding: 0
                rightPadding: 0
                selectByMouse: true
                Accessible.name: fb.placeholder
                onTextEdited: root.search = text
            }
        }
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

            // ---- En-tete --------------------------------------------------
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
                        text: new Date().toLocaleDateString(Qt.locale(), "dddd d MMMM yyyy") + (root.hereName.length ? " · " + root.hereName : "")
                    }
                    Text {
                        Layout.fillWidth: true
                        textFormat: Text.StyledText
                        text: root.pending.length > 1 ? qsTr("<b>%1</b> postes attendent votre décision.").arg(root.pending.length)
                              : root.pending.length === 1 ? qsTr("<b>%1</b> attend votre décision.").arg(root.esc(root.pending[0].host))
                              : qsTr("Le réseau est en ordre.")
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
                            width: Math.min(implicitWidth, parent.width, 620)
                            height: Math.max(implicitHeight, heroActions.implicitHeight)
                            verticalAlignment: Text.AlignVCenter
                            textFormat: Text.StyledText
                            wrapMode: Text.WordWrap
                            color: Theme.ink2
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(14.5)
                            text: {
                                const a = root.authorized.length, n = root.users.length, ad = root.admins.length
                                const role = root.roleKind === "server" ? qsTr("Ce poste est le <b>serveur officiel</b>")
                                           : root.roleKind === "backup" ? qsTr("Ce poste assure le <b>secours</b>")
                                           : qsTr("Ce poste est <b>client</b>")
                                return (a > 1 ? qsTr("%1 machines autorisées").arg(a) : qsTr("%1 machine autorisée").arg(a)) + ", "
                                     + (n > 1 ? qsTr("%1 comptes").arg(n) : qsTr("%1 compte").arg(n)) + " "
                                     + (ad > 1 ? qsTr("dont %1 administrateurs.").arg(ad) : qsTr("dont %1 administrateur.").arg(ad)) + " "
                                     + role + (root.election ? " " + qsTr("(génération %1).").arg(root.epoch) : ".")
                            }
                        }
                        Row {
                            id: heroActions
                            spacing: 8
                            AppButton { variant: "ink"; iconPath: Icons.plus; text: qsTr("Ajouter une machine"); onClicked: addSheet.open = true }
                            AppButton {
                                variant: "line"; iconPath: Icons.userPlus; text: qsTr("Nouveau compte")
                                onClicked: { accountSheet.mode = "new"; accountSheet.open = true }
                            }
                        }
                    }
                }

                // Quatre chiffres (menent a la section)
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
                                { key: "pending", label: qsTr("En attente"), value: root.pending.length, ctx: root.pending.length ? qsTr("à décider") : qsTr("aucune demande"), attention: root.pending.length > 0 },
                                { key: "authorized", label: qsTr("Autorisées"), value: root.authorized.length, ctx: qsTr("%1 en ligne").arg(root.authorized.filter(function(m) { return m.online || m.here }).length) },
                                { key: "users", label: qsTr("Comptes"), value: root.users.length, ctx: root.admins.length > 1 ? qsTr("%1 administrateurs").arg(root.admins.length) : qsTr("%1 administrateur").arg(root.admins.length) },
                                { key: "swaps", label: qsTr("Bascules"), value: root.swaps30, ctx: root.swaps30 ? qsTr("sur 30 jours") : qsTr("aucune en 30 jours") }
                            ]
                            delegate: Item {
                                id: fig
                                required property var modelData
                                required property int index
                                readonly property bool on: fig.modelData.key === "users" ? root.tab === 2
                                                          : fig.modelData.key === "swaps" ? root.tab === 3
                                                          : root.tab === 1 && root.machineFilter === fig.modelData.key
                                width: root.heroWide ? sf.width + (index === 0 ? 0 : 22) + (index === 3 ? 0 : 22) : figRow.width / 4
                                height: sf.implicitHeight + 6
                                Rectangle { visible: fig.index > 0; width: 1; height: sf.implicitHeight; color: Theme.line }
                                SerifFigure {
                                    id: sf
                                    x: fig.index === 0 ? 0 : (root.heroWide ? 22 : 18)
                                    width: Math.max(implicitWidth, 110)
                                    label: fig.modelData.label
                                    value: String(fig.modelData.value)
                                    context: fig.modelData.ctx
                                    attention: !!fig.modelData.attention
                                    valueSize: root.heroWide && root.height >= 720 ? Theme.fontSizeFigure : Theme.fs(32)
                                    onClicked: {
                                        const k = fig.modelData.key
                                        if (k === "users") root.currentTab = 2
                                        else if (k === "swaps") root.currentTab = 3
                                        else { root.currentTab = 1; root.machineFilter = root.machineFilter === k ? "all" : k }
                                    }
                                }
                                Rectangle { visible: fig.on; x: sf.x; y: sf.implicitHeight + 4; width: sf.width; height: 2; color: Theme.ruleInk }
                            }
                        }
                    }
                }
            }

            // ---- Sections ------------------------------------------------------
            ColumnLayout {
                Layout.fillWidth: true
                Layout.topMargin: -4
                spacing: 0
                Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 2; color: Theme.ruleInk }
                Row {
                    Layout.topMargin: 4
                    spacing: 26
                    SectionTab { text: qsTr("Machines"); count: String(root.machines.length); warn: root.pending.length > 0; current: root.tab === 1; onClicked: root.currentTab = 1 }
                    SectionTab { text: qsTr("Comptes"); count: String(root.users.length); current: root.tab === 2; onClicked: root.currentTab = 2 }
                    SectionTab { text: qsTr("Bascule serveur"); current: root.tab === 3; onClicked: root.currentTab = 3 }
                }
                Rectangle {
                    visible: root.notice.length > 0
                    Layout.fillWidth: true
                    Layout.topMargin: 14
                    implicitHeight: noticeRow.implicitHeight + 20
                    color: Theme.surface0
                    border.width: 1
                    border.color: Theme.line
                    Rectangle { width: 3; height: parent.height; color: root.noticeError ? Theme.dangerColor : Theme.successColor }
                    RowLayout {
                        id: noticeRow
                        anchors.verticalCenter: parent.verticalCenter
                        x: 16
                        width: parent.width - 26
                        spacing: 12
                        LineIcon { path: root.noticeError ? Icons.alertTriangle : Icons.check; size: 16; strokeWidth: 1.8; color: root.noticeError ? Theme.dangerInk : Theme.successInk }
                        Text { Layout.fillWidth: true; text: root.notice; wrapMode: Text.WordWrap; color: Theme.ink; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13) }
                        TextLink { text: qsTr("OK"); arrow: false; onClicked: root.notice = "" }
                    }
                }
                Rectangle { Layout.fillWidth: true; Layout.topMargin: root.notice.length ? 14 : 0; Layout.preferredHeight: 1; color: Theme.line }
            }

            GridLayout {
                Layout.fillWidth: true
                Layout.topMargin: -20
                columns: root.ficheDocked ? 2 : 1
                columnSpacing: 0
                rowSpacing: 0

                // -- Liste de la section ----------------------------------------
                ColumnLayout {
                    id: listCol
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    Layout.topMargin: 14
                    Layout.rightMargin: root.ficheDocked ? 24 : 0
                    spacing: 0

                    // ======== Machines ========
                    ColumnLayout {
                        visible: root.tab === 1
                        Layout.fillWidth: true
                        spacing: 0
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.bottomMargin: 8
                            CapsLabel { text: qsTr("Machines enregistrées"); Layout.fillWidth: true }
                            Text { text: root.machines.length; color: Theme.ink3; font.family: Theme.fontFamilySerif; font.pixelSize: Theme.fs(16); font.weight: Theme.weightBold }
                        }
                        Item {
                            Layout.fillWidth: true
                            implicitHeight: 36
                            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
                            Row {
                                anchors.bottom: parent.bottom
                                spacing: 18
                                InkTab { text: qsTr("Toutes"); count: String(root.machines.length); current: root.machineFilter === "all"; onClicked: root.machineFilter = "all" }
                                InkTab { text: qsTr("En attente"); danger: true; count: String(root.pending.length); current: root.machineFilter === "pending"; onClicked: root.machineFilter = "pending" }
                                InkTab { text: qsTr("Autorisées"); count: String(root.authorized.length); current: root.machineFilter === "authorized"; onClicked: root.machineFilter = "authorized" }
                                InkTab { text: qsTr("Révoquées"); count: String(root.revoked.length); current: root.machineFilter === "revoked"; onClicked: root.machineFilter = "revoked" }
                            }
                            FindBox { anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.bottomMargin: 6; implicitWidth: listCol.width > 760 ? 240 : 180; placeholder: qsTr("Nom, adresse ou empreinte…") }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: 12
                            Layout.leftMargin: 8
                            Layout.rightMargin: 8
                            Layout.bottomMargin: 6
                            spacing: 14
                            ColHead { Layout.fillWidth: true; text: qsTr("Machine") }
                            ColHead { Layout.preferredWidth: 150; text: qsTr("État") }
                            ColHead { visible: root.roomy; Layout.preferredWidth: 140; text: qsTr("Empreinte") }
                            ColHead { Layout.preferredWidth: 150; text: qsTr("Ajoutée") }
                        }
                        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.ruleInk }

                        Repeater {
                            model: {
                                const q = root.search.trim().toLowerCase()
                                const qfp = q.replace(/[^0-9a-f]/g, "")
                                const match = function(m) {
                                    return !q.length || m.host.toLowerCase().indexOf(q) !== -1 || m.ip.indexOf(q) !== -1
                                        || (qfp.length >= 4 && root.cleanFp(m.fingerprint).toLowerCase().indexOf(qfp) !== -1)
                                }
                                return [
                                    { key: "pending", label: qsTr("En attente · à décider"), rows: root.pending.filter(match) },
                                    { key: "authorized", label: qsTr("Autorisées"), rows: root.authorized.filter(match) },
                                    { key: "revoked", label: qsTr("Révoquées"), rows: root.revoked.filter(match) }
                                ].filter(function(g) { return (root.machineFilter === "all" || root.machineFilter === g.key) && g.rows.length > 0 })
                            }
                            delegate: ColumnLayout {
                                id: mg
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 0
                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.topMargin: 16
                                    Layout.leftMargin: 8
                                    Layout.bottomMargin: 6
                                    spacing: 10
                                    CapsLabel { text: mg.modelData.label; color: Theme.ink2 }
                                    Text { text: mg.modelData.rows.length; color: Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(11.5) }
                                }
                                Repeater {
                                    model: mg.modelData.rows
                                    delegate: Rectangle {
                                        id: mr
                                        required property var modelData
                                        readonly property var m: modelData
                                        readonly property bool on: mr.m.key === root.selectedMachine
                                        readonly property bool pend: mr.m.status === "pending"
                                        Layout.fillWidth: true
                                        implicitHeight: 56
                                        color: mr.on ? Theme.surface0 : (mrHover.hovered ? Theme.selectWash : "transparent")
                                        border.width: mr.on ? 1 : 0
                                        border.color: Theme.line
                                        Accessible.role: Accessible.ListItem
                                        Accessible.name: mr.m.host
                                        HoverHandler { id: mrHover; cursorShape: Qt.PointingHandCursor }
                                        TapHandler { onTapped: root.selectedMachine = mr.m.key }
                                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
                                        Rectangle { visible: mr.on || mr.pend; width: 3; height: parent.height; color: mr.pend ? Theme.warningColor : Theme.ruleInk }
                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 8
                                            anchors.rightMargin: 8
                                            spacing: 14
                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 12
                                                MachineMark { m: mr.m }
                                                ColumnLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 1
                                                    Row {
                                                        Layout.fillWidth: true
                                                        spacing: 7
                                                        Text { text: mr.m.host; color: mr.m.online || mr.pend || mr.m.here ? Theme.ink : Theme.ink2; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13.5); font.weight: Theme.weightSemibold; elide: Text.ElideRight; width: Math.min(implicitWidth, listCol.width * 0.32) }
                                                        Rectangle {
                                                            visible: mr.m.here
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            width: hereText.implicitWidth + 10; height: 16; radius: 2
                                                            color: "transparent"; border.width: 1; border.color: Theme.lineStrong
                                                            Text { id: hereText; anchors.centerIn: parent; text: qsTr("CE POSTE"); color: Theme.ink2; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(9.5); font.weight: Theme.weightBold; font.letterSpacing: 1 }
                                                        }
                                                    }
                                                    Text { Layout.fillWidth: true; text: mr.m.ip; color: Theme.ink3; font.family: "Cascadia Mono"; font.pixelSize: Theme.fs(11.5); elide: Text.ElideRight }
                                                }
                                            }
                                            StateWord {
                                                Layout.preferredWidth: 150
                                                glyph: mr.pend ? "decision" : mr.m.status === "revoked" ? "error" : "ok"
                                                word: mr.pend ? qsTr("À décider") : mr.m.status === "revoked" ? qsTr("Révoquée") : qsTr("Autorisée")
                                                extra: mr.m.status === "authorized" ? (mr.m.online || mr.m.here ? qsTr("en ligne") : qsTr("hors ligne")) : ""
                                                ink: mr.pend ? Theme.warningInk : mr.m.status === "revoked" ? Theme.dangerInk : Theme.successInk
                                            }
                                            Text { visible: root.roomy; Layout.preferredWidth: 140; text: root.shortPrint(mr.m.fingerprint); color: Theme.ink2; font.family: "Cascadia Mono"; font.pixelSize: Theme.fs(11.5) }
                                            Item {
                                                Layout.preferredWidth: 150
                                                implicitHeight: Math.max(dateCol.implicitHeight, pendRow.implicitHeight)
                                                ColumnLayout {
                                                    id: dateCol
                                                    visible: !mr.pend
                                                    width: parent.width
                                                    spacing: 1
                                                    Text { text: root.dateLabel(mr.m.addedAt); color: Theme.ink2; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12); font.weight: Theme.weightMedium }
                                                    Text { visible: text.length > 0; Layout.fillWidth: true; text: root.nameOfUser(mr.m.addedBy).length ? qsTr("par %1").arg(root.nameOfUser(mr.m.addedBy)) : ""; color: Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12); elide: Text.ElideRight }
                                                }
                                                Row {
                                                    id: pendRow
                                                    visible: mr.pend
                                                    anchors.right: parent.right
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    spacing: 6
                                                    AppButton { variant: "line"; size: "small"; text: qsTr("Refuser"); onClicked: { root.selectedMachine = mr.m.key; root.confirm = "deny" } }
                                                    AppButton { variant: "ink"; size: "small"; text: qsTr("Autoriser"); onClicked: { root.selectedMachine = mr.m.key; root.confirm = "allow" } }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        ColumnLayout {
                            visible: root.machines.filter(function(m) { return !m.here }).length === 0 || root.search.length > 0
                            Layout.fillWidth: true
                            Layout.topMargin: 16
                            Layout.leftMargin: 8
                            spacing: 4
                            readonly property bool none: root.machines.filter(function(m) { return !m.here }).length === 0
                            Text { text: parent.none ? qsTr("Aucune autre machine enregistrée.") : qsTr("Recherche : « %1 »").arg(root.search); color: Theme.ink; font.family: Theme.fontFamilySerif; font.pixelSize: Theme.fs(18) }
                            Text {
                                Layout.fillWidth: true
                                text: parent.none ? qsTr("Les postes qui demandent à rejoindre le réseau apparaissent ici ; vous pouvez aussi en ajouter un vous-même.")
                                                  : qsTr("Les machines qui ne correspondent pas sont masquées.")
                                color: Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12.5); wrapMode: Text.WordWrap
                            }
                        }
                    }

                    // ======== Comptes ========
                    ColumnLayout {
                        visible: root.tab === 2
                        Layout.fillWidth: true
                        spacing: 0
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.bottomMargin: 8
                            CapsLabel { text: qsTr("Comptes de l'espace"); Layout.fillWidth: true }
                            Text { text: root.users.length; color: Theme.ink3; font.family: Theme.fontFamilySerif; font.pixelSize: Theme.fs(16); font.weight: Theme.weightBold }
                        }
                        Item {
                            Layout.fillWidth: true
                            implicitHeight: 36
                            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
                            Row {
                                anchors.bottom: parent.bottom
                                spacing: 18
                                InkTab { text: qsTr("Tous"); count: String(root.users.length); current: root.userFilter === "all"; onClicked: root.userFilter = "all" }
                                InkTab { text: qsTr("Administrateurs"); count: String(root.admins.length); current: root.userFilter === "admin"; onClicked: root.userFilter = "admin" }
                                InkTab { text: qsTr("Utilisateurs"); count: String(root.users.length - root.admins.length); current: root.userFilter === "user"; onClicked: root.userFilter = "user" }
                            }
                            FindBox { anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.bottomMargin: 6; implicitWidth: listCol.width > 760 ? 240 : 180; placeholder: qsTr("Nom du compte…") }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: 12
                            Layout.leftMargin: 8
                            Layout.rightMargin: 8
                            Layout.bottomMargin: 6
                            spacing: 14
                            ColHead { Layout.fillWidth: true; text: qsTr("Compte") }
                            ColHead { Layout.preferredWidth: 140; text: qsTr("Rôle") }
                            ColHead { Layout.preferredWidth: 180; text: qsTr("Présence") }
                            ColHead { visible: root.roomy; Layout.preferredWidth: 100; text: qsTr("Créé le") }
                        }
                        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.ruleInk }
                        Repeater {
                            model: {
                                const q = root.search.trim().toLowerCase()
                                const match = function(u) { return !q.length || u.name.toLowerCase().indexOf(q) !== -1 }
                                return [
                                    { key: "admin", label: qsTr("Administrateurs"), rows: root.admins.filter(match) },
                                    { key: "user", label: qsTr("Utilisateurs"), rows: root.users.filter(function(u) { return !u.isAdmin }).filter(match) }
                                ].filter(function(g) { return (root.userFilter === "all" || root.userFilter === g.key) && g.rows.length > 0 })
                            }
                            delegate: ColumnLayout {
                                id: ug
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 0
                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.topMargin: 16
                                    Layout.leftMargin: 8
                                    Layout.bottomMargin: 6
                                    spacing: 10
                                    CapsLabel { text: ug.modelData.label; color: Theme.ink2 }
                                    Text { text: ug.modelData.rows.length; color: Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(11.5) }
                                }
                                Repeater {
                                    model: ug.modelData.rows
                                    delegate: Rectangle {
                                        id: ur
                                        required property var modelData
                                        readonly property var u: modelData
                                        readonly property bool on: ur.u.id === root.selectedUser
                                        Layout.fillWidth: true
                                        implicitHeight: 54
                                        color: ur.on ? Theme.surface0 : (urHover.hovered ? Theme.selectWash : "transparent")
                                        border.width: ur.on ? 1 : 0
                                        border.color: Theme.line
                                        Accessible.role: Accessible.ListItem
                                        Accessible.name: ur.u.name
                                        HoverHandler { id: urHover; cursorShape: Qt.PointingHandCursor }
                                        TapHandler { onTapped: root.selectedUser = ur.u.id }
                                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
                                        Rectangle { visible: ur.on; width: 3; height: parent.height; color: Theme.ruleInk }
                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 8
                                            anchors.rightMargin: 8
                                            spacing: 14
                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 12
                                                AccountMark { u: ur.u }
                                                Text { text: ur.u.name; color: Theme.ink; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13.5); font.weight: Theme.weightSemibold; elide: Text.ElideRight; Layout.maximumWidth: listCol.width * 0.4 }
                                                Rectangle {
                                                    visible: ur.u.me
                                                    width: meText.implicitWidth + 10; height: 16; radius: 2
                                                    color: "transparent"; border.width: 1; border.color: Theme.lineStrong
                                                    Text { id: meText; anchors.centerIn: parent; text: qsTr("VOUS"); color: Theme.ink2; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(9.5); font.weight: Theme.weightBold; font.letterSpacing: 1 }
                                                }
                                                Item { Layout.fillWidth: true }
                                            }
                                            Row {
                                                Layout.preferredWidth: 140
                                                spacing: 7
                                                LineIcon { visible: ur.u.isAdmin; anchors.verticalCenter: parent.verticalCenter; path: Icons.shield; size: 14; strokeWidth: 1.8; color: Theme.ink }
                                                Text { anchors.verticalCenter: parent.verticalCenter; text: ur.u.isAdmin ? qsTr("Administrateur") : qsTr("Utilisateur"); color: ur.u.isAdmin ? Theme.ink : Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12.5); font.weight: ur.u.isAdmin ? Theme.weightSemibold : Theme.weightMedium }
                                            }
                                            ColumnLayout {
                                                Layout.fillWidth: false
                                                Layout.preferredWidth: 180
                                                spacing: 1
                                                StateWord {
                                                    glyph: ur.u.presence
                                                    word: root.presenceWord(ur.u.presence)
                                                    ink: ur.u.presence === "online" ? Theme.successInk : ur.u.presence === "offline" ? Theme.ink3 : Theme.warningInk
                                                }
                                                Text { visible: ur.u.machine.length > 0; Layout.fillWidth: true; text: ur.u.machine; color: Theme.ink3; font.family: "Cascadia Mono"; font.pixelSize: Theme.fs(11); elide: Text.ElideRight }
                                            }
                                            Text { visible: root.roomy; Layout.preferredWidth: 100; text: root.dateLabel(ur.u.createdAt); color: Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12) }
                                        }
                                    }
                                }
                            }
                        }
                        Text {
                            visible: root.users.length <= 1
                            Layout.fillWidth: true
                            Layout.topMargin: 16
                            Layout.leftMargin: 8
                            text: qsTr("Créez un compte pour chaque personne qui utilisera LocaLink sur ce réseau.")
                            color: Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12.5); wrapMode: Text.WordWrap
                        }
                    }

                    // ======== Bascule serveur ========
                    ColumnLayout {
                        visible: root.tab === 3
                        Layout.fillWidth: true
                        spacing: 0
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.bottomMargin: 4
                            CapsLabel { text: qsTr("Historique des bascules"); Layout.fillWidth: true }
                            Text { text: root.history.length; color: Theme.ink3; font.family: Theme.fontFamilySerif; font.pixelSize: Theme.fs(16); font.weight: Theme.weightBold }
                        }
                        ColumnLayout {
                            visible: root.history.length === 0
                            Layout.fillWidth: true
                            Layout.topMargin: 14
                            spacing: 4
                            Text { text: qsTr("Aucune bascule pour l'instant."); color: Theme.ink; font.family: Theme.fontFamilySerif; font.pixelSize: Theme.fs(18) }
                            Text { Layout.fillWidth: true; text: qsTr("Le serveur officiel a toujours répondu. Si un jour il ne répond plus, la reprise par un autre poste sera notée ici."); color: Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12.5); wrapMode: Text.WordWrap }
                        }
                        Repeater {
                            model: root.episodes
                            delegate: ColumnLayout {
                                id: ep
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 0
                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.topMargin: 16
                                    Layout.leftMargin: 8
                                    Layout.bottomMargin: 6
                                    spacing: 10
                                    CapsLabel { text: ep.modelData.day; color: Theme.ink2 }
                                    Text { Layout.fillWidth: true; text: ep.modelData.summary; color: Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12); elide: Text.ElideRight }
                                }
                                Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.ruleInk }
                                Repeater {
                                    model: ep.modelData.events
                                    delegate: Rectangle {
                                        id: ev
                                        required property var modelData
                                        readonly property var look: root.eventLook(modelData)
                                        readonly property color tone: ev.look.tone === "danger" ? Theme.dangerColor : ev.look.tone === "warning" ? Theme.warningColor : ev.look.tone === "success" ? Theme.successColor : Theme.lineStrong
                                        readonly property color toneInk: ev.look.tone === "danger" ? Theme.dangerInk : ev.look.tone === "warning" ? Theme.warningInk : ev.look.tone === "success" ? Theme.successInk : Theme.ink2
                                        Layout.fillWidth: true
                                        implicitHeight: 50
                                        color: "transparent"
                                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 8
                                            anchors.rightMargin: 8
                                            spacing: 12
                                            Text { Layout.preferredWidth: 58; text: root.toDate(ev.modelData.createdAt).toLocaleTimeString(Qt.locale(), "HH:mm:ss"); color: Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12); font.features: ({ "tnum": 1 }) }
                                            Rectangle {
                                                implicitWidth: 24; implicitHeight: 24; radius: 12
                                                color: "transparent"; border.width: 1; border.color: ev.tone
                                                LineIcon { anchors.centerIn: parent; path: ev.look.icon; size: 13; strokeWidth: 1.8; color: ev.toneInk }
                                            }
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 1
                                                Text { Layout.fillWidth: true; textFormat: Text.StyledText; text: ev.look.line; color: Theme.ink; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13.5); font.weight: Theme.weightMedium; elide: Text.ElideRight }
                                                Text { Layout.fillWidth: true; text: ev.look.sub; color: Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12); elide: Text.ElideRight }
                                            }
                                            Text { visible: root.roomy; text: qsTr("génération %1").arg(ev.modelData.epoch); color: Theme.ink3; font.family: "Cascadia Mono"; font.pixelSize: Theme.fs(11.5) }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // -- Fiche ------------------------------------------------------
                Item {
                    id: ficheCol
                    visible: root.tab === 3 || (root.tab === 1 ? root.selMachine !== null : root.selUser !== null)
                    Layout.preferredWidth: root.ficheDocked ? (root.pageW > 1240 ? 340 : 300) : -1
                    Layout.fillWidth: !root.ficheDocked
                    Layout.alignment: Qt.AlignTop
                    implicitHeight: (root.tab === 1 ? mFiche.implicitHeight : root.tab === 2 ? uFiche.implicitHeight : bFiche.implicitHeight) + 34
                    Rectangle { visible: root.ficheDocked; width: 1; height: Math.max(parent.height, listCol.height + 14); color: Theme.line }
                    Rectangle { visible: !root.ficheDocked; width: parent.width; height: 1; y: 10; color: Theme.line }

                    // ======== Fiche machine ========
                    ColumnLayout {
                        id: mFiche
                        readonly property var m: root.selMachine
                        visible: root.tab === 1 && mFiche.m !== null
                        x: root.ficheDocked ? 24 : 0
                        y: root.ficheDocked ? 16 : 26
                        width: parent.width - x
                        spacing: 0

                        CapsLabel { text: mFiche.m && mFiche.m.status === "pending" ? qsTr("Demande d'accès") : qsTr("Machine") }
                        MachineMark { Layout.topMargin: 10; m: mFiche.m; size: 64 }
                        Text { Layout.fillWidth: true; Layout.topMargin: 10; text: mFiche.m ? mFiche.m.host : ""; color: Theme.ink; font.family: Theme.fontFamilySerif; font.pixelSize: Theme.fs(22); font.weight: Theme.weightBold; wrapMode: Text.WrapAtWordBoundaryOrAnywhere; Accessible.role: Accessible.Heading }
                        Text { Layout.fillWidth: true; Layout.topMargin: 2; text: mFiche.m ? mFiche.m.ip : ""; color: Theme.ink2; font.family: "Cascadia Mono"; font.pixelSize: Theme.fs(12.5) }
                        StateWord {
                            Layout.topMargin: 8
                            glyph: !mFiche.m ? "ok" : mFiche.m.status === "pending" ? "decision" : mFiche.m.status === "revoked" ? "error" : (mFiche.m.online || mFiche.m.here ? "online" : "offline")
                            word: !mFiche.m ? "" : mFiche.m.status === "pending" ? qsTr("En attente de votre décision") : mFiche.m.status === "revoked" ? qsTr("Accès révoqué")
                                  : mFiche.m.here ? qsTr("Ce poste") : mFiche.m.online ? qsTr("Autorisée · en ligne") : qsTr("Autorisée · hors ligne")
                            ink: Theme.ink2
                        }
                        Rectangle { Layout.fillWidth: true; Layout.topMargin: 14; Layout.bottomMargin: 10; Layout.preferredHeight: 1; color: Theme.line }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 7
                            Fact { visible: !!mFiche.m && mFiche.m.machineId.length > 0; key: qsTr("Identifiant"); value: mFiche.m ? mFiche.m.machineId : ""; mono: true }
                            Fact { key: mFiche.m && mFiche.m.status === "pending" ? qsTr("Demande reçue") : qsTr("Ajoutée le"); value: mFiche.m ? root.dateLabel(mFiche.m.addedAt) + (root.timeLabel(mFiche.m.addedAt) ? qsTr(" à %1").arg(root.timeLabel(mFiche.m.addedAt)) : "") : "" }
                            Fact { visible: !!mFiche.m && root.nameOfUser(mFiche.m.addedBy).length > 0; key: qsTr("Par"); value: mFiche.m ? root.nameOfUser(mFiche.m.addedBy) : "" }
                            Fact { visible: !!mFiche.m && mFiche.m.reason.length > 0; key: qsTr("Motif"); value: mFiche.m ? mFiche.m.reason : "" }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: 14
                            Layout.bottomMargin: 6
                            CapsLabel { Layout.fillWidth: true; text: qsTr("Empreinte du certificat") }
                            TextLink { visible: !!mFiche.m && mFiche.m.fingerprint.length > 0; text: qsTr("Copier"); arrow: false; fontSize: Theme.fs(12.5); onClicked: root.copyText(root.cleanFp(mFiche.m.fingerprint)) }
                        }
                        FingerprintGrid { Layout.fillWidth: true; fingerprint: mFiche.m ? mFiche.m.fingerprint : "" }

                        // Demande en attente
                        Rectangle {
                            visible: !!mFiche.m && mFiche.m.status === "pending"
                            Layout.fillWidth: true
                            Layout.topMargin: 14
                            implicitHeight: pendCol.implicitHeight + 24
                            color: Theme.warningSoft
                            Rectangle { width: 3; height: parent.height; color: Theme.warningColor }
                            ColumnLayout {
                                id: pendCol
                                x: 15; y: 12
                                width: parent.width - 28
                                spacing: 6
                                Text { Layout.fillWidth: true; text: qsTr("Ce poste demande à rejoindre le réseau."); color: Theme.ink; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13); font.weight: Theme.weightSemibold; wrapMode: Text.WordWrap }
                                Text { Layout.fillWidth: true; text: qsTr("Comparez l'empreinte ci-dessus avec celle affichée sur le poste avant d'autoriser."); color: Theme.ink2; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12.5); wrapMode: Text.WordWrap }
                                Row {
                                    Layout.topMargin: 6
                                    spacing: 8
                                    AppButton { variant: "line"; size: "small"; text: qsTr("Refuser"); onClicked: root.confirm = "deny" }
                                    AppButton { variant: "ink"; size: "small"; iconPath: Icons.check; text: qsTr("Autoriser"); onClicked: root.confirm = "allow" }
                                }
                            }
                        }

                        // Liens utiles
                        Rectangle {
                            visible: !!mFiche.m && mFiche.m.status !== "pending"
                            Layout.fillWidth: true
                            Layout.topMargin: 16
                            implicitHeight: mActions.implicitHeight + 2
                            radius: Theme.radiusSheet
                            color: "transparent"
                            border.width: 1
                            border.color: Theme.lineStrong
                            clip: true
                            ColumnLayout {
                                id: mActions
                                x: 1; y: 1
                                width: parent.width - 2
                                spacing: 0
                                FicheAction {
                                    first: true
                                    visible: !!mFiche.m && mFiche.m.online
                                    text: qsTr("Voir dans Postes")
                                    iconPath: Icons.monitor
                                    onClicked: root.peerRequested(mFiche.m.peerId)
                                }
                                FicheAction {
                                    first: !(mFiche.m && mFiche.m.online)
                                    visible: !!mFiche.m && mFiche.m.ip.length > 0
                                    text: qsTr("Événements de cette adresse")
                                    iconPath: Icons.journal
                                    hint: qsTr("Journal")
                                    onClicked: root.journalRequested(mFiche.m.ip)
                                }
                            }
                        }

                        // Autorisation
                        ColumnLayout {
                            visible: !!mFiche.m && mFiche.m.status !== "pending"
                            Layout.fillWidth: true
                            Layout.topMargin: 18
                            spacing: 8
                            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 2; color: Theme.ruleInk }
                            CapsLabel { Layout.topMargin: 4; text: qsTr("Autorisation") }
                            Text {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                text: {
                                    const m = mFiche.m
                                    if (!m) return ""
                                    if (m.status === "revoked")
                                        return qsTr("Accès retiré. Ce poste ne peut plus rejoindre le réseau ; s'il réessaie, la tentative est refusée et notée au journal.")
                                    const by = root.nameOfUser(m.addedBy)
                                    return by.length ? qsTr("Autorisée le %1 par %2.").arg(root.dateLabel(m.addedAt)).arg(by) : qsTr("Autorisée le %1.").arg(root.dateLabel(m.addedAt))
                                }
                                color: Theme.ink2; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12.5)
                            }
                            AppButton { visible: !!mFiche.m && mFiche.m.status === "revoked"; variant: "line"; size: "small"; text: qsTr("Autoriser de nouveau"); onClicked: root.confirm = "allow" }
                            DangerLink { visible: !!mFiche.m && mFiche.m.status === "authorized"; text: qsTr("Révoquer l'accès…"); iconPath: Icons.ban; onClicked: root.confirm = "revoke" }
                            DangerLink { text: qsTr("Retirer de la liste…"); iconPath: Icons.trash; onClicked: root.confirm = "remove" }
                        }
                    }

                    // ======== Fiche compte ========
                    ColumnLayout {
                        id: uFiche
                        readonly property var u: root.selUser
                        readonly property bool lastAdmin: !!uFiche.u && uFiche.u.isAdmin && root.admins.length <= 1
                        readonly property string lock: !uFiche.u ? "" : uFiche.u.me ? qsTr("Vous ne pouvez pas changer votre propre rôle ni supprimer votre compte.")
                                                     : uFiche.lastAdmin ? qsTr("Il doit toujours rester au moins un administrateur.") : ""
                        visible: root.tab === 2 && uFiche.u !== null
                        x: root.ficheDocked ? 24 : 0
                        y: root.ficheDocked ? 16 : 26
                        width: parent.width - x
                        spacing: 0

                        CapsLabel { text: qsTr("Compte") }
                        AccountMark { Layout.topMargin: 10; u: uFiche.u; size: 64 }
                        Text { Layout.fillWidth: true; Layout.topMargin: 10; text: uFiche.u ? uFiche.u.name : ""; color: Theme.ink; font.family: Theme.fontFamilySerif; font.pixelSize: Theme.fs(22); font.weight: Theme.weightBold; wrapMode: Text.WordWrap; Accessible.role: Accessible.Heading }
                        Row {
                            Layout.topMargin: 6
                            spacing: 7
                            LineIcon { visible: !!uFiche.u && uFiche.u.isAdmin; anchors.verticalCenter: parent.verticalCenter; path: Icons.shield; size: 14; strokeWidth: 1.8; color: Theme.ink2 }
                            Text { text: (uFiche.u && uFiche.u.isAdmin ? qsTr("Administrateur") : qsTr("Utilisateur")) + (uFiche.u && uFiche.u.me ? " · " + qsTr("vous") : ""); color: Theme.ink2; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13) }
                        }
                        Rectangle { Layout.fillWidth: true; Layout.topMargin: 14; Layout.bottomMargin: 10; Layout.preferredHeight: 1; color: Theme.line }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 7
                            Fact { key: qsTr("Présence"); value: uFiche.u ? root.presenceWord(uFiche.u.presence) : "" }
                            Fact { visible: !!uFiche.u && uFiche.u.machine.length > 0; key: qsTr("Poste"); value: uFiche.u ? uFiche.u.machine : ""; mono: true }
                            Fact { visible: !!uFiche.u && root.dateLabel(uFiche.u.createdAt).length > 0; key: qsTr("Créé le"); value: uFiche.u ? root.dateLabel(uFiche.u.createdAt) : "" }
                            Fact { visible: !!uFiche.u && uFiche.u.uuid.length > 0; key: qsTr("Identifiant"); value: uFiche.u ? uFiche.u.uuid : ""; mono: true }
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.topMargin: 16
                            implicitHeight: uActions.implicitHeight + 2
                            radius: Theme.radiusSheet
                            color: "transparent"
                            border.width: 1
                            border.color: Theme.lineStrong
                            clip: true
                            ColumnLayout {
                                id: uActions
                                x: 1; y: 1
                                width: parent.width - 2
                                spacing: 0
                                FicheAction {
                                    first: true
                                    text: qsTr("Réinitialiser le mot de passe…")
                                    iconPath: Icons.lock
                                    onClicked: {
                                        accountSheet.mode = "reset"
                                        accountSheet.userId = uFiche.u.id
                                        accountSheet.userName = uFiche.u.name
                                        accountSheet.isSelf = uFiche.u.me
                                        accountSheet.open = true
                                    }
                                }
                                FicheAction {
                                    enabled: uFiche.lock.length === 0
                                    text: uFiche.u && uFiche.u.isAdmin ? qsTr("Retirer les droits d'administration…") : qsTr("Donner les droits d'administration…")
                                    iconPath: Icons.shield
                                    onClicked: root.confirm = "role"
                                }
                                FicheAction {
                                    enabled: uFiche.lock.length === 0
                                    danger: true
                                    text: qsTr("Supprimer le compte…")
                                    iconPath: Icons.trash
                                    onClicked: root.confirm = "deluser"
                                }
                            }
                        }
                        Text { visible: uFiche.lock.length > 0; Layout.fillWidth: true; Layout.topMargin: 10; text: uFiche.lock; color: Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12); wrapMode: Text.WordWrap }
                        Text {
                            Layout.fillWidth: true
                            Layout.topMargin: 10
                            text: uFiche.u && uFiche.u.isAdmin ? qsTr("Un administrateur autorise les machines, gère les comptes et consulte le journal d'audit.")
                                                               : qsTr("Un utilisateur échange, partage et appelle ; il ne voit ni l'administration ni le journal d'audit.")
                            color: Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12); wrapMode: Text.WordWrap
                        }
                    }

                    // ======== Ce poste (bascule) ========
                    ColumnLayout {
                        id: bFiche
                        visible: root.tab === 3
                        x: root.ficheDocked ? 24 : 0
                        y: root.ficheDocked ? 16 : 26
                        width: parent.width - x
                        spacing: 0
                        readonly property int timeoutS: root.election && root.election.heartbeatTimeoutMs ? Math.round(root.election.heartbeatTimeoutMs / 1000) : 0

                        CapsLabel { text: qsTr("Ce poste") }
                        Text {
                            Layout.fillWidth: true
                            Layout.topMargin: 6
                            textFormat: Text.StyledText
                            text: root.roleKind === "server" ? qsTr("Serveur <b>officiel</b>") : root.roleKind === "backup" ? qsTr("Serveur <b>de secours</b>") : qsTr("Poste <b>client</b>")
                            color: Theme.ink; font.family: Theme.fontFamilySerif; font.pixelSize: Theme.fs(26)
                            Accessible.role: Accessible.Heading
                        }
                        StateWord {
                            Layout.topMargin: 4
                            glyph: root.roleKind === "backup" ? "away" : "online"
                            word: root.roleKind === "server" ? qsTr("les autres postes passent par lui")
                                  : root.roleKind === "backup" ? qsTr("en attendant le retour du serveur officiel")
                                  : qsTr("relié à %1").arg(root.activeServer)
                            ink: Theme.ink2
                        }
                        Rectangle { Layout.fillWidth: true; Layout.topMargin: 14; Layout.bottomMargin: 10; Layout.preferredHeight: 1; color: Theme.line }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 7
                            Fact { visible: root.activeServer.length > 0; key: qsTr("Serveur actif"); value: root.activeServer; mono: true }
                            Fact { key: qsTr("Génération"); value: String(root.epoch) }
                            Fact { visible: !!root.election && root.election.priorityWeight !== undefined; key: qsTr("Poids de priorité"); value: root.election ? String(root.election.priorityWeight) : "" }
                            Fact { visible: bFiche.timeoutS > 0; key: qsTr("Délai de détection"); value: qsTr("%1 s").arg(bFiche.timeoutS) }
                        }
                        Text {
                            Layout.fillWidth: true
                            Layout.topMargin: 14
                            text: (bFiche.timeoutS > 0 ? qsTr("Si le serveur officiel ne répond plus pendant %1 s, un autre poste prend le relais comme serveur de secours.").arg(bFiche.timeoutS)
                                                       : qsTr("Si le serveur officiel ne répond plus, un autre poste prend le relais comme serveur de secours."))
                                  + " " + qsTr("Le serveur officiel reprend la main à son retour et récupère ce qui s'est passé entre-temps.")
                            color: Theme.ink2; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12.5); lineHeight: 1.15; wrapMode: Text.WordWrap
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.topMargin: 16
                            implicitHeight: bActions.implicitHeight + 2
                            radius: Theme.radiusSheet
                            color: "transparent"
                            border.width: 1
                            border.color: Theme.lineStrong
                            clip: true
                            ColumnLayout {
                                id: bActions
                                x: 1; y: 1
                                width: parent.width - 2
                                spacing: 0
                                FicheAction { first: true; text: qsTr("Poids de priorité"); iconPath: Icons.sliders; hint: qsTr("Paramètres"); onClicked: root.settingsRequested() }
                                FicheAction { text: qsTr("Actualiser l'historique"); iconPath: Icons.refresh; onClicked: root.reloadElection() }
                            }
                        }
                    }
                }
            }
        }
    }

    // ======================================================================
    // Fenetres
    // ======================================================================
    MachineAddSheet {
        id: addSheet
        registered: root.machines
        onAdded: function(name) { root.showNotice(qsTr("%1 est autorisée.").arg(name), false); Qt.callLater(root.reload) }
    }
    AccountFormSheet {
        id: accountSheet
        onDone: function(message) { root.showNotice(message, false); Qt.callLater(root.reload) }
    }

    SheetModal {
        id: confirmSheet
        readonly property var m: root.selMachine
        readonly property var u: root.selUser
        readonly property bool onMachine: root.confirm === "allow" || root.confirm === "deny" || root.confirm === "revoke" || root.confirm === "remove"
        readonly property string target: root.esc(confirmSheet.onMachine ? (confirmSheet.m ? confirmSheet.m.host : "") : (confirmSheet.u ? confirmSheet.u.name : ""))
        open: root.confirm.length > 0 && (confirmSheet.onMachine ? confirmSheet.m !== null : confirmSheet.u !== null)
        boldTitle: false
        sheetWidth: 500
        kicker: {
            switch (root.confirm) {
            case "allow": return confirmSheet.m && confirmSheet.m.status === "revoked" ? qsTr("Rétablir l'accès") : qsTr("Autoriser un poste")
            case "deny": return qsTr("Refuser la demande")
            case "revoke": return qsTr("Révoquer l'accès")
            case "remove": return qsTr("Retirer de la liste")
            case "role": return qsTr("Droits d'administration")
            case "deluser": return qsTr("Supprimer le compte")
            }
            return ""
        }
        title: {
            switch (root.confirm) {
            case "allow": return qsTr("Autoriser <b>%1</b> ?").arg(confirmSheet.target)
            case "deny": return qsTr("Refuser <b>%1</b> ?").arg(confirmSheet.target)
            case "revoke": return qsTr("Révoquer <b>%1</b> ?").arg(confirmSheet.target)
            case "remove": return qsTr("Retirer <b>%1</b> ?").arg(confirmSheet.target)
            case "role": return confirmSheet.u && confirmSheet.u.isAdmin ? qsTr("Retirer les droits de <b>%1</b> ?").arg(confirmSheet.target)
                                                                          : qsTr("Donner les droits à <b>%1</b> ?").arg(confirmSheet.target)
            case "deluser": return qsTr("Supprimer le compte de <b>%1</b> ?").arg(confirmSheet.target)
            }
            return ""
        }
        onCloseRequested: root.confirm = ""

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 10
            Text {
                visible: text.length > 0
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: {
                    const name = confirmSheet.u ? confirmSheet.u.name : ""
                    switch (root.confirm) {
                    case "allow": return qsTr("Ce poste pourra échanger messages, fichiers et appels avec le réseau.")
                    case "deny": return qsTr("Le poste ne pourra pas rejoindre le réseau. Il reste dans la liste comme révoqué ; vous pourrez l'autoriser plus tard.")
                    case "remove": return qsTr("La machine disparaît de la liste. Si elle se reconnecte, elle réapparaîtra en attente d'autorisation.")
                    case "role": return confirmSheet.u && confirmSheet.u.isAdmin
                                        ? qsTr("%1 n'aura plus accès au journal d'audit ni à l'administration. Ses échanges ne changent pas.").arg(name)
                                        : qsTr("%1 pourra autoriser des machines, gérer les comptes et consulter le journal d'audit.").arg(name)
                    }
                    return ""
                }
                color: Theme.ink2; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13)
            }
            // Carte d'identite de la machine
            Rectangle {
                visible: confirmSheet.onMachine && root.confirm !== "revoke"
                Layout.fillWidth: true
                implicitHeight: idCol.implicitHeight + 22
                radius: Theme.radiusSheet
                color: Theme.surface0
                border.width: 1
                border.color: Theme.line
                ColumnLayout {
                    id: idCol
                    x: 14; y: 11
                    width: parent.width - 28
                    spacing: 6
                    Fact { key: qsTr("Machine"); value: confirmSheet.m ? confirmSheet.m.host : ""; mono: true }
                    Fact { visible: !!confirmSheet.m && confirmSheet.m.ip.length > 0; key: qsTr("Adresse"); value: confirmSheet.m ? confirmSheet.m.ip : ""; mono: true }
                    Fact { visible: !!confirmSheet.m && confirmSheet.m.machineId.length > 0; key: qsTr("Identifiant"); value: confirmSheet.m ? confirmSheet.m.machineId : ""; mono: true }
                }
            }
            Text { visible: root.confirm === "allow"; text: qsTr("Empreinte du certificat"); color: Theme.ink; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12.5); font.weight: Theme.weightSemibold }
            FingerprintGrid { visible: root.confirm === "allow"; Layout.fillWidth: true; large: true; fingerprint: confirmSheet.m ? confirmSheet.m.fingerprint : "" }
            Text {
                visible: root.confirm === "allow"
                Layout.fillWidth: true
                text: qsTr("Vérifiez qu'elle correspond à celle affichée sur le poste : c'est ce qui garantit que vous autorisez la bonne machine.")
                color: Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12); wrapMode: Text.WordWrap
            }
            Rectangle {
                visible: root.confirm === "revoke" || root.confirm === "deluser"
                Layout.fillWidth: true
                implicitHeight: warnRow.implicitHeight + 24
                color: Theme.dangerSoft
                Rectangle { width: 2; height: parent.height; color: Theme.dangerColor }
                RowLayout {
                    id: warnRow
                    x: 14; y: 12
                    width: parent.width - 28
                    spacing: 12
                    LineIcon { Layout.alignment: Qt.AlignTop; path: Icons.alertTriangle; size: 18; strokeWidth: 1.8; color: Theme.dangerInk }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Text {
                            Layout.fillWidth: true
                            text: root.confirm === "revoke" ? qsTr("Ce poste ne pourra plus communiquer avec le réseau tant qu'il n'aura pas été autorisé de nouveau.")
                                                            : qsTr("Cette personne ne pourra plus se connecter.")
                            color: Theme.ink; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13); wrapMode: Text.WordWrap
                        }
                        Text {
                            Layout.fillWidth: true
                            text: root.confirm === "revoke" ? qsTr("Ses tentatives de connexion seront refusées et notées au journal d'audit.") : qsTr("Cette action est définitive.")
                            color: Theme.ink2; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12.5); wrapMode: Text.WordWrap
                        }
                    }
                }
            }
        }

        footer: [
            AppButton { variant: "ghost"; text: qsTr("Annuler"); onClicked: root.confirm = "" },
            AppButton {
                readonly property bool danger: root.confirm === "deny" || root.confirm === "revoke" || root.confirm === "remove" || root.confirm === "deluser"
                                               || (root.confirm === "role" && !!confirmSheet.u && confirmSheet.u.isAdmin)
                variant: danger ? "danger" : "ink"
                iconPath: danger ? "" : (root.confirm === "role" ? Icons.shield : Icons.check)
                text: {
                    switch (root.confirm) {
                    case "allow": return qsTr("Autoriser")
                    case "deny": return qsTr("Refuser")
                    case "revoke": return qsTr("Révoquer l'accès")
                    case "remove": return qsTr("Retirer")
                    case "role": return confirmSheet.u && confirmSheet.u.isAdmin ? qsTr("Retirer les droits") : qsTr("Donner les droits")
                    case "deluser": return qsTr("Supprimer le compte")
                    }
                    return ""
                }
                onClicked: root.applyConfirm()
            }
        ]
    }
}
