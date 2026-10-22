import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import "../Components"
import "../Components/icons.js" as Icons

/*
 * ChatView - conversation ouverte (Ligne claire), colonne centrale de
 * l'espace Discussions, branchee sur MessagingContext.
 *
 * Messages par jour ; recus a gauche sur feuille, envoyes a droite avec le
 * filet d'encre (meme langage que la correspondance de Transferts) ; dans un
 * groupe, monogramme et nom de l'expediteur. Un repere « Nouveaux messages »
 * marque le premier non lu trouve a l'ouverture. Defilement automatique
 * seulement si l'on etait deja en bas.
 *
 * Redaction : Entree envoie, Maj+Entree passe a la ligne. Si l'envoi echoue,
 * l'avis donne la raison et le texte est remis dans le champ.
 *
 * Aucun indicateur « livre »/« lu » : l'application ne le connait pas.
 */
Item {
    id: root

    property var messagingContext: null
    property var conversationId: 0
    property string name: ""
    // Faux tant que ce panneau n'est pas reellement affiche : la
    // conversation n'est alors pas activee (pas d'acquittement de lecture).
    property bool conversationActive: true
    property string status: "offline"       // presence de l'interlocuteur
    property string machineName: ""        // poste de l'interlocuteur (reseau local)
    property int memberCount: 0
    property bool ficheOpen: false
    property bool showBackButton: false
    property int currentUserId: messagingContext ? messagingContext.currentUserId() : 0
    readonly property bool isGroup: messagingContext ? messagingContext.isGroupConversation(conversationId) : false
    readonly property bool reachable: !root.isGroup && root.machineName.length > 0
    readonly property int messageCount: messageListView.count

    readonly property string displayName: name.length > 0
        ? name
        : (messagingContext ? messagingContext.conversationDisplayName(conversationId) : qsTr("Conversation"))
    readonly property string firstName: root.displayName.split(" ")[0]

    signal backRequested()
    signal callRequested()
    signal sendFileRequested()
    signal ficheToggled()

    function activateConversationIfVisible() {
        if (conversationActive && messagingContext && conversationId > 0)
            messagingContext.setConversation(conversationId)
    }
    onConversationIdChanged: {
        messageListView.follow = true
        root.unreadAnchorPending = true
        root.unreadAnchorId = -1
        root.lastSentText = ""
        sendFail.visible = false
        root.activateConversationIfVisible()
    }
    onConversationActiveChanged: root.activateConversationIfVisible()

    function presenceWord(s) {
        switch (s) {
        case "online": return qsTr("En ligne")
        case "away": return qsTr("Absent")
        case "busy": return qsTr("Occupé")
        }
        return qsTr("Hors ligne")
    }
    function presenceKind(s) { return s === "online" || s === "away" || s === "busy" ? s : "offline" }
    function dayLabel(ts) {
        if (!ts) return ""
        const d = new Date(ts)
        const now = new Date()
        if (d.toDateString() === now.toDateString()) return qsTr("Aujourd'hui")
        const yesterday = new Date(now.getTime() - 86400000)
        if (d.toDateString() === yesterday.toDateString()) return qsTr("Hier")
        return d.toLocaleDateString(Qt.locale(), "dddd d MMMM")
    }
    function timeOf(ts) { return ts ? new Date(ts).toLocaleTimeString(Qt.locale(), "HH:mm") : "" }

    // ---- Repere « Nouveaux messages » -----------------------------------
    // Fige a la premiere lecture du fil : l'activation de la conversation
    // acquitte ensuite les messages, le repere doit pourtant rester visible.
    property bool unreadAnchorPending: true
    property var unreadAnchorId: -1
    property int unreadAnchorCount: 0
    function captureUnreadAnchor() {
        if (!root.unreadAnchorPending || !messagingContext) return
        const model = messagingContext.messageModel
        const total = model ? model.rowCount() : 0
        if (total === 0) return
        root.unreadAnchorPending = false
        let first = -1, n = 0
        for (let i = 0; i < total; i++) {
            const m = model.get(i)
            if (m.senderId !== root.currentUserId && m.isRead === false) {
                if (first < 0) first = m.messageId
                n++
            }
        }
        root.unreadAnchorId = first
        root.unreadAnchorCount = n
    }

    // ---- Envoi -------------------------------------------------------------
    property string lastSentText: ""
    property string sendErrorMessage: ""

    Connections {
        target: messagingContext
        ignoreUnknownSignals: true
        function onMessageSendFailed(error) {
            root.sendErrorMessage = error
            sendFail.visible = true
            // Le texte n'est pas perdu : il revient dans le champ.
            if (composer.text.trim().length === 0 && root.lastSentText.length > 0) {
                composer.text = root.lastSentText
                composer.cursorPosition = composer.text.length
            }
        }
    }

    function sendCurrentMessage() {
        const text = composer.text.trim()
        if (text.length === 0 || !messagingContext) return
        root.lastSentText = text
        sendFail.visible = false
        messagingContext.sendMessage(text)
        composer.text = ""
        composer.forceActiveFocus()
    }

    // Touche de clavier dessinee (aide de la redaction).
    component Key: Rectangle {
        property alias label: keyText.text
        width: keyText.implicitWidth + 10
        height: 17
        radius: Theme.radiusSheet
        color: "transparent"
        border.width: 1
        border.color: Theme.lineStrong
        Text { id: keyText; anchors.centerIn: parent; color: Theme.ink2; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(10.5); font.weight: Theme.weightSemibold }
    }

    // Petit bouton carre a filet de l'en-tete.
    component HeadButton: AbstractButton {
        id: hb
        property string iconPath: ""
        property string tip: ""
        property bool pressedState: false
        implicitWidth: 34
        implicitHeight: 34
        hoverEnabled: true
        focusPolicy: Qt.StrongFocus
        Accessible.name: hb.tip
        ToolTip.visible: hb.tip.length > 0 && hb.hovered
        ToolTip.text: hb.tip
        ToolTip.delay: 400
        HoverHandler { cursorShape: hb.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
        background: Rectangle {
            radius: Theme.radiusSheet
            color: hb.pressedState ? Theme.ink : "transparent"
            border.width: hb.pressedState ? 0 : (hb.visualFocus ? 2 : 1)
            border.color: hb.visualFocus ? Theme.focusRing : (!hb.enabled ? Theme.line : hb.hovered ? Theme.ink : Theme.lineStrong)
        }
        contentItem: Item {
            LineIcon {
                anchors.centerIn: parent
                path: hb.iconPath
                size: 16
                strokeWidth: 1.8
                color: hb.pressedState ? Theme.inkOnInk : (hb.enabled ? Theme.ink2 : Theme.inkDisabled)
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ---- En-tete -------------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: root.showBackButton ? 0 : 24
            Layout.topMargin: 14
            Layout.bottomMargin: 12
            spacing: 14
            HeadButton { visible: root.showBackButton; iconPath: Icons.chevronLeft; tip: qsTr("Retour aux discussions"); onClicked: root.backRequested() }
            ChatMonogram {
                label: root.displayName
                group: root.isGroup
                status: root.isGroup ? "" : root.status
                memberCount: root.memberCount
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Text {
                    Layout.fillWidth: true
                    text: root.displayName
                    color: Theme.ink
                    font.family: Theme.fontFamilySerif
                    font.pixelSize: Theme.fs(22)
                    font.weight: Theme.weightBold
                    elide: Text.ElideRight
                    Accessible.role: Accessible.Heading
                }
                Row {
                    spacing: 7
                    StateGlyph { visible: !root.isGroup; anchors.verticalCenter: parent.verticalCenter; kind: root.presenceKind(root.status); size: 10 }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.isGroup ? (root.memberCount > 0 ? qsTr("Groupe · %1 membres").arg(root.memberCount) : qsTr("Groupe"))
                                           : root.presenceWord(root.status) + (root.machineName.length ? " · " : "")
                        color: Theme.ink2
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(12.5)
                    }
                    Text {
                        visible: !root.isGroup && root.machineName.length > 0
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.machineName
                        color: Theme.ink3
                        font.family: "Cascadia Mono"
                        font.pixelSize: Theme.fs(11.5)
                    }
                }
            }
            Row {
                spacing: 6
                HeadButton { visible: !root.isGroup; iconPath: Icons.phone; enabled: root.reachable; tip: root.reachable ? qsTr("Appeler") : qsTr("Hors ligne : appel impossible"); onClicked: root.callRequested() }
                HeadButton { visible: !root.isGroup; iconPath: Icons.arrowUp; enabled: root.reachable; tip: qsTr("Envoyer un fichier"); onClicked: root.sendFileRequested() }
                HeadButton { iconPath: Icons.info; tip: qsTr("Fiche"); pressedState: root.ficheOpen; onClicked: root.ficheToggled() }
            }
        }
        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.line }

        // ---- Messages ------------------------------------------------------
        ListView {
            id: messageListView
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: root.showBackButton ? 0 : 24
            spacing: 0
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            header: Item { width: 1; height: 8 }
            footer: Item { width: 1; height: 14 }
            model: messagingContext ? messagingContext.messageModel : null
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            property bool wasAtBottom: true
            readonly property int autoScrollTolerance: 50
            // Suit la fin du fil tant que l'utilisateur n'a pas remonte lui-meme
            // (seul son geste coupe le suivi) : les bulles prennent leur
            // hauteur apres le premier positionnement.
            property bool follow: true
            onContentHeightChanged: if (messageListView.follow) messageListView.positionViewAtEnd()
            onMovementEnded: messageListView.follow = messageListView.atYEnd

            Connections {
                target: messageListView.model
                ignoreUnknownSignals: true
                function onRowsAboutToBeInserted() {
                    messageListView.wasAtBottom =
                        messageListView.contentY >= messageListView.contentHeight - messageListView.height - messageListView.autoScrollTolerance
                }
                function onModelAboutToBeReset() { messageListView.wasAtBottom = true; messageListView.follow = true }
                function onModelReset() { Qt.callLater(function() { root.captureUnreadAnchor(); messageListView.positionViewAtEnd() }) }
            }
            onCountChanged: Qt.callLater(function() {
                root.captureUnreadAnchor()
                if (messageListView.wasAtBottom)
                    messageListView.positionViewAtEnd()
            })

            delegate: Column {
                id: msg
                required property int index
                required property var messageId
                required property var senderId
                required property string content
                required property var timestamp
                readonly property bool isMine: msg.senderId === root.currentUserId
                readonly property var prevItem: (index > 0 && messagingContext) ? messagingContext.messageModel.get(index - 1) : null
                readonly property var nextItem: (messagingContext && index < messageListView.count - 1) ? messagingContext.messageModel.get(index + 1) : null
                readonly property string dayText: {
                    const label = root.dayLabel(msg.timestamp)
                    return msg.prevItem && msg.prevItem.timestamp && root.dayLabel(msg.prevItem.timestamp) === label ? "" : label
                }
                readonly property bool anchorHere: msg.messageId === root.unreadAnchorId
                readonly property bool groupStart: !msg.prevItem || msg.prevItem.senderId !== msg.senderId || msg.dayText.length > 0 || msg.anchorHere
                readonly property bool groupEnd: {
                    if (!msg.nextItem || msg.nextItem.senderId !== msg.senderId) return true
                    if (msg.nextItem.messageId === root.unreadAnchorId) return true
                    return root.dayLabel(msg.nextItem.timestamp) !== root.dayLabel(msg.timestamp)
                }
                readonly property string senderName: messagingContext ? messagingContext.userName(msg.senderId) : ""
                width: messageListView.width - 24
                spacing: 0

                // Separateur de jour
                Item {
                    visible: msg.dayText.length > 0
                    width: parent.width
                    height: visible ? 44 : 0
                    Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 1; color: Theme.line }
                    Rectangle {
                        anchors.centerIn: parent
                        width: dayCaps.implicitWidth + 20
                        height: 20
                        radius: 10
                        color: Theme.bg
                        border.width: 1
                        border.color: Theme.line
                        CapsLabel { id: dayCaps; anchors.centerIn: parent; text: msg.dayText; color: Theme.ink2 }
                    }
                }
                // Repere « Nouveaux messages »
                Item {
                    visible: msg.anchorHere
                    width: parent.width
                    height: visible ? 34 : 0
                    CapsLabel {
                        id: newCaps
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.unreadAnchorCount > 1 ? qsTr("Nouveaux messages · %1").arg(root.unreadAnchorCount) : qsTr("Nouveau message")
                        color: Theme.navActiveInk
                    }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        x: newCaps.implicitWidth + 10
                        width: parent.width - x
                        height: 1
                        color: Theme.markTransfer
                    }
                }
                Item { width: 1; height: msg.groupStart ? 10 : 3 }

                Row {
                    anchors.right: msg.isMine ? parent.right : undefined
                    spacing: 10
                    // Monogramme de l'expediteur (groupe), en bas du bloc
                    Item {
                        visible: !msg.isMine && root.isGroup
                        width: 28
                        height: bubbleCol.height
                        ChatMonogram {
                            visible: msg.groupEnd
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 18
                            size: 28
                            label: msg.senderName
                        }
                    }
                    Column {
                        id: bubbleCol
                        spacing: 3
                        Text {
                            visible: !msg.isMine && root.isGroup && msg.groupStart
                            leftPadding: 2
                            text: msg.senderName
                            color: Theme.ink2
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(11.5)
                            font.weight: Theme.weightSemibold
                        }
                        Rectangle {
                            id: bubble
                            anchors.right: msg.isMine ? parent.right : undefined
                            readonly property real maxW: Math.min(620, messageListView.width * 0.72)
                            width: Math.min(body.implicitWidth, maxW) + 24 + (msg.isMine ? 3 : 0)
                            height: body.implicitHeight + 16
                            radius: Theme.radiusSheet
                            color: msg.isMine ? Theme.surface1 : Theme.surface0
                            border.width: 1
                            border.color: Theme.line
                            Rectangle { visible: msg.isMine; anchors.right: parent.right; width: 3; height: parent.height; color: Theme.ruleInk }
                            TextEdit {
                                id: body
                                x: 12
                                y: 8
                                width: Math.min(implicitWidth, bubble.maxW)
                                text: msg.content
                                readOnly: true
                                selectByMouse: true
                                wrapMode: Text.Wrap
                                textFormat: TextEdit.PlainText
                                color: Theme.ink
                                selectionColor: Theme.accentMuted
                                selectedTextColor: Theme.ink
                                font.pixelSize: Theme.fs(14)
                                font.family: Theme.fontFamily
                            }
                        }
                        Text {
                            visible: msg.groupEnd
                            anchors.right: msg.isMine ? parent.right : undefined
                            leftPadding: 2
                            rightPadding: 2
                            text: (msg.isMine ? qsTr("Vous · ") : "") + root.timeOf(msg.timestamp)
                            color: Theme.ink3
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(11)
                            font.features: ({ "tnum": 1 })
                        }
                    }
                }
            }

            // Discussion sans message
            ColumnLayout {
                visible: messageListView.count === 0
                anchors.centerIn: parent
                width: Math.min(parent.width - 48, 420)
                spacing: 6
                CapsLabel { Layout.alignment: Qt.AlignHCenter; text: qsTr("Nouvelle discussion") }
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: root.isGroup ? qsTr("Écrivez le premier message du groupe.") : qsTr("Écrivez le premier message à %1.").arg(root.firstName)
                    color: Theme.ink
                    font.family: Theme.fontFamilySerif
                    font.pixelSize: Theme.fs(24)
                    wrapMode: Text.WordWrap
                }
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: root.isGroup || root.reachable ? qsTr("Il sera remis tout de suite sur les postes connectés.")
                                                         : qsTr("Il sera remis à sa prochaine connexion au réseau.")
                    color: Theme.ink3
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(13)
                    wrapMode: Text.WordWrap
                }
            }
        }

        // ---- Redaction -----------------------------------------------------
        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.ruleInk }
        ColumnLayout {
            Layout.fillWidth: true
            Layout.leftMargin: root.showBackButton ? 0 : 24
            Layout.topMargin: 10
            Layout.bottomMargin: 14
            spacing: 6

            Rectangle {
                id: sendFail
                visible: false
                Layout.fillWidth: true
                Layout.bottomMargin: 4
                implicitHeight: failRow.implicitHeight + 14
                color: Theme.dangerSoft
                Rectangle { width: 2; height: parent.height; color: Theme.dangerColor }
                RowLayout {
                    id: failRow
                    anchors.verticalCenter: parent.verticalCenter
                    x: 12
                    width: parent.width - 18
                    spacing: 10
                    LineIcon { path: Icons.alertTriangle; size: 15; strokeWidth: 1.8; color: Theme.dangerInk }
                    Text {
                        Layout.fillWidth: true
                        textFormat: Text.StyledText
                        wrapMode: Text.WordWrap
                        text: "<b><font color=\"" + Theme.dangerInk + "\">" + qsTr("Message non envoyé.") + "</font></b> "
                              + root.sendErrorMessage.replace(/&/g, "&amp;").replace(/</g, "&lt;")
                              + (root.lastSentText.length ? " " + qsTr("Votre texte est resté dans le champ.") : "")
                        color: Theme.ink
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(12.5)
                    }
                    AppButton { variant: "ghost"; size: "small"; text: qsTr("OK"); onClicked: sendFail.visible = false }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(140, Math.max(42, composer.implicitHeight + 2))
                    radius: Theme.radiusSheet
                    color: Theme.surface0
                    border.width: composer.activeFocus ? 1.5 : 1
                    border.color: composer.activeFocus ? Theme.ink : Theme.lineStrong
                    ScrollView {
                        anchors.fill: parent
                        anchors.margins: 1
                        clip: true
                        TextArea {
                            id: composer
                            placeholderText: root.isGroup ? qsTr("Écrire à « %1 »…").arg(root.displayName) : qsTr("Écrire à %1…").arg(root.firstName)
                            placeholderTextColor: Theme.inkDisabled
                            color: Theme.ink
                            font.pixelSize: Theme.fs(14)
                            font.family: Theme.fontFamily
                            wrapMode: TextArea.Wrap
                            selectByMouse: true
                            selectionColor: Theme.accentMuted
                            selectedTextColor: Theme.ink
                            leftPadding: 12
                            rightPadding: 12
                            topPadding: 10
                            bottomPadding: 10
                            background: Item {}
                            Accessible.name: qsTr("Message")
                            Keys.onPressed: function(event) {
                                if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                                        && !(event.modifiers & Qt.ShiftModifier)) {
                                    root.sendCurrentMessage()
                                    event.accepted = true
                                }
                            }
                        }
                    }
                }
                AppButton {
                    Layout.alignment: Qt.AlignBottom
                    variant: "ink"
                    iconPath: Icons.send
                    text: qsTr("Envoyer")
                    enabled: composer.text.trim().length > 0
                    onClicked: root.sendCurrentMessage()
                }
            }
            Row {
                spacing: 16
                Row {
                    spacing: 5
                    Key { label: qsTr("Entrée") }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("envoie"); color: Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(11.5) }
                }
                Row {
                    spacing: 5
                    Key { label: qsTr("Maj") }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "+"; color: Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(11.5) }
                    Key { label: qsTr("Entrée") }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("nouvelle ligne"); color: Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(11.5) }
                }
            }
        }
    }

    Component.onCompleted: root.activateConversationIfVisible()
}
