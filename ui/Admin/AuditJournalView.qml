import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import QtCore
import Themes
import "../Components"
import "../Components/icons.js" as Icons
import "../Call/callPeople.js" as People
import "auditText.js" as AuditText

/*
 * AuditJournalView - ecran « Journal d'audit » en Ligne claire :
 *
 *   [surtitre · « N événements aujourd'hui. » · refus du jour ... 4 chiffres]
 *   [types · recherche / période · acteur                                  ]
 *   [journal groupé par jour                       | fiche de l'événement  ]
 *
 * Donnees : auditLogModel (200 entrees au plus par requete, filtrees en
 * base par type, periode et utilisateur). Le type, la periode et l'acteur
 * passent donc par les filtres du modele -- l'export CSV reprend exactement
 * ces filtres -- ; seule la recherche se fait ici. Trois lectures par
 * rechargement : le jour (en-tete), la periode tous types (onglets), puis
 * le type choisi. Les filtres sont remis a zero en quittant l'ecran
 * (l'accueil lit le meme modele).
 *
 * La phrase de chaque ligne est derivee du texte enregistre (auditText.js) ;
 * le texte brut reste dans la fiche.
 */
Item {
    id: root

    property var audit: (typeof auditLogModel !== "undefined") ? auditLogModel : null
    property var peersSource: (typeof peersModel !== "undefined") ? peersModel : null
    property var messaging: (typeof messagingContext !== "undefined") ? messagingContext : null

    signal backRequested()
    signal peerRequested(string peerId)
    signal conversationRequested(int conversationId)
    signal authorizationsRequested()
    signal transfersRequested()

    // ======================================================================
    // Filtres
    // ======================================================================
    property string type: "all"           // all | connection | message | transfer | call | access_denied
    property string period: "7d"          // today | 7d | 30d | custom
    property string customFrom: ""        // AAAA-MM-JJ
    property string customTo: ""
    property int actorId: 0
    property string actorName: ""
    property string search: ""
    property int selectedId: -1
    property bool customOpen: false       // champs de dates affiches

    // ======================================================================
    // Donnees
    // ======================================================================
    property var peers: []
    property var users: ({})
    property var todayEntries: []
    property var periodEntries: []
    property var entries: []
    property bool busy: false

    function dayIso(d) { return d.toLocaleDateString(Qt.locale("C"), "yyyy-MM-dd") }
    function daysAgo(n) { const d = new Date(); d.setDate(d.getDate() - n); return d }
    readonly property var range: {
        switch (root.period) {
        case "today": return { from: root.dayIso(new Date()) + "T00:00:00", to: "" }
        case "30d": return { from: root.dayIso(root.daysAgo(29)) + "T00:00:00", to: "" }
        case "custom": return { from: root.customFrom.length ? root.customFrom + "T00:00:00" : "",
                                to: root.customTo.length ? root.customTo + "T23:59:59" : "" }
        }
        return { from: root.dayIso(root.daysAgo(6)) + "T00:00:00", to: "" }
    }

    function readEntries() {
        const out = []
        const n = root.audit ? (root.audit.count || 0) : 0
        for (let i = 0; i < n; i++) {
            const e = root.audit.get(i)
            if (e) out.push({ id: Number(e.id), timestamp: e.timestamp, eventType: e.eventType || "",
                              description: e.description || "", userId: Number(e.userId || 0), actorLabel: e.actorLabel || "" })
        }
        return out
    }

    function reload() {
        const a = root.audit
        if (!a || !a.setDateRange) {
            root.todayEntries = []; root.periodEntries = []; root.entries = []
            return
        }
        root.busy = true
        a.setUserIdFilter(0)
        a.setEventTypeFilter("")
        a.setDateRange(root.dayIso(new Date()) + "T00:00:00", "")
        root.todayEntries = root.readEntries()
        a.setDateRange(root.range.from, root.range.to)
        a.setUserIdFilter(root.actorId)
        const all = root.readEntries()
        root.periodEntries = all
        if (root.type !== "all") {
            a.setEventTypeFilter(root.type)
            root.entries = root.readEntries()
        } else {
            root.entries = all
        }
        root.busy = false
        if (root.selectedId >= 0 && !root.entryById(root.selectedId))
            root.selectedId = -1
        if (root.selectedId < 0 && root.rows.length > 0)
            root.selectedId = root.rows[0].id
    }
    function scheduleReload() { if (!root.busy) Qt.callLater(root.reload) }
    // Nouveau filtre : relecture, et retour a la premiere tranche de lignes.
    onTypeChanged: { root.rowsLimit = root.rowsPage; root.scheduleReload() }
    onRangeChanged: { root.rowsLimit = root.rowsPage; root.scheduleReload() }
    onActorIdChanged: { root.rowsLimit = root.rowsPage; root.scheduleReload() }
    onSearchChanged: root.rowsLimit = root.rowsPage

    Connections {
        target: root.audit
        ignoreUnknownSignals: true
        // Un evenement enregistre recharge le modele (AuditManager::eventRecorded).
        function onModelReset() { root.scheduleReload() }
        function onCountChanged() { root.scheduleReload() }
    }

    function reloadPeople() {
        root.peers = People.readPeers(root.peersSource)
        root.users = People.readUsers(root.messaging)
    }
    Connections {
        target: root.peersSource
        ignoreUnknownSignals: true
        function onCountChanged() { root.reloadPeople() }
        function onModelReset() { root.reloadPeople() }
    }

    Component.onCompleted: { root.reloadPeople(); root.reload() }
    Component.onDestruction: if (root.audit && root.audit.clearFilters) root.audit.clearFilters()

    // ---- Lecture ---------------------------------------------------------
    function who(address) { return People.labelFor(root.peers, root.users, address, "") }
    function convName(id) { return root.messaging && root.messaging.conversationDisplayName ? root.messaging.conversationDisplayName(id) : "" }
    function readOf(e) {
        return AuditText.read(e, { who: root.who, conv: root.convName, danger: String(Theme.dangerInk), ok: String(Theme.successInk) })
    }
    function actorOf(e) {
        if (e.userId > 0) {
            const n = root.messaging && root.messaging.userName ? root.messaging.userName(e.userId) : ""
            return n && n.length ? n : qsTr("compte n° %1").arg(e.userId)
        }
        if (e.actorLabel.length)
            return AuditText.isAddress(e.actorLabel) ? root.who(e.actorLabel) : e.actorLabel
        return "—"
    }
    function plain(html) { return String(html || "").replace(/<[^>]*>/g, "").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&") }
    function isToday(iso) { const d = new Date(iso); return !isNaN(d.getTime()) && d.toDateString() === new Date().toDateString() }
    function dayLabel(iso) {
        const d = new Date(iso)
        if (isNaN(d.getTime())) return ""
        const now = new Date()
        if (d.toDateString() === now.toDateString()) return qsTr("Aujourd'hui")
        if (d.toDateString() === root.daysAgo(1).toDateString()) return qsTr("Hier")
        return d.toLocaleDateString(Qt.locale(), "dddd d MMMM")
    }
    function timeOf(iso) { const d = new Date(iso); return isNaN(d.getTime()) ? "" : d.toLocaleTimeString(Qt.locale(), "HH:mm") }
    function fullDate(iso) {
        const d = new Date(iso)
        return isNaN(d.getTime()) ? String(iso || "") : d.toLocaleDateString(Qt.locale(), "dddd d MMMM yyyy") + ", " + d.toLocaleTimeString(Qt.locale(), "HH:mm")
    }
    function kindOf(t) {
        switch (t) {
        case "connection": return { w: qsTr("Connexion"), icon: Icons.link }
        case "message": return { w: qsTr("Message"), icon: Icons.messageCircle }
        case "transfer": return { w: qsTr("Transfert"), icon: Icons.exchange }
        case "call": return { w: qsTr("Appel"), icon: Icons.phoneLine }
        case "access_denied": return { w: qsTr("Refus"), icon: Icons.ban }
        }
        return { w: t, icon: Icons.journal }
    }
    function entryById(id) {
        for (let i = 0; i < root.entries.length; i++) if (root.entries[i].id === id) return root.entries[i]
        return null
    }

    // Lignes creees par tranches (jusqu a 200 entrees par lecture).
    readonly property int rowsPage: 80
    property int rowsLimit: rowsPage

    // Lignes affichees : texte en clair, recherche, separateurs de jour.
    readonly property var rows: {
        const q = root.search.trim().toLowerCase()
        const out = []
        let day = ""
        for (let i = 0; i < root.entries.length; i++) {
            const e = root.entries[i]
            const r = root.readOf(e)
            const actor = root.actorOf(e)
            if (q.length && (root.plain(r.line) + " " + root.plain(r.sub) + " " + actor + " " + e.description + " " + e.actorLabel).toLowerCase().indexOf(q) === -1)
                continue
            const d = root.dayLabel(e.timestamp)
            out.push({ id: e.id, e: e, r: r, actor: actor, refused: e.eventType === "access_denied", newDay: d !== day, day: d })
            day = d
        }
        return out
    }
    // L'evenement choisi disparait (recherche, filtre) : on prend le premier visible.
    onRowsChanged: Qt.callLater(function() {
        if (!root.selected && root.rows.length > 0)
            root.selectedId = root.rows[0].id
    })
    // Comptes par jour calcules une fois par liste : dayCount() refiltrait
    // toute la liste pour chaque ligne (cout quadratique sur un long historique).
    readonly property var dayTotals: {
        const m = {}
        for (let i = 0; i < root.rows.length; i++) m[root.rows[i].day] = (m[root.rows[i].day] || 0) + 1
        return m
    }
    function dayCount(day) { return root.dayTotals[day] || 0 }
    function typeCount(t) { return t === "all" ? root.periodEntries.length : root.periodEntries.filter(function(e) { return e.eventType === t }).length }
    function todayCount(t) { return root.todayEntries.filter(function(e) { return e.eventType === t }).length }

    readonly property var selected: {
        for (let i = 0; i < root.rows.length; i++) if (root.rows[i].id === root.selectedId) return root.rows[i]
        return null
    }
    readonly property var refusedToday: root.todayEntries.filter(function(e) { return e.eventType === "access_denied" })
    readonly property int failuresToday: root.todayEntries.filter(function(e) { return e.eventType !== "access_denied" && root.readOf(e).bad }).length
    readonly property bool nothingAtAll: root.todayEntries.length === 0 && root.periodEntries.length === 0
                                         && root.type === "all" && root.period !== "custom" && root.actorId === 0

    // ======================================================================
    // Export
    // ======================================================================
    property string exportStage: ""        // "" | "ask" | "done"
    property string exportPath: ""
    property string exportError: ""
    readonly property string exportFolder: StandardPaths.writableLocation(StandardPaths.DocumentsLocation).toString()
    function localPath(url) {
        const s = String(url || "")
        return decodeURIComponent(s.replace(/^file:\/{3}(?=[A-Za-z]:)/, "").replace(/^file:\/\//, ""))
    }
    // Entrees exportees : toute la periode filtree (l'affichage s'arrete a 200).
    property int exportTotal: 0
    function openExport() {
        root.exportError = ""
        root.exportTotal = (root.audit && root.audit.exportCount) ? root.audit.exportCount() : root.entries.length
        if (!root.exportPath.length)
            root.exportPath = root.localPath(root.exportFolder) + "/journal-localink-" + root.dayIso(new Date()) + ".csv"
        root.exportStage = "ask"
    }
    function runExport() {
        if (!root.audit || !root.audit.exportToCsv) return
        const done = root.audit.exportToCsv(root.exportPath)
        if (done && String(done).length) {
            root.exportError = ""
            root.exportStage = "done"
        } else {
            root.exportError = qsTr("Le fichier n'a pas pu être écrit à cet emplacement. Choisissez un autre dossier.")
        }
    }
    Connections {
        target: root.audit
        ignoreUnknownSignals: true
        function onError(message) { if (root.exportStage === "ask") root.exportError = message }
    }
    FileDialog {
        id: exportDialog
        title: qsTr("Exporter le journal d'audit")
        fileMode: FileDialog.SaveFile
        nameFilters: [qsTr("Fichiers CSV (*.csv)")]
        defaultSuffix: "csv"
        currentFolder: root.exportFolder
        onAccepted: root.exportPath = root.localPath(selectedFile)
    }
    readonly property string typeWords: ({ all: qsTr("tous les types"), connection: qsTr("connexions"), message: qsTr("messages"),
                                           transfer: qsTr("transferts"), call: qsTr("appels"), access_denied: qsTr("refus") })[root.type] || root.type
    readonly property string periodWords: {
        switch (root.period) {
        case "today": return qsTr("aujourd'hui")
        case "30d": return qsTr("30 derniers jours")
        case "custom":
            return (root.customFrom.length ? qsTr("du %1").arg(root.customFrom) : qsTr("depuis le début"))
                   + " " + (root.customTo.length ? qsTr("au %1").arg(root.customTo) : qsTr("à aujourd'hui"))
        }
        return qsTr("7 derniers jours")
    }

    // ======================================================================
    // Composants
    // ======================================================================
    readonly property real pageW: width - 2 * Theme.pagePadding
    readonly property bool heroWide: pageW > 1180
    readonly property bool ficheDocked: pageW > 980
    readonly property bool roomy: pageW > 1180

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

    // Puce de periode (pleine d'encre quand choisie).
    component PeriodChip: AbstractButton {
        id: pc
        property bool current: false
        hoverEnabled: true
        focusPolicy: Qt.StrongFocus
        implicitHeight: 28
        implicitWidth: pcText.implicitWidth + 24
        Accessible.name: pc.text
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        background: Rectangle {
            radius: height / 2
            color: pc.current ? Theme.ink : "transparent"
            border.width: pc.current ? (pc.visualFocus ? 2 : 0) : (pc.visualFocus ? 2 : 1)
            border.color: pc.visualFocus ? Theme.focusRing : (pc.hovered ? Theme.ink : Theme.lineStrong)
        }
        contentItem: Text {
            id: pcText
            text: pc.text
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            color: pc.current ? Theme.inkOnInk : (pc.hovered ? Theme.ink : Theme.ink2)
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fs(12.5)
            font.weight: Theme.weightSemibold
        }
    }

    // Champ de date AAAA-MM-JJ.
    component DateField: TextField {
        implicitWidth: 118
        implicitHeight: 28
        leftPadding: 10
        rightPadding: 8
        placeholderTextColor: Theme.ink3
        color: Theme.ink
        font.family: "Cascadia Mono"
        font.pixelSize: Theme.fs(12)
        selectByMouse: true
        validator: RegularExpressionValidator { regularExpression: /^$|^\d{4}-\d{2}-\d{2}$/ }
        background: Rectangle {
            radius: Theme.radiusSheet
            color: Theme.surface0
            border.width: parent.activeFocus ? 2 : 1
            border.color: parent.activeFocus ? Theme.focusRing : Theme.lineStrong
        }
    }

    // Pastille ronde d'un type d'evenement.
    component KindMark: Rectangle {
        property string icon: ""
        property bool danger: false
        property int size: 24
        implicitWidth: size
        implicitHeight: size
        radius: size / 2
        color: "transparent"
        border.width: 1
        border.color: danger ? Theme.dangerColor : Theme.lineStrong
        LineIcon { anchors.centerIn: parent; path: parent.icon; size: Math.round(parent.size * 0.54); strokeWidth: 1.8; color: parent.danger ? Theme.dangerInk : Theme.ink2 }
    }

    component FicheAction: AbstractButton {
        id: fa
        property string iconPath: ""
        property string hint: ""
        property bool first: false
        Layout.fillWidth: true
        implicitHeight: 42
        hoverEnabled: true
        focusPolicy: Qt.StrongFocus
        Accessible.name: fa.text
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        background: Rectangle {
            color: fa.hovered ? Theme.ink : "transparent"
            border.width: fa.visualFocus ? 2 : 0
            border.color: Theme.focusRing
            Rectangle { visible: !fa.first; width: parent.width; height: 1; color: Theme.lineStrong }
        }
        contentItem: RowLayout {
            spacing: 10
            LineIcon { Layout.leftMargin: 12; path: fa.iconPath; size: 15; strokeWidth: 1.8; color: fa.hovered ? Theme.inkOnInk : Theme.ink3 }
            Text { Layout.fillWidth: true; text: fa.text; color: fa.hovered ? Theme.inkOnInk : Theme.ink; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13); font.weight: Theme.weightSemibold }
            Text {
                Layout.maximumWidth: fa.width * 0.42
                Layout.rightMargin: 12
                horizontalAlignment: Text.AlignRight
                visible: fa.hint.length > 0
                text: fa.hint
                elide: Text.ElideRight
                color: fa.hovered ? Theme.inkOnInk : Theme.ink3
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(11.5)
            }
        }
    }

    component Fact: RowLayout {
        property string key: ""
        property string value: ""
        property bool mono: false
        Layout.fillWidth: true
        spacing: 16
        Text { Layout.alignment: Qt.AlignTop; text: parent.key; color: Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13) }
        Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignRight
            text: parent.value
            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
            color: Theme.ink
            font.family: parent.mono ? "Cascadia Mono" : Theme.fontFamily
            font.pixelSize: parent.mono ? Theme.fs(12) : Theme.fs(13)
            font.features: ({ "tnum": 1 })
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
                        text: {
                            const d = new Date().toLocaleDateString(Qt.locale(), "dddd d MMMM yyyy")
                            return d + ((typeof settingsModel !== "undefined" && settingsModel && settingsModel.machineName && settingsModel.machineName.length > 0)
                                        ? " · " + settingsModel.machineName : "")
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        textFormat: Text.StyledText
                        text: root.nothingAtAll ? qsTr("Aucun événement enregistré.")
                              : root.todayEntries.length === 1 ? qsTr("<b>1</b> événement aujourd'hui.")
                              : qsTr("<b>%1</b> événements aujourd'hui.").arg(root.todayEntries.length)
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
                                if (root.nothingAtAll)
                                    return qsTr("Les connexions, messages, transferts, appels et refus d'accès sur ce réseau apparaîtront ici.")
                                let t = ""
                                const n = root.refusedToday.length
                                if (n > 0) {
                                    const last = root.refusedToday[0]
                                    const r = root.readOf(last)
                                    t = "<b><font color=\"" + Theme.dangerInk + "\">"
                                        + (n > 1 ? qsTr("%1 tentatives refusées").arg(n) : qsTr("1 tentative refusée")) + "</font></b>"
                                        + (n > 1 ? qsTr(", la dernière à %1").arg(root.timeOf(last.timestamp)) : qsTr(" à %1").arg(root.timeOf(last.timestamp)))
                                        + (r.ip ? qsTr(" depuis %1").arg(AuditText.esc(root.who(r.ip))) : "") + "."
                                } else {
                                    t = qsTr("Aucune tentative refusée aujourd'hui.")
                                }
                                if (root.failuresToday > 0)
                                    t += " " + (root.failuresToday > 1 ? qsTr("%1 échecs ou appels manqués.").arg(root.failuresToday) : qsTr("1 échec ou appel manqué."))
                                return t
                            }
                        }
                        Row {
                            id: heroActions
                            spacing: 8
                            AppButton {
                                visible: root.entries.length > 0
                                variant: "line"
                                iconPath: Icons.arrowUpRight
                                text: qsTr("Exporter en CSV")
                                onClicked: root.openExport()
                            }
                        }
                    }
                }

                // Quatre chiffres du jour (filtrent le journal)
                Item {
                    visible: !root.nothingAtAll
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
                                { key: "connection", label: qsTr("Connexions") },
                                { key: "transfer", label: qsTr("Transferts") },
                                { key: "call", label: qsTr("Appels") },
                                { key: "access_denied", label: qsTr("Refus") }
                            ]
                            delegate: Item {
                                id: fig
                                required property var modelData
                                required property int index
                                readonly property int n: root.todayCount(fig.modelData.key)
                                readonly property bool refus: fig.modelData.key === "access_denied"
                                width: root.heroWide ? sf.width + (index === 0 ? 0 : 22) + (index === 3 ? 0 : 22) : figRow.width / 4
                                height: sf.implicitHeight + 6
                                Rectangle { visible: fig.index > 0; width: 1; height: sf.implicitHeight; color: Theme.line }
                                SerifFigure {
                                    id: sf
                                    x: fig.index === 0 ? 0 : (root.heroWide ? 22 : 18)
                                    width: Math.max(implicitWidth, 110)
                                    label: fig.modelData.label
                                    value: String(fig.n)
                                    context: fig.refus ? (fig.n > 0 ? qsTr("à examiner") : qsTr("aucun")) : qsTr("aujourd'hui")
                                    attention: fig.refus && fig.n > 0
                                    valueSize: root.heroWide && root.height >= 720 ? Theme.fontSizeFigure : Theme.fs(32)
                                    onClicked: root.type = root.type === fig.modelData.key ? "all" : fig.modelData.key
                                }
                                Rectangle {
                                    visible: root.type === fig.modelData.key
                                    x: sf.x
                                    y: sf.implicitHeight + 4
                                    width: sf.width
                                    height: 2
                                    color: Theme.ruleInk
                                }
                            }
                        }
                    }
                }
            }

            // ---- Journal | fiche ------------------------------------------
            Rectangle { Layout.fillWidth: true; Layout.topMargin: -4; Layout.preferredHeight: 2; color: Theme.ruleInk }

            GridLayout {
                Layout.fillWidth: true
                Layout.topMargin: -20
                columns: root.ficheDocked ? 2 : 1
                columnSpacing: 0
                rowSpacing: 0

                // -- Journal ----------------------------------------------------
                ColumnLayout {
                    id: logCol
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    Layout.topMargin: 14
                    Layout.rightMargin: root.ficheDocked && root.selected ? 24 : 0
                    spacing: 0

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.bottomMargin: 8
                        CapsLabel { text: qsTr("Événements"); Layout.fillWidth: true }
                        Text { text: root.rows.length; color: Theme.ink3; font.family: Theme.fontFamilySerif; font.pixelSize: Theme.fs(16); font.weight: Theme.weightBold }
                    }

                    // Types et recherche
                    Item {
                        Layout.fillWidth: true
                        implicitHeight: Math.max(tabsFlow.implicitHeight, findBox.height + 6)
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
                        Flow {
                            id: tabsFlow
                            width: parent.width - findBox.width - 16
                            spacing: 18
                            InkTab { text: qsTr("Tout"); count: String(root.typeCount("all")); current: root.type === "all"; onClicked: root.type = "all" }
                            InkTab { text: qsTr("Connexions"); count: String(root.typeCount("connection")); current: root.type === "connection"; onClicked: root.type = "connection" }
                            InkTab { text: qsTr("Messages"); count: String(root.typeCount("message")); current: root.type === "message"; onClicked: root.type = "message" }
                            InkTab { text: qsTr("Transferts"); count: String(root.typeCount("transfer")); current: root.type === "transfer"; onClicked: root.type = "transfer" }
                            InkTab { text: qsTr("Appels"); count: String(root.typeCount("call")); current: root.type === "call"; onClicked: root.type = "call" }
                            InkTab { text: qsTr("Refus"); danger: true; count: String(root.typeCount("access_denied")); current: root.type === "access_denied"; onClicked: root.type = "access_denied" }
                        }
                        Rectangle {
                            id: findBox
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 6
                            width: logCol.width > 760 ? 240 : 180
                            height: 30
                            radius: Theme.radiusSheet
                            color: "transparent"
                            border.width: 1
                            border.color: findField.activeFocus ? Theme.ink : Theme.line
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 6
                                spacing: 7
                                LineIcon { path: Icons.search; size: 14; strokeWidth: 1.8; color: Theme.ink3 }
                                TextField {
                                    id: findField
                                    Layout.fillWidth: true
                                    text: root.search
                                    placeholderText: qsTr("Poste, personne, fichier…")
                                    placeholderTextColor: Theme.ink3
                                    color: Theme.ink
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(12.5)
                                    background: Item {}
                                    leftPadding: 0
                                    rightPadding: 0
                                    selectByMouse: true
                                    Accessible.name: qsTr("Rechercher dans le journal")
                                    onTextEdited: root.search = text
                                }
                                AbstractButton {
                                    visible: root.search.length > 0
                                    implicitWidth: 20
                                    implicitHeight: 20
                                    Accessible.name: qsTr("Effacer la recherche")
                                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                                    contentItem: LineIcon { path: Icons.close; size: 12; strokeWidth: 2; color: Theme.ink3 }
                                    onClicked: root.search = ""
                                }
                            }
                        }
                    }

                    // Periode et acteur
                    Flow {
                        Layout.fillWidth: true
                        Layout.topMargin: 10
                        spacing: 8
                        Text { height: 28; verticalAlignment: Text.AlignVCenter; text: qsTr("Période"); color: Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12) }
                        PeriodChip { text: qsTr("Aujourd'hui"); current: root.period === "today" && !root.customOpen; onClicked: { root.customOpen = false; root.period = "today" } }
                        PeriodChip { text: qsTr("7 jours"); current: root.period === "7d" && !root.customOpen; onClicked: { root.customOpen = false; root.period = "7d" } }
                        PeriodChip { text: qsTr("30 jours"); current: root.period === "30d" && !root.customOpen; onClicked: { root.customOpen = false; root.period = "30d" } }
                        PeriodChip {
                            text: qsTr("Personnalisée")
                            current: root.period === "custom" || root.customOpen
                            onClicked: {
                                root.customOpen = true
                                fromField.text = root.customFrom.length ? root.customFrom : root.dayIso(root.daysAgo(29))
                                toField.text = root.customTo
                                fromField.forceActiveFocus()
                            }
                        }
                        Row {
                            id: customRow
                            visible: root.customOpen || root.period === "custom"
                            spacing: 6
                            Text { height: 28; verticalAlignment: Text.AlignVCenter; text: qsTr("du"); color: Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12.5) }
                            DateField { id: fromField; text: root.customFrom; placeholderText: qsTr("AAAA-MM-JJ"); Accessible.name: qsTr("Date de début") }
                            Text { height: 28; verticalAlignment: Text.AlignVCenter; text: qsTr("au"); color: Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12.5) }
                            DateField { id: toField; text: root.customTo; placeholderText: qsTr("aujourd'hui"); Accessible.name: qsTr("Date de fin"); onAccepted: applyBtn.clicked() }
                            AppButton {
                                id: applyBtn
                                variant: "ink"
                                size: "small"
                                text: qsTr("Appliquer")
                                enabled: fromField.acceptableInput && toField.acceptableInput && (fromField.text.length > 0 || toField.text.length > 0)
                                onClicked: {
                                    root.customFrom = fromField.text
                                    root.customTo = toField.text
                                    root.period = "custom"
                                    root.customOpen = false
                                }
                            }
                        }
                        Rectangle {
                            visible: root.actorId > 0
                            height: 28
                            width: actorChipRow.implicitWidth + 20
                            radius: 14
                            color: Theme.surface1
                            border.width: 1
                            border.color: Theme.lineStrong
                            Row {
                                id: actorChipRow
                                anchors.centerIn: parent
                                spacing: 6
                                Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Acteur : %1").arg(root.actorName); color: Theme.ink; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12); font.weight: Theme.weightSemibold }
                                AbstractButton {
                                    anchors.verticalCenter: parent.verticalCenter
                                    implicitWidth: 16
                                    implicitHeight: 16
                                    Accessible.name: qsTr("Retirer le filtre d'acteur")
                                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                                    contentItem: LineIcon { path: Icons.close; size: 11; strokeWidth: 2.2; color: Theme.ink2 }
                                    onClicked: { root.actorId = 0; root.actorName = "" }
                                }
                            }
                        }
                    }

                    // Etats vides
                    ColumnLayout {
                        visible: root.rows.length === 0
                        Layout.fillWidth: true
                        Layout.topMargin: 22
                        Layout.leftMargin: 8
                        spacing: 4
                        Text {
                            text: root.nothingAtAll ? qsTr("Rien d'enregistré pour l'instant.") : qsTr("Aucun événement ne correspond.")
                            color: Theme.ink
                            font.family: Theme.fontFamilySerif
                            font.pixelSize: Theme.fs(20)
                        }
                        Row {
                            spacing: 6
                            Text {
                                text: root.nothingAtAll ? qsTr("Le journal se remplit au fil des connexions, transferts, appels et refus d'accès.")
                                                        : qsTr("Élargissez la période, changez de type ou effacez la recherche.")
                                color: Theme.ink3
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(12.5)
                            }
                            TextLink {
                                visible: !root.nothingAtAll
                                text: qsTr("Tout afficher")
                                arrow: false
                                fontSize: Theme.fs(12.5)
                                onClicked: {
                                    root.search = ""
                                    root.actorId = 0
                                    root.actorName = ""
                                    root.type = "all"
                                    root.customOpen = false
                                    root.period = "30d"
                                }
                            }
                        }
                    }

                    Repeater {
                        model: root.rows.length > root.rowsLimit ? root.rows.slice(0, root.rowsLimit) : root.rows
                        delegate: ColumnLayout {
                            id: er
                            required property var modelData
                            readonly property var x0: modelData
                            readonly property bool on: er.x0.id === root.selectedId
                            readonly property var kind: root.kindOf(er.x0.e.eventType)
                            Layout.fillWidth: true
                            spacing: 0

                            RowLayout {
                                visible: er.x0.newDay
                                Layout.fillWidth: true
                                Layout.topMargin: 16
                                Layout.leftMargin: 8
                                Layout.bottomMargin: 6
                                spacing: 10
                                CapsLabel { text: er.x0.day; color: Theme.ink2 }
                                Text {
                                    readonly property int n: root.dayCount(er.x0.day)
                                    text: n > 1 ? qsTr("%1 événements").arg(n) : qsTr("1 événement")
                                    color: Theme.ink3
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(11.5)
                                }
                            }
                            Rectangle { visible: er.x0.newDay; Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.ruleInk }

                            Rectangle {
                                id: evRow
                                Layout.fillWidth: true
                                implicitHeight: Math.max(50, whatCol.implicitHeight + 14)
                                color: er.on ? Theme.surface0 : (evHover.hovered ? Theme.selectWash : "transparent")
                                border.width: er.on ? 1 : 0
                                border.color: Theme.line
                                Accessible.role: Accessible.ListItem
                                Accessible.name: root.timeOf(er.x0.e.timestamp) + ", " + er.kind.w + ", " + root.plain(er.x0.r.line)
                                HoverHandler { id: evHover; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: root.selectedId = er.x0.id }
                                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
                                Rectangle {
                                    visible: er.on || er.x0.refused
                                    width: 3
                                    height: parent.height
                                    color: er.x0.refused ? Theme.dangerColor : Theme.ruleInk
                                }
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    spacing: 14
                                    Text {
                                        Layout.preferredWidth: 40
                                        text: root.timeOf(er.x0.e.timestamp)
                                        color: Theme.ink3
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fs(12)
                                        font.features: ({ "tnum": 1 })
                                    }
                                    Row {
                                        visible: logCol.width > 640
                                        Layout.preferredWidth: 112
                                        spacing: 8
                                        KindMark { anchors.verticalCenter: parent.verticalCenter; icon: er.kind.icon; danger: er.x0.refused }
                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: er.kind.w
                                            color: er.x0.refused ? Theme.dangerInk : Theme.ink2
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fs(12.5)
                                            font.weight: Theme.weightSemibold
                                        }
                                    }
                                    ColumnLayout {
                                        id: whatCol
                                        Layout.fillWidth: true
                                        spacing: 1
                                        Text {
                                            Layout.fillWidth: true
                                            textFormat: Text.StyledText
                                            text: er.x0.r.line
                                            color: Theme.ink
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fs(13.5)
                                            font.weight: Theme.weightMedium
                                            elide: Text.ElideRight
                                            maximumLineCount: 1
                                        }
                                        Text {
                                            visible: er.x0.r.sub.length > 0
                                            Layout.fillWidth: true
                                            textFormat: Text.StyledText
                                            text: er.x0.r.sub
                                            color: Theme.ink3
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fs(12)
                                            elide: Text.ElideRight
                                            maximumLineCount: 1
                                        }
                                    }
                                    Text {
                                        visible: root.roomy
                                        Layout.preferredWidth: 160
                                        text: er.x0.actor
                                        color: Theme.ink2
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fs(12.5)
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }
                    }

                    TextLink {
                        visible: root.rows.length > root.rowsLimit
                        Layout.topMargin: 10
                        text: qsTr("Afficher %1 entrées de plus (%2 restantes)")
                              .arg(Math.min(root.rowsPage, root.rows.length - root.rowsLimit))
                              .arg(root.rows.length - root.rowsLimit)
                        arrow: false
                        fontSize: Theme.fs(12.5)
                        onClicked: root.rowsLimit += root.rowsPage
                    }

                    RowLayout {
                        visible: root.rows.length > 0
                        Layout.fillWidth: true
                        Layout.topMargin: 10
                        Text { Layout.fillWidth: true; text: qsTr("Enregistré sur ce poste · les plus récents en tête."); color: Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12); elide: Text.ElideRight }
                        Text {
                            text: root.rows.length === root.entries.length ? (root.rows.length > 1 ? qsTr("%1 événements").arg(root.rows.length) : qsTr("1 événement"))
                                  : qsTr("%1 sur %2 événements").arg(root.rows.length).arg(root.entries.length)
                            color: Theme.ink3
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(12)
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
                    Rectangle { visible: root.ficheDocked; width: 1; height: Math.max(parent.height, logCol.height + 14); color: Theme.line }
                    Rectangle { visible: !root.ficheDocked; width: parent.width; height: 1; y: 10; color: Theme.line }

                    ColumnLayout {
                        id: fiche
                        readonly property var s: root.selected
                        readonly property var e: fiche.s ? fiche.s.e : null
                        readonly property var r: fiche.s ? fiche.s.r : null
                        readonly property var kind: fiche.e ? root.kindOf(fiche.e.eventType) : ({ w: "", icon: "" })
                        readonly property var peer: fiche.r && fiche.r.ip ? People.peerAt(root.peers, fiche.r.ip) : null
                        readonly property bool refused: !!fiche.e && fiche.e.eventType === "access_denied"
                        readonly property bool canPeer: fiche.peer !== null
                        readonly property bool canAuth: fiche.refused && !!fiche.r && !!fiche.r.ip && fiche.peer === null
                        readonly property bool canConv: !!fiche.r && fiche.r.conv > 0
                        readonly property bool canTransfers: !!fiche.r && !!fiche.r.file
                        readonly property bool canActor: !!fiche.e && fiche.e.userId > 0 && root.actorId !== fiche.e.userId
                        readonly property bool canAddress: !!fiche.e && fiche.e.userId <= 0 && !!fiche.r && !!fiche.r.ip && root.search !== fiche.r.ip
                        x: root.ficheDocked ? 24 : 0
                        y: root.ficheDocked ? 16 : 26
                        width: parent.width - x
                        spacing: 0

                        Row {
                            spacing: 9
                            KindMark { anchors.verticalCenter: parent.verticalCenter; size: 30; icon: fiche.kind.icon; danger: fiche.refused }
                            CapsLabel { anchors.verticalCenter: parent.verticalCenter; text: fiche.kind.w; color: fiche.refused ? Theme.dangerInk : Theme.ink2 }
                        }
                        Text {
                            Layout.fillWidth: true
                            Layout.topMargin: 12
                            textFormat: Text.StyledText
                            text: fiche.r ? fiche.r.line : ""
                            color: Theme.ink
                            font.family: Theme.fontFamilySerif
                            font.pixelSize: Theme.fs(21)
                            lineHeight: 1.15
                            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                            Accessible.role: Accessible.Heading
                        }
                        Text {
                            visible: !!fiche.r && fiche.r.sub.length > 0
                            Layout.fillWidth: true
                            Layout.topMargin: 4
                            textFormat: Text.StyledText
                            text: fiche.r ? fiche.r.sub : ""
                            color: Theme.ink2
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(12.5)
                            wrapMode: Text.WordWrap
                        }

                        Rectangle { Layout.fillWidth: true; Layout.topMargin: 14; Layout.bottomMargin: 10; Layout.preferredHeight: 1; color: Theme.line }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 7
                            Fact { key: qsTr("Date"); value: fiche.e ? root.fullDate(fiche.e.timestamp) : "" }
                            Fact { key: qsTr("Acteur"); value: fiche.s ? fiche.s.actor : "" }
                            Fact { visible: !!fiche.r && !!fiche.r.ip; key: qsTr("Poste"); value: fiche.peer ? fiche.peer.machine : qsTr("inconnu") }
                            Fact { visible: !!fiche.r && !!fiche.r.ip; key: qsTr("Adresse"); value: fiche.r && fiche.r.ip ? fiche.r.ip : ""; mono: true }
                            Fact { key: qsTr("Référence"); value: fiche.e ? "#" + fiche.e.id : ""; mono: true }
                        }

                        CapsLabel { Layout.topMargin: 16; text: qsTr("Texte enregistré") }
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.topMargin: 6
                            implicitHeight: rawText.implicitHeight + 20
                            radius: Theme.radiusSheet
                            color: Theme.surface0
                            border.width: 1
                            border.color: Theme.line
                            TextEdit {
                                id: rawText
                                x: 12
                                y: 10
                                width: parent.width - 24
                                readOnly: true
                                selectByMouse: true
                                text: fiche.e ? fiche.e.description : ""
                                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                                color: Theme.ink2
                                selectionColor: Theme.selectWash
                                selectedTextColor: Theme.ink
                                font.family: "Cascadia Mono"
                                font.pixelSize: Theme.fs(12)
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.topMargin: 16
                            implicitHeight: actions.implicitHeight + 2
                            visible: fiche.canPeer || fiche.canAuth || fiche.canConv || fiche.canTransfers || fiche.canActor || fiche.canAddress
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
                                    id: viewPeer
                                    first: true
                                    visible: fiche.canPeer
                                    text: qsTr("Voir le poste")
                                    iconPath: Icons.monitor
                                    hint: fiche.peer ? fiche.peer.machine : ""
                                    onClicked: root.peerRequested(fiche.peer.id)
                                }
                                FicheAction {
                                    id: manageAuth
                                    first: !fiche.canPeer
                                    visible: fiche.canAuth
                                    text: qsTr("Gérer les autorisations")
                                    iconPath: Icons.shield
                                    onClicked: root.authorizationsRequested()
                                }
                                FicheAction {
                                    id: openConv
                                    first: !fiche.canPeer && !fiche.canAuth
                                    visible: fiche.canConv
                                    text: qsTr("Ouvrir la discussion")
                                    iconPath: Icons.messageCircle
                                    onClicked: root.conversationRequested(fiche.r.conv)
                                }
                                FicheAction {
                                    id: openTransfers
                                    first: !fiche.canPeer && !fiche.canAuth && !fiche.canConv
                                    visible: fiche.canTransfers
                                    text: qsTr("Voir les transferts")
                                    iconPath: Icons.exchange
                                    hint: qsTr("Transferts")
                                    onClicked: root.transfersRequested()
                                }
                                FicheAction {
                                    id: byActor
                                    first: !fiche.canPeer && !fiche.canAuth && !fiche.canConv && !fiche.canTransfers
                                    visible: fiche.canActor
                                    text: qsTr("Événements de cet acteur")
                                    iconPath: Icons.users
                                    hint: fiche.s ? fiche.s.actor : ""
                                    onClicked: { root.actorName = fiche.s.actor; root.actorId = fiche.e.userId }
                                }
                                FicheAction {
                                    id: byAddress
                                    first: !fiche.canPeer && !fiche.canAuth && !fiche.canConv && !fiche.canTransfers && !fiche.canActor
                                    visible: fiche.canAddress
                                    text: qsTr("Événements de cette adresse")
                                    iconPath: Icons.search
                                    hint: fiche.r && fiche.r.ip ? fiche.r.ip : ""
                                    onClicked: { root.search = fiche.r.ip; root.type = "all" }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ======================================================================
    // Fenetre d'export
    // ======================================================================
    SheetModal {
        id: exportSheet
        open: root.exportStage.length > 0
        kicker: qsTr("Exporter le journal")
        title: root.exportStage === "done" ? qsTr("Export terminé") : qsTr("Exporter en CSV")
        sheetWidth: 480
        onCloseRequested: root.exportStage = ""

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 10

            // -- Avant export
            Text {
                visible: root.exportStage === "ask"
                Layout.fillWidth: true
                text: root.search.length ? qsTr("L'export reprend ces filtres :") : qsTr("L'export reprend exactement les événements affichés :")
                color: Theme.ink2
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(13)
                wrapMode: Text.WordWrap
            }
            ColumnLayout {
                visible: root.exportStage === "ask"
                Layout.fillWidth: true
                spacing: 7
                Fact { key: qsTr("Types"); value: root.typeWords }
                Fact { key: qsTr("Période"); value: root.periodWords }
                Fact { visible: root.actorId > 0; key: qsTr("Acteur"); value: root.actorName }
                Fact { key: qsTr("Événements"); value: String(root.exportTotal) }
            }

            // -- Apres export
            Rectangle {
                visible: root.exportStage === "done"
                Layout.fillWidth: true
                implicitHeight: doneCol.implicitHeight + 24
                color: Theme.surface0
                border.width: 1
                border.color: Theme.line
                Rectangle { width: 2; height: parent.height; color: Theme.successColor }
                RowLayout {
                    x: 14
                    y: 12
                    width: parent.width - 28
                    spacing: 10
                    StateGlyph { Layout.alignment: Qt.AlignTop; Layout.topMargin: 2; kind: "ok"; size: 14 }
                    ColumnLayout {
                        id: doneCol
                        Layout.fillWidth: true
                        spacing: 2
                        Text { text: root.exportTotal > 1 ? qsTr("%1 événements exportés.").arg(root.exportTotal) : qsTr("1 événement exporté."); color: Theme.ink; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13); font.weight: Theme.weightSemibold }
                        Text { Layout.fillWidth: true; text: qsTr("Le fichier contient les textes enregistrés tels quels (date, type, description, acteur)."); color: Theme.ink2; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12.5); wrapMode: Text.WordWrap }
                    }
                }
            }

            // Emplacement
            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 2
                implicitHeight: Math.max(pathText.implicitHeight, 30) + 24
                radius: Theme.radiusSheet
                color: Theme.surface0
                border.width: 1
                border.color: Theme.ruleInk
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 12
                    spacing: 12
                    LineIcon { path: Icons.file; size: 20; strokeWidth: 1.6; color: Theme.ink2 }
                    Text {
                        id: pathText
                        Layout.fillWidth: true
                        text: root.exportPath
                        color: Theme.ink
                        font.family: "Cascadia Mono"
                        font.pixelSize: Theme.fs(12.5)
                        wrapMode: Text.WrapAnywhere
                    }
                    AppButton {
                        visible: root.exportStage === "ask"
                        variant: "line"
                        size: "small"
                        text: qsTr("Changer…")
                        onClicked: exportDialog.open()
                    }
                }
            }
            Text {
                visible: root.exportStage === "ask"
                Layout.fillWidth: true
                textFormat: Text.StyledText
                text: qsTr("Colonnes : ID, date, type, description, utilisateur, acteur · séparateur virgule, UTF-8.")
                      + (root.search.length ? "<br>" + qsTr("La recherche « %1 » n'est pas reprise : l'export suit le type, la période et l'acteur.").arg(AuditText.esc(root.search)) : "")
                color: Theme.ink3
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(12)
                wrapMode: Text.WordWrap
            }
            Text {
                visible: root.exportError.length > 0
                Layout.fillWidth: true
                text: root.exportError
                color: Theme.dangerInk
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(12.5)
                font.weight: Theme.weightSemibold
                wrapMode: Text.WordWrap
            }
        }

        footer: [
            AppButton {
                variant: "ghost"
                text: root.exportStage === "done" ? qsTr("Fermer") : qsTr("Annuler")
                onClicked: root.exportStage = ""
            },
            AppButton {
                visible: root.exportStage === "ask"
                variant: "ink"
                iconPath: Icons.arrowUpRight
                text: root.exportTotal > 1 ? qsTr("Exporter %1 événements").arg(root.exportTotal) : qsTr("Exporter 1 événement")
                enabled: root.exportTotal > 0 && root.exportPath.length > 0
                onClicked: root.runExport()
            },
            AppButton {
                visible: root.exportStage === "done"
                variant: "ink"
                iconPath: Icons.folder
                text: qsTr("Ouvrir le dossier")
                onClicked: {
                    const p = root.exportPath
                    const dir = p.substring(0, Math.max(p.lastIndexOf("/"), p.lastIndexOf("\\")))
                    Qt.openUrlExternally("file:///" + dir.replace(/^\/+/, ""))
                }
            }
        ]
    }
}
