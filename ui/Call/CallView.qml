import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import "../Components"
import "../Chat"
import "../Components/icons.js" as Icons
import "callPeople.js" as People

/*
 * CallView - ecran « Appels » en Ligne claire, meme coque que les autres :
 *
 *   [surtitre · phrase-titre · qui a essaye de joindre ... 4 chiffres serif]
 *   [Postes joignables (Appeler)   | Journal des appels par jour          ]
 *
 * L'appel en cours n'est pas gere ici : CallOverlay (Main.qml) l'affiche
 * par-dessus tous les ecrans (fenetre centrale puis bande en bas).
 *
 * Donnees : peersModel (postes), callHistoryModel (journal du compte
 * connecte), callContext (appel en cours), messagingContext (nom des
 * personnes, via userUuid).
 */
Item {
    id: root

    property var call: (typeof callContext !== "undefined") ? callContext : null
    property var peersSource: (typeof peersModel !== "undefined") ? peersModel : null
    property var history: (typeof callHistoryModel !== "undefined") ? callHistoryModel : null
    property var messaging: (typeof messagingContext !== "undefined") ? messagingContext : null

    signal backRequested()

    readonly property string callState: root.call ? root.call.callState : "idle"
    readonly property bool inCall: root.callState !== "" && root.callState !== "idle"
    readonly property string remoteAddress: root.call ? root.call.remoteAddress : ""

    // ======================================================================
    // Donnees
    // ======================================================================
    property var peers: []
    property var users: ({})
    function reloadPeers() {
        root.peers = People.readPeers(root.peersSource)
        root.users = People.readUsers(root.messaging)
    }
    Connections {
        target: root.peersSource
        ignoreUnknownSignals: true
        function onCountChanged() { root.reloadPeers() }
        function onRowsInserted() { root.reloadPeers() }
        function onRowsRemoved() { root.reloadPeers() }
        function onModelReset() { root.reloadPeers() }
        function onDataChanged() { root.reloadPeers() }
    }
    Connections {
        target: root.messaging
        ignoreUnknownSignals: true
        function onAvailableUsersChanged() { root.reloadPeers() }
        function onPresenceChanged() { root.reloadPeers() }
    }

    Instantiator {
        id: historySource
        model: root.history
        delegate: QtObject {
            required property string direction
            required property string peerAddress
            required property string peerName
            required property string status
            required property var startedAt
            required property int durationSeconds
        }
        onObjectAdded: Qt.callLater(root.rebuildHistory)
        onObjectRemoved: Qt.callLater(root.rebuildHistory)
    }
    property var calls: []
    function rebuildHistory() {
        const out = []
        for (let i = 0; i < historySource.count; i++) {
            const o = historySource.objectAt(i)
            if (o) out.push({ direction: o.direction, address: o.peerAddress, name: o.peerName, status: o.status,
                              startedAt: o.startedAt, duration: o.durationSeconds })
        }
        out.sort(function(a, b) { return new Date(b.startedAt).getTime() - new Date(a.startedAt).getTime() })
        root.calls = out
    }

    Component.onCompleted: { root.reloadPeers(); root.rebuildHistory() }
    // Un appel qui se termine s'ajoute au journal.
    onCallStateChanged: if (!root.inCall && root.history && root.history.refresh) Qt.callLater(root.history.refresh)

    function labelOf(address, fallback) { return People.labelFor(root.peers, root.users, address, fallback) }
    function isToday(iso) { const d = new Date(iso); return !isNaN(d.getTime()) && d.toDateString() === new Date().toDateString() }
    function dayLabel(iso) {
        const d = new Date(iso)
        if (isNaN(d.getTime())) return ""
        const now = new Date()
        if (d.toDateString() === now.toDateString()) return qsTr("Aujourd'hui")
        const y = new Date(now.getTime() - 86400000)
        if (d.toDateString() === y.toDateString()) return qsTr("Hier")
        return d.toLocaleDateString(Qt.locale(), "dddd d MMMM")
    }
    function timeOf(iso) { const d = new Date(iso); return isNaN(d.getTime()) ? "" : d.toLocaleTimeString(Qt.locale(), "HH:mm") }
    function esc(t) { return String(t === undefined || t === null ? "" : t).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;") }

    readonly property var today: root.calls.filter(function(c) { return root.isToday(c.startedAt) })
    readonly property var missedToday: root.today.filter(function(c) { return c.status === "missed" })
    readonly property int talkToday: root.today.reduce(function(a, c) { return a + (c.status === "completed" ? c.duration : 0) }, 0)
    readonly property var reachable: root.peers.filter(function(p) { return People.presenceKind(p.status) !== "offline" })

    // ======================================================================
    // Actions
    // ======================================================================
    property string filter: "all"           // "all" | "missed" | "out" | "in"
    property string peerSearch: ""
    property string errorText: ""

    function callPeer(p) {
        if (!root.call || !p || root.inCall) return
        if (!root.call.call(p.address, p.signalingPort || 0))
            root.showError(qsTr("Impossible d'appeler %1.").arg(People.personOf(p, root.users) || p.machine || p.address))
    }
    function callBack(address) {
        root.callPeer(People.peerAt(root.peers, address))
    }
    function showError(text) { root.errorText = text; errorTimer.restart() }
    Timer { id: errorTimer; interval: 6000; onTriggered: root.errorText = "" }

    readonly property var historyRows: {
        const f = root.filter
        const list = root.calls.filter(function(c) {
            return f === "missed" ? c.status === "missed" : f === "out" ? c.direction === "outgoing" : f === "in" ? c.direction !== "outgoing" : true
        })
        const out = []
        let day = ""
        for (let i = 0; i < list.length; i++) {
            const d = root.dayLabel(list[i].startedAt)
            out.push(Object.assign({ newDay: d !== day, day: d }, list[i]))
            day = d
        }
        return out
    }
    function dayCount(day) { return root.historyRows.filter(function(r) { return r.day === day }).length }

    readonly property var peerRows: {
        const q = root.peerSearch.trim().toLowerCase()
        const rank = function(p) { return People.presenceKind(p.status) === "busy" ? 1 : 0 }
        return root.peers.filter(function(p) {
            const name = (People.personOf(p, root.users) || p.machine).toLowerCase()
            return q.length === 0 || name.indexOf(q) !== -1 || p.machine.toLowerCase().indexOf(q) !== -1
        }).sort(function(a, b) {
            return rank(a) - rank(b) || (People.personOf(a, root.users) || a.machine).localeCompare(People.personOf(b, root.users) || b.machine)
        })
    }

    // ======================================================================
    // Composants
    // ======================================================================
    readonly property real pageW: width - 2 * Theme.pagePadding
    readonly property bool heroWide: pageW > 1180
    readonly property bool twoCols: pageW > 900

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

    // Bouton « Appeler » a filet (plein d'encre au survol).
    component CallButton: AbstractButton {
        id: cb
        property string tip: ""
        hoverEnabled: true
        focusPolicy: Qt.StrongFocus
        implicitHeight: 32
        implicitWidth: cbRow.implicitWidth + 24
        Accessible.name: cb.tip.length ? cb.tip : cb.text
        ToolTip.visible: cb.tip.length > 0 && cb.hovered
        ToolTip.text: cb.tip
        ToolTip.delay: 400
        HoverHandler { cursorShape: cb.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
        background: Rectangle {
            radius: Theme.radiusSheet
            color: cb.hovered && cb.enabled ? Theme.ink : "transparent"
            border.width: cb.hovered && cb.enabled ? 0 : (cb.visualFocus ? 2 : 1)
            border.color: cb.visualFocus ? Theme.focusRing : (cb.enabled ? Theme.lineStrong : Theme.line)
        }
        contentItem: Item {
            Row {
                id: cbRow
                anchors.centerIn: parent
                spacing: 7
                LineIcon { anchors.verticalCenter: parent.verticalCenter; path: Icons.phoneLine; size: 15; strokeWidth: 1.7; color: !cb.enabled ? Theme.inkDisabled : cb.hovered ? Theme.inkOnInk : Theme.ink }
                Text { anchors.verticalCenter: parent.verticalCenter; text: cb.text; color: !cb.enabled ? Theme.inkDisabled : cb.hovered ? Theme.inkOnInk : Theme.ink; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12.5); font.weight: Theme.weightSemibold }
            }
        }
    }

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

            // ---- Avis d'erreur ------------------------------------------
            Rectangle {
                visible: root.errorText.length > 0
                Layout.fillWidth: true
                implicitHeight: errRow.implicitHeight + 20
                color: Theme.surface0
                border.width: 1
                border.color: Theme.line
                Rectangle { width: 3; height: parent.height; color: Theme.dangerColor }
                RowLayout {
                    id: errRow
                    anchors.verticalCenter: parent.verticalCenter
                    x: 16
                    width: parent.width - 26
                    spacing: 12
                    LineIcon { path: Icons.alertTriangle; size: 16; strokeWidth: 1.8; color: Theme.dangerInk }
                    Text { Layout.fillWidth: true; text: root.errorText; wrapMode: Text.WordWrap; color: Theme.ink; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13) }
                    TextLink { text: qsTr("OK"); arrow: false; onClicked: root.errorText = "" }
                }
            }

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
                        text: root.callState === "connected" ? qsTr("En appel avec <b>%1</b>.").arg(root.esc(root.labelOf(root.remoteAddress, "")))
                              : root.peers.length === 0 && root.calls.length === 0 ? qsTr("Aucun appel pour l'instant.")
                              : root.missedToday.length > 1 ? qsTr("<b>%1</b> appels manqués.").arg(root.missedToday.length)
                              : root.missedToday.length === 1 ? qsTr("<b>1</b> appel manqué.")
                              : qsTr("Aucun appel en cours.")
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
                                let t = root.peers.length === 0
                                        ? qsTr("Aucun poste n'est joignable : les appels passent de poste à poste sur le réseau local, sans Internet.")
                                        : (root.reachable.length > 1 ? qsTr("<b>%1</b> postes joignables sur le réseau local.").arg(root.reachable.length)
                                                                     : qsTr("<b>%1</b> poste joignable sur le réseau local.").arg(root.reachable.length))
                                if (root.missedToday.length > 0) {
                                    const m = root.missedToday[0]
                                    t += " " + qsTr("%1 a essayé de vous joindre à %2.")
                                         .arg("<b><font color=\"" + Theme.dangerInk + "\">" + root.esc(root.labelOf(m.address, m.name)) + "</font></b>")
                                         .arg(root.timeOf(m.startedAt))
                                }
                                return t
                            }
                        }
                        Row {
                            id: heroActions
                            spacing: 8
                            AppButton {
                                readonly property var m: root.missedToday.length ? root.missedToday[0] : null
                                visible: m !== null
                                variant: "ink"
                                iconPath: Icons.phoneLine
                                text: m ? qsTr("Rappeler %1").arg(root.labelOf(m.address, m.name).split(" ")[0]) : ""
                                enabled: !root.inCall && m !== null && People.peerAt(root.peers, m.address) !== null
                                tooltip: m && People.peerAt(root.peers, m.address) === null ? qsTr("Ce poste n'est plus sur le réseau") : ""
                                onClicked: root.callBack(m.address)
                            }
                        }
                    }
                }

                // Quatre chiffres
                Item {
                    visible: root.peers.length > 0 || root.calls.length > 0
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
                                { key: "", label: qsTr("Joignables"), value: String(root.reachable.length), ctx: qsTr("postes en ligne") },
                                { key: "all", label: qsTr("Aujourd'hui"), value: String(root.today.length), ctx: root.today.length > 1 ? qsTr("appels") : qsTr("appel") },
                                { key: "missed", label: qsTr("Manqués"), value: String(root.missedToday.length), ctx: root.missedToday.length ? qsTr("à rappeler") : qsTr("aucun"), attention: root.missedToday.length > 0 },
                                { key: "", label: qsTr("Temps d'appel"), value: root.talkToday >= 60 ? String(Math.round(root.talkToday / 60)) : String(root.talkToday),
                                  suffix: root.talkToday >= 60 ? qsTr("min") : qsTr("s"), ctx: qsTr("aujourd'hui") }
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
                                    value: fig.modelData.value
                                    suffix: fig.modelData.suffix ? " " + fig.modelData.suffix : ""
                                    context: fig.modelData.ctx
                                    attention: !!fig.modelData.attention
                                    valueSize: root.heroWide && root.height >= 720 ? Theme.fontSizeFigure : Theme.fs(32)
                                    onClicked: if (fig.modelData.key.length) root.filter = (root.filter === fig.modelData.key && fig.modelData.key !== "all") ? "all" : fig.modelData.key
                                }
                            }
                        }
                    }
                }
            }

            // ---- Postes | journal --------------------------------------------
            Rectangle { Layout.fillWidth: true; Layout.topMargin: -4; Layout.preferredHeight: 2; color: Theme.ruleInk }

            GridLayout {
                Layout.fillWidth: true
                Layout.topMargin: -20
                columns: root.twoCols ? 2 : 1
                columnSpacing: 0
                rowSpacing: 0

                // -- Postes joignables ----------------------------------------
                ColumnLayout {
                    id: peerCol
                    Layout.fillWidth: !root.twoCols
                    Layout.preferredWidth: root.twoCols ? root.pageW * 0.44 : -1
                    Layout.alignment: Qt.AlignTop
                    Layout.topMargin: 14
                    Layout.rightMargin: root.twoCols ? 24 : 0
                    spacing: 0

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.bottomMargin: 10
                        CapsLabel { text: qsTr("Postes joignables"); Layout.fillWidth: true }
                        Text { text: root.peers.length; color: Theme.ink3; font.family: Theme.fontFamilySerif; font.pixelSize: Theme.fs(16); font.weight: Theme.weightBold }
                    }
                    Rectangle {
                        visible: root.peers.length > 0
                        Layout.fillWidth: true
                        Layout.preferredHeight: 32
                        Layout.bottomMargin: 6
                        radius: Theme.radiusSheet
                        color: "transparent"
                        border.width: 1
                        border.color: peerFind.activeFocus ? Theme.ink : Theme.line
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 8
                            spacing: 7
                            LineIcon { path: Icons.search; size: 14; strokeWidth: 1.8; color: Theme.ink3 }
                            TextField {
                                id: peerFind
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
                                Accessible.name: qsTr("Rechercher un poste")
                                onTextChanged: root.peerSearch = text
                            }
                        }
                    }
                    Text {
                        visible: root.peers.length === 0
                        Layout.fillWidth: true
                        text: qsTr("Les postes du réseau local apparaissent ici dès qu'ils sont détectés. Un poste doit être en ligne pour être appelé.")
                        color: Theme.ink3
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(12.5)
                        wrapMode: Text.WordWrap
                    }

                    Repeater {
                        model: root.peerRows
                        delegate: Rectangle {
                            id: pr
                            required property var modelData
                            required property int index
                            readonly property var p: modelData
                            readonly property string person: People.personOf(pr.p, root.users)
                            readonly property bool here: root.inCall && pr.p.address === root.remoteAddress
                            Layout.fillWidth: true
                            implicitHeight: 60
                            color: prHover.hovered ? Theme.selectWash : "transparent"
                            radius: Theme.radiusSheet
                            HoverHandler { id: prHover }
                            Rectangle { visible: pr.index > 0; width: parent.width; height: 1; color: Theme.line }
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                spacing: 12
                                ChatMonogram { label: pr.person.length ? pr.person : pr.p.machine; machine: pr.person.length === 0; status: pr.p.status || "online" }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1
                                    Text { Layout.fillWidth: true; text: pr.person.length ? pr.person : pr.p.machine; color: Theme.ink; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13.5); font.weight: Theme.weightSemibold; elide: Text.ElideRight }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 0
                                        Text { visible: pr.person.length > 0; text: pr.p.machine + " · "; color: Theme.ink3; font.family: "Cascadia Mono"; font.pixelSize: Theme.fs(11.5) }
                                        Text {
                                            Layout.fillWidth: true
                                            text: People.presenceWord(pr.p.status) + (People.presenceKind(pr.p.status) === "busy" ? " · " + qsTr("peut refuser l'appel") : "")
                                            color: Theme.ink3
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fs(12)
                                            elide: Text.ElideRight
                                        }
                                    }
                                }
                                CallButton {
                                    text: pr.here ? qsTr("En appel") : qsTr("Appeler")
                                    enabled: !root.inCall && root.call !== null
                                    tip: root.inCall ? qsTr("Un appel est déjà en cours") : qsTr("Appeler %1").arg(pr.person.length ? pr.person : pr.p.machine)
                                    onClicked: root.callPeer(pr.p)
                                }
                            }
                        }
                    }
                }

                // -- Journal des appels ---------------------------------------
                Item {
                    id: histCol
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    Layout.minimumHeight: peerCol.implicitHeight + 14
                    implicitHeight: histInner.implicitHeight + 18
                    readonly property bool roomy: width > 600

                    Rectangle { visible: root.twoCols; width: 1; height: Math.max(parent.height, peerCol.height + 14); color: Theme.line }
                    Rectangle { visible: !root.twoCols; width: parent.width; height: 1; y: 4; color: Theme.line }

                    ColumnLayout {
                        id: histInner
                        x: root.twoCols ? 28 : 0
                        y: root.twoCols ? 14 : 18
                        width: parent.width - x
                        spacing: 0

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.bottomMargin: 8
                            CapsLabel { text: qsTr("Journal des appels"); Layout.fillWidth: true }
                            Text { text: root.calls.length; color: Theme.ink3; font.family: Theme.fontFamilySerif; font.pixelSize: Theme.fs(16); font.weight: Theme.weightBold }
                        }
                        Item {
                            Layout.fillWidth: true
                            implicitHeight: 31
                            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
                            Row {
                                spacing: 18
                                InkTab { text: qsTr("Tous"); count: String(root.calls.length); current: root.filter === "all"; onClicked: root.filter = "all" }
                                InkTab { text: qsTr("Manqués"); danger: true; count: String(root.calls.filter(function(c) { return c.status === "missed" }).length); current: root.filter === "missed"; onClicked: root.filter = "missed" }
                                InkTab { text: qsTr("Émis"); count: String(root.calls.filter(function(c) { return c.direction === "outgoing" }).length); current: root.filter === "out"; onClicked: root.filter = "out" }
                                InkTab { text: qsTr("Reçus"); count: String(root.calls.filter(function(c) { return c.direction !== "outgoing" }).length); current: root.filter === "in"; onClicked: root.filter = "in" }
                            }
                        }
                        Text {
                            visible: root.historyRows.length === 0
                            Layout.topMargin: 12
                            text: root.calls.length ? qsTr("Aucun appel dans cette catégorie.") : qsTr("Vos appels émis et reçus apparaîtront ici.")
                            color: Theme.ink3
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(12.5)
                        }

                        Repeater {
                            model: root.historyRows
                            delegate: ColumnLayout {
                                id: hr
                                required property var modelData
                                readonly property var c: modelData
                                readonly property bool missed: hr.c.status === "missed"
                                readonly property bool out: hr.c.direction === "outgoing"
                                readonly property var peer: People.peerAt(root.peers, hr.c.address)
                                readonly property var st: {
                                    switch (hr.c.status) {
                                    case "completed": return { w: qsTr("Terminé"), g: "ok", c: Theme.successInk }
                                    case "missed": return { w: qsTr("Manqué"), g: "error", c: Theme.dangerInk }
                                    case "rejected": return { w: qsTr("Refusé"), g: "error", c: Theme.dangerInk }
                                    case "failed": return { w: qsTr("Échoué"), g: "error", c: Theme.dangerInk }
                                    case "cancelled": return { w: qsTr("Annulé"), g: "watch", c: Theme.ink3 }
                                    }
                                    return { w: qsTr("En cours"), g: "transferring", c: Theme.navActiveInk }
                                }
                                Layout.fillWidth: true
                                spacing: 0

                                RowLayout {
                                    visible: hr.c.newDay
                                    Layout.fillWidth: true
                                    Layout.topMargin: 14
                                    Layout.bottomMargin: 6
                                    spacing: 10
                                    CapsLabel { text: hr.c.day; color: Theme.ink2 }
                                    Text { text: root.dayCount(hr.c.day) > 1 ? qsTr("%1 appels").arg(root.dayCount(hr.c.day)) : qsTr("1 appel"); color: Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(11.5) }
                                }
                                Rectangle { visible: hr.c.newDay; Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.ruleInk }

                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 50
                                    color: hrHover.hovered ? Theme.selectWash : "transparent"
                                    HoverHandler { id: hrHover }
                                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
                                    RowLayout {
                                        anchors.fill: parent
                                        spacing: 12
                                        Rectangle {
                                            Layout.preferredWidth: 22
                                            Layout.preferredHeight: 22
                                            radius: 11
                                            color: "transparent"
                                            border.width: 1
                                            border.color: hr.missed ? Theme.dangerColor : Theme.lineStrong
                                            LineIcon { anchors.centerIn: parent; path: hr.out ? Icons.arrowUp : Icons.arrowDown; size: 12; strokeWidth: 2.1; color: hr.missed ? Theme.dangerInk : Theme.ink2 }
                                        }
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 1
                                            Text { Layout.fillWidth: true; text: root.labelOf(hr.c.address, hr.c.name); color: hr.missed ? Theme.dangerInk : Theme.ink; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13.5); font.weight: Theme.weightSemibold; elide: Text.ElideRight }
                                            Text {
                                                Layout.fillWidth: true
                                                text: (hr.out ? qsTr("Émis") : qsTr("Reçu")) + " · " + (hr.peer ? hr.peer.machine : (hr.c.name && hr.c.name.length ? hr.c.name : hr.c.address))
                                                color: Theme.ink3
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.fs(12)
                                                elide: Text.ElideRight
                                            }
                                        }
                                        Row {
                                            Layout.preferredWidth: 104
                                            spacing: 6
                                            StateGlyph { anchors.verticalCenter: parent.verticalCenter; kind: hr.st.g; size: 11 }
                                            Text { anchors.verticalCenter: parent.verticalCenter; text: hr.st.w; color: hr.st.c; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12.5); font.weight: hr.c.status === "cancelled" ? Theme.weightMedium : Theme.weightSemibold }
                                        }
                                        Text { Layout.preferredWidth: 66; horizontalAlignment: Text.AlignRight; text: People.duration(hr.c.duration); color: Theme.ink2; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12.5); font.features: ({ "tnum": 1 }) }
                                        Text { visible: histCol.roomy; Layout.preferredWidth: 40; horizontalAlignment: Text.AlignRight; text: root.timeOf(hr.c.startedAt); color: Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12); font.features: ({ "tnum": 1 }) }
                                        TextLink {
                                            Layout.preferredWidth: 84
                                            arrow: false
                                            text: qsTr("Rappeler")
                                            fontSize: Theme.fs(12.5)
                                            opacity: hr.missed || hrHover.hovered ? 1 : 0
                                            enabled: hr.peer !== null && !root.inCall
                                            tooltip: hr.peer === null ? qsTr("Poste hors ligne") : ""
                                            onClicked: root.callBack(hr.c.address)
                                        }
                                    }
                                }
                            }
                        }
                        RowLayout {
                            visible: root.calls.length > 0
                            Layout.fillWidth: true
                            Layout.topMargin: 10
                            Text { Layout.fillWidth: true; text: qsTr("Appels de votre compte, sur ce poste."); color: Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12) }
                            TextLink { text: qsTr("Actualiser"); arrow: false; fontSize: Theme.fs(12); onClicked: if (root.history && root.history.refresh) root.history.refresh() }
                        }
                    }
                }
            }
        }
    }
}
