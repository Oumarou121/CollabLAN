import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes

/*
 * CallView - ecran d'appel vocal P2P, fusionnant l'ancien duo
 * CallView / CallHistoryView (issues #60/#61/#64) en une seule vue de
 * type "application telephone" :
 *
 *  - un en-tete avec un selecteur a deux onglets, "Contacts" (postes du
 *    reseau local a appeler, reutilise "peersModel") et "Recents"
 *    (historique persiste en base, "callHistoryModel", voir
 *    core::CallHistoryManager / database::CallHistoryRepository) ;
 *  - un panneau plein ecran, superpose aux deux onglets, refletant l'etat
 *    d'appel en cours (calling/ringing/connecting/connected/ending) avec
 *    les actions pertinentes, dans un style proche des ecrans d'appel
 *    mobiles (avatar avec anneaux de pulsation, boutons ronds).
 *
 * S'appuie, comme avant, sur les contextes QML globaux "callContext"
 * (core::CallContext) et "peersModel" / "callHistoryModel", exposes
 * depuis app/main.cpp.
 */
Item {
    id: root

    // Proprietes optionnelles : permettent de charger cette vue dans un
    // contexte de preview/design sans que les contextes globaux existent.
    property var call: (typeof callContext !== "undefined") ? callContext : null
    property var peers: (typeof peersModel !== "undefined") ? peersModel : null
    property var history: (typeof callHistoryModel !== "undefined") ? callHistoryModel : null

    readonly property string callState: root.call ? root.call.callState : "idle"
    readonly property bool inCall: root.callState !== "idle"

    // Onglet initial ("contacts" ou "recents") : permet a Main.qml
    // d'ouvrir directement sur l'historique depuis l'entree de menu
    // dediee, sans dupliquer l'ecran.
    property string initialTab: "contacts"
    property int activeTab: initialTab === "recents" ? 1 : 0

    signal backRequested()

    // ---- Historique : formatage / libelles (inchange fonctionnellement) --
    function statusLabel(status) {
        switch (status) {
        case "completed": return qsTr("Termine")
        case "missed": return qsTr("Manque")
        case "rejected": return qsTr("Refuse")
        case "cancelled": return qsTr("Annule")
        case "failed": return qsTr("Echoue")
        default: return qsTr("En cours")
        }
    }

    function statusColor(status) {
        switch (status) {
        case "completed": return Theme.success
        case "missed": return Theme.error
        case "rejected": return Theme.error
        case "cancelled": return Theme.textSecondary
        case "failed": return Theme.error
        default: return Theme.primary
        }
    }

    // Icone directionnelle façon "recents" mobile : fleche pleine, coloree
    // en rouge quand l'appel a ete manque, pour un reperage immediat.
    function directionArrow(direction) {
        return direction === "outgoing" ? "\u2197" : "\u2199"
    }

    function formatDuration(seconds) {
        if (seconds === undefined || seconds === null || seconds < 0)
            return ""
        const m = Math.floor(seconds / 60)
        const s = seconds % 60
        return (m > 0 ? (m + " min ") : "") + s + " s"
    }

    function formatElapsed(seconds) {
        const m = Math.floor(seconds / 60)
        const s = seconds % 60
        return (m < 10 ? "0" + m : m) + ":" + (s < 10 ? "0" + s : s)
    }

    function formatDate(isoString) {
        if (!isoString)
            return ""
        const d = new Date(isoString)
        const now = new Date()
        const sameDay = d.toDateString() === now.toDateString()
        return sameDay ? d.toLocaleString(Qt.locale(), "HH:mm")
                       : d.toLocaleString(Qt.locale(), "dd/MM/yyyy HH:mm")
    }

    // Duree ecoulee affichee pendant un appel en cours (issue design :
    // aucun compteur en direct auparavant).
    property int connectedSeconds: 0
    Timer {
        interval: 1000
        repeat: true
        running: root.callState === "connected"
        onTriggered: root.connectedSeconds++
    }
    onCallStateChanged: if (callState !== "connected") root.connectedSeconds = 0

    Rectangle {
        anchors.fill: parent
        color: Theme.background
    }

    // Banniere d'erreur discrete (adresse invalide, appel refuse par le
    // service, perte de connexion...), auto-masquee apres quelques secondes.
    Rectangle {
        id: errorBanner
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: errorLabel.implicitHeight + Theme.spacingMedium
        color: Theme.error
        visible: opacity > 0
        opacity: 0
        z: 10

        Behavior on opacity { NumberAnimation { duration: 150 } }

        Label {
            id: errorLabel
            anchors.centerIn: parent
            width: parent.width - Theme.spacingLarge * 2
            color: "#FFFFFF"
            font.pixelSize: Theme.fontSizeSmall
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

    // ======================================================================
    // Ecran hors appel : Contacts / Recents
    // ======================================================================
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacingLarge
        spacing: Theme.spacingMedium
        visible: !root.inCall

        // ---- En-tete ------------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSmall

            Button {
                text: qsTr("< Retour")
                Layout.preferredHeight: 32

                background: Rectangle {
                    radius: Theme.radiusSmall
                    color: parent.hovered ? Theme.surfaceAlt : "transparent"
                    border.width: 1
                    border.color: Theme.border
                }

                contentItem: Text {
                    text: qsTr("< Retour")
                    color: Theme.text
                    font.pixelSize: Theme.fontSizeSmall
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                onClicked: root.backRequested()
            }

            Label {
                text: qsTr("Appels")
                font.pixelSize: Theme.fontSizeHeading
                font.bold: true
                font.family: Theme.fontFamily
                color: Theme.text
            }

            Item { Layout.fillWidth: true }

            // Bouton d'actualisation de l'historique, visible seulement
            // sur l'onglet "Recents" (l'onglet Contacts se rafraichit
            // automatiquement via peersModel).
            Rectangle {
                Layout.preferredWidth: 30
                Layout.preferredHeight: 30
                radius: 15
                visible: root.activeTab === 1
                color: refreshArea.containsMouse ? Theme.surfaceAlt : "transparent"
                border.width: 1
                border.color: Theme.border

                Text {
                    anchors.centerIn: parent
                    text: "\u27F3"
                    color: Theme.textSecondary
                    font.pixelSize: 15
                }

                MouseArea {
                    id: refreshArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (root.history) root.history.refresh()
                }

                ToolTip.visible: refreshArea.containsMouse
                ToolTip.delay: 400
                ToolTip.text: qsTr("Actualiser")
            }
        }

        // ---- Selecteur d'onglets (segmented control) -----------------------
        Rectangle {
            Layout.preferredWidth: 260
            Layout.preferredHeight: 40
            Layout.alignment: Qt.AlignHCenter
            radius: height / 2
            color: Theme.surfaceAlt
            border.width: 1
            border.color: Theme.border

            Rectangle {
                id: tabIndicator
                width: parent.width / 2 - 4
                height: parent.height - 4
                anchors.verticalCenter: parent.verticalCenter
                x: root.activeTab === 0 ? 2 : parent.width / 2 + 2
                radius: height / 2
                color: Theme.primary

                Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            }

            RowLayout {
                anchors.fill: parent
                spacing: 0

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    Label {
                        anchors.centerIn: parent
                        text: qsTr("Contacts")
                        font.pixelSize: Theme.fontSizeSmall
                        font.bold: true
                        color: root.activeTab === 0 ? Theme.primaryText : Theme.textSecondary
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.activeTab = 0
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    Label {
                        anchors.centerIn: parent
                        text: qsTr("Recents")
                        font.pixelSize: Theme.fontSizeSmall
                        font.bold: true
                        color: root.activeTab === 1 ? Theme.primaryText : Theme.textSecondary
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.activeTab = 1
                    }
                }
            }
        }

        // ---- Contenu de l'onglet actif -------------------------------------
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Theme.radiusLarge
            color: Theme.surface
            border.color: Theme.border
            border.width: 1
            clip: true

            // -- Onglet Contacts : postes du reseau local a appeler ---------
            Item {
                anchors.fill: parent
                visible: root.activeTab === 0

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: Theme.spacingSmall
                    visible: contactsListView.count === 0
                    width: parent.width * 0.7

                    Label {
                        Layout.alignment: Qt.AlignHCenter
                        text: qsTr("Aucun poste detecte pour le moment")
                        font.pixelSize: Theme.fontSizeBody
                        font.bold: true
                        color: Theme.text
                        horizontalAlignment: Text.AlignHCenter
                    }

                    Label {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.fillWidth: true
                        text: qsTr("Choisissez un poste des que quelqu'un est detecte pour l'appeler.")
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeSmall
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                    }
                }

                ListView {
                    id: contactsListView
                    anchors.fill: parent
                    anchors.margins: Theme.spacingSmall
                    spacing: Theme.spacingSmall
                    clip: true
                    model: root.peers

                    delegate: Rectangle {
                        width: contactsListView.width
                        height: 64
                        radius: Theme.radiusMedium
                        color: contactArea.containsMouse ? Theme.surfaceHover : Theme.surfaceAlt

                        Behavior on color { ColorAnimation { duration: 100 } }

                        MouseArea {
                            id: contactArea
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.NoButton
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.spacingMedium
                            anchors.rightMargin: Theme.spacingMedium
                            spacing: Theme.spacingMedium

                            Rectangle {
                                width: 42
                                height: 42
                                radius: 21
                                color: Theme.colorForName(name)

                                Text {
                                    anchors.centerIn: parent
                                    text: name && name.length > 0 ? name.charAt(0).toUpperCase() : "?"
                                    color: "#FFFFFF"
                                    font.pixelSize: 16
                                    font.bold: true
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                Label {
                                    text: name
                                    color: Theme.text
                                    font.pixelSize: Theme.fontSizeBody
                                    font.bold: true
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }

                                Label {
                                    text: address + " \u00B7 " + qsTr("port %1").arg(signalingPort)
                                    color: Theme.textSecondary
                                    font.pixelSize: Theme.fontSizeSmall
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                            }

                            Rectangle {
                                width: 40
                                height: 40
                                radius: 20
                                color: !root.call ? Theme.surfaceAlt
                                       : (callBtnArea.containsMouse ? Theme.primaryHover : Theme.primary)
                                opacity: root.call ? 1 : 0.5

                                Behavior on color { ColorAnimation { duration: 100 } }

                                Text {
                                    anchors.centerIn: parent
                                    text: "\u260E"
                                    color: root.call ? Theme.primaryText : Theme.textSecondary
                                    font.pixelSize: 17
                                }

                                MouseArea {
                                    id: callBtnArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    enabled: root.call !== null
                                    onClicked: {
                                        console.log("CallView: Appel vers", address, "sur port", signalingPort)
                                        if (!root.call.call(address, signalingPort)) {
                                            errorBanner.show(qsTr("Impossible d'appeler %1").arg(name))
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // -- Onglet Recents : historique des appels ----------------------
            Item {
                anchors.fill: parent
                visible: root.activeTab === 1

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: Theme.spacingSmall
                    visible: recentsListView.count === 0
                    width: parent.width * 0.7

                    Label {
                        Layout.alignment: Qt.AlignHCenter
                        text: qsTr("Aucun appel dans l'historique")
                        font.pixelSize: Theme.fontSizeBody
                        font.bold: true
                        color: Theme.text
                        horizontalAlignment: Text.AlignHCenter
                    }

                    Label {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.fillWidth: true
                        text: qsTr("Vos appels emis et recus apparaitront ici automatiquement.")
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeSmall
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                    }
                }

                ListView {
                    id: recentsListView
                    anchors.fill: parent
                    anchors.margins: Theme.spacingSmall
                    spacing: Theme.spacingSmall
                    clip: true
                    model: root.history

                    delegate: Rectangle {
                        width: recentsListView.width
                        height: 64
                        radius: Theme.radiusMedium
                        color: Theme.surfaceAlt

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.spacingMedium
                            anchors.rightMargin: Theme.spacingMedium
                            spacing: Theme.spacingMedium

                            // Avatar avec badge directionnel superpose,
                            // comme dans un journal d'appels mobile.
                            Item {
                                width: 42
                                height: 42

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 21
                                    color: Theme.colorForName((peerName && peerName.length > 0) ? peerName : peerAddress)

                                    Text {
                                        anchors.centerIn: parent
                                        text: (peerName && peerName.length > 0)
                                              ? peerName.charAt(0).toUpperCase()
                                              : (peerAddress && peerAddress.length > 0 ? peerAddress.charAt(0).toUpperCase() : "?")
                                        color: "#FFFFFF"
                                        font.pixelSize: 16
                                        font.bold: true
                                    }
                                }

                                Rectangle {
                                    width: 18
                                    height: 18
                                    radius: 9
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    anchors.margins: -2
                                    color: root.statusColor(status)
                                    border.width: 2
                                    border.color: Theme.surfaceAlt

                                    Text {
                                        anchors.centerIn: parent
                                        text: root.directionArrow(direction)
                                        color: "#FFFFFF"
                                        font.pixelSize: 9
                                        font.bold: true
                                    }
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                Label {
                                    text: (peerName && peerName.length > 0) ? peerName : peerAddress
                                    color: status === "missed" ? Theme.error : Theme.text
                                    font.pixelSize: Theme.fontSizeBody
                                    font.bold: true
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }

                                Label {
                                    text: root.statusLabel(status)
                                           + (durationSeconds >= 0 ? (" \u2022 " + root.formatDuration(durationSeconds)) : "")
                                    color: Theme.textSecondary
                                    font.pixelSize: Theme.fontSizeSmall
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                            }

                            Label {
                                text: root.formatDate(startedAt)
                                color: Theme.textTertiary
                                font.pixelSize: Theme.fontSizeCaption
                            }
                        }
                    }
                }
            }
        }
    }

    // ======================================================================
    // Panneau plein ecran pendant un appel
    // ======================================================================
    Item {
        anchors.fill: parent
        visible: root.inCall

        ColumnLayout {
            anchors.fill: parent
            anchors.topMargin: Theme.spacingXl
            anchors.bottomMargin: Theme.spacingXl * 1.5
            spacing: Theme.spacingLarge

            Item { Layout.fillHeight: true; Layout.preferredHeight: 1 }

            // ---- Avatar avec anneaux de pulsation --------------------------
            Item {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 168
                Layout.preferredHeight: 168

                Repeater {
                    model: (root.callState === "calling" || root.callState === "ringing"
                            || root.callState === "connecting") ? 2 : 0

                    delegate: Rectangle {
                        anchors.centerIn: parent
                        width: 128
                        height: 128
                        radius: 64
                        color: "transparent"
                        border.width: 2
                        border.color: Theme.primary

                        SequentialAnimation on opacity {
                            loops: Animation.Infinite
                            PauseAnimation { duration: index * 600 }
                            NumberAnimation { from: 0.55; to: 0; duration: 1600; easing.type: Easing.OutQuad }
                        }
                        SequentialAnimation on scale {
                            loops: Animation.Infinite
                            PauseAnimation { duration: index * 600 }
                            NumberAnimation { from: 1; to: 1.55; duration: 1600; easing.type: Easing.OutQuad }
                        }
                    }
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: 128
                    height: 128
                    radius: 64
                    color: root.call ? Theme.colorForName(root.call.remoteAddress) : Theme.primary

                    Text {
                        anchors.centerIn: parent
                        text: root.call && root.call.remoteAddress.length > 0
                              ? root.call.remoteAddress.charAt(0).toUpperCase() : "?"
                        color: "#FFFFFF"
                        font.pixelSize: 44
                        font.bold: true
                    }
                }
            }

            Label {
                Layout.alignment: Qt.AlignHCenter
                text: root.call ? root.call.remoteAddress : ""
                color: Theme.text
                font.pixelSize: Theme.fontSizeTitle
                font.bold: true
                font.family: Theme.fontFamily
            }

            Label {
                Layout.alignment: Qt.AlignHCenter
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeBody
                text: {
                    switch (root.callState) {
                    case "calling":    return qsTr("Appel en cours...")
                    case "ringing":    return qsTr("Appel entrant")
                    case "connecting": return qsTr("Connexion...")
                    case "connected":  return root.formatElapsed(root.connectedSeconds)
                    case "ending":     return qsTr("Fin de l'appel...")
                    default:           return ""
                    }
                }
            }

            Item { Layout.fillHeight: true; Layout.preferredHeight: 1 }

            // ---- Appel entrant : accepter / refuser -------------------------
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: Theme.spacingXl
                visible: root.callState === "ringing"

                CallActionButton {
                    icon: "\u260E"
                    iconRotation: 135
                    label: qsTr("Refuser")
                    bgColor: Theme.error
                    onClicked: root.call && root.call.hangUp()
                }

                CallActionButton {
                    icon: "\u260E"
                    label: qsTr("Repondre")
                    bgColor: Theme.success
                    diameter: 72
                    onClicked: root.call && root.call.acceptCall()
                }
            }

            // ---- Appel sortant / en negociation : annuler --------------------
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: Theme.spacingXl
                visible: root.callState === "calling" || root.callState === "connecting"

                CallActionButton {
                    icon: "\u260E"
                    iconRotation: 135
                    label: qsTr("Annuler")
                    bgColor: Theme.error
                    diameter: 72
                    onClicked: root.call && root.call.hangUp()
                }
            }

            // ---- Appel etabli : mute + raccrocher -----------------------------
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: Theme.spacingXl
                visible: root.callState === "connected"

                CallActionButton {
                    icon: root.call && root.call.muted ? "\u2298" : "\u25CF"
                    label: root.call && root.call.muted ? qsTr("Reactiver") : qsTr("Muet")
                    bgColor: root.call && root.call.muted ? Theme.warning : Theme.surfaceAlt
                    iconColor: root.call && root.call.muted ? Theme.primaryText : Theme.text
                    onClicked: root.call && root.call.toggleMute()
                }

                CallActionButton {
                    icon: "\u260E"
                    iconRotation: 135
                    label: qsTr("Raccrocher")
                    bgColor: Theme.error
                    diameter: 72
                    onClicked: root.call && root.call.hangUp()
                }
            }

            Item { Layout.fillHeight: true; Layout.preferredHeight: 1 }
        }
    }

    // Bouton d'action rond (raccrocher/decrocher/mute...) avec libelle,
    // dans l'esprit des ecrans d'appel des applications mobiles.
    component CallActionButton: ColumnLayout {
        id: actionBtn

        property string icon: ""
        property string label: ""
        property color bgColor: Theme.primary
        property color iconColor: "#FFFFFF"
        property int diameter: 64
        property real iconRotation: 0

        signal clicked()

        spacing: Theme.spacingXs

        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            width: actionBtn.diameter
            height: actionBtn.diameter
            radius: width / 2
            color: btnArea.pressed ? Qt.darker(actionBtn.bgColor, 1.15)
                   : (btnArea.containsMouse ? Qt.lighter(actionBtn.bgColor, 1.08) : actionBtn.bgColor)

            Behavior on color { ColorAnimation { duration: 100 } }

            Text {
                anchors.centerIn: parent
                text: actionBtn.icon
                color: actionBtn.iconColor
                font.pixelSize: actionBtn.diameter * 0.38
                rotation: actionBtn.iconRotation
            }

            MouseArea {
                id: btnArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: actionBtn.clicked()
            }
        }

        Label {
            Layout.alignment: Qt.AlignHCenter
            text: actionBtn.label
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSizeSmall
            visible: actionBtn.label.length > 0
        }
    }
}
