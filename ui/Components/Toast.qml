import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Themes
import "icons.js" as Icons

/*
 * Toast - notification ephemere en Ligne claire (issue #58).
 *
 * Feuille de papier a filet, avec a gauche un filet de couleur selon la
 * nature de l'evenement (encre, bleu transfert, vert poste connecte, gris
 * poste deconnecte, rouge pour un echec). Surtitre en capitales, titre,
 * message sur deux lignes, lien d'action, croix ; le temps restant est un
 * filet d'encre qui se vide en bas de la feuille.
 *
 * Rafale (count > 1, regroupement fait par ToastHost) : une seule feuille
 * avec un compteur serif et deux feuilles devinees derriere.
 *
 * Reste affiche `duration` ms, repousse pendant une rafale, jamais plus de
 * maxLifetimeMs ; emet dismissed() apres le fondu de sortie.
 */
Item {
    id: root

    property string title: ""
    property string message: ""
    property string category: "message" // message | transfer | connection | disconnection | group | folder | call
    property int duration: 4000
    property int conversationId: 0
    property int count: 1
    // Pile du bas : les feuilles devinees de la rafale sont sous la carte.
    property bool fromBottom: false

    readonly property bool isGrouped: count > 1
    readonly property bool isMessageCategory: category === "message"
    readonly property bool failed: root.title === "Échec du transfert" || root.title === "Accès révoqué"

    signal replyRequested(string senderName)
    signal conversationRequested(int conversationId)
    signal actionRequested(string category)
    signal dismissed()

    function kindWord() {
        switch (category) {
        case "message": return qsTr("Message")
        case "transfer": return qsTr("Transfert")
        case "connection":
        case "disconnection": return qsTr("Poste")
        case "group": return qsTr("Groupe")
        case "folder": return qsTr("Dossier")
        case "call": return qsTr("Appel")
        }
        return qsTr("Notification")
    }
    function actionLabel() {
        switch (category) {
        case "message": return qsTr("Répondre")
        case "transfer": return qsTr("Voir les transferts")
        case "folder": return qsTr("Voir les dossiers")
        case "connection":
        case "disconnection": return qsTr("Voir les postes")
        case "group": return qsTr("Ouvrir les discussions")
        case "call": return qsTr("Voir les appels")
        }
        return qsTr("Voir")
    }
    function groupedLabel() {
        switch (category) {
        case "message": return qsTr("%1 nouveaux messages").arg(count)
        case "transfer": return qsTr("%1 transferts").arg(count)
        case "connection": return qsTr("%1 postes connectés").arg(count)
        case "disconnection": return qsTr("%1 postes déconnectés").arg(count)
        case "group": return qsTr("%1 nouveaux groupes").arg(count)
        case "folder": return qsTr("%1 événements de dossiers").arg(count)
        }
        return qsTr("%1 notifications").arg(count)
    }
    readonly property string iconPath: {
        switch (category) {
        case "transfer": return Icons.exchange
        case "connection":
        case "disconnection": return Icons.monitor
        case "group": return Icons.users
        case "folder": return Icons.folder
        case "call": return Icons.phoneLine
        }
        return Icons.messageCircle
    }
    readonly property color tone: root.failed ? Theme.dangerColor
                                  : category === "transfer" ? Theme.accentColor
                                  : category === "connection" ? Theme.successColor
                                  : category === "disconnection" ? Theme.ink3
                                  : Theme.ruleInk
    readonly property color toneInk: root.failed ? Theme.dangerInk
                                     : category === "transfer" ? Theme.navActiveInk
                                     : category === "connection" ? Theme.successInk
                                     : Theme.ink3
    function initials(name) {
        const parts = (name || "").trim().split(/[\s&-]+/).filter(function(p) { return p.length > 0 })
        if (parts.length === 0) return ""
        return (parts[0].charAt(0) + (parts.length > 1 ? parts[parts.length - 1].charAt(0) : parts[0].charAt(1))).toUpperCase()
    }

    // Horodatage relatif, fige a l'affichage puis reevalue toutes les 30 s.
    property real createdAt: 0
    property int _tick: 0
    function elapsedText() {
        root._tick
        const diffMin = Math.floor((Date.now() - root.createdAt) / 60000)
        if (diffMin < 1) return qsTr("à l'instant")
        return qsTr("il y a %1 min").arg(diffMin)
    }
    Timer { interval: 30000; running: true; repeat: true; onTriggered: root._tick++ }

    readonly property int peek: root.isGrouped ? 8 : 0
    width: Math.min(360, parent ? parent.width : 360)
    implicitHeight: card.height + root.peek
    height: implicitHeight
    opacity: 0
    scale: 0.97
    Behavior on opacity { NumberAnimation { duration: 150 } }
    Behavior on scale { NumberAnimation { duration: 150 } }

    // Feuilles devinees derriere une rafale.
    Repeater {
        model: root.isGrouped ? 2 : 0
        delegate: Rectangle {
            required property int index
            x: index === 0 ? 16 : 8
            width: root.width - 2 * x
            height: 12
            y: root.fromBottom ? card.y + card.height - 12 + (index === 0 ? 8 : 4) : (index === 0 ? 0 : 4)
            radius: Theme.radiusSheet
            color: Theme.surface0
            border.width: 1
            border.color: Theme.lineStrong
        }
    }

    RectangularShadow {
        anchors.fill: card
        offset.y: 10
        blur: 28
        spread: -6
        radius: card.radius
        color: Theme.shadowStrong
    }

    Rectangle {
        id: card
        y: root.fromBottom ? 0 : root.peek
        width: root.width
        height: content.implicitHeight + 28
        radius: Theme.radiusSheet
        color: Theme.bg
        border.width: 1
        border.color: Theme.lineStrong
        clip: true
        Accessible.role: Accessible.AlertMessage
        Accessible.name: root.kindWord() + ". " + (root.isGrouped ? root.groupedLabel() : root.title) + ". " + root.message

        // Clic sur la feuille : meme effet que le lien d'action.
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            hoverEnabled: true
            // Survol : la notification attend qu'on ait fini de la lire.
            onEntered: { autoHideTimer.stop(); progressAnimation.pause() }
            onExited: if (root.opacity > 0) { autoHideTimer.restart(); progressAnimation.restart() }
            onClicked: root.activate()
        }

        Rectangle { width: 3; height: parent.height; color: root.tone }

        RowLayout {
            id: content
            x: 15
            y: 13
            width: parent.width - 27
            spacing: 12

            // Avatar (message), compteur (rafale) ou icone.
            Rectangle {
                Layout.alignment: Qt.AlignTop
                implicitWidth: 36
                implicitHeight: 36
                radius: 18
                color: root.isMessageCategory && !root.isGrouped ? Theme.ink : "transparent"
                border.width: root.isMessageCategory && !root.isGrouped ? 0 : 1
                border.color: root.failed || root.category === "connection" || root.category === "transfer" ? root.tone : Theme.lineStrong
                Text {
                    visible: root.isGrouped || root.isMessageCategory
                    anchors.centerIn: parent
                    text: root.isGrouped ? String(root.count) : root.initials(root.title)
                    color: root.isGrouped ? (root.failed || root.category === "connection" || root.category === "transfer" ? root.toneInk : Theme.ink) : Theme.inkOnInk
                    font.family: Theme.fontFamilySerif
                    font.pixelSize: root.isGrouped ? Theme.fs(19) : Theme.fs(13)
                    font.weight: Theme.weightBold
                }
                LineIcon {
                    visible: !root.isGrouped && !root.isMessageCategory
                    anchors.centerIn: parent
                    path: root.iconPath
                    size: 16
                    strokeWidth: 1.7
                    color: root.failed || root.category === "connection" || root.category === "transfer" ? root.toneInk : Theme.ink2
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Row {
                    spacing: 6
                    Text { text: root.kindWord().toUpperCase(); color: root.failed || root.category === "connection" || root.category === "transfer" ? root.toneInk : Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(10); font.weight: Theme.weightBold; font.letterSpacing: 1.2 }
                    Text { text: "· " + (root.isGrouped ? qsTr("en rafale") : root.elapsedText()); color: Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(11) }
                }
                Text {
                    Layout.fillWidth: true
                    Layout.topMargin: 1
                    text: root.isGrouped ? root.groupedLabel() : root.title
                    elide: Text.ElideRight
                    color: Theme.ink
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(13.5)
                    font.weight: Theme.weightSemibold
                }
                Text {
                    visible: text.length > 0
                    Layout.fillWidth: true
                    text: root.isGrouped ? (root.isMessageCategory ? root.title + " : " + root.message : qsTr("Dernier : %1").arg(root.message.length ? root.message : root.title))
                                         : root.message
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    color: Theme.ink2
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(12.5)
                    lineHeight: 1.1
                }
                TextLink {
                    Layout.topMargin: 5
                    text: root.actionLabel()
                    fontSize: Theme.fs(12.5)
                    enabled: !root.isMessageCategory || root.conversationId > 0
                    onClicked: root.activate()
                }
            }

            AbstractButton {
                Layout.alignment: Qt.AlignTop
                implicitWidth: 24
                implicitHeight: 24
                hoverEnabled: true
                Accessible.name: qsTr("Fermer la notification")
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                background: Rectangle { radius: 12; color: parent.hovered ? Theme.selectWash : "transparent" }
                contentItem: Item { LineIcon { anchors.centerIn: parent; path: Icons.close; size: 13; strokeWidth: 2; color: Theme.ink3 } }
                onClicked: root.hide()
            }
        }

        // Temps restant : filet d'encre qui se vide.
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 3
            height: 2
            color: Theme.line
            Rectangle {
                id: progressBar
                property real fraction: 1.0
                width: parent.width * fraction
                height: 2
                color: Theme.ruleInk
            }
        }
    }

    function activate() {
        if (root.isMessageCategory) {
            if (root.conversationId > 0)
                root.conversationRequested(root.conversationId)
            else
                root.replyRequested(root.title)
        } else {
            root.actionRequested(root.category)
        }
    }

    Timer { id: autoHideTimer; interval: root.duration; onTriggered: root.hide() }

    // Filet de securite : une rafale qui se prolonge ne garde jamais le toast
    // indefiniment (le delai n'est pas relance par les nouveaux evenements).
    readonly property int maxLifetimeMs: 20000
    Timer { id: maxLifetimeTimer; interval: root.maxLifetimeMs; onTriggered: root.hide() }

    // Chaque nouvel evenement regroupe repousse la disparition.
    onCountChanged: if (count > 1) { autoHideTimer.restart(); progressAnimation.restart() }

    NumberAnimation {
        id: progressAnimation
        target: progressBar
        property: "fraction"
        from: 1.0
        to: 0.0
        duration: root.duration
    }

    function show() {
        opacity = 1
        scale = 1
        autoHideTimer.restart()
        maxLifetimeTimer.restart()
        progressAnimation.restart()
    }
    function hide() {
        autoHideTimer.stop()
        maxLifetimeTimer.stop()
        progressAnimation.stop()
        opacity = 0
        scale = 0.97
        hideTimer.start()
    }
    // Laisse jouer le fondu de sortie avant de retirer le toast de la file.
    Timer { id: hideTimer; interval: 160; onTriggered: root.dismissed() }

    Component.onCompleted: {
        createdAt = Date.now()
        show()
    }
}
