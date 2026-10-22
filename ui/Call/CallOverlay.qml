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
 *  - Fin d'appel ou incident : avis bref (callEnded, errorOccurred).
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

    // ---- Correspondant ----------------------------------------------------
    property var peers: []
    property var users: ({})
    function reloadPeople() {
        root.peers = People.readPeers(root.peersSource)
        root.users = People.readUsers(root.messaging)
    }
    readonly property string shownAddress: root.remoteAddress.length ? root.remoteAddress : root.lastAddress
    readonly property var remotePeer: People.peerAt(root.peers, root.shownAddress)
    readonly property string remoteName: {
        const fallback = root.peersSource && root.peersSource.nameForAddress ? root.peersSource.nameForAddress(root.shownAddress) : ""
        return People.labelFor(root.peers, root.users, root.shownAddress, fallback)
    }
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
            root.noteKind = ""
        }
        if (root.callState !== "connected" && root.callState !== "ending") {
            if (root.connectedSeconds > 0) root.lastDuration = root.connectedSeconds
            root.connectedSeconds = 0
        }
        if (root.callState === "connected") root.expanded = false
    }

    // ---- Avis de fin ----------------------------------------------------------
    property string noteKind: ""            // "" | "ended" | "lost" | "busy" | "missed" | "noanswer" | "error"
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
        function onCallEnded(reason) {
            const who = root.esc(root.remoteName)
            const d = root.lastDuration > 0 ? root.lastDuration : root.connectedSeconds
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
        }
    }

    function esc(t) { return String(t === undefined || t === null ? "" : t).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;") }

    readonly property bool sheetOpen: root.callState === "ringing" || root.callState === "calling" || root.callState === "connecting"
                                      || (root.callState === "connected" && root.expanded)

    // Bouton d'appel rond avec libelle.
    component CallAction: AbstractButton {
        id: ca
        property string iconPath: ""
        property string tone: "line"         // "line" | "danger" | "accept" | "on"
        property real diameter: 56
        hoverEnabled: true
        focusPolicy: Qt.StrongFocus
        Accessible.name: ca.text
        // Disques alignes par le bas, libelles sur une meme ligne.
        implicitWidth: Math.max(ca.diameter, caLabel.implicitWidth)
        implicitHeight: 64 + 7 + caLabel.implicitHeight
        HoverHandler { cursorShape: Qt.PointingHandCursor }
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
                     : (ca.hovered ? Theme.selectWash : Theme.surface0)
                border.width: ca.tone === "line" ? 1 : 0
                border.color: ca.hovered ? Theme.ink : Theme.lineStrong
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
        implicitHeight: 36
        implicitWidth: bb.iconOnly ? 36 : bbRow.implicitWidth + 24
        HoverHandler { cursorShape: bb.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
        background: Rectangle {
            radius: Theme.radiusSheet
            color: bb.tone === "danger" ? (bb.hovered ? Theme.dangerHover : Theme.dangerColor) : bb.tone === "warn" ? Theme.warningSoft : (bb.hovered ? Theme.selectWash : "transparent")
            border.width: bb.tone === "danger" ? 0 : (bb.visualFocus ? 2 : 1)
            border.color: bb.visualFocus ? Theme.focusRing : bb.tone === "warn" ? Theme.warningColor : (bb.hovered ? Theme.ink : Theme.lineStrong)
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
        width: Math.min(400, root.width - 32)
        height: sheetCol.implicitHeight + 48
        radius: Theme.radiusSheet
        color: Theme.bg
        border.width: 1
        border.color: Theme.ruleInk
        visible: opacity > 0
        opacity: root.sheetOpen ? 1 : 0
        scale: root.sheetOpen ? 1 : 0.97
        Behavior on opacity { NumberAnimation { duration: Theme.durationNormal } }
        Behavior on scale { NumberAnimation { duration: Theme.durationNormal; easing.type: Easing.OutCubic } }
        Accessible.role: Accessible.Dialog
        Accessible.name: qsTr("Appel")

        AbstractButton {
            id: reduceBtn
            visible: root.callState === "connected"
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 10
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

        ColumnLayout {
            id: sheetCol
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
                CallAction { visible: root.callState === "connected"; text: qsTr("Raccrocher"); tone: "danger"; diameter: 64; iconPath: Icons.hangup; onClicked: root.call && root.call.hangUp() }
            }
            Text {
                Layout.fillWidth: true
                Layout.topMargin: 16
                visible: root.callState === "ringing" || root.callState === "connected"
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: root.callState === "ringing" ? qsTr("Sans réponse, l'appel sera noté « manqué » dans le journal.")
                                                   : qsTr("Réduisez la fenêtre : l'appel reste en bas de l'écran pendant que vous travaillez.")
                color: Theme.ink3
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(12)
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
        visible: (root.callState === "connected" && !root.expanded) || callBar.ending
        x: root.leftInset + Theme.pagePadding
        width: root.width - x - Theme.pagePadding
        y: root.height - height - 16
        height: 60
        radius: Theme.radiusSheet
        color: Theme.bg
        border.width: 1
        border.color: Theme.ruleInk
        Accessible.role: Accessible.Grouping
        Accessible.name: qsTr("Appel en cours avec %1").arg(root.remoteName)
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }
        Rectangle { x: 0; y: 0; width: 4; height: parent.height; color: Theme.successColor }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 12
            spacing: 14
            ChatMonogram {
                size: 32
                label: root.remoteName
                machine: !root.remotePeer || People.personOf(root.remotePeer, root.users).length === 0
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                Text { Layout.fillWidth: true; text: root.remoteName; color: Theme.ink; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(14); font.weight: Theme.weightBold; elide: Text.ElideRight }
                Text {
                    Layout.fillWidth: true
                    textFormat: Text.StyledText
                    elide: Text.ElideRight
                    text: callBar.ending ? qsTr("Fin de l'appel…")
                          : (root.remotePeer && People.personOf(root.remotePeer, root.users).length ? root.esc(root.remotePeer.machine) + " · " : "")
                            + (root.muted ? "<b><font color=\"" + Theme.warningInk + "\">" + qsTr("micro coupé") + "</font></b>" : qsTr("micro actif"))
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
            BarButton { iconOnly: true; tip: qsTr("Agrandir"); iconPath: Icons.maximize; enabled: !callBar.ending; onClicked: root.expanded = true }
            BarButton {
                text: qsTr("Raccrocher")
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
    // Avis de fin d'appel
    // ======================================================================
    Rectangle {
        id: note
        visible: root.noteKind.length > 0 && !root.inCall
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.horizontalCenterOffset: root.leftInset / 2
        y: root.height - height - 22
        width: Math.min(noteRow.implicitWidth + 32, root.width - root.leftInset - 32)
        height: noteRow.implicitHeight + 22
        radius: Theme.radiusSheet
        color: Theme.bg
        border.width: 1
        border.color: Theme.ruleInk
        Rectangle { width: 3; height: parent.height; color: root.noteKind === "ended" ? Theme.ruleInk : Theme.dangerColor }
        RowLayout {
            id: noteRow
            anchors.verticalCenter: parent.verticalCenter
            x: 16
            width: parent.width - 26
            spacing: 12
            LineIcon { path: root.noteKind === "ended" ? Icons.phoneLine : Icons.alertTriangle; size: 16; strokeWidth: 1.8; color: root.noteKind === "ended" ? Theme.ink2 : Theme.dangerInk }
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
