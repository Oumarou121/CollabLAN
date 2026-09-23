import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import "../Components"

/*
 * NetworkWorkspace - Carte réseau, transcription fidèle de la maquette
 * HTML (localink-workspace-v2-1.html, section « Réseau local »).
 *
 * Dimensions figées à 840×456 (priorité 1440×900, pas de responsive à ce
 * stade - voir doc étape 3, §3). Toute la géométrie ci-dessous (centre,
 * orbites, halos, connexions) recopie exactement les constantes de la
 * fonction buildNet() de la maquette : CX=352, CY=220, orbite intérieure
 * 226×104, orbite extérieure 312×138.
 */
Rectangle {
    id: root
    implicitWidth: 840
    implicitHeight: 456
    width: 840
    height: 456
    color: "transparent"
    radius: Theme.radiusMedium
    clip: true

    // --- Données ---------------------------------------------------------
    // Postes présents (authentifiés, peersModel) : {name, address, status,
    // angle (degrés, optionnel), userName}. status attendu : online/away/busy,
    // remplacé par "transferring"/"calling" si le poste apparaît dans
    // activeTransfers / activeCalls (doc §39, dérivation).
    property var peers: []
    // Postes autorisés mais absents (authorizedMachineModel moins peersModel) :
    // {name, address, angle}. Vide par défaut - non exposé côté client non
    // administrateur (doc §38).
    property var offlinePeers: []
    property string localPeerName: "Ce poste"
    property string localPeerStatusLabel: qsTr("Serveur actif")
    // transferContext.activeTransfers : {peerAddress, peerName, fileName,
    // direction, percent, ...}
    property var activeTransfers: []
    // [{remoteAddress, callState}] dérivé de callContext côté appelant
    property var activeCalls: []

    // Mode de validation visuelle (doc §37) : désactivé par défaut, ne doit
    // jamais être activé en production.
    property bool debugStatesEnabled: false

    // Mode demo : utilise les données de la maquette HTML pour validation
    property bool demoMode: false
    property string viewMode: "map"

    // Données de démo de la maquette HTML
    property var demoPeers: [
        { id: "PC-COMPTA-01", name: "PC-COMPTA-01", address: "192.168.1.21", status: "transferring", angle: -45 },
        { id: "PC-LOGISTIQUE", name: "PC-LOGISTIQUE", address: "192.168.1.34", status: "transferring", angle: 0 },
        { id: "PC-ACCUEIL", name: "PC-ACCUEIL", address: "192.168.1.15", status: "online", angle: 45 },
        { id: "PC-COMMERCIAL-04", name: "PC-COMMERCIAL-04", address: "192.168.1.47", status: "transferring", angle: 90 },
        { id: "PC-IT-03", name: "PC-IT-03", address: "192.168.1.19", status: "online", angle: 135 },
        { id: "PC-DIRECTION", name: "PC-DIRECTION", address: "192.168.1.14", status: "calling", angle: 180 },
        { id: "PC-RH-02", name: "PC-RH-02", address: "192.168.1.28", status: "away", angle: 225 },
        { id: "PC-ARCHIVES", name: "PC-ARCHIVES", address: "192.168.1.52", status: "online", angle: 270 }
    ]
    property var demoOfflinePeers: [
        { id: "PC-STAGE-01", name: "PC-STAGE-01", address: "192.168.1.58", angle: 30 },
        { id: "PC-FINANCE-02", name: "PC-FINANCE-02", address: "192.168.1.63", angle: 150 },
        { id: "PC-JURIDIQUE", name: "PC-JURIDIQUE", address: "192.168.1.77", angle: 270 }
    ]

    // Override peers with demo data when demoMode is true
    readonly property var effectivePeers: demoMode ? demoPeers : peers
    readonly property var effectiveOfflinePeers: demoMode ? demoOfflinePeers : offlinePeers

    signal peerClicked(var peer)
    signal peerDoubleClicked(var peer)
    signal sendFileRequested(var peer)
    signal callRequested(var peer)
    signal messageRequested(var peer)

    // --- Géométrie de référence (buildNet()) ------------------------------
    // Centre calculé dynamiquement - toujours au centre du canvas
    readonly property real cx: width / 2
    readonly property real cy: height / 2
    readonly property real irx: 226
    readonly property real iry: 104
    readonly property real orx: 312
    readonly property real ory: 138

    property string selectedId: ""
    property string hoveredId: ""

    function findTransferFor(p) {
        if (root.demoMode) return null
        if (!root.activeTransfers) return null
        for (var j = 0; j < root.activeTransfers.length; j++) {
            var t = root.activeTransfers[j]
            if (!t) continue
            if ((p.address && t.peerAddress === p.address) || (p.name && t.peerName === p.name))
                return t
        }
        return null
    }

    function findCallFor(p) {
        if (root.demoMode) return null
        if (!root.activeCalls) return null
        for (var k = 0; k < root.activeCalls.length; k++) {
            var c = root.activeCalls[k]
            if (c && p.address && c.remoteAddress === p.address)
                return c
        }
        return null
    }

    function peerIdFor(p) {
        return (p.address && p.address.length > 0) ? p.address : (p.name || "")
    }

    // Postes présents, positionnés sur l'orbite intérieure - état dérivé
    // (transfert/appel) et position recalculés dès que peers/activeTransfers/
    // activeCalls changent.
    property var presentPeers: {
        var list = []
        var sourcePeers = root.demoMode ? root.demoPeers : root.peers
        var count = sourcePeers.length
        for (var i = 0; i < count; i++) {
            var p = sourcePeers[i] || {}
            var angleDeg = (p.angle !== undefined && p.angle !== null)
                    ? p.angle : (-90 + (360 * i / Math.max(count, 1)))
            var status = p.status || "online"
            var direction = ""
            var xfer = null
            var call = null

            // En mode demo, utiliser le status tel quel
            if (!root.demoMode) {
                xfer = root.findTransferFor(p)
                call = root.findCallFor(p)
                if (xfer) {
                    status = "transferring"
                    direction = xfer.direction || ""
                } else if (call) {
                    status = "calling"
                }
            }

            var rad = angleDeg * Math.PI / 180
            // Position sur l'orbite intérieure (226×104)
            var px = root.cx + root.irx * Math.cos(rad)
            var py = root.cy + root.iry * Math.sin(rad)
            list.push({
                id: root.demoMode ? p.id : root.peerIdFor(p),
                name: p.name || "",
                address: p.address || "",
                userUuid: p.userUuid || "",
                userName: xfer ? (xfer.peerUserName || "") : "",
                status: status,
                direction: direction,
                transfer: xfer || null,
                x: px,
                y: py,
                index: i
            })
        }
        return list
    }

    // Postes hors ligne, orbite extérieure
    property var offlinePeersPositioned: {
        var list = []
        var sourceOffline = root.demoMode ? root.demoOfflinePeers : root.offlinePeers
        var count = sourceOffline.length
        for (var i = 0; i < count; i++) {
            var p = sourceOffline[i] || {}
            var angleDeg = (p.angle !== undefined && p.angle !== null)
                    ? p.angle : (-90 + (360 * i / Math.max(count, 1)) + 18)
            var rad = angleDeg * Math.PI / 180
            // Position sur l'orbite extérieure (312×138)
            var px = root.cx + root.orx * Math.cos(rad)
            var py = root.cy + root.ory * Math.sin(rad)
            list.push({
                id: root.demoMode ? p.id : root.peerIdFor(p),
                name: p.name || "",
                address: p.address || "",
                x: px,
                y: py
            })
        }
        return list
    }

    function selectedPeer() {
        for (var i = 0; i < root.presentPeers.length; i++) {
            if (root.presentPeers[i].id === root.selectedId) return root.presentPeers[i]
        }
        return null
    }

    function hoveredPeer() {
        for (var i = 0; i < root.presentPeers.length; i++) {
            if (root.presentPeers[i].id === root.hoveredId) return root.presentPeers[i]
        }
        return null
    }

    function clearSelection() { root.selectedId = "" }

    Keys.onEscapePressed: root.clearSelection()
    focus: true

    // --- Fond --------------------------------------------------------
    // radial-gradient(70% 80% at 50% 50%, #FFFFFF 0%, #F5F9F9 70%, #EDF2F2 100%)
    Rectangle {
        anchors.fill: parent
        // Coins arrondis alignés sur la carte englobante (HomeView.qml,
        // Rectangle radius:12) : sans ce radius, ce fond opaque recouvrait
        // les coins arrondis du conteneur parent et les rendait carrés.
        radius: Theme.radiusMedium
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#FFFFFF" }
            GradientStop { position: 0.7; color: "#F5F9F9" }
            GradientStop { position: 1.0; color: "#EDF2F2" }
        }
    }

    // Grille de points 22×22, masque radial - CSS :
    // background-image: radial-gradient(rgba(11,92,112,.14) 1px, transparent 1.4px);
    // background-size: 22px 22px; mask: radial-gradient(55% 70% at 50% 50%, #000, transparent)
    Canvas {
        id: gridCanvas
        anchors.fill: parent
        visible: root.viewMode === "map"
        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            var spacing = 22
            var w = width, h = height
            var centerX = w / 2, centerY = h / 2
            var maskRx = w * 0.55
            var maskRy = h * 0.70
            for (var x = spacing / 2; x < w; x += spacing) {
                for (var y = spacing / 2; y < h; y += spacing) {
                    var dx = (x - centerX) / maskRx
                    var dy = (y - centerY) / maskRy
                    var d = Math.sqrt(dx * dx + dy * dy)
                    var alpha = (1 - d) * 0.14
                    if (alpha <= 0.004) continue
                    ctx.beginPath()
                    ctx.fillStyle = "rgba(11,92,112," + alpha.toFixed(3) + ")"
                    ctx.arc(x, y, 1, 0, 2 * Math.PI)
                    ctx.fill()
                }
            }
        }
    }

    // Titre - left 20, top 16 (uniquement en mode carte)
    Column {
        x: 20
        y: 16
        visible: root.viewMode === "map"
        spacing: 2

        Label {
            text: qsTr("Réseau local")
            color: "#15222B"
            font.pixelSize: 15
            font.bold: true
            font.family: Theme.fontFamily
        }
        Label {
            text: qsTr("Postes détectés autour de ce poste, disposition indicative")
            color: "#62717A"
            font.pixelSize: 12
            font.family: Theme.fontFamily
        }
    }

    // Contrôle segmenté Carte/Liste - right 16, top 14 (visible dans les deux modes)
    Row {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: 14
        anchors.rightMargin: 16
        spacing: 2
        z: 1000

        Rectangle {
            radius: 6
            height: 26
            width: mapLabel.implicitWidth + 22
            color: root.viewMode === "map" ? "#15222B" : "transparent"

            Label {
                id: mapLabel
                anchors.centerIn: parent
                text: qsTr("Carte")
                color: root.viewMode === "map" ? "#FFFFFF" : "#4A5961"
                font.pixelSize: 12
                font.bold: true
                font.family: Theme.fontFamily
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.viewMode = "map"
            }
        }

        Rectangle {
            radius: 6
            height: 26
            width: listLabel.implicitWidth + 22
            color: root.viewMode === "list" ? "#15222B" : "transparent"
            border.width: root.viewMode === "list" ? 0 : 1
            border.color: "#DDE4E2"

            Label {
                id: listLabel
                anchors.centerIn: parent
                text: qsTr("Liste")
                color: root.viewMode === "list" ? "#FFFFFF" : "#4A5961"
                font.pixelSize: 12
                font.bold: true
                font.family: Theme.fontFamily
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.viewMode = "list"
            }
        }
    }

    // Orbites - pointillées 2 6 (uniquement en mode carte)
    Canvas {
        id: orbitsCanvas
        anchors.fill: parent
        visible: root.viewMode === "map"
        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            ctx.setLineDash([2, 6])
            ctx.strokeStyle = "#B9CBCF"
            ctx.lineWidth = 1
            ctx.beginPath()
            ctx.ellipse(root.cx, root.cy, root.irx, root.iry, 0, 0, 2 * Math.PI)
            ctx.stroke()

            ctx.strokeStyle = "#CBD6D8"
            ctx.beginPath()
            ctx.ellipse(root.cx, root.cy, root.orx, root.ory, 0, 0, 2 * Math.PI)
            ctx.stroke()
        }
        Connections {
            target: root
            function onWidthChanged() { orbitsCanvas.requestPaint() }
            function onHeightChanged() { orbitsCanvas.requestPaint() }
        }
    }

    // Vue liste (uniquement en mode liste)
    NetworkListView {
        anchors.fill: parent
        anchors.topMargin: 0
        visible: root.viewMode === "list"
        peers: root.peers
        offlinePeers: root.offlinePeers
        localPeerName: root.localPeerName
        localPeerStatusLabel: root.localPeerStatusLabel
        activeTransfers: root.activeTransfers
        activeCalls: root.activeCalls

        onPeerClicked: function(peer) { root.peerClicked(peer) }
        onMessageRequested: function(peer) { root.messageRequested(peer) }
        onTransferRequested: function(peer) { root.sendFileRequested(peer) }
        onCallRequested: function(peer) { root.callRequested(peer) }
    }

    // Connexions actives - uniquement transfert/appel (doc §29). Courbe
    // quadratique légère (doc §32), flèche de sens pour un transfert,
    // pointillés animés (3.4s linéaire, doc §30/§33).
    Canvas {
        id: connectionsCanvas
        anchors.fill: parent
        z: 1
        visible: root.viewMode === "map"
        property real dashPhase: 0

        NumberAnimation on dashPhase {
            from: 0; to: 13; duration: 3400
            loops: Animation.Infinite
            running: true
        }
        onDashPhaseChanged: connectionsCanvas.requestPaint()
        Connections {
            target: root
            function onPresentPeersChanged() { connectionsCanvas.requestPaint() }
        }

        function curveFor(px, py, idx) {
            var dx = px - root.cx, dy = py - root.cy
            var len = Math.max(1, Math.hypot(dx, dy))
            var nx = -dy / len, ny = dx / len
            var b = len * 0.07 * (idx % 2 ? 1 : -1)
            return {
                qx: (root.cx + px) / 2 + nx * b,
                qy: (root.cy + py) / 2 + ny * b
            }
        }

        // t=0.56 fixe (valeur de la maquette) place la flèche à mi-course,
        // ce qui convient tant que le poste est assez loin du hub. Avec peu
        // de postes réels, l'angle par défaut (-90/90°, doc refreshNetworkPeers)
        // peut placer un poste très près du hub sur l'axe vertical : à cette
        // distance réduite, t=0.56 fait tomber la flèche sur l'étiquette du
        // poste (s'il est au-dessus du hub) ou sur celle du hub (s'il est en
        // dessous). On resserre t vers le bord opposé à l'étiquette concernée
        // uniquement dans ces cas, sans toucher aux postes bien dégagés
        // (angles de la maquette, où t reste 0.56 - calcul vérifié).
        function arrowParam(px, py, len) {
            var dy = py - root.cy
            var t = 0.56
            if (dy < 0) {
                // Poste au-dessus du hub : dégager son étiquette (nom +
                // statut, ~50px sous son icône).
                t = Math.min(t, 1 - 50 / len)
            } else if (dy > 0) {
                // Poste en dessous du hub : dégager l'étiquette du hub
                // ("Ce poste" + statut, ~74px sous son icône).
                t = Math.max(t, 74 / len)
            }
            return Math.max(0.15, Math.min(0.85, t))
        }

        function drawArrow(ctx, q, p, t, fwd, col) {
            var bx = (1 - t) * (1 - t) * root.cx + 2 * (1 - t) * t * q.qx + t * t * p.x
            var by = (1 - t) * (1 - t) * root.cy + 2 * (1 - t) * t * q.qy + t * t * p.y
            var tx = 2 * (1 - t) * (q.qx - root.cx) + 2 * t * (p.x - q.qx)
            var ty = 2 * (1 - t) * (q.qy - root.cy) + 2 * t * (p.y - q.qy)
            var a = Math.atan2(ty, tx)
            if (!fwd) a += Math.PI
            ctx.save()
            ctx.translate(bx, by)
            ctx.rotate(a)
            ctx.fillStyle = col
            ctx.strokeStyle = "#FFFFFF"
            ctx.lineWidth = 1.4
            ctx.beginPath()
            ctx.moveTo(6, 0)
            ctx.lineTo(-4, 4)
            ctx.lineTo(-4, -4)
            ctx.closePath()
            ctx.fill()
            ctx.stroke()
            ctx.restore()
        }

        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            var list = root.presentPeers
            for (var i = 0; i < list.length; i++) {
                var n = list[i]
                if (n.status !== "transferring" && n.status !== "calling") continue
                var q = curveFor(n.x, n.y, n.index)
                ctx.beginPath()
                ctx.moveTo(root.cx, root.cy)
                ctx.quadraticCurveTo(q.qx, q.qy, n.x, n.y)
                if (n.status === "transferring") {
                    var reverse = n.direction === qsTr("Réception")
                    ctx.strokeStyle = "#0B5C70"
                    ctx.lineWidth = 1.6
                    ctx.globalAlpha = 0.75
                    ctx.setLineDash([3, 10])
                    ctx.lineDashOffset = reverse ? dashPhase : -dashPhase
                    ctx.stroke()
                    var arrowLen = Math.max(1, Math.hypot(n.x - root.cx, n.y - root.cy))
                    drawArrow(ctx, q, n, arrowParam(n.x, n.y, arrowLen), !reverse, "#0B5C70")
                } else {
                    ctx.strokeStyle = "#7A55B0"
                    ctx.lineWidth = 1.8
                    ctx.globalAlpha = 0.85
                    ctx.setLineDash([])
                    ctx.stroke()
                }
                ctx.globalAlpha = 1
            }
        }
    }

    // Ce poste - centre CX/CY
    Item {
        anchors.centerIn: parent
        width: 88
        height: 88
        z: 2
        visible: root.viewMode === "map"

        Rectangle {
            anchors.centerIn: parent
            width: 88; height: 88; radius: 44
            color: "#0B5C70"; opacity: 0.06
        }
        Rectangle {
            anchors.centerIn: parent
            width: 70; height: 70; radius: 35
            color: "#0B5C70"; opacity: 0.09
        }
        Rectangle {
            anchors.centerIn: parent
            width: 50; height: 50; radius: 25
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#1B7C93" }
                GradientStop { position: 1.0; color: "#0B5C70" }
            }
            Label {
                anchors.centerIn: parent
                text: "\uf108"
                color: "#FFFFFF"
                font.pixelSize: 22
                font.family: "FontAwesome"
            }
        }
        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.bottom
            anchors.topMargin: 4
            text: root.localPeerName
            color: "#15222B"
            font.pixelSize: 12
            font.bold: true
            font.family: Theme.fontFamily
        }
        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.bottom
            anchors.topMargin: 17
            text: root.localPeerStatusLabel
            color: "#62717A"
            font.pixelSize: 11
            font.family: Theme.fontFamily
        }
    }

    // Postes hors ligne - orbite extérieure, sous les postes présents
    Repeater {
        model: root.offlinePeersPositioned
        delegate: NetworkPeer {
            x: modelData.x - width / 2
            y: modelData.y - 25
            z: 2
            peerId: modelData.id
            label: modelData.name
            address: modelData.address
            status: "offline"
            visible: root.viewMode === "map"
        }
    }

    // Postes présents - orbite intérieure
    Repeater {
        model: root.presentPeers
        delegate: NetworkPeer {
            id: peerDelegate
            x: modelData.x - width / 2
            y: modelData.y - 25
            z: 3
            peerId: modelData.id
            label: modelData.name
            address: modelData.address
            status: modelData.status
            visible: root.viewMode === "map"
            isSelected: root.selectedId === modelData.id
            isHovered: root.hoveredId === modelData.id

            onEntered: root.hoveredId = modelData.id
            onExited: if (root.hoveredId === modelData.id) root.hoveredId = ""
            onClicked: {
                root.forceActiveFocus()
                root.hoveredId = ""
                root.selectedId = (root.selectedId === modelData.id) ? "" : modelData.id
                root.peerClicked(modelData)
            }
        }
    }

    // Tooltip de survol - masqué si le poste est sélectionné (doc §24 : ne
    // pas mélanger hover et selected)
    Loader {
        active: root.hoveredId.length > 0 && root.hoveredId !== root.selectedId && root.hoveredPeer() !== null
        z: 4
        sourceComponent: Component {
            Rectangle {
                property var peer: root.hoveredPeer()
                x: peer ? Math.min(peer.x + 30, root.width - width - 4) : 0
                y: peer ? Math.max(peer.y - 26, 4) : 0
                width: tipCol.implicitWidth + 22
                height: tipCol.implicitHeight + 16
                radius: 8
                color: "#15222B"

                Column {
                    id: tipCol
                    anchors.centerIn: parent
                    spacing: 2
                    Label {
                        text: peer ? peer.name : ""
                        color: "#FFFFFF"
                        font.pixelSize: 12
                        font.bold: true
                        font.family: Theme.fontFamily
                    }
                    Label {
                        text: peer ? (statusLabelFor(peer.status) + " · " + peer.address) : ""
                        color: "#B3C2C8"
                        font.pixelSize: 11
                        font.family: Theme.fontFamily
                    }
                }

                function statusLabelFor(s) {
                    switch (s) {
                        case "transferring": return qsTr("En transfert")
                        case "calling": return qsTr("En appel")
                        case "away": return qsTr("Absent")
                        case "busy": return qsTr("Occupé")
                        case "offline": return qsTr("Hors ligne")
                        default: return qsTr("En ligne")
                    }
                }
            }
        }
    }

    // Panneau de détails - poste sélectionné (doc §26/§27). Position
    // droite si la place le permet, sinon gauche ; clamp vertical.
    Loader {
        active: root.selectedId.length > 0 && root.selectedPeer() !== null
        z: 5
        sourceComponent: Component {
            PeerDetailsPanel {
                id: panel
                property var peer: root.selectedPeer()
                readonly property bool openRight: peer ? (peer.x + 40 + width <= root.width - 4) : true
                x: peer ? (openRight ? peer.x + 40 : peer.x - 40 - width) : 0
                y: peer ? Math.max(52, Math.min(peer.y - 96, root.height - 40 - implicitHeight)) : 0

                peerName: peer ? peer.name : ""
                peerAddress: peer ? peer.address : ""
                peerStatus: peer ? peer.status : "online"
                accountName: peer ? peer.userName : ""
                activeTransfer: peer ? peer.transfer : null
                notchSide: openRight ? "right" : "left"
                notchOffset: peer ? Math.max(16, Math.min(peer.y - y - 5, 200)) : 30

                onCloseRequested: root.clearSelection()
                onSendFileRequested: root.sendFileRequested(peer)
                onCallRequested: root.callRequested(peer)
                onMessageRequested: root.messageRequested(peer)
            }
        }
    }

    // Clic sur le fond de la carte : ferme le panneau (doc §28)
    MouseArea {
        anchors.fill: parent
        z: 0
        propagateComposedEvents: true
        visible: root.viewMode === "map"
        enabled: root.viewMode === "map"
        onClicked: {
            root.forceActiveFocus()
            root.clearSelection()
        }
    }

    // Légende - height 40
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 40
        color: Qt.rgba(1, 1, 1, 0.85)
        border.width: 1
        border.color: "#DDE4E2"
        // Seuls les coins bas doivent suivre l'arrondi de la carte (le
        // haut de la légende touche la zone de grille, pas un coin de carte).
        topLeftRadius: 0
        topRightRadius: 0
        bottomLeftRadius: Theme.radiusMedium
        bottomRightRadius: Theme.radiusMedium
        z: 6

        Row {
            // anchors.fill (+ hauteur fixe 40 héritée du parent) alignait la
            // Row - et donc ses puces de 24px - en haut par défaut (Row ne
            // centre pas ses enfants verticalement tout seul), d'où l'espace
            // vide visible sous les puces. anchors.verticalCenter fait que
            // la Row ne prend que la hauteur de ses enfants (24px) et se
            // centre dans les 40px de la barre.
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            spacing: 8

            Repeater {
                model: [
                    { color: "#2E9A66", label: qsTr("En ligne"), count: root.presentPeers.filter(function(p) { return p.status === "online" }).length },
                    { color: "#C27A0E", label: qsTr("Absent"), count: root.presentPeers.filter(function(p) { return p.status === "away" || p.status === "busy" }).length },
                    { color: "#0B5C70", label: qsTr("En transfert"), count: root.presentPeers.filter(function(p) { return p.status === "transferring" }).length },
                    { color: "#7A55B0", label: qsTr("En appel"), count: root.presentPeers.filter(function(p) { return p.status === "calling" }).length },
                    { color: "transparent", label: qsTr("Hors ligne"), count: root.offlinePeersPositioned.length, hasBorder: true }
                ]
                delegate: Rectangle {
                    width: chipContent.implicitWidth + 20
                    height: 24
                    radius: 999
                    color: modelData.hasBorder ? "transparent" : "#FFFFFF"
                    border.width: modelData.hasBorder ? 1.5 : 1
                    border.color: "#DDE4E2"

                    Row {
                        id: chipContent
                        anchors.centerIn: parent
                        spacing: 6

                        Rectangle {
                            width: 8; height: 8; radius: 4
                            color: modelData.hasBorder ? "transparent" : modelData.color
                            border.width: modelData.hasBorder ? 1.5 : 0
                            border.color: "#B4C1C5"
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Label {
                            text: modelData.label
                            color: "#4A5961"
                            font.pixelSize: 12
                            font.bold: true
                            font.family: Theme.fontFamily
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Label {
                            text: modelData.count
                            color: "#62717A"
                            font.pixelSize: 12
                            font.weight: Font.Medium
                            font.family: Theme.fontFamily
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }
            }
        }
    }

    // --- Mode de validation (dev uniquement, doc §37) ---------------------
    // Trois boutons pour forcer Normal/Survolé/Sélectionné sur un poste de
    // démonstration, sans dépendre de peersModel. N'apparaît que si
    // `debugStatesEnabled` est explicitement mis à true par l'appelant.
    Row {
        visible: root.debugStatesEnabled && root.presentPeers.length > 0
        z: 7
        x: 20
        y: 456 - 40 - height - 8
        spacing: 6

        Repeater {
            model: [
                { m: "normal", t: "Normal" },
                { m: "hover", t: "Poste survolé" },
                { m: "select", t: "Poste sélectionné" }
            ]
            delegate: Rectangle {
                height: 22
                width: dbgLabel.implicitWidth + 14
                radius: 6
                color: "#15222B"
                opacity: 0.85

                Label {
                    id: dbgLabel
                    anchors.centerIn: parent
                    text: modelData.t
                    color: "#FFFFFF"
                    font.pixelSize: 10
                    font.family: Theme.fontFamily
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        var demoId = root.presentPeers[0].id
                        if (modelData.m === "normal") {
                            root.hoveredId = ""; root.selectedId = ""
                        } else if (modelData.m === "hover") {
                            root.selectedId = ""; root.hoveredId = demoId
                        } else {
                            root.hoveredId = ""; root.selectedId = demoId
                        }
                    }
                }
            }
        }
    }
}
