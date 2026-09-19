import QtQuick
import QtQuick.Controls
import Themes

/*
 * Toast - notification visuelle ephemere reutilisable (issue #58).
 *
 * Affiche un titre + un message, se rend visible avec un fondu, reste a
 * l'ecran `duration` ms puis se retire (fondu sortant) et emet
 * dismissed() pour que l'hote (ToastHost.qml) le retire de la file.
 *
 * category determine la couleur d'accent (barre laterale + icone) afin
 * que le style du toast reste coherent avec le type d'evenement recu
 * (message / transfert / connexion / deconnexion).
 */
Rectangle {
    id: root

    property string title: ""
    property string message: ""
    property string category: "message" // "message" | "transfer" | "connection" | "disconnection" | "group" | "folder"
    property int duration: 4000
    property int conversationId: 0

    // Nombre d'evenements regroupes dans ce toast (rafale, cf.
    // ToastHost::addToast). count === 1 : affichage normal (design A ou B).
    // count > 1 : design C (groupe empile + compteur), quelle que soit la
    // categorie, au lieu d'empiler un toast par evenement individuel.
    property int count: 1
    readonly property bool isGrouped: count > 1

    // Design A (carte enrichie) : utilise pour TOUTES les categories des
    // qu'il n'y a qu'un seul evenement (isGrouped == false). Les messages
    // gardent un avatar avec initiales ; les autres categories affichent
    // un badge icone colore (accentColor) a la place. Design C (groupe
    // empile) prend le relais des qu'un meme type d'evenement se repete.
    readonly property bool isCard: !isGrouped
    readonly property bool isMessageCategory: category === "message"

    function groupedLabel() {
        switch (category) {
        case "message": return qsTr("%1 nouveaux messages").arg(count)
        case "transfer": return qsTr("%1 transferts terminés").arg(count)
        case "connection": return qsTr("%1 postes connectés").arg(count)
        case "disconnection": return qsTr("%1 postes déconnectés").arg(count)
        case "group": return qsTr("%1 nouveaux groupes").arg(count)
        case "folder": return qsTr("%1 dossiers partagés").arg(count)
        default: return qsTr("%1 notifications").arg(count)
        }
    }

    // Emis quand l'utilisateur clique "Repondre" sur une carte message.
    // NB: notificationRequested() ne transporte aujourd'hui ni l'id de
    // l'expediteur ni celui de la conversation -- le titre (nom resolu,
    // cf. NotificationManager::onMessageReceived) est tout ce qu'on peut
    // remonter pour l'instant. Pour ouvrir reellement la conversation
    // correspondante il faudra etendre le signal C++ avec un identifiant.
    signal replyRequested(string senderName)
    signal conversationRequested(int conversationId)
    // Emis quand l'utilisateur clique sur une notification non-message
    // (transfert/connexion/deconnexion/groupe/dossier) ou son lien
    // d'action : ToastHost le relaie a Main.qml qui route vers l'ecran
    // pertinent pour cette categorie.
    signal actionRequested(string category)
    signal dismissed()

    // Libelle du lien d'action affiche sous le message, adapte a la
    // categorie (ex: "Repondre" pour un message, "Voir" pour les autres).
    function actionLabel() {
        switch (category) {
        case "message": return qsTr("Répondre")
        case "transfer": return qsTr("Voir les transferts")
        case "folder": return qsTr("Ouvrir le dossier")
        case "connection":
        case "disconnection": return qsTr("Voir les postes")
        case "group": return qsTr("Voir les groupes")
        default: return qsTr("Voir")
        }
    }

    readonly property color accentColor: {
        switch (category) {
        case "transfer": return Theme.primary
        case "connection": return Theme.success
        case "disconnection": return Theme.textSecondary
        case "group": return Theme.accent
        case "folder": return Theme.primary
        default: return Theme.accent
        }
    }

    readonly property string iconGlyph: {
        switch (category) {
        case "transfer": return "\uf019"       // telechargement
        case "connection": return "\uf234"      // utilisateur connecte
        case "disconnection": return "\uf235"   // utilisateur deconnecte
        case "group": return "\uf0c0"           // groupe d'utilisateurs
        case "folder": return "\uf07b"          // dossier
        default: return "\uf0e0"                // enveloppe
        }
    }

    FontLoader {
        id: iconFont
        source: "qrc:/ui/Assets/fonts/fontawesome-webfont.ttf"
    }

    function initials(name) {
        const trimmed = (name || "").trim()
        if (trimmed.length === 0)
            return ""
        const parts = trimmed.split(/\s+/)
        if (parts.length === 1)
            return parts[0].substring(0, 2).toUpperCase()
        return (parts[0].charAt(0) + parts[parts.length - 1].charAt(0)).toUpperCase()
    }

    // Horodatage relatif (cf. maquette "il y a 2 min"). createdAt est fige
    // a l'affichage du toast ; _tick force la reevaluation de elapsedText()
    // toutes les 30s (un toast reste rarement affiche plus de 4s par
    // defaut, mais peut etre laisse ouvert plus longtemps par l'utilisateur).
    property real createdAt: 0
    property int _tick: 0

    function elapsedText() {
        _tick // force la dependance au timer
        const diffMin = Math.floor((Date.now() - createdAt) / 60000)
        if (diffMin < 1)
            return qsTr("à l'instant")
        if (diffMin === 1)
            return qsTr("il y a 1 min")
        return qsTr("il y a %1 min").arg(diffMin)
    }

    Timer {
        interval: 30000
        running: root.isCard
        repeat: true
        onTriggered: root._tick++
    }

    // stackPeek : marge reservee pour laisser depasser les deux calques
    // arriere du design C (cf. mockup "Groupe empile", rectangles decales
    // en haut/a droite derriere la carte de premier plan).
    readonly property int stackPeek: 8

    width: Math.min(360, parent ? parent.width - 32 : 360) + (root.isGrouped ? stackPeek : 0)
    height: root.isGrouped ? 52 + stackPeek : cardColumn.implicitHeight + Theme.spacingMedium * 2
    radius: Theme.radiusMedium
    // En mode groupe, le fond/la bordure du calque de premier plan
    // jouent ce role (cf. groupedStack ci-dessous) ; root reste transparent.
    color: root.isGrouped ? "transparent" : Theme.surface
    border.color: Theme.border
    border.width: root.isGrouped ? 0 : 1
    // La barre de progression reste confinee dans la notification afin de
    // ne pas depasser de ses bords arrondis.
    clip: !root.isGrouped

    // Legere ombre portee simulee par un rectangle en fond, decale.
    Rectangle {
        visible: !root.isGrouped
        anchors.fill: parent
        anchors.topMargin: 3
        radius: parent.radius
        color: Theme.shadow
        z: -1
    }

    opacity: 0
    scale: 0.96

    // ---- Design A : carte enrichie (toutes categories, count === 1) ------

    // Zone de clic pleine carte : place en sibling de cardRow (et non a
    // l'interieur, un Row n'accepte pas d'ancrage sur ses enfants -- c'etait
    // la cause des warnings "Cannot specify ... anchors for items inside
    // Row"). z:-1 pour rester derriere le contenu texte/liens, qui ont
    // chacun leur propre MouseArea prioritaire.
    MouseArea {
        anchors.fill: cardRow
        visible: root.isCard
        z: -1
        enabled: root.isMessageCategory ? root.conversationId > 0 : true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.isMessageCategory
                   ? root.conversationRequested(root.conversationId)
                   : root.actionRequested(root.category)
    }

    Row {
        id: cardRow
        visible: root.isCard
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: Theme.spacingMedium
        anchors.rightMargin: Theme.spacingSmall
        anchors.topMargin: Theme.spacingMedium
        spacing: Theme.spacingSmall

        Rectangle {
            id: avatar
            width: 36
            height: 36
            radius: 18
            color: root.isMessageCategory ? Theme.colorForName(root.title) : root.accentColor

            Text {
                anchors.centerIn: parent
                text: root.isMessageCategory ? root.initials(root.title) : root.iconGlyph
                color: "#FFFFFF"
                font.pixelSize: root.isMessageCategory ? Theme.fontSizeSmall : Theme.fontSizeBody
                font.bold: true
                font.family: root.isMessageCategory ? Theme.fontFamily : iconFont.name
            }
        }

        Column {
            id: cardColumn
            width: cardRow.width - cardRow.spacing * 2 - avatar.width - closeLabelCard.width
            spacing: 3

            Row {
                width: parent.width
                spacing: Theme.spacingXs

                Text {
                    id: senderName
                    text: root.title
                    color: Theme.text
                    font.pixelSize: Theme.fontSizeBody
                    font.bold: true
                    elide: Text.ElideRight
                    width: parent.width - timestampLabel.width - Theme.spacingXs
                }
                Text {
                    id: timestampLabel
                    text: root.elapsedText()
                    color: Theme.textTertiary
                    font.pixelSize: Theme.fontSizeCaption
                }
            }

            Text {
                text: root.message
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeSmall
                width: parent.width
                elide: Text.ElideRight
                maximumLineCount: 2
                wrapMode: Text.Wrap
            }

            Text {
                text: root.actionLabel()
                color: Theme.primary
                font.pixelSize: Theme.fontSizeSmall
                font.bold: true
                topPadding: 2

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -4
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.isMessageCategory
                               ? root.replyRequested(root.title)
                               : root.actionRequested(root.category)
                }
            }
        }

        Text {
            id: closeLabelCard
            text: "\u2715"
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSizeSmall

            MouseArea {
                anchors.fill: parent
                anchors.margins: -8
                cursorShape: Qt.PointingHandCursor
                onClicked: root.hide()
            }
        }
    }

    // Barre de progression (temps restant avant disparition automatique).

    Item {
        id: progressTrack
        visible: root.isCard && !root.isGrouped
        height: 3
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 4
        anchors.rightMargin: 4
        anchors.bottomMargin: 1

        Rectangle {
            id: progressBar
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            radius: root.radius
            color: root.accentColor
            width: parent.width * progressFraction

            property real progressFraction: 1.0
        }
    }

    // ---- Design C : groupe empile (rafale d'evenements identiques) -------
    //
    // Utilise quand plusieurs notifications de meme categorie arrivent
    // coup sur coup (cf. ToastHost::addToast) : au lieu d'empiler un toast
    // par evenement, on affiche une seule carte avec un compteur, deux
    // calques legerement decales en dessous suggerant la pile.

    Item {
        id: groupedStack
        visible: root.isGrouped
        anchors.fill: parent

        Rectangle {
            anchors.top: parent.top
            anchors.topMargin: root.stackPeek
            anchors.left: parent.left
            anchors.leftMargin: root.stackPeek
            width: parent.width - root.stackPeek
            height: 52
            radius: Theme.radiusMedium
            color: Theme.background
            border.color: Theme.border
            border.width: 1
        }

        Rectangle {
            anchors.top: parent.top
            anchors.topMargin: root.stackPeek * 0.4
            anchors.left: parent.left
            anchors.leftMargin: root.stackPeek * 0.4
            width: parent.width - root.stackPeek * 0.4
            height: 52
            radius: Theme.radiusMedium
            color: Theme.surfaceAlt
            border.color: Theme.border
            border.width: 1
        }

        Rectangle {
            id: groupedFront
            anchors.top: parent.top
            anchors.left: parent.left
            width: parent.width - root.stackPeek
            height: 52
            radius: Theme.radiusMedium
            color: Theme.surface
            border.color: Theme.border
            border.width: 1

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.isMessageCategory
                           ? root.conversationRequested(root.conversationId)
                           : root.actionRequested(root.category)
            }

            Row {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Theme.spacingMedium
                anchors.rightMargin: Theme.spacingMedium
                spacing: Theme.spacingSmall

                Text {
                    text: root.iconGlyph
                    color: root.accentColor
                    font.pixelSize: Theme.fontSizeBody
                    font.family: iconFont.name
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    id: groupedLabelText
                    text: root.groupedLabel()
                    color: Theme.text
                    font.pixelSize: Theme.fontSizeSmall
                    elide: Text.ElideRight
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - parent.spacing * 2 - 16 - countBadge.width
                }

                Rectangle {
                    id: countBadge
                    radius: Theme.radiusPill
                    color: Theme.primaryMuted
                    height: 20
                    width: countLabel.implicitWidth + Theme.spacingSmall * 2
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        id: countLabel
                        anchors.centerIn: parent
                        text: "+" + root.count
                        color: Theme.primary
                        font.pixelSize: Theme.fontSizeCaption
                        font.bold: true
                    }
                }
            }
        }
    }

    Behavior on opacity { NumberAnimation { duration: 150 } }
    Behavior on scale { NumberAnimation { duration: 150 } }

    Timer {
        id: autoHideTimer
        interval: root.duration
        running: false
        repeat: false
        onTriggered: root.hide()
    }

    // Filet de sécurité (debrief : "le récapitulatif reste bloqué sans
    // disparaître") : quelle que soit la cause d'une fusion répétée d'un
    // même toast groupé (cf. onCountChanged ci-dessous, ou ToastHost::
    // addToast), ce toast ne doit jamais rester affiché indéfiniment.
    // maxLifetimeTimer démarre UNE SEULE FOIS à la création (jamais
    // relancé) et force la disparition passé ce délai, même si
    // autoHideTimer continue d'être repoussé par de nouveaux évènements.
    readonly property int maxLifetimeMs: 20000
    Timer {
        id: maxLifetimeTimer
        interval: root.maxLifetimeMs
        running: false
        repeat: false
        onTriggered: root.hide()
    }

    // A chaque nouvel evenement regroupe (count incremente par
    // ToastHost::addToast), on repousse la disparition automatique : une
    // rafale en cours ne doit pas voir son toast disparaitre au milieu.
    // maxLifetimeTimer n'est PAS relance ici -- c'est tout le point du
    // filet de securite ci-dessus.
    onCountChanged: {
        if (count > 1) {
            autoHideTimer.restart()
        }
    }

    function show() {
        opacity = 1
        scale = 1
        autoHideTimer.restart()
        maxLifetimeTimer.restart()
        if (isCard) {
            progressBar.progressFraction = 1.0
            progressAnimation.restart()
        }
    }

    NumberAnimation {
        id: progressAnimation
        target: progressBar
        property: "progressFraction"
        from: 1.0
        to: 0.0
        duration: root.duration
        easing.type: Easing.Linear
    }

    function hide() {
        autoHideTimer.stop()
        maxLifetimeTimer.stop()
        progressAnimation.stop()
        opacity = 0
        scale = 0.96
        hideTimer.start()
    }

    // Laisse le temps au fondu sortant de jouer avant de signaler la
    // suppression definitive (evite un "saut" visuel dans la ListView hote).
    Timer {
        id: hideTimer
        interval: 160
        running: false
        repeat: false
        onTriggered: root.dismissed()
    }

    Component.onCompleted: {
        createdAt = Date.now()
        show()
    }
}
