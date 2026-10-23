import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Themes
import "../Components"
import "../Chat"
import "../Components/icons.js" as Icons
import "callPeople.js" as People

/*
 * CallOverlay - l'appel en cours, par-dessus tous les ecrans (Main.qml).
 *
 * Ligne claire : l'appel ne bloque plus l'application pendant toute sa
 * duree.
 *  - Sonnerie (ringing), appel sortant (calling), mise en relation
 *    (connecting) : fenetre centrale sur voile — Refuser / Repondre, ou
 *    Annuler.
 *  - Appel etabli (connected) : il se range dans une bande en bas de
 *    l'ecran, a droite de la barre laterale (leftInset), avec chronometre,
 *    micro, Agrandir et Raccrocher ; l'ecran du dessous reste utilisable.
 *    Agrandir rouvre la fenetre centrale, Reduire la referme.
 *  - Appel de groupe (4 personnes au plus, vous compris) : une case par
 *    participant (qui parle, micro coupe, invitation en cours), « Ajouter »
 *    pour inviter, « Quitter » qui laisse les autres continuer ; la bande
 *    empile les visages et nomme qui parle.
 *  - Fin d'appel, arrivee ou depart d'un participant, incident : avis bref.
 */
Item {
    id: root

    property var call: (typeof callContext !== "undefined") ? callContext : null
    property var peersSource: (typeof peersModel !== "undefined") ? peersModel : null
    property var messaging: (typeof messagingContext !== "undefined") ? messagingContext : null
    // Largeur de la barre laterale de l'ecran hote : la bande ne la couvre pas.
    property real leftInset: 0
    // Hauteur reservee par la bande (l'ecran hote peut s'en ecarter).
    readonly property real barReserve: callBar.visible ? callBar.height + 32 : 0

    readonly property string callState: root.call ? root.call.callState : "idle"
    readonly property bool inCall: root.callState !== "" && root.callState !== "idle"
    readonly property string remoteAddress: root.call ? root.call.remoteAddress : ""
    readonly property bool muted: root.call ? root.call.muted : false

    property bool expanded: false
    property bool incoming: false
    property string lastAddress: ""
    // Volet « Ajouter a l'appel ».
    property bool adding: false
    property var picked: []

    // ---- Participants ---------------------------------------------------------
    readonly property var participants: root.call && root.call.participants ? root.call.participants : []
    readonly property bool group: root.call ? root.call.groupCall : false
    readonly property bool canInvite: root.call ? root.call.canInvite : false
    readonly property int maxPeople: root.call ? root.call.maxParticipants : 4
    readonly property var joined: root.participants.filter(function(p) { return p.status === "joined" })
    readonly property var inviter: {
        for (let i = 0; i < root.participants.length; i++)
            if (root.participants[i].status === "inviting") return root.participants[i]
        return null
    }
    readonly property var speaker: {
        for (let i = 0; i < root.joined.length; i++)
            if (root.joined[i].speaking) return root.joined[i]
        return null
    }
    readonly property string selfName: (typeof userManager !== "undefined" && userManager && userManager.currentUsername)
                                       ? userManager.currentUsername : qsTr("Vous")
    readonly property string selfMachine: (typeof settingsModel !== "undefined" && settingsModel && settingsModel.machineName)
                                          ? settingsModel.machineName : ""

    // ---- Correspondant ----------------------------------------------------
    property var peers: []
    property var users: ({})
    function reloadPeople() {
        root.peers = People.readPeers(root.peersSource)
        root.users = People.readUsers(root.messaging)
    }
    function labelOf(address) {
        const fallback = root.peersSource && root.peersSource.nameForAddress ? root.peersSource.nameForAddress(address) : ""
        return People.labelFor(root.peers, root.users, address, fallback)
    }
    function isMachine(address) {
        const p = People.peerAt(root.peers, address)
        return !p || People.personOf(p, root.users).length === 0
    }
    function machineOf(address) {
        const p = People.peerAt(root.peers, address)
        return p ? p.machine : address
    }
    function namesOf(list) { return People.listNames(list.map(function(p) { return root.labelOf(p.address) })) }

    readonly property string shownAddress: root.remoteAddress.length ? root.remoteAddress : root.lastAddress
    readonly property var remotePeer: People.peerAt(root.peers, root.shownAddress)
    readonly property string remoteName: root.labelOf(root.shownAddress)
    readonly property string remoteDetail: {
        const p = root.remotePeer
        if (!p) return root.shownAddress
        return (People.personOf(p, root.users).length ? p.machine + " · " : "") + p.address
    }

    // ---- Chronometre --------------------------------------------------------
    property int connectedSeconds: 0
    property int lastDuration: 0
    Timer {
        interval: 1000
        repeat: true
        running: root.callState === "connected"
        onTriggered: root.connectedSeconds++
    }
    onCallStateChanged: {
        if (root.callState === "ringing") root.incoming = true
        else if (root.callState === "calling") root.incoming = false
        if (root.inCall) {
            root.reloadPeople()
            if (root.remoteAddress.length) root.lastAddress = root.remoteAddress
            if (root.noteKind === "ended" || root.noteKind === "lost") root.noteKind = ""
        } else {
            root.adding = false
        }
        if (root.callState !== "connected" && root.callState !== "ending") {
            if (root.connectedSeconds > 0) root.lastDuration = root.connectedSeconds
            root.connectedSeconds = 0
        }
        if (root.callState === "connected") root.expanded = false
    }
    // Pour l'avis de fin : qui etait dans l'appel, et si c'etait un groupe.
    property bool lastWasGroup: false
    property string lastGroupNames: ""
    onParticipantsChanged: {
        if (!root.inCall) return
        root.reloadPeople()
        root.lastWasGroup = root.group
        const inside = (root.participants || []).filter(function(p) { return p.status === "joined" })
        if (inside.length > 0) root.lastGroupNames = root.namesOf(inside)
    }

    // ---- Avis -------------------------------------------------------------------
    property string noteKind: ""            // "" | "ended" | "lost" | "busy" | "missed" | "noanswer" | "error" | "joined" | "left" | "declined" | "full"
    property string noteText: ""
    function showNote(kind, text) {
        root.noteKind = kind
        root.noteText = text
        noteTimer.restart()
    }
    Timer { id: noteTimer; interval: 7000; onTriggered: root.noteKind = "" }

    Connections {
        target: root.call
        ignoreUnknownSignals: true
        function onErrorOccurred(message) {
            root.showNote("error", "<b>" + qsTr("Appel impossible.") + "</b> " + root.esc(message))
        }
        function onParticipantJoined(address) {
            // Le premier qui repond a un appel a deux ne merite pas d'avis.
            if (root.joined.length > 1 || root.group)
                root.showNote("joined", qsTr("<b>%1 a rejoint l'appel.</b>").arg(root.esc(root.labelOf(address))))
        }
        function onParticipantLeft(address, reason) {
            const others = root.joined.filter(function(p) { return p.address !== address })
            const rest = others.length ? " " + qsTr("L'appel continue avec %1.").arg(root.esc(root.namesOf(others))) : ""
            root.showNote("left", (reason === "connection-lost"
                                   ? qsTr("<b>Connexion perdue avec %1.</b>") : qsTr("<b>%1 a quitté l'appel.</b>"))
                                  .arg(root.esc(root.labelOf(address))) + rest)
        }
        function onParticipantDeclined(address, reason) {
            const who = root.esc(root.labelOf(address))
            switch (reason) {
            case "busy": root.showNote("busy", qsTr("<b>%1 est déjà en communication.</b>").arg(who)); break
            case "noanswer": root.showNote("noanswer", qsTr("<b>Pas de réponse</b> de %1.").arg(who)); break
            case "full": root.showNote("full", qsTr("<b>Groupe complet.</b> Un appel de groupe réunit %1 personnes au plus.").arg(root.maxPeople)); break
            case "unreachable": root.showNote("declined", qsTr("<b>%1 est injoignable.</b>").arg(who)); break
            default: root.showNote("declined", qsTr("<b>%1 a refusé l'invitation.</b>").arg(who))
            }
        }
        function onCallEnded(reason) {
            const who = root.esc(root.remoteName)
            const d = root.lastDuration > 0 ? root.lastDuration : root.connectedSeconds
            if (root.lastWasGroup && d > 0 && reason !== "shutdown") {
                root.showNote("ended", qsTr("<b>Appel de groupe terminé</b> · %1%2.")
                              .arg(People.duration(d))
                              .arg(root.lastGroupNames.length ? " " + qsTr("avec %1").arg(root.esc(root.lastGroupNames)) : ""))
                root.lastDuration = 0
                root.lastWasGroup = false
                return
            }
            switch (reason) {
            case "connection-lost":
            case "signaling-disconnected":
                root.showNote("lost", qsTr("<b>Connexion perdue</b> avec %1%2. L'appel est noté dans le journal.")
                              .arg(who).arg(d > 0 ? " " + qsTr("après %1").arg(People.duration(d)) : ""))
                break
            case "busy":
                root.showNote("busy", qsTr("<b>%1 est déjà en communication.</b> Réessayez dans un instant.").arg(who))
                break
            case "timeout":
                root.showNote(root.incoming ? "missed" : "noanswer", root.incoming
                              ? qsTr("<b>Appel manqué</b> de %1.").arg(who)
                              : qsTr("<b>Pas de réponse</b> de %1.").arg(who))
                break
            case "shutdown":
                break
            default:
                if (d > 0)
                    root.showNote("ended", qsTr("<b>Appel terminé</b> avec %1 · %2.").arg(who).arg(People.duration(d)))
            }
            root.lastDuration = 0
            root.lastWasGroup = false
        }
    }

    function esc(t) { return String(t === undefined || t === null ? "" : t).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;") }

    // ---- Ajout de participants ----------------------------------------------------
    readonly property int freeSeats: Math.max(0, root.maxPeople - 1 - root.participants.length)
    readonly property var candidates: {
        const taken = {}
        for (let i = 0; i < root.participants.length; i++) taken[root.participants[i].address + ":" + root.participants[i].port] = true
        return root.peers.filter(function(p) {
            return People.presenceKind(p.status) !== "offline" && !taken[p.address + ":" + (p.signalingPort || 0)]
                   && !root.participants.some(function(q) { return q.address === p.address })
        })
    }
    function openAdd() {
        root.reloadPeople()
        root.picked = []
        root.adding = true
    }
    function togglePick(id) {
        const i = root.picked.indexOf(id)
        if (i >= 0) root.picked = root.picked.filter(function(x) { return x !== id })
        else if (root.picked.length < root.freeSeats) root.picked = root.picked.concat([id])
    }
    function confirmAdd() {
        for (let i = 0; i < root.candidates.length; i++) {
            const p = root.candidates[i]
            if (root.picked.indexOf(p.id) >= 0 && root.call)
                root.call.invite(p.address, p.signalingPort || 0)
        }
        root.adding = false
    }

    // ---- Fenetre centrale : quel contenu ---------------------------------------------
    readonly property bool sheetOpen: root.adding || root.callState === "ringing" || root.callState === "calling"
                                      || root.callState === "connecting" || (root.callState === "connected" && root.expanded)
    // "add" | "invite" (invitation de groupe recue) | "group" | "duo"
    readonly property string sheetMode: root.adding ? "add"
                                       : root.callState === "ringing" ? (root.group ? "invite" : "duo")
                                       : root.group ? "group" : "duo"

    // Bouton d'appel rond avec libelle.
    component CallAction: AbstractButton {
        id: ca
        property string iconPath: ""
        property string tone: "line"         // "line" | "danger" | "accept" | "on"
        property real diameter: 56
        hoverEnabled: true
        focusPolicy: Qt.StrongFocus
        Accessible.name: ca.text
        opacity: ca.enabled ? 1 : 0.45
        // Disques alignes par le bas, libelles sur une meme ligne.
        implicitWidth: Math.max(ca.diameter, caLabel.implicitWidth)
        implicitHeight: 64 + 7 + caLabel.implicitHeight
        HoverHandler { cursorShape: ca.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
        background: Item {}
        contentItem: Item {
            Rectangle {
                id: disc
                anchors.horizontalCenter: parent.horizontalCenter
                y: 64 - ca.diameter
                width: ca.diameter
                height: ca.diameter
                radius: ca.diameter / 2
                color: ca.tone === "danger" ? (ca.hovered ? Theme.dangerHover : Theme.dangerColor)
                     : ca.tone === "accept" ? Theme.successColor
                     : ca.tone === "on" ? Theme.ink
                     : (ca.hovered && ca.enabled ? Theme.selectWash : Theme.surface0)
                border.width: ca.tone === "line" ? 1 : 0
                border.color: ca.hovered && ca.enabled ? Theme.ink : Theme.lineStrong
                Rectangle { anchors.fill: parent; anchors.margins: -4; radius: width / 2; color: "transparent"; border.width: 2; border.color: Theme.focusRing; visible: ca.visualFocus }
                LineIcon {
                    anchors.centerIn: parent
                    path: ca.iconPath
                    size: Math.round(ca.diameter * 0.4)
                    strokeWidth: 1.8
                    color: ca.tone === "danger" ? Theme.inkOnDanger : ca.tone === "accept" ? Theme.inkOnSuccess : ca.tone === "on" ? Theme.inkOnInk : Theme.ink
                }
            }
            Text {
                id: caLabel
                anchors.horizontalCenter: parent.horizontalCenter
                y: 64 + 7
                text: ca.text
                color: Theme.ink2
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(12)
                font.weight: Theme.weightSemibold
            }
        }
    }

    // Bouton rectangulaire de la bande.
    component BarButton: AbstractButton {
        id: bb
        property string iconPath: ""
        property string tone: "line"         // "line" | "danger" | "warn"
        property string tip: ""
        property bool iconOnly: false
        hoverEnabled: true
        focusPolicy: Qt.StrongFocus
        Accessible.name: bb.text.length ? bb.text : bb.tip
        ToolTip.visible: bb.tip.length > 0 && bb.hovered
        ToolTip.text: bb.tip
        ToolTip.delay: 400
        opacity: bb.enabled ? 1 : 0.45
        implicitHeight: 36
        implicitWidth: bb.iconOnly ? 36 : bbRow.implicitWidth + 24
        HoverHandler { cursorShape: bb.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
        background: Rectangle {
            radius: Theme.radiusSheet
            color: bb.tone === "danger" ? (bb.hovered ? Theme.dangerHover : Theme.dangerColor) : bb.tone === "warn" ? Theme.warningSoft : (bb.hovered && bb.enabled ? Theme.selectWash : "transparent")
            border.width: bb.tone === "danger" ? 0 : (bb.visualFocus ? 2 : 1)
            border.color: bb.visualFocus ? Theme.focusRing : bb.tone === "warn" ? Theme.warningColor : (bb.hovered && bb.enabled ? Theme.ink : Theme.lineStrong)
        }
        contentItem: Item {
            Row {
                id: bbRow
                anchors.centerIn: parent
                spacing: 7
                LineIcon { anchors.verticalCenter: parent.verticalCenter; path: bb.iconPath; size: 16; strokeWidth: 1.8; color: bb.tone === "danger" ? Theme.inkOnDanger : bb.tone === "warn" ? Theme.warningInk : Theme.ink }
                Text { visible: !bb.iconOnly; anchors.verticalCenter: parent.verticalCenter; text: bb.text; color: bb.tone === "danger" ? Theme.inkOnDanger : bb.tone === "warn" ? Theme.warningInk : Theme.ink; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12.5); font.weight: Theme.weightSemibold }
            }
        }
    }

    // Visages empiles (bande, invitation, volet d'ajout).
    component FaceStack: Row {
        id: fs
        property var addresses: []
        property real size: 28
        spacing: -4
        Repeater {
            model: fs.addresses
            delegate: Rectangle {
                required property var modelData
                width: fs.size + 4
                height: fs.size + 4
                radius: width / 2
                color: Theme.bg
                ChatMonogram {
                    anchors.centerIn: parent
                    size: fs.size
                    label: root.labelOf(parent.modelData)
                    machine: root.isMachine(parent.modelData)
                }
            }
        }
    }

    // Case d'un participant dans l'appel de groupe.
    component Tile: Rectangle {
        id: tile
        property string label: ""
        property bool isMachine: false
        property bool me: false
        property string sub: ""
        property color subColor: Theme.ink3
        property bool subBold: false
        property bool speaking: false
        property bool mutedMic: false
        property bool pending: false
        radius: Theme.radiusSheet
        color: tile.pending ? "transparent" : Theme.surface0
        border.width: tile.speaking ? 1.5 : 1
        border.color: tile.speaking ? Theme.successColor : Theme.line
        implicitHeight: tileCol.implicitHeight + 28
        Accessible.role: Accessible.StaticText
        Accessible.name: tile.label + (tile.sub.length ? ", " + tile.sub : "")

        Column {
            id: tileCol
            anchors.centerIn: parent
            width: parent.width - 20
            spacing: 4
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 70
                height: 70
                // Qui parle : anneau vert qui respire autour du visage.
                Rectangle {
                    id: talkRing
                    anchors.centerIn: parent
                    width: 70
                    height: 70
                    radius: 35
                    color: "transparent"
                    border.width: 2
                    border.color: Theme.successColor
                    visible: tile.speaking
                    SequentialAnimation on scale {
                        running: tile.speaking
                        loops: Animation.Infinite
                        NumberAnimation { from: 1; to: 1.06; duration: 700; easing.type: Easing.InOutSine }
                        NumberAnimation { from: 1.06; to: 1; duration: 700; easing.type: Easing.InOutSine }
                    }
                }
                ChatMonogram {
                    anchors.centerIn: parent
                    size: 60
                    label: tile.label
                    machine: tile.isMachine
                    opacity: tile.pending ? 0.45 : 1
                }
                Rectangle {
                    visible: tile.mutedMic
                    x: parent.width - width - 2
                    y: parent.height - height - 2
                    width: 22
                    height: 22
                    radius: 11
                    color: Theme.warningSoft
                    border.width: 2
                    border.color: Theme.surface0
                    LineIcon { anchors.centerIn: parent; path: Icons.micOff; size: 12; strokeWidth: 2; color: Theme.warningInk }
                }
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: tile.label
                color: Theme.ink
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(13.5)
                font.weight: Theme.weightBold
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: tile.sub
                color: tile.subColor
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(12)
                font.weight: tile.subBold ? Theme.weightSemibold : Theme.weightRegular
                elide: Text.ElideRight
            }
        }
    }

    // ======================================================================
    // Fenetre centrale
    // ======================================================================
    Rectangle {
        anchors.fill: parent
        color: Theme.scrim
        visible: opacity > 0
        opacity: root.sheetOpen ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.durationFast } }
        // Avale les clics : l'ecran du dessous n'est pas utilisable pendant la sonnerie.
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }
    }

    RectangularShadow {
        anchors.fill: sheet
        visible: sheet.visible
        opacity: sheet.opacity
        offset.y: 14
        blur: 36
        spread: -4
        radius: sheet.radius
        color: Theme.shadowStrong
    }
    Rectangle {
        id: sheet
        anchors.centerIn: parent
        width: Math.min(root.sheetMode === "group" ? 560 : root.sheetMode === "add" ? 460 : 400, root.width - 32)
        height: Math.min(root.height - 32,
                         (root.sheetMode === "add" ? addCol.implicitHeight
                          : root.sheetMode === "group" ? groupCol.implicitHeight
                          : root.sheetMode === "invite" ? inviteCol.implicitHeight
                          : sheetCol.implicitHeight) + 48)
        radius: Theme.radiusSheet
        color: Theme.bg
        border.width: 1
        border.color: Theme.ruleInk
        clip: true
        visible: opacity > 0
        opacity: root.sheetOpen ? 1 : 0
        scale: root.sheetOpen ? 1 : 0.97
        Behavior on opacity { NumberAnimation { duration: Theme.durationNormal } }
        Behavior on scale { NumberAnimation { duration: Theme.durationNormal; easing.type: Easing.OutCubic } }
        Accessible.role: Accessible.Dialog
        Accessible.name: root.sheetMode === "add" ? qsTr("Ajouter à l'appel") : qsTr("Appel")

        AbstractButton {
            id: reduceBtn
            visible: root.callState === "connected" && !root.adding
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 10
            z: 2
            width: 34
            height: 34
            hoverEnabled: true
            Accessible.name: qsTr("Réduire en bande")
            ToolTip.visible: hovered
            ToolTip.text: qsTr("Réduire en bande")
            onClicked: root.expanded = false
            background: Rectangle { radius: 17; color: reduceBtn.hovered ? Theme.selectWash : "transparent" }
            contentItem: Item { LineIcon { anchors.centerIn: parent; path: Icons.minimize; size: 16; strokeWidth: 1.8; color: Theme.ink2 } }
        }

        // ---- Appel a deux ------------------------------------------------------
        ColumnLayout {
            id: sheetCol
            visible: root.sheetMode === "duo"
            anchors.horizontalCenter: parent.horizontalCenter
            y: 26
            width: parent.width - 52
            spacing: 0

            CapsLabel {
                Layout.alignment: Qt.AlignHCenter
                text: root.callState === "ringing" ? qsTr("Appel entrant")
                      : root.callState === "calling" ? qsTr("Appel sortant")
                      : root.callState === "connecting" ? qsTr("Mise en relation") : qsTr("En appel")
            }
            // Monogramme et anneaux qui pulsent tant que l'appel n'est pas etabli
            Item {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 16
                Layout.bottomMargin: 12
                implicitWidth: 132
                implicitHeight: 132
                Repeater {
                    model: root.callState === "ringing" || root.callState === "calling" || root.callState === "connecting" ? 2 : 0
                    delegate: Rectangle {
                        required property int index
                        anchors.centerIn: parent
                        width: 88
                        height: 88
                        radius: 44
                        color: "transparent"
                        border.width: 1.5
                        border.color: Theme.ruleInk
                        opacity: 0
                        SequentialAnimation on opacity {
                            loops: Animation.Infinite
                            PauseAnimation { duration: index * 600 }
                            NumberAnimation { from: 0.55; to: 0; duration: 1800; easing.type: Easing.OutQuad }
                        }
                        SequentialAnimation on scale {
                            loops: Animation.Infinite
                            PauseAnimation { duration: index * 600 }
                            NumberAnimation { from: 1; to: 1.5; duration: 1800; easing.type: Easing.OutQuad }
                        }
                    }
                }
                ChatMonogram {
                    anchors.centerIn: parent
                    size: 88
                    label: root.remoteName
                    machine: !root.remotePeer || People.personOf(root.remotePeer, root.users).length === 0
                }
            }
            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: root.remoteName
                color: Theme.ink
                font.family: Theme.fontFamilySerif
                font.pixelSize: Theme.fs(26)
                font.weight: Theme.weightBold
                wrapMode: Text.WordWrap
                Accessible.role: Accessible.Heading
            }
            Text {
                Layout.fillWidth: true
                Layout.topMargin: 4
                horizontalAlignment: Text.AlignHCenter
                text: root.remoteDetail
                color: Theme.ink2
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(13)
                elide: Text.ElideMiddle
            }
            Text {
                Layout.fillWidth: true
                Layout.topMargin: 12
                horizontalAlignment: Text.AlignHCenter
                textFormat: Text.StyledText
                text: root.callState === "ringing" ? qsTr("%1 vous appelle depuis le réseau local.").arg(root.esc(root.remoteName.split(" ")[0]))
                      : root.callState === "calling" ? qsTr("Sonnerie chez votre correspondant…")
                      : root.callState === "connecting" ? qsTr("Connexion de l'audio…")
                      : "<b>" + People.clock(root.connectedSeconds) + "</b>" + (root.muted ? " · " + qsTr("micro coupé") : "")
                color: Theme.ink2
                font.family: Theme.fontFamilySerif
                font.pixelSize: Theme.fs(15)
                wrapMode: Text.WordWrap
            }
            Row {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 20
                spacing: 22
                CallAction { visible: root.callState === "ringing"; text: qsTr("Refuser"); tone: "danger"; iconPath: Icons.hangup; onClicked: root.call && root.call.hangUp() }
                CallAction { visible: root.callState === "ringing"; text: qsTr("Répondre"); tone: "accept"; diameter: 64; iconPath: Icons.phoneLine; onClicked: root.call && root.call.acceptCall() }
                CallAction { visible: root.callState === "calling" || root.callState === "connecting"; text: qsTr("Annuler"); tone: "danger"; diameter: 64; iconPath: Icons.hangup; onClicked: root.call && root.call.hangUp() }
                CallAction {
                    visible: root.callState === "connected"
                    text: root.muted ? qsTr("Réactiver") : qsTr("Couper le micro")
                    tone: root.muted ? "on" : "line"
                    iconPath: root.muted ? Icons.micOff : Icons.mic
                    onClicked: root.call && root.call.toggleMute()
                }
                CallAction {
                    visible: root.callState === "connected"
                    text: qsTr("Ajouter une personne")
                    iconPath: Icons.userPlus
                    enabled: root.canInvite
                    onClicked: root.openAdd()
                }
                CallAction { visible: root.callState === "connected"; text: qsTr("Raccrocher"); tone: "danger"; diameter: 64; iconPath: Icons.hangup; onClicked: root.call && root.call.hangUp() }
            }
            Text {
                Layout.fillWidth: true
                Layout.topMargin: 16
                visible: root.callState === "ringing" || root.callState === "connected"
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: root.callState === "ringing" ? qsTr("Sans réponse, l'appel sera noté « manqué » dans le journal.")
                                                   : qsTr("Ajoutez jusqu'à deux personnes : l'appel devient un appel de groupe.")
                color: Theme.ink3
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(12)
            }
        }

        // ---- Invitation a un appel de groupe ---------------------------------------
        ColumnLayout {
            id: inviteCol
            visible: root.sheetMode === "invite"
            anchors.horizontalCenter: parent.horizontalCenter
            y: 26
            width: parent.width - 52
            spacing: 0
            readonly property string host: root.inviter ? root.inviter.address : root.shownAddress
            readonly property var already: {
                const out = [inviteCol.host]
                const roster = root.call ? root.call.inviteRoster : []
                for (let i = 0; i < roster.length; i++) out.push(roster[i].address)
                return out
            }

            CapsLabel { Layout.alignment: Qt.AlignHCenter; text: qsTr("Appel de groupe entrant") }
            Item {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 16
                Layout.bottomMargin: 12
                implicitWidth: 132
                implicitHeight: 132
                Repeater {
                    model: 2
                    delegate: Rectangle {
                        required property int index
                        anchors.centerIn: parent
                        width: 88
                        height: 88
                        radius: 44
                        color: "transparent"
                        border.width: 1.5
                        border.color: Theme.ruleInk
                        opacity: 0
                        SequentialAnimation on opacity {
                            running: inviteCol.visible
                            loops: Animation.Infinite
                            PauseAnimation { duration: index * 600 }
                            NumberAnimation { from: 0.55; to: 0; duration: 1800; easing.type: Easing.OutQuad }
                        }
                        SequentialAnimation on scale {
                            running: inviteCol.visible
                            loops: Animation.Infinite
                            PauseAnimation { duration: index * 600 }
                            NumberAnimation { from: 1; to: 1.5; duration: 1800; easing.type: Easing.OutQuad }
                        }
                    }
                }
                ChatMonogram { anchors.centerIn: parent; size: 88; label: root.labelOf(inviteCol.host); machine: root.isMachine(inviteCol.host) }
            }
            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: root.labelOf(inviteCol.host)
                color: Theme.ink
                font.family: Theme.fontFamilySerif
                font.pixelSize: Theme.fs(26)
                font.weight: Theme.weightBold
                wrapMode: Text.WordWrap
                Accessible.role: Accessible.Heading
            }
            Text {
                Layout.fillWidth: true
                Layout.topMargin: 4
                horizontalAlignment: Text.AlignHCenter
                text: qsTr("vous invite à un appel de groupe")
                color: Theme.ink2
                font.family: Theme.fontFamilySerif
                font.pixelSize: Theme.fs(15)
            }
            Row {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 12
                spacing: 10
                FaceStack { anchors.verticalCenter: parent.verticalCenter; addresses: inviteCol.already; size: 24 }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.StyledText
                    text: qsTr("Déjà dans l'appel : <b>%1</b>").arg(root.esc(People.listNames(inviteCol.already.map(root.labelOf))))
                    color: Theme.ink2
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(12.5)
                }
            }
            Row {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 20
                spacing: 22
                CallAction { text: qsTr("Refuser"); tone: "danger"; iconPath: Icons.hangup; onClicked: root.call && root.call.hangUp() }
                CallAction { text: qsTr("Rejoindre"); tone: "accept"; diameter: 64; iconPath: Icons.phoneLine; onClicked: root.call && root.call.acceptCall() }
            }
            Text {
                Layout.fillWidth: true
                Layout.topMargin: 16
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: qsTr("Sans réponse, l'appel sera noté « manqué » dans le journal.")
                color: Theme.ink3
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(12)
            }
        }

        // ---- Appel de groupe : invitations puis participants --------------------------
        ColumnLayout {
            id: groupCol
            visible: root.sheetMode === "group"
            x: 26
            y: 26
            width: parent.width - 52
            spacing: 0
            readonly property bool outgoing: root.callState !== "connected"
            readonly property var invitees: root.participants.filter(function(p) { return p.status !== "inviting" })
            readonly property int total: groupCol.invitees.length + 1
            readonly property bool full: groupCol.total >= root.maxPeople

            CapsLabel {
                text: groupCol.outgoing ? qsTr("Appel de groupe · invitations") : qsTr("Appel de groupe")
            }
            Text {
                Layout.fillWidth: true
                Layout.topMargin: 6
                text: groupCol.outgoing
                      ? (groupCol.invitees.length > 1
                         ? qsTr("%1 sur %2 personnes ont rejoint").arg(root.joined.length).arg(groupCol.invitees.length)
                         : qsTr("%1 sur %2 personne a rejoint").arg(root.joined.length).arg(groupCol.invitees.length))
                      : qsTr("%1 personnes").arg(root.joined.length + 1)
                color: Theme.ink
                font.family: Theme.fontFamilySerif
                font.pixelSize: Theme.fs(26)
                font.weight: Theme.weightBold
                wrapMode: Text.WordWrap
                Accessible.role: Accessible.Heading
            }
            Text {
                Layout.fillWidth: true
                Layout.topMargin: 6
                textFormat: Text.StyledText
                text: groupCol.outgoing ? qsTr("Chacun rejoint en répondant à l'invitation.")
                                        : "<b>" + People.clock(root.connectedSeconds) + "</b>" + (root.muted ? " · " + qsTr("micro coupé") : "")
                color: Theme.ink2
                font.family: Theme.fontFamilySerif
                font.pixelSize: Theme.fs(15)
            }
            GridLayout {
                Layout.fillWidth: true
                Layout.topMargin: 16
                columns: 2
                columnSpacing: 10
                rowSpacing: 10
                Tile {
                    // A trois, votre case prend toute la largeur au-dessus des deux autres.
                    Layout.columnSpan: groupCol.total === 3 ? 2 : 1
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    label: root.selfName
                    me: true
                    speaking: root.call ? root.call.localSpeaking : false
                    mutedMic: root.muted
                    sub: qsTr("Vous") + (root.selfMachine.length ? " · " + root.selfMachine : "") + (root.muted ? " · " + qsTr("micro coupé") : "")
                }
                Repeater {
                    model: groupCol.invitees
                    delegate: Tile {
                        required property var modelData
                        readonly property string st: modelData.status
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        label: root.labelOf(modelData.address)
                        isMachine: root.isMachine(modelData.address)
                        pending: st !== "joined"
                        speaking: modelData.speaking
                        mutedMic: modelData.muted
                        sub: st === "invited" ? qsTr("Sonnerie…")
                             : st === "connecting" ? qsTr("Connexion…")
                             : modelData.speaking ? qsTr("parle")
                             : root.machineOf(modelData.address) + (modelData.muted ? " · " + qsTr("micro coupé") : "")
                        subColor: modelData.speaking ? Theme.successInk : Theme.ink3
                        subBold: modelData.speaking || st !== "joined"
                    }
                }
            }
            Row {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 20
                spacing: 22
                CallAction {
                    text: root.muted ? qsTr("Réactiver") : qsTr("Couper le micro")
                    tone: root.muted ? "on" : "line"
                    iconPath: root.muted ? Icons.micOff : Icons.mic
                    onClicked: root.call && root.call.toggleMute()
                }
                CallAction {
                    text: groupCol.full ? qsTr("Groupe complet") : qsTr("Ajouter")
                    iconPath: Icons.userPlus
                    enabled: root.canInvite
                    ToolTip.visible: groupCol.full && hovered
                    ToolTip.text: qsTr("%1 personnes au plus").arg(root.maxPeople)
                    onClicked: root.openAdd()
                }
                CallAction {
                    readonly property bool cancel: groupCol.outgoing && root.joined.length === 0
                    text: cancel ? qsTr("Annuler") : qsTr("Quitter")
                    tone: "danger"
                    diameter: 64
                    iconPath: Icons.hangup
                    onClicked: root.call && root.call.hangUp()
                }
            }
            Text {
                Layout.fillWidth: true
                Layout.topMargin: 16
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: groupCol.outgoing ? qsTr("Vous pouvez commencer dès qu'une personne a rejoint.")
                                        : qsTr("Quitter vous retire de l'appel : les autres continuent sans vous.")
                color: Theme.ink3
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(12)
            }
        }

        // ---- Ajouter a l'appel -----------------------------------------------------------
        ColumnLayout {
            id: addCol
            visible: root.sheetMode === "add"
            x: 26
            y: 26
            width: parent.width - 52
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                CapsLabel { Layout.fillWidth: true; text: root.group ? qsTr("Ajouter à l'appel") : qsTr("Passer en appel de groupe") }
                AbstractButton {
                    id: addClose
                    Layout.preferredWidth: 30
                    Layout.preferredHeight: 30
                    hoverEnabled: true
                    Accessible.name: qsTr("Fermer")
                    onClicked: root.adding = false
                    background: Rectangle { radius: 15; color: addClose.hovered ? Theme.selectWash : "transparent" }
                    contentItem: Item { LineIcon { anchors.centerIn: parent; path: Icons.close; size: 14; strokeWidth: 1.8; color: Theme.ink2 } }
                }
            }
            Text {
                Layout.fillWidth: true
                Layout.topMargin: 4
                text: root.freeSeats > 1 ? qsTr("Inviter jusqu'à %1 personnes").arg(root.freeSeats) : qsTr("Inviter une personne")
                color: Theme.ink
                font.family: Theme.fontFamilySerif
                font.pixelSize: Theme.fs(24)
                font.weight: Theme.weightBold
                wrapMode: Text.WordWrap
            }
            Text {
                Layout.fillWidth: true
                Layout.topMargin: 6
                text: (root.group || root.joined.length === 0
                       ? qsTr("L'appel continue pendant l'invitation.")
                       : qsTr("%1 reste en ligne : les personnes invitées rejoignent l'appel en répondant.").arg(root.labelOf(root.joined[0].address)))
                      + " " + qsTr("%1 personnes au plus, vous compris.").arg(root.maxPeople)
                color: Theme.ink2
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(13)
                wrapMode: Text.WordWrap
            }
            Text {
                visible: root.candidates.length === 0
                Layout.fillWidth: true
                Layout.topMargin: 14
                text: qsTr("Aucun autre poste n'est joignable sur le réseau local.")
                color: Theme.ink3
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(12.5)
                wrapMode: Text.WordWrap
            }
            ListView {
                id: addList
                visible: root.candidates.length > 0
                Layout.fillWidth: true
                Layout.topMargin: 12
                Layout.preferredHeight: Math.min(contentHeight, 300)
                clip: true
                spacing: 2
                boundsBehavior: Flickable.StopAtBounds
                model: root.candidates
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                delegate: AbstractButton {
                    id: cand
                    required property var modelData
                    readonly property string person: People.personOf(modelData, root.users)
                    readonly property bool on: root.picked.indexOf(modelData.id) >= 0
                    width: ListView.view.width
                    implicitHeight: 54
                    enabled: cand.on || root.picked.length < root.freeSeats
                    hoverEnabled: true
                    Accessible.role: Accessible.CheckBox
                    Accessible.checked: cand.on
                    Accessible.name: cand.person.length ? cand.person : modelData.machine
                    onClicked: root.togglePick(modelData.id)
                    HoverHandler { cursorShape: cand.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
                    background: Rectangle {
                        radius: Theme.radiusSheet
                        color: cand.on ? Theme.selectWash : (cand.hovered ? Theme.surface0 : "transparent")
                        border.width: cand.on ? 1 : 0
                        border.color: Theme.ink
                    }
                    contentItem: RowLayout {
                        spacing: 12
                        opacity: cand.enabled ? 1 : 0.5
                        ChatMonogram { Layout.leftMargin: 8; label: cand.person.length ? cand.person : cand.modelData.machine; machine: cand.person.length === 0; status: cand.modelData.status || "online" }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            Text { Layout.fillWidth: true; text: cand.person.length ? cand.person : cand.modelData.machine; color: Theme.ink; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13.5); font.weight: Theme.weightSemibold; elide: Text.ElideRight }
                            Text { Layout.fillWidth: true; text: (cand.person.length ? cand.modelData.machine + " · " : "") + People.presenceWord(cand.modelData.status); color: Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12); elide: Text.ElideRight }
                        }
                        Rectangle {
                            Layout.rightMargin: 10
                            Layout.preferredWidth: 20
                            Layout.preferredHeight: 20
                            radius: 3
                            color: cand.on ? Theme.ink : "transparent"
                            border.width: cand.on ? 0 : 1.5
                            border.color: Theme.lineStrong
                            LineIcon { visible: cand.on; anchors.centerIn: parent; path: Icons.check; size: 13; strokeWidth: 2.4; color: Theme.inkOnInk }
                        }
                    }
                }
            }
            Rectangle { Layout.fillWidth: true; Layout.topMargin: 16; Layout.preferredHeight: 1; color: Theme.ruleInk }
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 14
                Item { Layout.fillWidth: true }
                AppButton { variant: "ghost"; text: qsTr("Annuler"); onClicked: root.adding = false }
                AppButton {
                    variant: "ink"
                    iconPath: Icons.userPlus
                    enabled: root.picked.length > 0
                    text: {
                        if (root.picked.length === 0) return qsTr("Inviter")
                        if (root.picked.length > 1) return qsTr("Inviter %1 personnes").arg(root.picked.length)
                        for (let i = 0; i < root.candidates.length; i++)
                            if (root.candidates[i].id === root.picked[0])
                                return qsTr("Inviter %1").arg(People.firstName(People.personOf(root.candidates[i], root.users) || root.candidates[i].machine))
                        return qsTr("Inviter")
                    }
                    onClicked: root.confirmAdd()
                }
            }
        }
    }

    // ======================================================================
    // Bande d'appel etabli
    // ======================================================================
    RectangularShadow {
        anchors.fill: callBar
        visible: callBar.visible
        offset.y: 10
        blur: 30
        spread: -6
        radius: callBar.radius
        color: Theme.shadowStrong
    }
    Rectangle {
        id: callBar
        readonly property bool ending: root.callState === "ending"
        readonly property bool tight: width < 640
        visible: ((root.callState === "connected" && !root.expanded) || callBar.ending) && !root.adding
        x: root.leftInset + Theme.pagePadding
        width: root.width - x - Theme.pagePadding
        y: root.height - height - 16
        height: 60
        radius: Theme.radiusSheet
        color: Theme.bg
        border.width: 1
        border.color: Theme.ruleInk
        Accessible.role: Accessible.Grouping
        Accessible.name: root.group ? qsTr("Appel de groupe en cours") : qsTr("Appel en cours avec %1").arg(root.remoteName)
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }
        Rectangle { x: 0; y: 0; width: 4; height: parent.height; color: Theme.successColor }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 12
            spacing: 14
            ChatMonogram {
                visible: !root.group
                size: 32
                label: root.remoteName
                machine: !root.remotePeer || People.personOf(root.remotePeer, root.users).length === 0
            }
            FaceStack {
                visible: root.group
                size: 28
                addresses: root.joined.map(function(p) { return p.address })
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                Text {
                    Layout.fillWidth: true
                    text: root.group ? qsTr("Appel de groupe · %1 personnes").arg(root.joined.length + 1) : root.remoteName
                    color: Theme.ink
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(14)
                    font.weight: Theme.weightBold
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    textFormat: Text.StyledText
                    elide: Text.ElideRight
                    text: callBar.ending ? qsTr("Fin de l'appel…")
                          : root.muted ? (!root.group && root.remotePeer && People.personOf(root.remotePeer, root.users).length ? root.esc(root.remotePeer.machine) + " · " : "")
                                         + "<b><font color=\"" + Theme.warningInk + "\">" + qsTr("micro coupé") + "</font></b>"
                          : root.group ? (root.speaker ? "<b><font color=\"" + Theme.successInk + "\">"
                                                         + qsTr("%1 parle").arg(root.esc(People.firstName(root.labelOf(root.speaker.address)))) + "</font></b>"
                                                       : qsTr("micro actif"))
                          : (root.remotePeer && People.personOf(root.remotePeer, root.users).length ? root.esc(root.remotePeer.machine) + " · " : "") + qsTr("micro actif")
                    color: Theme.ink3
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(12)
                }
            }
            Text {
                text: People.clock(root.connectedSeconds)
                color: Theme.ink
                font.family: Theme.fontFamilySerif
                font.pixelSize: Theme.fs(22)
                font.weight: Theme.weightBold
                font.features: ({ "tnum": 1 })
            }
            BarButton {
                text: root.muted ? qsTr("Réactiver le micro") : qsTr("Couper le micro")
                tip: callBar.tight ? text : ""
                iconOnly: callBar.tight
                tone: root.muted ? "warn" : "line"
                iconPath: root.muted ? Icons.micOff : Icons.mic
                enabled: !callBar.ending
                onClicked: root.call && root.call.toggleMute()
            }
            BarButton {
                iconOnly: true
                tip: root.canInvite ? qsTr("Ajouter une personne") : qsTr("Groupe complet (%1 personnes)").arg(root.maxPeople)
                iconPath: Icons.userPlus
                enabled: !callBar.ending && root.canInvite
                onClicked: root.openAdd()
            }
            BarButton { iconOnly: true; tip: qsTr("Agrandir"); iconPath: Icons.maximize; enabled: !callBar.ending; onClicked: root.expanded = true }
            BarButton {
                text: root.group ? qsTr("Quitter") : qsTr("Raccrocher")
                tip: callBar.tight ? text : ""
                iconOnly: callBar.tight
                tone: "danger"
                iconPath: Icons.hangup
                enabled: !callBar.ending
                onClicked: root.call && root.call.hangUp()
            }
        }
    }

    // ======================================================================
    // Avis (fin d'appel, arrivees et departs)
    // ======================================================================
    Rectangle {
        id: note
        readonly property bool positive: root.noteKind === "ended" || root.noteKind === "joined" || root.noteKind === "left"
        visible: root.noteKind.length > 0 && !root.sheetOpen
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.horizontalCenterOffset: root.leftInset / 2
        // Pendant l'appel, au-dessus de la bande.
        y: callBar.visible ? callBar.y - height - 10 : root.height - height - 22
        width: Math.min(noteRow.implicitWidth + 32, root.width - root.leftInset - 32)
        height: noteRow.implicitHeight + 22
        radius: Theme.radiusSheet
        color: Theme.bg
        border.width: 1
        border.color: Theme.ruleInk
        Rectangle { width: 3; height: parent.height; color: note.positive ? Theme.ruleInk : Theme.dangerColor }
        RowLayout {
            id: noteRow
            anchors.verticalCenter: parent.verticalCenter
            x: 16
            width: parent.width - 26
            spacing: 12
            LineIcon {
                path: root.noteKind === "ended" ? Icons.phoneLine
                      : root.noteKind === "joined" ? Icons.userPlus
                      : root.noteKind === "left" ? Icons.users : Icons.alertTriangle
                size: 16
                strokeWidth: 1.8
                color: note.positive ? Theme.ink2 : Theme.dangerInk
            }
            Text {
                Layout.fillWidth: true
                Layout.maximumWidth: 620
                text: root.noteText
                textFormat: Text.StyledText
                wrapMode: Text.WordWrap
                color: Theme.ink
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(13)
            }
            AbstractButton {
                id: noteClose
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                hoverEnabled: true
                Accessible.name: qsTr("Fermer")
                onClicked: root.noteKind = ""
                background: Rectangle { radius: 14; color: noteClose.hovered ? Theme.selectWash : "transparent" }
                contentItem: Item { LineIcon { anchors.centerIn: parent; path: Icons.close; size: 14; strokeWidth: 1.8; color: Theme.ink2 } }
            }
        }
    }

    Component.onCompleted: root.reloadPeople()
}
