import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import Core
import "../Components"

/*
 * ChatView - conversation ouverte (panneau droit de l'espace Discussions),
 * branchee sur MessagingManager via MessagingContext.
 *
 * Bulles regroupees par expediteur (avatar et nom sur le premier message
 * d'un groupe en conversation de groupe), separateurs de date
 * ("Aujourd'hui", "Hier", date), defilement automatique seulement si
 * l'utilisateur etait deja en bas. Zone de redaction multiligne : Entree
 * envoie, Maj+Entree passe a la ligne.
 *
 * Aucun indicateur "livre"/"lu" : l'application ne dispose pas de cette
 * information, l'afficher serait trompeur.
 */
Item {
    id: root

    property var messagingContext: null
    property var conversationId: 0
    property string name: ""
    // Faux tant que ce panneau n'est pas reellement affiche : la
    // conversation n'est alors pas activee (pas d'acquittement de lecture).
    property bool conversationActive: true
    property int currentUserId: messagingContext ? messagingContext.currentUserId() : 0
    readonly property bool isGroup: messagingContext ? messagingContext.isGroupConversation(conversationId) : false

    property bool showBackButton: false

    readonly property string displayName: name.length > 0
        ? name
        : (messagingContext ? messagingContext.conversationDisplayName(conversationId) : qsTr("Conversation"))

    signal backRequested()

    function activateConversationIfVisible() {
        if (conversationActive && messagingContext && conversationId > 0)
            messagingContext.setConversation(conversationId)
    }

    // ---- Presence de l'interlocuteur (conversation individuelle) --------
    property string otherUserStatus: "offline"

    function refreshPresence() {
        if (!messagingContext || root.isGroup || root.conversationId <= 0) {
            root.otherUserStatus = "offline"
            return
        }
        const otherId = messagingContext.otherParticipantId(root.conversationId)
        root.otherUserStatus = otherId > 0 ? messagingContext.userStatus(otherId) : "offline"
    }

    function presenceLabel(status) {
        switch (status) {
        case "online": return qsTr("En ligne")
        case "away": return qsTr("Absent")
        case "busy": return qsTr("Occupé")
        default: return qsTr("Hors ligne")
        }
    }

    function dayLabel(ts) {
        if (!ts)
            return ""
        const d = new Date(ts)
        const now = new Date()
        if (d.toDateString() === now.toDateString())
            return qsTr("Aujourd'hui")
        const yesterday = new Date(now.getTime() - 86400000)
        if (d.toDateString() === yesterday.toDateString())
            return qsTr("Hier")
        const s = d.toLocaleDateString(Qt.locale(), "dddd d MMMM yyyy")
        return s.charAt(0).toUpperCase() + s.slice(1)
    }

    Connections {
        target: messagingContext
        ignoreUnknownSignals: true
        function onAvailableUsersChanged() { root.refreshPresence() }
        function onPresenceChanged() { root.refreshPresence() }
    }

    onConversationIdChanged: {
        root.refreshPresence()
        root.activateConversationIfVisible()
    }
    onConversationActiveChanged: root.activateConversationIfVisible()
    onIsGroupChanged: root.refreshPresence()

    // ---- Erreur d'envoi -------------------------------------------------
    property string sendErrorMessage: ""

    Connections {
        target: messagingContext
        ignoreUnknownSignals: true
        function onMessageSendFailed(error) {
            root.sendErrorMessage = error
            sendErrorBanner.visible = true
            sendErrorHideTimer.restart()
        }
    }

    Timer {
        id: sendErrorHideTimer
        interval: 6000
        onTriggered: sendErrorBanner.visible = false
    }

    function sendCurrentMessage() {
        const text = composer.text.trim()
        if (text.length === 0 || !messagingContext)
            return
        messagingContext.sendMessage(text)
        composer.text = ""
        composer.forceActiveFocus()
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.bg
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ---- En-tete de conversation ------------------------------------
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.compact ? 54 : 62
            color: Theme.surface0

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 1
                color: Theme.line
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.cardPadding
                anchors.rightMargin: Theme.cardPadding
                spacing: 10

                IconButton {
                    visible: root.showBackButton
                    glyph: ""
                    tooltip: qsTr("Retour")
                    onClicked: root.backRequested()
                }

                Avatar {
                    name: root.displayName
                    size: 36
                    showStatus: !root.isGroup
                    status: root.otherUserStatus
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    Text {
                        text: root.displayName
                        color: Theme.ink
                        font.pixelSize: Theme.fs(14)
                        font.weight: Theme.weightSemibold
                        font.family: Theme.fontFamily
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                        Accessible.role: Accessible.Heading
                    }

                    Text {
                        text: root.isGroup ? qsTr("Conversation de groupe")
                                           : root.presenceLabel(root.otherUserStatus)
                        color: Theme.ink3
                        font.pixelSize: Theme.fs(12)
                        font.family: Theme.fontFamily
                    }
                }
            }
        }

        // ---- Erreur d'envoi -----------------------------------------------
        Rectangle {
            id: sendErrorBanner
            Layout.fillWidth: true
            Layout.preferredHeight: visible ? 40 : 0
            visible: false
            color: Theme.dangerSoft
            clip: true

            Behavior on Layout.preferredHeight { NumberAnimation { duration: Theme.durationFast } }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.cardPadding
                anchors.rightMargin: Theme.cardPadding - 6
                spacing: 8

                FaIcon {
                    glyph: ""
                    color: Theme.dangerInk
                    font.pixelSize: Theme.fs(13)
                }

                Text {
                    Layout.fillWidth: true
                    text: qsTr("Le message n'a pas pu être envoyé : %1").arg(root.sendErrorMessage)
                    color: Theme.dangerInk
                    font.pixelSize: Theme.fs(12)
                    font.family: Theme.fontFamily
                    elide: Text.ElideRight
                }

                IconButton {
                    glyph: ""
                    size: 28
                    iconSize: Theme.fs(11)
                    tooltip: qsTr("Fermer")
                    glyphColorOverride: Theme.dangerInk
                    onClicked: sendErrorBanner.visible = false
                }
            }
        }

        // ---- Messages -----------------------------------------------------
        ListView {
            id: messageListView
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: Theme.spacingLarge
            Layout.rightMargin: Theme.spacingLarge
            spacing: 0
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            verticalLayoutDirection: ListView.TopToBottom
            header: Item { width: 1; height: 12 }
            footer: Item { width: 1; height: 12 }

            model: messagingContext ? messagingContext.messageModel : null

            // Defilement automatique vers le dernier message uniquement si
            // l'utilisateur etait deja en bas (il peut relire l'historique
            // sans etre ramene en bas a chaque message recu).
            property bool wasAtBottom: true
            readonly property int autoScrollTolerance: 50

            Connections {
                target: messageListView.model
                ignoreUnknownSignals: true
                function onRowsAboutToBeInserted() {
                    messageListView.wasAtBottom =
                        messageListView.contentY >= messageListView.contentHeight - messageListView.height - messageListView.autoScrollTolerance
                }
                function onModelAboutToBeReset() {
                    messageListView.wasAtBottom = true
                }
            }

            onCountChanged: Qt.callLater(function() {
                if (messageListView.wasAtBottom)
                    messageListView.positionViewAtEnd()
            })

            delegate: Column {
                id: messageDelegate
                readonly property bool isMine: senderId === root.currentUserId
                width: messageListView.width
                spacing: 0

                readonly property var prevItem: (index > 0 && messagingContext)
                    ? messagingContext.messageModel.get(index - 1) : null
                readonly property var nextItem: (messagingContext && index < messagingContext.messageModel.count - 1)
                    ? messagingContext.messageModel.get(index + 1) : null

                readonly property bool sameSenderAsPrev: prevItem && prevItem.senderId === senderId
                readonly property bool sameSenderAsNext: nextItem && nextItem.senderId === senderId

                readonly property string dayText: {
                    if (!timestamp) return ""
                    const label = root.dayLabel(timestamp)
                    if (messageDelegate.prevItem && messageDelegate.prevItem.timestamp
                            && root.dayLabel(messageDelegate.prevItem.timestamp) === label)
                        return ""
                    return label
                }
                readonly property bool groupStart: !messageDelegate.sameSenderAsPrev || messageDelegate.dayText.length > 0
                readonly property bool groupEnd: !messageDelegate.sameSenderAsNext

                // Separateur de date
                Item {
                    width: parent.width
                    height: messageDelegate.dayText.length > 0 ? 44 : 0
                    visible: messageDelegate.dayText.length > 0

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        height: 1
                        color: Theme.line
                    }
                    Rectangle {
                        anchors.centerIn: parent
                        width: dayLabel.implicitWidth + 20
                        height: 22
                        radius: 11
                        color: Theme.bg
                        border.width: 1
                        border.color: Theme.line

                        Text {
                            id: dayLabel
                            anchors.centerIn: parent
                            text: messageDelegate.dayText
                            color: Theme.ink3
                            font.pixelSize: Theme.fs(11)
                            font.weight: Theme.weightSemibold
                            font.family: Theme.fontFamily
                        }
                    }
                }

                Item {
                    width: 1
                    height: messageDelegate.groupStart ? 10 : 2
                }

                RowLayout {
                    anchors.right: messageDelegate.isMine ? parent.right : undefined
                    anchors.left: messageDelegate.isMine ? undefined : parent.left
                    spacing: 8
                    layoutDirection: messageDelegate.isMine ? Qt.RightToLeft : Qt.LeftToRight

                    Item {
                        visible: !messageDelegate.isMine && root.isGroup
                        Layout.alignment: Qt.AlignBottom
                        Layout.preferredWidth: 28
                        Layout.preferredHeight: 28

                        Avatar {
                            anchors.fill: parent
                            visible: messageDelegate.groupEnd
                            name: messagingContext ? messagingContext.userName(senderId) : ""
                            size: 28
                        }
                    }

                    Rectangle {
                        id: bubble
                        Layout.preferredWidth: Math.min(bubbleColumn.implicitWidth + 24,
                                                         Math.min(messageListView.width * 0.68, 620))
                        Layout.preferredHeight: bubbleColumn.implicitHeight + 16
                        color: messageDelegate.isMine ? Theme.accentColor : Theme.surface0
                        border.width: messageDelegate.isMine ? 0 : 1
                        border.color: Theme.line
                        // Angle "d'ancrage" reduit sur le dernier message
                        // d'un groupe, du cote de l'expediteur.
                        topLeftRadius: 14
                        topRightRadius: 14
                        bottomLeftRadius: (!messageDelegate.isMine && messageDelegate.groupEnd) ? 4 : 14
                        bottomRightRadius: (messageDelegate.isMine && messageDelegate.groupEnd) ? 4 : 14

                        ColumnLayout {
                            id: bubbleColumn
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            anchors.topMargin: 8
                            anchors.bottomMargin: 8
                            spacing: 2

                            Text {
                                Layout.fillWidth: true
                                text: messagingContext ? messagingContext.userName(senderId) : ""
                                visible: !messageDelegate.isMine && root.isGroup && messageDelegate.groupStart
                                font.pixelSize: Theme.fs(12)
                                font.weight: Theme.weightSemibold
                                font.family: Theme.fontFamily
                                color: Theme.colorForName(messagingContext ? messagingContext.userName(senderId) : "")
                            }

                            TextEdit {
                                Layout.fillWidth: true
                                text: content
                                readOnly: true
                                selectByMouse: true
                                wrapMode: Text.Wrap
                                textFormat: TextEdit.PlainText
                                color: messageDelegate.isMine ? Theme.accentInk : Theme.ink
                                selectionColor: messageDelegate.isMine ? Theme.alpha(Theme.accentInk, 0.3) : Theme.accentMuted
                                selectedTextColor: messageDelegate.isMine ? Theme.accentInk : Theme.ink
                                font.pixelSize: Theme.fs(14)
                                font.family: Theme.fontFamily
                            }

                            Text {
                                Layout.alignment: Qt.AlignRight
                                text: timestamp ? new Date(timestamp).toLocaleTimeString(Qt.locale(), "HH:mm") : ""
                                font.pixelSize: Theme.fs(11)
                                font.family: Theme.fontFamily
                                color: messageDelegate.isMine ? Theme.alpha(Theme.accentInk, 0.75) : Theme.ink3
                            }
                        }
                    }
                }
            }

            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            EmptyState {
                anchors.centerIn: parent
                width: Math.min(parent.width, 380)
                height: 220
                visible: messageListView.count === 0
                iconName: "chat"
                title: qsTr("Aucun message pour le moment")
                description: root.isGroup
                             ? qsTr("Envoyez le premier message au groupe.")
                             : qsTr("Envoyez le premier message pour démarrer la conversation avec %1.").arg(root.displayName)
            }
        }

        // ---- Redaction ------------------------------------------------------
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: composerRow.implicitHeight + 24
            color: Theme.surface0

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 1
                color: Theme.line
            }

            RowLayout {
                id: composerRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Theme.cardPadding
                anchors.rightMargin: Theme.cardPadding
                spacing: 10

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(140, Math.max(Theme.controlHeight + 4, composer.implicitHeight + 4))
                    radius: Theme.radiusMedium
                    color: Theme.surface1
                    border.width: 1
                    border.color: composer.activeFocus ? Theme.accentColor : Theme.lineStrong

                    ScrollView {
                        anchors.fill: parent
                        anchors.margins: 2
                        clip: true

                        TextArea {
                            id: composer
                            placeholderText: qsTr("Écrivez un message à %1…").arg(root.displayName)
                            placeholderTextColor: Theme.ink3
                            color: Theme.ink
                            font.pixelSize: Theme.fs(14)
                            font.family: Theme.fontFamily
                            wrapMode: TextArea.Wrap
                            selectByMouse: true
                            selectionColor: Theme.accentColor
                            selectedTextColor: Theme.accentInk
                            leftPadding: 10
                            rightPadding: 10
                            topPadding: 9
                            bottomPadding: 9
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

                IconButton {
                    id: sendButton
                    Layout.alignment: Qt.AlignBottom
                    Layout.bottomMargin: 2
                    size: Theme.controlHeight + 2
                    variant: "primary"
                    glyph: ""
                    iconSize: Theme.fs(14)
                    tooltip: qsTr("Envoyer (Entrée)")
                    enabledLook: composer.text.trim().length > 0
                    onClicked: root.sendCurrentMessage()
                }
            }
        }
    }

    Component.onCompleted: {
        root.activateConversationIfVisible()
        root.refreshPresence()
    }
}
