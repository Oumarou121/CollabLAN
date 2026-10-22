import QtQuick
import QtQuick.Controls
import QtQuick.Shapes
import Themes
import "../Components"
import "../Components/icons.js" as Icons
import "hemicycleLayout.js" as L

/*
 * Hemicycle - representation des postes de Ligne claire.
 *
 * Les postes sont des sieges regroupes par etat sur un demi-cercle, ce
 * poste (« tribune ») au centre du sol. La FORME du siege porte l'etat
 * (plein, demi, barre, pointille), l'anneau d'un transfert sa progression ;
 * seuls les transferts et l'appel en cours sont relies a la tribune. Les
 * noms sont en marge, de part et d'autre. Disposition indicative, pas une
 * topologie.
 *
 * peers : [{ id, name, address, userName, status, server, transfer }]
 *         (status deja derive : calling/transferring/online/busy/away/offline ;
 *         transfer = entree de transferContext.activeTransfers ou null).
 *
 * Le Repeater des sieges ne depend que de { id, status } et de la taille :
 * un tick de progression ne recree pas les sieges (un clic en cours n'est
 * jamais perdu), il met seulement a jour l'anneau via livePeer().
 */
Item {
    id: root

    property var peers: []
    property string selectedId: ""
    property var hiddenStatuses: []
    property string localName: ""
    // "server" | "backup" | "client"
    property string localState: "server"
    property string localLabel: ""

    signal seatActivated(string peerId)

    readonly property int peerCount: peers.length
    readonly property bool namesForAll: peerCount <= L.MAX_ALL_LABELS

    function statusHidden(s) { return root.hiddenStatuses.indexOf(s) >= 0 }

    function livePeer(id) {
        for (let i = 0; i < root.peers.length; i++)
            if (root.peers[i].id === id)
                return root.peers[i]
        return null
    }

    function percentOf(p) {
        if (!p || !p.transfer)
            return 0
        return Math.max(0, Math.min(100, p.transfer.percent || 0))
    }

    function detailOf(p) {
        if (!p)
            return ""
        switch (p.status) {
        case "transferring":
            return (p.transfer && p.transfer.incoming ? qsTr("Réception") : qsTr("Envoi"))
                   + " · " + Math.round(root.percentOf(p)) + " %"
        case "calling": return qsTr("En appel")
        case "offline": return qsTr("Hors ligne")
        case "away": return qsTr("Absent")
        case "busy": return qsTr("Occupé")
        }
        return p.server ? qsTr("Serveur · en ligne") : qsTr("En ligne")
    }

    function detailColor(status) {
        switch (status) {
        case "transferring": return Theme.navActiveInk
        case "calling": return Theme.callInk
        case "away":
        case "busy": return Theme.warningInk
        }
        return Theme.ink3
    }

    // ---- Geometrie ----------------------------------------------------------
    // Cle de structure : identite et etat des postes, taille. Ni la
    // progression ni la selection n'y figurent.
    readonly property string structureKey: {
        const sorted = L.sortPeers(root.peers)
        return sorted.map(function(p) { return p.id + ":" + p.status }).join("|")
               + "#" + Math.round(width) + "x" + Math.round(height)
    }
    property var sortedPeers: []
    property var geo: ({ seats: [], cx: 0, cy: 0, rOut: 0, rIn: 0, rows: 0, s: 10, rT: 26,
                         labelW: 140, floorY: 0, allLabels: true })
    property var labels: []
    // Sieges relies a la tribune (transfert, appel) : recalcules avec la
    // structure et les filtres, pas a chaque tick de progression.
    property var flowSeats: []

    function relayoutSeats() {
        root.sortedPeers = L.sortPeers(root.peers)
        root.geo = L.computeSeats(root.sortedPeers, root.width, root.height)
        root.relayoutLabels()
    }

    function relayoutFlows() {
        const out = []
        for (let i = 0; i < root.geo.seats.length; i++) {
            const st = root.geo.seats[i]
            const p = root.sortedPeers[st.index]
            if (p && !root.statusHidden(p.status) && (p.status === "transferring" || p.status === "calling"))
                out.push(st)
        }
        root.flowSeats = out
    }

    function relayoutLabels() {
        const info = {}
        for (let i = 0; i < root.sortedPeers.length; i++) {
            const p = root.sortedPeers[i]
            info[p.id] = {
                visible: !root.statusHidden(p.status),
                notable: p.status === "transferring" || p.status === "calling" || !!p.server,
                selected: p.id === root.selectedId,
                ring: p.status === "transferring"
            }
        }
        root.labels = L.computeLabels(root.geo, info, Math.round(labelMetrics.height * 2 + 6))
        root.relayoutFlows()
    }

    onStructureKeyChanged: Qt.callLater(root.relayoutSeats)
    onSelectedIdChanged: Qt.callLater(root.relayoutLabels)
    onHiddenStatusesChanged: Qt.callLater(root.relayoutLabels)
    Component.onCompleted: relayoutSeats()

    FontMetrics {
        id: labelMetrics
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fs(12.5)
    }

    readonly property real cx: geo.cx
    readonly property real cy: geo.cy
    readonly property real s: geo.s
    readonly property real rT: geo.rT

    // ---- Reperes : arcs et sol ----------------------------------------------
    Shape {
        anchors.fill: parent
        visible: root.peerCount > 0
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: "transparent"
            strokeColor: Theme.line
            strokeWidth: 1
            PathAngleArc {
                centerX: root.cx; centerY: root.cy
                radiusX: root.geo.rOut + root.s + 10; radiusY: radiusX
                startAngle: 180; sweepAngle: 180
            }
        }
        ShapePath {
            fillColor: "transparent"
            strokeColor: root.geo.rows > 1 ? Theme.line : "transparent"
            strokeWidth: 1
            strokeStyle: ShapePath.DashLine
            dashPattern: [1, 4]
            PathAngleArc {
                centerX: root.cx; centerY: root.cy
                radiusX: Math.max(1, root.geo.rIn - root.s - 10); radiusY: radiusX
                startAngle: 180; sweepAngle: 180
            }
        }
        ShapePath {
            strokeColor: Theme.lineStrong
            strokeWidth: 1
            fillColor: "transparent"
            startX: 12; startY: root.cy
            PathLine { x: root.width - 12; y: root.cy }
        }
    }

    // ---- Traits de rappel (sous les sieges) ---------------------------------
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillColor: "transparent"
            strokeColor: Theme.lineStrong
            strokeWidth: 1
            PathMultiline {
                paths: root.labels.filter(function(l) { return !l.selected })
                                  .map(function(l) { return [Qt.point(l.x0, l.y0), Qt.point(l.x1, l.y1)] })
            }
        }
        ShapePath {
            fillColor: "transparent"
            strokeColor: Theme.ruleInk
            strokeWidth: 1
            PathMultiline {
                paths: root.labels.filter(function(l) { return l.selected })
                                  .map(function(l) { return [Qt.point(l.x0, l.y0), Qt.point(l.x1, l.y1)] })
            }
        }
    }

    // ---- Flux : transferts et appel de CE poste -----------------------------
    Repeater {
        model: root.flowSeats

        delegate: Shape {
            id: flow
            required property var modelData
            readonly property var peer: root.livePeer(modelData.id)
            readonly property bool incoming: !!(peer && peer.transfer && peer.transfer.incoming)
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                id: flowPath
                fillColor: "transparent"
                strokeColor: flow.peer && flow.peer.status === "calling" ? Theme.callColor : Theme.markTransfer
                strokeWidth: 1.5
                strokeStyle: ShapePath.DashLine
                dashPattern: [2, 3.4]
                capStyle: ShapePath.RoundCap
                startX: root.cx
                startY: root.cy - root.rT
                PathQuad {
                    x: flow.modelData.x
                    y: flow.modelData.y
                    controlX: (root.cx + flow.modelData.x) / 2 + (flow.modelData.y - root.cy) * 0.16
                    controlY: (root.cy - root.rT + flow.modelData.y) / 2 - (flow.modelData.x - root.cx) * 0.16
                }
            }
            NumberAnimation {
                target: flowPath
                property: "dashOffset"
                from: 0
                to: flow.incoming ? 5.4 : -5.4
                duration: 1100
                loops: Animation.Infinite
                running: root.visible
            }
        }
    }

    // ---- Sieges ---------------------------------------------------------------
    Repeater {
        id: seatRepeater
        model: root.geo.seats

        delegate: Item {
            id: seat
            required property var modelData
            required property int index
            readonly property var peer: root.livePeer(modelData.id)
            readonly property string status: peer ? peer.status : "online"
            readonly property bool hidden: root.statusHidden(status)
            readonly property bool selected: modelData.id === root.selectedId
            readonly property real r: root.s

            x: modelData.x - width / 2
            y: modelData.y - height / 2
            width: r * 2 + 18
            height: width
            opacity: hidden ? 0.14 : 1
            enabled: !hidden
            activeFocusOnTab: !hidden
            Accessible.role: Accessible.Button
            Accessible.name: (peer ? peer.name : "") + ", " + root.detailOf(peer) + (selected ? qsTr(", sélectionné") : "")
            Behavior on opacity { NumberAnimation { duration: Theme.durationNormal } }

            function activate() { root.seatActivated(seat.modelData.id) }
            Keys.onReturnPressed: activate()
            Keys.onEnterPressed: activate()
            Keys.onSpacePressed: activate()
            Keys.onRightPressed: root.stepFrom(seat.index, 1)
            Keys.onDownPressed: root.stepFrom(seat.index, 1)
            Keys.onLeftPressed: root.stepFrom(seat.index, -1)
            Keys.onUpPressed: root.stepFrom(seat.index, -1)

            // Anneau de selection / survol / focus clavier.
            Rectangle {
                anchors.centerIn: parent
                readonly property real d: (seat.status === "transferring" ? seat.r + 8 : seat.r + 5) * 2
                width: d
                height: d
                radius: d / 2
                color: "transparent"
                border.width: seat.selected || seat.activeFocus ? 2 : (hover.hovered ? 1.5 : 0)
                border.color: seat.activeFocus && !seat.selected ? Theme.focusRing
                            : seat.selected ? Theme.ruleInk : Theme.ink3
            }

            // Appel en cours : onde discrete.
            Rectangle {
                id: pulse
                visible: seat.status === "calling"
                anchors.centerIn: parent
                width: seat.r * 2
                height: width
                radius: width / 2
                color: Theme.callColor
                opacity: 0
                SequentialAnimation on scale {
                    running: pulse.visible && root.visible
                    loops: Animation.Infinite
                    NumberAnimation { from: 1; to: 1.9; duration: 2200; easing.type: Easing.OutQuad }
                }
                SequentialAnimation on opacity {
                    running: pulse.visible && root.visible
                    loops: Animation.Infinite
                    NumberAnimation { from: 0.45; to: 0; duration: 2200; easing.type: Easing.OutQuad }
                }
            }

            // Transfert : piste + progression autour du siege.
            Shape {
                visible: seat.status === "transferring"
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    fillColor: "transparent"
                    strokeColor: Theme.lineStrong
                    strokeWidth: 2
                    PathAngleArc {
                        centerX: seat.width / 2; centerY: seat.height / 2
                        radiusX: seat.r + 4; radiusY: radiusX
                        startAngle: 0; sweepAngle: 360
                    }
                }
                ShapePath {
                    fillColor: "transparent"
                    strokeColor: Theme.markTransfer
                    strokeWidth: 2
                    capStyle: ShapePath.FlatCap
                    PathAngleArc {
                        centerX: seat.width / 2; centerY: seat.height / 2
                        radiusX: seat.r + 4; radiusY: radiusX
                        startAngle: -90; sweepAngle: Math.max(0.1, root.percentOf(seat.peer) * 3.6)
                    }
                }
            }

            StateGlyph {
                anchors.centerIn: parent
                kind: seat.status
                size: seat.r * 2
            }

            // Serveur : losange creuse au centre du siege.
            Rectangle {
                visible: !!(seat.peer && seat.peer.server)
                anchors.centerIn: parent
                width: 6.5
                height: 6.5
                rotation: 45
                color: Theme.surface0
            }

            HoverHandler {
                id: hover
                cursorShape: Qt.PointingHandCursor
            }
            TapHandler { onTapped: seat.activate() }

            ToolTip.visible: hover.hovered
            ToolTip.delay: 300
            ToolTip.text: seat.peer
                          ? seat.peer.name + "\n" + (seat.peer.userName || qsTr("Aucun compte connecté"))
                            + (seat.peer.address ? " · " + seat.peer.address : "") + "\n" + root.detailOf(seat.peer)
                          : ""
        }
    }

    // Fleches : siege suivant / precedent dans l'ordre visuel (sieges visibles).
    function stepFrom(index, delta) {
        const n = seatRepeater.count
        for (let k = 1; k <= n; k++) {
            const j = (index + delta * k + n * k) % n
            const it = seatRepeater.itemAt(j)
            if (it && !it.hidden) {
                it.forceActiveFocus()
                root.seatActivated(it.modelData.id)
                return
            }
        }
    }

    // ---- Noms en marge -----------------------------------------------------
    Repeater {
        model: root.labels

        delegate: Item {
            id: lbl
            required property var modelData
            readonly property var peer: root.livePeer(modelData.id)
            readonly property bool leftSide: modelData.side === "L"
            x: leftSide ? modelData.x - root.geo.labelW : modelData.x
            y: modelData.y - labelMetrics.ascent
            width: root.geo.labelW
            height: col.implicitHeight

            Column {
                id: col
                width: parent.width
                spacing: 1

                Text {
                    width: parent.width
                    horizontalAlignment: lbl.leftSide ? Text.AlignRight : Text.AlignLeft
                    text: lbl.peer ? lbl.peer.name : ""
                    color: Theme.ink
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(12.5)
                    font.weight: lbl.modelData.selected ? Theme.weightBold : Theme.weightSemibold
                    font.underline: lbl.modelData.selected || nameHover.hovered
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    horizontalAlignment: lbl.leftSide ? Text.AlignRight : Text.AlignLeft
                    text: root.detailOf(lbl.peer)
                    color: root.detailColor(lbl.peer ? lbl.peer.status : "")
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11.5)
                    elide: Text.ElideRight
                }
            }

            HoverHandler { id: nameHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.seatActivated(lbl.modelData.id) }
            ToolTip.visible: nameHover.hovered && lbl.peer && lbl.peer.name.length > 22
            ToolTip.text: lbl.peer ? lbl.peer.name : ""
            ToolTip.delay: 400
        }
    }

    // ---- Tribune : ce poste ----------------------------------------------------
    Shape {
        visible: root.peerCount > 0
        x: root.cx - root.rT - 6
        y: root.cy - root.rT - 6
        width: root.rT * 2 + 12
        height: root.rT + 6
        preferredRendererType: Shape.CurveRenderer

        // Mode secours : arc ambre en tirets autour de la tribune.
        ShapePath {
            fillColor: "transparent"
            strokeColor: root.localState === "backup" ? Theme.warningColor : "transparent"
            strokeWidth: 2
            strokeStyle: ShapePath.DashLine
            dashPattern: [2, 1.5]
            PathAngleArc {
                centerX: root.rT + 6; centerY: root.rT + 6
                radiusX: root.rT + 5; radiusY: radiusX
                startAngle: 180; sweepAngle: 180
            }
        }
        ShapePath {
            fillColor: root.localState === "client" ? Theme.surface0 : Theme.ink
            strokeColor: root.localState === "client" ? Theme.ink : "transparent"
            strokeWidth: 1.5
            startX: 6; startY: root.rT + 6
            PathArc {
                x: root.rT * 2 + 6; y: root.rT + 6
                radiusX: root.rT; radiusY: root.rT
            }
            PathLine { x: 6; y: root.rT + 6 }
        }
    }
    LineIcon {
        visible: root.peerCount > 0
        x: root.cx - size / 2
        y: root.cy - root.rT * 0.5 - size / 2
        size: 18
        strokeWidth: 1.7
        path: root.localState === "client" ? Icons.monitor : Icons.server
        color: root.localState === "client" ? Theme.ink : Theme.inkOnInk
    }
    Column {
        visible: root.peerCount > 0
        x: root.cx - width / 2
        y: root.cy + 7
        spacing: 2

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.localName
            color: Theme.ink
            font.family: Theme.fontFamilySerif
            font.pixelSize: Theme.fs(15)
            font.weight: Theme.weightBold
        }
        CapsLabel {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.localLabel + " · " + qsTr("vous")
            color: root.localState === "backup" ? Theme.warningInk : Theme.ink3
            font.pixelSize: Theme.fs(9.5)
        }
    }
}
