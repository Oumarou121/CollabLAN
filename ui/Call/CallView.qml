import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import "../Components"

/*
 * CallView - ecran d'appel vocal P2P, fusionnant l'ancien duo
 * CallView / CallHistoryView (issues #60/#61/#64) en une seule vue.
 *
 * Refonte design (juillet 2026) : alignement complet sur le style
 * "portail corporate" deja retenu pour Login/Home/Parametres/Discussions/
 * Postes connectes -- barre superieure identique (bouton retour circulaire
 * + titre + badge), contenu centre a largeur maximale, police d'icones
 * Font Awesome 4.7.0 (au lieu des glyphes Unicode "systeme"), composant
 * Avatar partage (au lieu de cercles dessines a la main), et memes seuils
 * de grille que Postes connectes/Home (900 / 560) pour un rendu coherent
 * sur les differentes resolutions/tailles de fenetre desktop.
 *
 * Pense pour du desktop grand ecran plutot que pour un layout mobile :
 *  - Contacts (postes du reseau local a appeler, "peersModel") et Recents
 *    (historique persiste en base, "callHistoryModel", voir
 *    core::CallHistoryManager / database::CallHistoryRepository) sont
 *    affiches simultanement, cote a cote, plutot que derriere un
 *    selecteur d'onglets. En dessous de 900px de large (meme seuil que
 *    la grille de Postes connectes), les deux panneaux s'empilent ;
 *  - un appel en cours (calling/ringing/connecting/connected/ending) est
 *    represente par une carte compacte centree, superposee (avec fond
 *    assombri) a la liste plutot que par un ecran plein ecran : evite un
 *    grand vide sur les moniteurs larges, a la maniere d'un softphone de
 *    bureau (Teams/Skype). Sa largeur s'adapte aussi aux petites fenetres.
 *
 * S'appuie, comme avant, sur les contextes QML globaux "callContext"
 * (core::CallContext) et "peersModel" / "callHistoryModel", exposes
 * depuis app/main.cpp. API publique (proprietes/signaux) inchangee.
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

    signal backRequested()

    // ---- Jetons locaux "portail corporate", alignes sur LoginView/
    // HomeView/DashboardCard (meme palette navy dans toute l'app). ----
    readonly property color blue700: Theme.darkMode ? "#3E6C99" : "#1E3A5F"
    readonly property color blue600: Theme.darkMode ? "#4E86B8" : "#2E6BAA"
    readonly property color blueTint: Theme.darkMode ? "#1B2531" : "#E8F1F9"

    // Police d'icones Font Awesome 4.7.0, memes glyphes que Home/Postes
    // connectes/Discussions - pour un rendu monochrome coherent d'un
    // ecran a l'autre au lieu des glyphes Unicode "systeme".
    FontLoader {
        id: iconFont
        source: "../Assets/fonts/fontawesome-webfont.ttf"
    }
    readonly property string iconFontFamily: iconFont.name

    // ---- Historique : formatage / libelles --------------------------------
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

    // Icone directionnelle (fleche pleine Font Awesome, rotation appliquee
    // au rendu) : sortant = vers le haut/droite, entrant = vers le bas/gauche.
    function directionGlyph(direction) {
        return direction === "outgoing" ? "\uf062" : "\uf063"
    }
    function directionRotation(direction) {
        return direction === "outgoing" ? 45 : -45
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

    // Nom affiche pour le correspondant courant : core::CallContext ne
    // connait que l'adresse IP (remoteAddress), donc on resout le nom via
    // peersModel (network::PeersModel::nameForAddress) - celui-ci connait
    // les postes actuellement detectes sur le reseau local. Repli sur
    // l'adresse IP brute si le correspondant n'est pas (ou plus) dans la
    // liste des postes decouverts (ex. appel recu d'un poste deja perdu).
    readonly property string remoteDisplayName: {
        const addr = root.call ? root.call.remoteAddress : ""
        if (!addr)
            return ""
        // Force la reevaluation quand la liste de postes change (un
        // correspondant peut etre (re)decouvert pendant que la sonnerie
        // est deja affichee).
        const _dep = root.peers ? root.peers.count : 0
        const resolved = root.peers ? root.peers.nameForAddress(addr) : ""
        return (resolved && resolved.length > 0) ? resolved : addr
    }

    // Duree ecoulee affichee pendant un appel en cours.
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
        z: 30

        Behavior on opacity { NumberAnimation { duration: 150 } }

        Label {
            id: errorLabel
            anchors.centerIn: parent
            width: parent.width - Theme.spacingLarge * 2
            color: "#FFFFFF"
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

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ---- Barre superieure (identique au style Home/Parametres/
        // Postes connectes) : retour circulaire + titre + badge. ----------
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 64
            color: Theme.surface

            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: Theme.border
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.spacingMedium
                anchors.rightMargin: Theme.spacingMedium
                spacing: Theme.spacingMedium

                Rectangle {
                    Layout.preferredWidth: 36
                    Layout.preferredHeight: 36
                    radius: Theme.radiusMedium
                    color: callBackArea.containsMouse ? Theme.surfaceHover : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "\u2190"
                        color: Theme.text
                        font.pixelSize: 18
                    }

                    MouseArea {
                        id: callBackArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.backRequested()
                    }
                }

                Rectangle {
                    Layout.preferredWidth: 36
                    Layout.preferredHeight: 36
                    radius: Theme.radiusMedium
                    color: root.blueTint

                    Text {
                        anchors.centerIn: parent
                        text: "\uf095"
                        font.family: root.iconFontFamily
                        font.pixelSize: 15
                        color: root.blue700
                    }
                }

                Label {
                    text: qsTr("Appels")
                    font.pixelSize: Theme.fontSizeSubheading
                    font.bold: true
                    font.family: Theme.fontFamily
                    color: Theme.text
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    Layout.preferredWidth: peersCountLabel.implicitWidth + Theme.spacingMedium * 2
                    Layout.preferredHeight: 28
                    radius: height / 2
                    color: Theme.surfaceAlt
                    border.color: Theme.border
                    border.width: 1

                    Label {
                        id: peersCountLabel
                        anchors.centerIn: parent
                        text: root.peers ? qsTr("%n poste(s) en ligne", "", root.peers.count) : qsTr("0 poste")
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeSmall
                        font.family: Theme.fontFamily
                    }
                }
            }
        }

        // ---- Contenu principal : deux panneaux, centres a largeur
        // maximale (memes seuils que la grille de Postes connectes). ------
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ColumnLayout {
                id: contentColumn
                width: Math.min(parent.width - 2 * Theme.spacingXl, 1200)
                height: parent.height - 2 * Theme.spacingLarge
                x: (parent.width - width) / 2
                y: Theme.spacingLarge
                spacing: 0

                GridLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    // Seuil aligne sur la grille de Postes connectes : deux
                    // panneaux cote a cote par defaut, empiles en dessous
                    // de 900px de large.
                    columns: contentColumn.width > 900 ? 2 : 1
                    columnSpacing: Theme.spacingMedium
                    rowSpacing: Theme.spacingMedium

                    // ================================================
                    // Panneau Contacts
                    // ================================================
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: Theme.radiusLarge
                        color: Theme.surface
                        border.color: Theme.border
                        border.width: 1
                        clip: true

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: Theme.spacingMedium
                            spacing: Theme.spacingSmall

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.leftMargin: Theme.spacingXs
                                Layout.topMargin: Theme.spacingXs
                                spacing: Theme.spacingMedium

                                Rectangle {
                                    Layout.preferredWidth: 32
                                    Layout.preferredHeight: 32
                                    radius: Theme.radiusMedium
                                    color: Theme.primaryMuted

                                    Text {
                                        anchors.centerIn: parent
                                        text: "\uf0c0"
                                        font.family: root.iconFontFamily
                                        font.pixelSize: 13
                                        color: Theme.primary
                                    }
                                }

                                Label {
                                    text: qsTr("Contacts")
                                    font.pixelSize: Theme.fontSizeSubheading
                                    font.bold: true
                                    font.family: Theme.fontFamily
                                    color: Theme.text
                                }

                                Item { Layout.fillWidth: true }

                                Label {
                                    text: root.peers ? qsTr("%n poste(s)", "", root.peers.count) : ""
                                    color: Theme.textSecondary
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.family: Theme.fontFamily
                                }
                            }

                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true

                                ColumnLayout {
                                    anchors.centerIn: parent
                                    spacing: Theme.spacingSmall
                                    visible: contactsListView.count === 0
                                    width: parent.width * 0.8

                                    Label {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: qsTr("Aucun poste detecte pour le moment")
                                        font.pixelSize: Theme.fontSizeBody
                                        font.bold: true
                                        font.family: Theme.fontFamily
                                        color: Theme.text
                                        horizontalAlignment: Text.AlignHCenter
                                    }

                                    Label {
                                        Layout.alignment: Qt.AlignHCenter
                                        Layout.fillWidth: true
                                        text: qsTr("Choisissez un poste des que quelqu'un est detecte pour l'appeler.")
                                        color: Theme.textSecondary
                                        font.pixelSize: Theme.fontSizeSmall
                                        font.family: Theme.fontFamily
                                        horizontalAlignment: Text.AlignHCenter
                                        wrapMode: Text.WordWrap
                                    }
                                }

                                ListView {
                                    id: contactsListView
                                    anchors.fill: parent
                                    spacing: Theme.spacingSmall
                                    clip: true
                                    model: root.peers

                                    delegate: Rectangle {
                                        width: contactsListView.width
                                        height: 64
                                        radius: Theme.radiusMedium
                                        color: contactArea.containsMouse ? Theme.surfaceHover : Theme.surfaceAlt
                                        border.width: 1
                                        border.color: Theme.border

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

                                            Avatar {
                                                name: name
                                                size: 42
                                                showStatus: true
                                                online: true
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 2

                                                Label {
                                                    text: name
                                                    color: Theme.text
                                                    font.pixelSize: Theme.fontSizeBody
                                                    font.bold: true
                                                    font.family: Theme.fontFamily
                                                    elide: Text.ElideRight
                                                    Layout.fillWidth: true
                                                }

                                                Label {
                                                    text: address + " \u00B7 " + qsTr("port %1").arg(signalingPort)
                                                    color: Theme.textSecondary
                                                    font.pixelSize: Theme.fontSizeSmall
                                                    font.family: Theme.fontFamily
                                                    elide: Text.ElideRight
                                                    Layout.fillWidth: true
                                                }
                                            }

                                            IconButton {
                                                glyph: "\uf095"
                                                variant: "primary"
                                                size: 40
                                                enabledLook: root.call !== null
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
                    }

                    // ================================================
                    // Panneau Recents
                    // ================================================
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: Theme.radiusLarge
                        color: Theme.surface
                        border.color: Theme.border
                        border.width: 1
                        clip: true

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: Theme.spacingMedium
                            spacing: Theme.spacingSmall

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.leftMargin: Theme.spacingXs
                                Layout.topMargin: Theme.spacingXs
                                spacing: Theme.spacingMedium

                                Rectangle {
                                    Layout.preferredWidth: 32
                                    Layout.preferredHeight: 32
                                    radius: Theme.radiusMedium
                                    color: Theme.primaryMuted

                                    Text {
                                        anchors.centerIn: parent
                                        text: "\uf1da"
                                        font.family: root.iconFontFamily
                                        font.pixelSize: 13
                                        color: Theme.primary
                                    }
                                }

                                Label {
                                    text: qsTr("Recents")
                                    font.pixelSize: Theme.fontSizeSubheading
                                    font.bold: true
                                    font.family: Theme.fontFamily
                                    color: Theme.text
                                }

                                Item { Layout.fillWidth: true }

                                IconButton {
                                    id: refreshHistoryButton
                                    glyph: "\uf021"
                                    variant: "ghost"
                                    size: 32
                                    onClicked: if (root.history) root.history.refresh()

                                    ToolTip.visible: refreshHistoryButton.hovered
                                    ToolTip.delay: 400
                                    ToolTip.text: qsTr("Actualiser")
                                }
                            }

                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true

                                ColumnLayout {
                                    anchors.centerIn: parent
                                    spacing: Theme.spacingSmall
                                    visible: recentsListView.count === 0
                                    width: parent.width * 0.8

                                    Label {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: qsTr("Aucun appel dans l'historique")
                                        font.pixelSize: Theme.fontSizeBody
                                        font.bold: true
                                        font.family: Theme.fontFamily
                                        color: Theme.text
                                        horizontalAlignment: Text.AlignHCenter
                                    }

                                    Label {
                                        Layout.alignment: Qt.AlignHCenter
                                        Layout.fillWidth: true
                                        text: qsTr("Vos appels emis et recus apparaitront ici automatiquement.")
                                        color: Theme.textSecondary
                                        font.pixelSize: Theme.fontSizeSmall
                                        font.family: Theme.fontFamily
                                        horizontalAlignment: Text.AlignHCenter
                                        wrapMode: Text.WordWrap
                                    }
                                }

                                ListView {
                                    id: recentsListView
                                    anchors.fill: parent
                                    spacing: Theme.spacingSmall
                                    clip: true
                                    model: root.history

                                    delegate: Rectangle {
                                        width: recentsListView.width
                                        height: 64
                                        radius: Theme.radiusMedium
                                        color: Theme.surfaceAlt
                                        border.width: 1
                                        border.color: Theme.border

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: Theme.spacingMedium
                                            anchors.rightMargin: Theme.spacingMedium
                                            spacing: Theme.spacingMedium

                                            // Avatar avec badge directionnel superpose.
                                            Item {
                                                Layout.preferredWidth: 42
                                                Layout.preferredHeight: 42

                                                Avatar {
                                                    anchors.fill: parent
                                                    name: (peerName && peerName.length > 0) ? peerName : peerAddress
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
                                                        text: root.directionGlyph(direction)
                                                        rotation: root.directionRotation(direction)
                                                        color: "#FFFFFF"
                                                        font.family: root.iconFontFamily
                                                        font.pixelSize: 8
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
                                                    font.family: Theme.fontFamily
                                                    elide: Text.ElideRight
                                                    Layout.fillWidth: true
                                                }

                                                Label {
                                                    text: root.statusLabel(status)
                                                           + (durationSeconds >= 0 ? (" \u2022 " + root.formatDuration(durationSeconds)) : "")
                                                    color: Theme.textSecondary
                                                    font.pixelSize: Theme.fontSizeSmall
                                                    font.family: Theme.fontFamily
                                                    elide: Text.ElideRight
                                                    Layout.fillWidth: true
                                                }
                                            }

                                            Label {
                                                text: root.formatDate(startedAt)
                                                color: Theme.textTertiary
                                                font.pixelSize: Theme.fontSizeCaption
                                                font.family: Theme.fontFamily
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ======================================================================
    // Appel en cours : fond assombri + carte compacte centree (pas de
    // plein ecran, pour rester ergonomique sur un grand moniteur). Largeur
    // adaptee aux petites fenetres via callCardWidth.
    // ======================================================================
    readonly property int callCardWidth: Math.min(380, root.width - Theme.spacingLarge * 2)

    Rectangle {
        id: backdrop
        anchors.fill: parent
        color: Theme.overlay
        visible: opacity > 0
        opacity: root.inCall ? 1 : 0
        z: 20

        Behavior on opacity { NumberAnimation { duration: 150 } }

        // Avale les clics pour ne pas interagir avec la liste derriere.
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
                    case "calling":    return qsTr("Appel en cours...")
                    case "ringing":    return qsTr("Appel entrant")
                    case "connecting": return qsTr("Connexion...")
                    case "connected":  return root.formatElapsed(root.connectedSeconds)
                    case "ending":     return qsTr("Fin de l'appel...")
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
                    bgColor: Theme.error
                    onClicked: root.call && root.call.hangUp()
                }

                CallActionButton {
                    glyph: "\uf095"
                    label: qsTr("Repondre")
                    bgColor: Theme.success
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
                    bgColor: Theme.error
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
                    label: root.call && root.call.muted ? qsTr("Reactiver") : qsTr("Muet")
                    bgColor: root.call && root.call.muted ? Theme.warning : Theme.surfaceAlt
                    iconColor: root.call && root.call.muted ? Theme.primaryText : Theme.text
                    onClicked: root.call && root.call.toggleMute()
                }

                CallActionButton {
                    glyph: "\uf095"
                    iconRotation: 135
                    label: qsTr("Raccrocher")
                    bgColor: Theme.error
                    diameter: 64
                    onClicked: root.call && root.call.hangUp()
                }
            }
        }
    }

    // Bouton d'action rond (raccrocher/decrocher/mute...) avec libelle,
    // en Font Awesome pour rester coherent avec le reste de l'application.
    component CallActionButton: ColumnLayout {
        id: actionBtn

        property string glyph: ""
        property string label: ""
        property color bgColor: Theme.primary
        property color iconColor: "#FFFFFF"
        property int diameter: 56
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
                text: actionBtn.glyph
                color: actionBtn.iconColor
                font.family: root.iconFontFamily
                font.pixelSize: actionBtn.diameter * 0.34
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
            font.family: Theme.fontFamily
            visible: actionBtn.label.length > 0
        }
    }
}
