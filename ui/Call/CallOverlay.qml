import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import "../Components"

/*
 * CallOverlay - carte d'appel en cours (calling/ringing/connecting/
 * connected/ending), affichee en superposition (fond assombri) par-dessus
 * l'ecran actif, quel qu'il soit (Dashboard, Discussions, ...).
 *
 * Extrait de l'ancien CallView (qui poussait tout l'ecran "Appels" dans le
 * StackView des qu'un appel demarrait, masquant le Dashboard). Desormais
 * instancie une seule fois au niveau de Main.qml, comme ToastHost, et
 * visible tant que callContext.callState !== "idle" - aussi bien pour
 * l'appelant (callState "calling") que pour le destinataire (callState
 * "ringing"), sans quitter l'ecran sur lequel chacun se trouve.
 *
 * L'ecran "Appels" (CallView, contacts + historique) reste accessible via
 * le menu, mais ne gere plus l'affichage de l'appel en cours.
 */
Item {
    id: root

    property var call: (typeof callContext !== "undefined") ? callContext : null
    property var peers: (typeof peersModel !== "undefined") ? peersModel : null

    readonly property string callState: root.call ? root.call.callState : "idle"
    readonly property bool inCall: root.callState !== "idle"

    readonly property color blue600: Theme.accentColor

    FontLoader {
        id: iconFont
        source: "../Assets/fonts/fontawesome-webfont.ttf"
    }
    readonly property string iconFontFamily: iconFont.name

    // Nom affiche pour le correspondant courant (voir CallView pour le
    // detail du repli sur l'adresse IP brute).
    readonly property string remoteDisplayName: {
        const addr = root.call ? root.call.remoteAddress : ""
        if (!addr)
            return ""
        const _dep = root.peers ? root.peers.count : 0
        const resolved = root.peers ? root.peers.nameForAddress(addr) : ""
        return (resolved && resolved.length > 0) ? resolved : addr
    }

    property int connectedSeconds: 0
    Timer {
        interval: 1000
        repeat: true
        running: root.callState === "connected"
        onTriggered: root.connectedSeconds++
    }
    onCallStateChanged: if (callState !== "connected") root.connectedSeconds = 0

    function formatElapsed(seconds) {
        const m = Math.floor(seconds / 60)
        const s = seconds % 60
        return (m < 10 ? "0" + m : m) + ":" + (s < 10 ? "0" + s : s)
    }

    // Banniere d'erreur discrete (appel refuse, perte de connexion...).
    Rectangle {
        id: errorBanner
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: errorLabel.implicitHeight + Theme.spacingMedium
        color: Theme.error
        visible: opacity > 0
        opacity: 0
        z: 30

        Behavior on opacity { NumberAnimation { duration: 150 } }

        Label {
            id: errorLabel
            anchors.centerIn: parent
            width: parent.width - Theme.spacingLarge * 2
            color: Theme.inkOnDanger
            font.pixelSize: Theme.fontSizeSmall
            font.family: Theme.fontFamily
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }

        Timer {
            id: hideErrorTimer
            interval: 4000
            onTriggered: errorBanner.opacity = 0
        }

        function show(message) {
            errorLabel.text = message
            opacity = 1
            hideErrorTimer.restart()
        }
    }

    Connections {
        target: root.call
        function onErrorOccurred(message) { errorBanner.show(message) }
        function onCallEnded(reason) {
            if (reason === "connection-lost") {
                errorBanner.show(qsTr("Connexion perdue avec le correspondant."))
            }
        }
    }

    readonly property int callCardWidth: Math.min(380, root.width - Theme.spacingLarge * 2)

    Rectangle {
        id: backdrop
        anchors.fill: parent
        color: Theme.overlay
        visible: opacity > 0
        opacity: root.inCall ? 1 : 0
        z: 20

        Behavior on opacity { NumberAnimation { duration: 150 } }

        // Avale les clics pour ne pas interagir avec l'ecran derriere.
        MouseArea { anchors.fill: parent }
    }

    Rectangle {
        id: callCard
        anchors.centerIn: parent
        width: root.callCardWidth
        height: callCardColumn.implicitHeight + Theme.spacingXl * 2
        radius: Theme.radiusLarge
        color: Theme.surface
        border.width: 1
        border.color: Theme.border
        visible: opacity > 0
        opacity: root.inCall ? 1 : 0
        scale: root.inCall ? 1 : 0.94
        z: 21

        Behavior on opacity { NumberAnimation { duration: 180 } }
        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

        ColumnLayout {
            id: callCardColumn
            width: parent.width - Theme.spacingXl * 2
            anchors.centerIn: parent
            spacing: Theme.spacingMedium

            // ---- Avatar avec anneaux de pulsation --------------------------
            Item {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 132
                Layout.preferredHeight: 132

                Repeater {
                    model: (root.callState === "calling" || root.callState === "ringing"
                            || root.callState === "connecting") ? 2 : 0

                    delegate: Rectangle {
                        anchors.centerIn: parent
                        width: 96
                        height: 96
                        radius: 48
                        color: "transparent"
                        border.width: 2
                        border.color: root.blue600

                        SequentialAnimation on opacity {
                            loops: Animation.Infinite
                            PauseAnimation { duration: index * 600 }
                            NumberAnimation { from: 0.55; to: 0; duration: 1400; easing.type: Easing.OutQuad }
                        }
                        SequentialAnimation on scale {
                            loops: Animation.Infinite
                            PauseAnimation { duration: index * 600 }
                            NumberAnimation { from: 1; to: 1.5; duration: 1400; easing.type: Easing.OutQuad }
                        }
                    }
                }

                Avatar {
                    anchors.centerIn: parent
                    size: 96
                    name: root.remoteDisplayName
                }
            }

            Label {
                Layout.alignment: Qt.AlignHCenter
                text: root.remoteDisplayName
                color: Theme.text
                font.pixelSize: Theme.fontSizeHeading
                font.bold: true
                font.family: Theme.fontFamily
            }

            Label {
                Layout.alignment: Qt.AlignHCenter
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeBody
                font.family: Theme.fontFamily
                text: {
                    switch (root.callState) {
                    case "calling":    return qsTr("Appel en cours…")
                    case "ringing":    return qsTr("Appel entrant")
                    case "connecting": return qsTr("Connexion…")
                    case "connected":  return root.formatElapsed(root.connectedSeconds)
                    case "ending":     return qsTr("Fin de l'appel…")
                    default:           return ""
                    }
                }
            }

            // ---- Appel entrant : accepter / refuser -------------------------
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: Theme.spacingSmall
                spacing: Theme.spacingLarge
                visible: root.callState === "ringing"

                CallActionButton {
                    glyph: "\uf095"
                    iconRotation: 135
                    label: qsTr("Refuser")
                    bgColor: Theme.dangerColor
                    iconColor: Theme.inkOnDanger
                    onClicked: root.call && root.call.hangUp()
                }

                CallActionButton {
                    glyph: "\uf095"
                    label: qsTr("Répondre")
                    bgColor: Theme.successColor
                    iconColor: Theme.inkOnSuccess
                    diameter: 64
                    onClicked: root.call && root.call.acceptCall()
                }
            }

            // ---- Appel sortant / en negociation : annuler --------------------
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: Theme.spacingSmall
                spacing: Theme.spacingLarge
                visible: root.callState === "calling" || root.callState === "connecting"

                CallActionButton {
                    glyph: "\uf095"
                    iconRotation: 135
                    label: qsTr("Annuler")
                    bgColor: Theme.dangerColor
                    iconColor: Theme.inkOnDanger
                    diameter: 64
                    onClicked: root.call && root.call.hangUp()
                }
            }

            // ---- Appel etabli : mute + raccrocher -----------------------------
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: Theme.spacingSmall
                spacing: Theme.spacingLarge
                visible: root.callState === "connected"

                CallActionButton {
                    glyph: root.call && root.call.muted ? "\uf131" : "\uf130"
                    label: root.call && root.call.muted ? qsTr("Réactiver le micro") : qsTr("Couper le micro")
                    bgColor: root.call && root.call.muted ? Theme.warningColor : Theme.sunken
                    iconColor: root.call && root.call.muted ? Theme.accentInk : Theme.ink
                    onClicked: root.call && root.call.toggleMute()
                }

                CallActionButton {
                    glyph: "\uf095"
                    iconRotation: 135
                    label: qsTr("Raccrocher")
                    bgColor: Theme.dangerColor
                    iconColor: Theme.inkOnDanger
                    diameter: 64
                    onClicked: root.call && root.call.hangUp()
                }
            }
        }
    }

    // Bouton d'action rond (raccrocher/decrocher/mute...) avec libelle.
    // AbstractButton : utilisable au clavier (Tab, Espace/Entree) et
    // annonce par son libelle aux lecteurs d'ecran.
    component CallActionButton: ColumnLayout {
        id: actionBtn

        property string glyph: ""
        property string label: ""
        property color bgColor: Theme.accentColor
        property color iconColor: Theme.accentInk
        property int diameter: 56
        property real iconRotation: 0

        signal clicked()

        spacing: Theme.spacingXs

        AbstractButton {
            id: btn
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: actionBtn.diameter
            implicitHeight: actionBtn.diameter
            hoverEnabled: true
            focusPolicy: Qt.StrongFocus
            Accessible.name: actionBtn.label
            onClicked: actionBtn.clicked()

            HoverHandler { cursorShape: Qt.PointingHandCursor }

            background: Rectangle {
                radius: width / 2
                color: btn.down ? Qt.darker(actionBtn.bgColor, 1.15)
                       : (btn.hovered ? Qt.lighter(actionBtn.bgColor, 1.08) : actionBtn.bgColor)

                Behavior on color { ColorAnimation { duration: Theme.durationFast } }

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -4
                    radius: width / 2
                    color: "transparent"
                    border.width: 2
                    border.color: Theme.focusRing
                    visible: btn.visualFocus
                }
            }

            contentItem: Text {
                text: actionBtn.glyph
                color: actionBtn.iconColor
                font.family: root.iconFontFamily
                font.pixelSize: actionBtn.diameter * 0.34
                rotation: actionBtn.iconRotation
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: actionBtn.label
            color: Theme.ink2
            font.pixelSize: Theme.fs(12)
            font.family: Theme.fontFamily
            visible: actionBtn.label.length > 0
        }
    }
}
