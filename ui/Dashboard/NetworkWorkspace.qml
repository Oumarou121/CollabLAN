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

    // Rayons des coins de la surface, par côté : la carte est accolée à la
    // colonne « À traiter » dans une surface unique (HomeView) ; le côté qui
    // touche « À traiter » doit avoir un angle droit, sinon un cran visible
    // apparaît à la jonction. Par défaut : arrondi sur les deux côtés.
    property real leftRadius: Theme.radiusMedium
    property real rightRadius: Theme.radiusMedium

    // Mode de validation visuelle (doc §37) : désactivé par défaut, ne doit
    // jamais être activé en production.
    property bool debugStatesEnabled: false

    // Mode demo : utilise les données de la maquette HTML pour validation
    property bool demoMode: false
    property string viewMode: "map"

    // Données de démo de la maquette HTML
    property var demoPeers: [
        { id: "PC-COMPTA-01", name: "PC-COMPTA-01", address: "192.168.1.21", status: "transferring" },
        { id: "PC-LOGISTIQUE", name: "PC-LOGISTIQUE", address: "192.168.1.34", status: "transferring" },
        { id: "PC-ACCUEIL", name: "PC-ACCUEIL", address: "192.168.1.15", status: "online" },
        { id: "PC-COMMERCIAL-04", name: "PC-COMMERCIAL-04", address: "192.168.1.47", status: "transferring" },
        { id: "PC-IT-03", name: "PC-IT-03", address: "192.168.1.19", status: "online" },
        { id: "PC-DIRECTION", name: "PC-DIRECTION", address: "192.168.1.14", status: "calling" },
        { id: "PC-RH-02", name: "PC-RH-02", address: "192.168.1.28", status: "away" },
        { id: "PC-ARCHIVES", name: "PC-ARCHIVES", address: "192.168.1.52", status: "online" }
    ]
    property var demoOfflinePeers: [
        { id: "PC-STAGE-01", name: "PC-STAGE-01", address: "192.168.1.58" },
        { id: "PC-FINANCE-02", name: "PC-FINANCE-02", address: "192.168.1.63" },
        { id: "PC-JURIDIQUE", name: "PC-JURIDIQUE", address: "192.168.1.77" }
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
    // Rayons de référence (maquette 1440x900). Horizontalement ils restent
    // fixes ; verticalement ils sont réduits (jamais sous 60 %) quand la
    // hauteur disponible ne permet pas de loger l'orbite extérieure avec
    // les nœuds (78px de haut) et la légende (40px) sans débordement.
    readonly property real refIrx: 226
    readonly property real refIry: 104
    readonly property real refOrx: 312
    readonly property real refOry: 138
    readonly property real fitY: Math.max(0.6, Math.min(1,
            Math.min(cy - 47, height - 83 - cy) / refOry))
    readonly property real irx: refIrx
    readonly property real iry: refIry * fitY
    readonly property real orx: refOrx
    readonly property real ory: refOry * fitY

    property string selectedId: ""
    property string hoveredId: ""

    function findTransferFor(p) {
        if (root.demoMode) return null
        if (!root.activeTransfers) return null
        var latestTransfer = null
        var latestTimestamp = ""
        for (var j = 0; j < root.activeTransfers.length; j++) {
            var t = root.activeTransfers[j]
            if (!t) continue
            // Ne considérer que les transferts réellement en cours (state == "in_progress")
            // et non l'historique (transferKey ne commence pas par "history:")
            if (t.state !== "in_progress") continue
            if (t.transferKey && t.transferKey.indexOf("history:") === 0) continue
            // Rattachement par peerMachineId d'abord, puis par adresse en repli
            var matches = false
            if (p.id && t.peerMachineId && t.peerMachineId === p.id) {
                matches = true
            } else if (p.address && t.peerAddress === p.address) {
                matches = true
            } else if (p.name && t.peerName === p.name) {
                matches = true
            }
            if (matches) {
                // Prendre le transfert le plus récent
                if (!latestTransfer || (t.timestamp && t.timestamp > latestTimestamp)) {
                    latestTransfer = t
                    latestTimestamp = t.timestamp || ""
                }
            }
        }
        return latestTransfer
    }

    function findCallFor(p) {
        if (root.demoMode) return null
        if (!root.activeCalls) return null
        for (var k = 0; k < root.activeCalls.length; k++) {
            var c = root.activeCalls[k]
            if (!c) continue
            // Rattachement par peerMachineId d'abord, puis par adresse en repli
            if (p.id && c.remoteMachineId && c.remoteMachineId === p.id) {
                return c
            } else if (c && p.address && c.remoteAddress === p.address) {
                return c
            }
        }
        return null
    }

    // Identifiant unique d'un poste sur la carte. On privilégie l'id machine
    // (unique par poste, fourni par peersModel) : l'adresse IP ne l'est pas
    // (plusieurs instances sur une même machine, NAT...), et deux postes
    // partageant la même clé se retrouvaient tous résolus vers le premier
    // par livePeer() -> le panneau du 1er poste s'ouvrait à chaque clic.
    function peerIdFor(p) {
        if (p.id && p.id.length > 0) return p.id
        return (p.address && p.address.length > 0) ? p.address : (p.name || "")
    }

    // Fonction de calcul du statut effectif normalisé
    // Priorité : offline > calling > transferring > busy > away > online
    function computeEffectiveStatus(p) {
        if (!p) return "online"
        // Statut hors ligne explicite
        if (p.status === "offline") return "offline"
        // Appel en cours
        var call = findCallFor(p)
        if (call) return "calling"
        // Transfert en cours
        var transfer = findTransferFor(p)
        if (transfer) return "transferring"
        // Statut occupé
        if (p.status === "busy") return "busy"
        // Statut absent
        if (p.status === "away") return "away"
        // Statut en ligne ou inconnu
        return "online"
    }

    // --- Placement automatique des postes ---------------------------------
    // Un poste placé juste au-dessus ou en dessous du hub est collé à lui
    // (10 px d'écart seulement, la carte est bien plus large que haute) et
    // son fil devient minuscule. On répartit donc les postes présents sur
    // deux arcs, à droite et à gauche du hub, à égale distance le long de
    // l'ellipse. L'axe vertical n'est utilisé que si la place manque.
    // Tailles (px) d'un poste : icône + libellés ; hub : halo + libellés.
    readonly property real peerBoxW: 80
    readonly property real peerBoxH: 67
    readonly property real peerBoxDy: 16.5   // centre de la boîte sous le centre de l'icône
    readonly property real hubBoxW: 92
    readonly property real hubBoxH: 120
    readonly property real hubBoxDy: 16
    readonly property real boxMargin: 6

    function boxItem(x, y) { return { x: x, y: y + peerBoxDy, w: peerBoxW, h: peerBoxH } }
    function hubBox() { return { x: 0, y: hubBoxDy, w: hubBoxW, h: hubBoxH } }

    // Écart normalisé entre deux boîtes : >= 1 = pas de chevauchement
    function boxGap(a, b) {
        var kx = (a.w + b.w) / 2 + boxMargin
        var ky = (a.h + b.h) / 2 + boxMargin
        return Math.max(Math.abs(a.x - b.x) / kx, Math.abs(a.y - b.y) / ky)
    }

    function minBoxGap(item, others) {
        var m = Infinity
        for (var i = 0; i < others.length; i++)
            m = Math.min(m, root.boxGap(item, others[i]))
        return m
    }

    // n angles (degrés) répartis à égale distance d'arc sur deux arcs :
    // droite [-maxDeg, +maxDeg] et gauche [180-maxDeg, 180+maxDeg]. Ordre
    // horaire : arc droit de haut en bas, puis arc gauche de bas en haut.
    function slotAngles(n, rx, ry, maxDeg) {
        var out = []
        if (n <= 0) return out
        var a = maxDeg * Math.PI / 180
        var steps = 64
        var cum = [0]
        for (var s = 1; s <= steps; s++) {
            var t0 = -a + 2 * a * (s - 1) / steps
            var t1 = -a + 2 * a * s / steps
            var tm = (t0 + t1) / 2
            var v = Math.sqrt(rx * rx * Math.sin(tm) * Math.sin(tm)
                              + ry * ry * Math.cos(tm) * Math.cos(tm))
            cum.push(cum[s - 1] + v * (t1 - t0))
        }
        var total = cum[steps]
        function angleAt(frac) {
            var target = frac * total
            var k = 1
            while (k < steps && cum[k] < target) k++
            var seg = cum[k] - cum[k - 1]
            var u = seg > 0 ? (target - cum[k - 1]) / seg : 0
            return (-a + 2 * a * ((k - 1) + u) / steps) * 180 / Math.PI
        }
        var kRight = Math.ceil(n / 2)
        var kLeft = n - kRight
        for (var i = 0; i < kRight; i++) out.push(angleAt((i + 0.5) / kRight))
        for (var j = 0; j < kLeft; j++) out.push(180 + angleAt((j + 0.5) / kLeft))
        return out
    }

    // Angles des postes présents sur l'orbite intérieure. On part d'un cône
    // vertical interdit de 27° de chaque côté (les postes restent à plus de
    // ~100 px du centre en horizontal, donc hors de l'emprise du hub) et on
    // ne l'élargit, par pas de 3°, que si des postes se chevauchent (7 postes
    // et plus, ou hauteur de carte réduite).
    function presentAngles(n, rx, ry) {
        var best = null
        for (var maxDeg = 63; maxDeg <= 90; maxDeg += 3) {
            var ang = root.slotAngles(n, rx, ry, maxDeg)
            var items = []
            var score = Infinity
            for (var i = 0; i < ang.length; i++) {
                var r = ang[i] * Math.PI / 180
                var it = root.boxItem(rx * Math.cos(r), ry * Math.sin(r))
                score = Math.min(score, root.minBoxGap(it, items), root.boxGap(it, root.hubBox()))
                items.push(it)
            }
            if (score >= 1) return ang
            if (best === null || score > best.score) best = { ang: ang, score: score }
        }
        return best.ang
    }

    // Angles des postes hors ligne sur l'orbite extérieure : chacun prend
    // la place la plus dégagée (hub, postes présents, autres hors ligne).
    // Ils vont donc naturellement dans les vides, souvent en haut et en bas.
    function offlineAngles(m, orx, ory, fixedItems) {
        var placed = [root.hubBox()].concat(fixedItems)
        var out = []
        for (var i = 0; i < m; i++) {
            var bestA = -90
            var bestS = -1
            for (var d = 0; d < 360; d += 6) {
                var a = -90 + d
                var r = a * Math.PI / 180
                var s = root.minBoxGap(root.boxItem(orx * Math.cos(r), ory * Math.sin(r)), placed)
                if (s > bestS + 1e-6) { bestS = s; bestA = a }
            }
            var rr = bestA * Math.PI / 180
            placed.push(root.boxItem(orx * Math.cos(rr), ory * Math.sin(rr)))
            out.push(bestA)
        }
        return out
    }

    // Postes présents - STRUCTURE : identité + position sur l'orbite
    // intérieure (226×104). Ne dépend volontairement NI de activeTransfers
    // NI de activeCalls : c'est le modèle du Repeater, et un Repeater dont
    // le modèle change détruit puis recrée tous ses délégués. Or
    // transferContext.activeTransfers change à chaque tick de progression :
    // les postes étaient recréés en plein clic (appui sur l'ancien
    // délégué, relâchement sur le nouveau -> clic perdu).
    property var peerLayout: {
        var list = []
        var sourcePeers = root.demoMode ? root.demoPeers : root.peers
        var count = sourcePeers.length
        var autoAngles = root.presentAngles(count, root.irx, root.iry)
        for (var i = 0; i < count; i++) {
            var p = sourcePeers[i] || {}
            var angleDeg = (p.angle !== undefined && p.angle !== null)
                    ? p.angle : autoAngles[i]
            var rad = angleDeg * Math.PI / 180
            list.push({
                id: root.demoMode ? p.id : root.peerIdFor(p),
                name: p.name || "",
                address: p.address || "",
                userUuid: p.userUuid || "",
                baseStatus: p.status || "online",
                x: root.cx + root.irx * Math.cos(rad),
                y: root.cy + root.iry * Math.sin(rad),
                index: i
            })
        }
        return list
    }

    // Postes présents - ÉTAT COURANT : même liste, même ordre que
    // peerLayout, avec le statut dérivé (transfert/appel) et le transfert
    // attaché. Recalculé à chaque changement de activeTransfers/activeCalls
    // sans toucher aux délégués (ils lisent cet état via livePeer()).
    property var presentPeers: {
        var list = []
        var layout = root.peerLayout
        for (var i = 0; i < layout.length; i++) {
            var b = layout[i]
            var xfer = null
            var call = null
            var direction = ""

            // En mode demo, utiliser le status tel quel
            if (!root.demoMode) {
                xfer = root.findTransferFor(b)
                call = root.findCallFor(b)
            }

            // Calculer le statut effectif avec la fonction normalisée
            var peerObj = {
                id: b.id,
                name: b.name,
                address: b.address,
                userUuid: b.userUuid,
                status: b.baseStatus
            }
            var effectiveStatus = root.computeEffectiveStatus(peerObj)
            if (xfer) {
                direction = xfer.direction || ""
            }

            list.push({
                id: b.id,
                name: b.name,
                address: b.address,
                userUuid: b.userUuid,
                userName: xfer ? (xfer.peerUserName || "") : "",
                status: effectiveStatus,
                direction: direction,
                transfer: xfer || null,
                x: b.x,
                y: b.y,
                index: b.index
            })
        }
        return list
    }

    function livePeer(id) {
        for (var i = 0; i < root.presentPeers.length; i++) {
            if (root.presentPeers[i].id === id) return root.presentPeers[i]
        }
        return null
    }

    // Postes hors ligne, orbite extérieure
    property var offlinePeersPositioned: {
        var list = []
        var sourceOffline = root.demoMode ? root.demoOfflinePeers : root.offlinePeers
        var count = sourceOffline.length
        var fixedItems = []
        for (var k = 0; k < root.peerLayout.length; k++)
            fixedItems.push(root.boxItem(root.peerLayout[k].x - root.cx,
                                         root.peerLayout[k].y - root.cy))
        var autoAngles = root.offlineAngles(count, root.orx, root.ory, fixedItems)
        for (var i = 0; i < count; i++) {
            var p = sourceOffline[i] || {}
            var angleDeg = (p.angle !== undefined && p.angle !== null)
                    ? p.angle : autoAngles[i]
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

    function selectedPeer() { return root.livePeer(root.selectedId) }
    function hoveredPeer() { return root.livePeer(root.hoveredId) }

    function clearSelection() { root.selectedId = "" }

    // Aire de recouvrement (px²) entre deux rectangles {x, y, w, h}
    // (x, y = centre).
    function overlapArea(a, b) {
        var ox = Math.min(a.x + a.w / 2, b.x + b.w / 2) - Math.max(a.x - a.w / 2, b.x - b.w / 2)
        var oy = Math.min(a.y + a.h / 2, b.y + b.h / 2) - Math.max(a.y - a.h / 2, b.y - b.h / 2)
        return (ox > 0 && oy > 0) ? ox * oy : 0
    }

    // Emplacement du panneau de détails (w × h) pour le poste `peer`.
    // Le panneau est au-dessus des postes (z) et capte les clics : un poste
    // recouvert n'est plus cliquable, on ne peut alors plus changer de
    // sélection. On essaie donc côté droit puis gauche, avec des écarts et
    // des décalages verticaux croissants, et on garde le premier emplacement
    // qui ne recouvre aucun autre poste (à défaut, le moins gênant : une
    // icône recouverte coûte 20× plus qu'une simple étiquette).
    function detailsSpot(peer, w, h) {
        var gaps = [40, 64, 96, 128]
        var dys = [-96, -40, 20, -150]
        var best = null
        for (var g = 0; g < gaps.length; g++) {
            for (var s = 0; s < 2; s++) {
                var right = (s === 0)
                var x = right ? peer.x + gaps[g] : peer.x - gaps[g] - w
                if (x < 4 || x + w > root.width - 4) continue
                for (var d = 0; d < dys.length; d++) {
                    var y = Math.max(52, Math.min(peer.y + dys[d], root.height - 40 - h))
                    var rect = { x: x + w / 2, y: y + h / 2, w: w, h: h }
                    var cost = 0
                    for (var i = 0; i < root.peerLayout.length; i++) {
                        var o = root.peerLayout[i]
                        if (o.id === peer.id) continue
                        cost += root.overlapArea(rect, root.boxItem(o.x, o.y))
                                + 20 * root.overlapArea(rect, { x: o.x, y: o.y, w: 34, h: 34 })
                    }
                    if (best === null || cost < best.cost)
                        best = { x: x, y: y, right: right, cost: cost }
                    if (cost === 0) return best
                }
            }
        }
        if (best !== null) return best
        // Aucun emplacement ne tient dans la carte : repli d'origine.
        var fallRight = peer.x + 40 + w <= root.width - 4
        return { x: fallRight ? peer.x + 40 : peer.x - 40 - w,
                 y: Math.max(52, Math.min(peer.y - 96, root.height - 40 - h)),
                 right: fallRight, cost: -1 }
    }

    // Le panneau de détails et l'infobulle n'existent que sur la carte :
    // en passant à la vue liste, on ferme tout (sinon la sélection reste
    // en mémoire et le panneau réapparaît au retour sur la carte).
    onViewModeChanged: {
        if (root.viewMode !== "map") {
            root.hoveredId = ""
            root.clearSelection()
        }
    }

    Keys.onEscapePressed: root.clearSelection()
    focus: true

    // --- Fond --------------------------------------------------------
    // radial-gradient(70% 80% at 50% 50%, #FFFFFF 0%, #F5F9F9 70%, #EDF2F2 100%)
    Rectangle {
        anchors.fill: parent
        // Coins arrondis alignés sur la surface englobante (HomeView.qml) :
        // sans ces rayons, ce fond opaque recouvrirait les coins arrondis du
        // conteneur parent et les rendrait carrés. Côté « À traiter » : 0.
        topLeftRadius: root.leftRadius
        bottomLeftRadius: root.leftRadius
        topRightRadius: root.rightRadius
        bottomRightRadius: root.rightRadius
        // Les 2 arrets etaient restes en hex clair fige : la surface reseau
        // ne changeait quasiment pas en mode sombre. Repris avec les jetons
        // Theme.dashboardXxx deja definis (meme hierarchie surface -> surface
        // alt -> fond que la maquette, mais qui suit le theme actif).
        gradient: Gradient {
            GradientStop { position: 0.0; color: Theme.dashboardSurface }
            GradientStop { position: 0.7; color: Theme.dashboardSurfaceAlt }
            GradientStop { position: 1.0; color: Theme.dashboardBackground }
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
            color: Theme.dashboardInk
            font.pixelSize: 15
            font.bold: true
            font.family: Theme.fontFamily
        }
        Label {
            text: qsTr("Postes détectés autour de ce poste, disposition indicative")
            color: Theme.dashboardInkTertiary
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
            color: root.viewMode === "map" ? Theme.dashboardInk : "transparent"

            Label {
                id: mapLabel
                anchors.centerIn: parent
                text: qsTr("Carte")
                color: root.viewMode === "map" ? Theme.dashboardSurface : Theme.dashboardInkSecondary
                font.pixelSize: 12
                font.bold: true
                font.family: Theme.fontFamily
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root.viewMode = "map"
                }
            }
        }

        Rectangle {
            radius: 6
            height: 26
            width: listLabel.implicitWidth + 22
            color: root.viewMode === "list" ? Theme.dashboardInk : "transparent"
            border.width: root.viewMode === "list" ? 0 : 1
            border.color: Theme.dashboardLine

            Label {
                id: listLabel
                anchors.centerIn: parent
                text: qsTr("Liste")
                color: root.viewMode === "list" ? Theme.dashboardSurface : Theme.dashboardInkSecondary
                font.pixelSize: 12
                font.bold: true
                font.family: Theme.fontFamily
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root.viewMode = "list"
                }
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
            ctx.lineWidth = 1

            // Context2D de Qt Quick : ellipse(x, y, w, h) prend le rectangle
            // ENGLOBANT (coin haut-gauche + largeur/hauteur), et non
            // (cx, cy, rx, ry) comme en HTML5.
            ctx.strokeStyle = Theme.darkMode ? "#3B5057" : "#B9CBCF"
            ctx.beginPath()
            ctx.ellipse(root.cx - root.irx, root.cy - root.iry, 2 * root.irx, 2 * root.iry)
            ctx.stroke()

            ctx.strokeStyle = Theme.darkMode ? "#2C3F45" : "#CBD6D8"
            ctx.beginPath()
            ctx.ellipse(root.cx - root.orx, root.cy - root.ory, 2 * root.orx, 2 * root.ory)
            ctx.stroke()
        }
        Connections {
            target: root
            function onWidthChanged() { orbitsCanvas.requestPaint() }
            function onHeightChanged() { orbitsCanvas.requestPaint() }
        }
        Connections {
            target: Theme
            function onDarkModeChanged() { orbitsCanvas.requestPaint() }
        }
    }

    // Vue liste (uniquement en mode liste)
    NetworkListView {
        anchors.fill: parent
        anchors.topMargin: 0
        visible: root.viewMode === "list"
        peers: root.effectivePeers
        offlinePeers: root.effectiveOfflinePeers
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
        // de postes réels, un poste explicitement placé sur l'axe vertical
        // (propriété angle) peut être très près du hub : à cette
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
            ctx.strokeStyle = Theme.dashboardSurface
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
                    ctx.strokeStyle = Theme.dashboardPrimary
                    ctx.lineWidth = 1.6
                    ctx.globalAlpha = 0.75
                    ctx.setLineDash([3, 10])
                    ctx.lineDashOffset = reverse ? dashPhase : -dashPhase
                    ctx.stroke()
                    var arrowLen = Math.max(1, Math.hypot(n.x - root.cx, n.y - root.cy))
                    drawArrow(ctx, q, n, arrowParam(n.x, n.y, arrowLen), !reverse, Theme.dashboardPrimary)
                } else {
                    ctx.strokeStyle = Theme.dashboardCall
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
            color: Theme.dashboardPrimary; opacity: 0.06
        }
        Rectangle {
            anchors.centerIn: parent
            width: 70; height: 70; radius: 35
            color: Theme.dashboardPrimary; opacity: 0.09
        }
        Rectangle {
            anchors.centerIn: parent
            width: 50; height: 50; radius: 25
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#1B7C93" }
                GradientStop { position: 1.0; color: Theme.dashboardPrimary }
            }
            Label {
                anchors.centerIn: parent
                text: "\uf108"
                color: Theme.dashboardSurface
                font.pixelSize: 22
                font.family: "FontAwesome"
            }
        }
        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.bottom
            anchors.topMargin: 4
            text: root.localPeerName
            color: Theme.dashboardInk
            font.pixelSize: 12
            font.bold: true
            font.family: Theme.fontFamily
        }
        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.bottom
            anchors.topMargin: 17
            text: root.localPeerStatusLabel
            color: Theme.dashboardInkTertiary
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
        // Modèle = structure seule (voir peerLayout) : les délégués ne sont
        // recréés que si les postes ou la géométrie changent.
        model: root.peerLayout
        delegate: NetworkPeer {
            id: peerDelegate
            // État courant (statut dérivé transfert/appel), mis à jour sur
            // place sans recréer le délégué.
            readonly property var live: root.livePeer(modelData.id)
            x: modelData.x - width / 2
            y: modelData.y - 25
            z: 3
            peerId: modelData.id
            label: modelData.name
            address: modelData.address
            status: live ? live.status : modelData.baseStatus
            visible: root.viewMode === "map"
            isSelected: root.selectedId === modelData.id
            isHovered: root.hoveredId === modelData.id

            onEntered: root.hoveredId = modelData.id
            onExited: if (root.hoveredId === modelData.id) root.hoveredId = ""
            onClicked: {
                root.forceActiveFocus()
                root.hoveredId = ""
                root.selectedId = (root.selectedId === modelData.id) ? "" : modelData.id
                root.peerClicked(peerDelegate.live || modelData)
            }
        }
    }

    // Tooltip de survol - masqué si le poste est sélectionné (doc §24 : ne
    // pas mélanger hover et selected)
    Loader {
        active: root.viewMode === "map" && root.hoveredId.length > 0
                && root.hoveredId !== root.selectedId && root.hoveredPeer() !== null
        z: 4
        sourceComponent: Component {
            Rectangle {
                property var peer: root.hoveredPeer()
                x: peer ? Math.min(peer.x + 30, root.width - width - 4) : 0
                y: peer ? Math.max(peer.y - 26, 4) : 0
                width: tipCol.implicitWidth + 22
                height: tipCol.implicitHeight + 16
                radius: 8
                color: Theme.dashboardInk

                Column {
                    id: tipCol
                    anchors.centerIn: parent
                    spacing: 2
                    Label {
                        text: peer ? peer.name : ""
                        color: Theme.dashboardSurface
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
        id: detailsLoader
        active: root.viewMode === "map" && root.selectedId.length > 0
                && root.selectedPeer() !== null
        z: 5
        sourceComponent: detailsComponent
    }

    Component {
        id: detailsComponent
        PeerDetailsPanel {
            id: panel
            // Lié (et non copié au chargement) : le panneau suit le poste
            // sélectionné et la progression de son transfert.
            readonly property var peer: root.selectedPeer()
            readonly property var spot: peer ? root.detailsSpot(peer, width, implicitHeight) : null
            readonly property bool openRight: spot ? spot.right : true
            x: spot ? spot.x : 0
            y: spot ? spot.y : 0

            peerName: peer ? peer.name : ""
            peerAddress: peer ? peer.address : ""
            peerStatus: peer ? peer.status : "online"
            accountName: peer ? peer.userName : ""
            activeTransfer: peer ? peer.transfer : null
            notchSide: openRight ? "right" : "left"
            notchOffset: peer ? Math.max(16, Math.min(peer.y - y - 5, 200)) : 30

            onCloseRequested: root.clearSelection()
            onSendFileRequested: root.sendFileRequested(peer)
            onCallRequested: {
                root.callRequested(peer)
                // Ferme le panneau une fois l'appel lance, comme onCloseRequested :
                // sans ca, la carte du poste reste ouverte par-dessus l'overlay
                // d'appel qui vient de s'afficher.
                root.clearSelection()
            }
            onMessageRequested: root.messageRequested(peer)
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
        // Maquette : `border-top` uniquement. Une bordure sur les 4 côtés
        // doublait la bordure de la surface (gauche/bas) et ajoutait un
        // second filet contre la séparation avec « À traiter » (droite).
        // Seuls les coins bas doivent suivre l'arrondi de la surface (le
        // haut de la légende touche la zone de grille, pas un coin).
        topLeftRadius: 0
        topRightRadius: 0
        bottomLeftRadius: root.leftRadius
        bottomRightRadius: root.rightRadius
        z: 6

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 1
            color: Theme.dashboardLine
        }

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
                    { color: Theme.dashboardSuccess, label: qsTr("En ligne"), count: root.presentPeers.filter(function(p) { return p.status === "online" }).length },
                    { color: Theme.dashboardWarning, label: qsTr("Absent"), count: root.presentPeers.filter(function(p) { return p.status === "away" }).length },
                    { color: Theme.dashboardWarning, label: qsTr("Occupé"), count: root.presentPeers.filter(function(p) { return p.status === "busy" }).length },
                    { color: Theme.dashboardPrimary, label: qsTr("En transfert"), count: root.presentPeers.filter(function(p) { return p.status === "transferring" }).length },
                    { color: Theme.dashboardCall, label: qsTr("En appel"), count: root.presentPeers.filter(function(p) { return p.status === "calling" }).length },
                    { color: "transparent", label: qsTr("Hors ligne"), count: root.offlinePeersPositioned.length, hasBorder: true }
                ]
                delegate: Rectangle {
                    width: chipContent.implicitWidth + 20
                    height: 24
                    radius: 999
                    color: modelData.hasBorder ? "transparent" : Theme.dashboardSurface
                    border.width: modelData.hasBorder ? 1.5 : 1
                    border.color: Theme.dashboardLine

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
                            color: Theme.dashboardInkSecondary
                            font.pixelSize: 12
                            font.bold: true
                            font.family: Theme.fontFamily
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Label {
                            text: modelData.count
                            color: Theme.dashboardInkTertiary
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
                color: Theme.dashboardInk
                opacity: 0.85

                Label {
                    id: dbgLabel
                    anchors.centerIn: parent
                    text: modelData.t
                    color: Theme.dashboardSurface
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
