import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import Core
import "../Components"

/*
 * ChatView - Interface de conversation individuelle
 * Branchee sur MessagingManager via MessagingContext
 */
Item {
    id: root

    property var messagingContext: null
    property var conversationId: 0
    property string name: ""
    property int currentUserId: messagingContext ? messagingContext.currentUserId() : 0

    // CORRECTIF (refonte UI type WhatsApp Web) : quand ChatView est le
    // panneau de droite de ChatWorkspaceView, il n'y a rien "en dessous"
    // dans une pile -- la fleche retour n'a pas de sens et prenait de la
    // place inutilement a cote du nom du contact.
    property bool showBackButton: true

    // Nom reel du contact/groupe : priorite au nom transmis par ConversationsView,
    // sinon repli sur la resolution cote MessagingContext (utile si ouvert sans nom)
    readonly property string displayName: name.length > 0
        ? name
        : (messagingContext ? messagingContext.conversationDisplayName(conversationId) : qsTr("Conversation"))

    signal backRequested()

    // CORRECTIF : un echec d'envoi (pas de conversation active, service
    // deconnecte, erreur base de donnees...) ne produisait auparavant
    // qu'un qWarning() cote C++ -- rien ne remontait jamais ici. Bandeau
    // transitoire, discret mais visible, qui disparait tout seul.
    property string sendErrorMessage: ""

    Connections {
        target: messagingContext
        function onMessageSendFailed(error) {
            root.sendErrorMessage = error
            sendErrorBanner.visible = true
            sendErrorHideTimer.restart()
        }
    }

    Timer {
        id: sendErrorHideTimer
        interval: 4000
        onTriggered: sendErrorBanner.visible = false
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.background
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Header de la conversation
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 64
            color: Theme.surface
            border.width: 0

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
                spacing: Theme.spacingSmall

                Rectangle {
                    Layout.preferredWidth: 36
                    Layout.preferredHeight: 36
                    radius: Theme.radiusMedium
                    color: backArea.containsMouse ? Theme.surfaceHover : "transparent"
                    visible: root.showBackButton

                    Text {
                        anchors.centerIn: parent
                        text: "\u2190"
                        color: Theme.text
                        font.pixelSize: 18
                    }

                    MouseArea {
                        id: backArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.backRequested()
                    }
                }

                Avatar {
                    name: root.displayName
                    size: 36
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    Label {
                        text: root.displayName
                        font.pixelSize: Theme.fontSizeSubheading
                        font.bold: true
                        font.family: Theme.fontFamily
                        color: Theme.text
                    }

                    // Le statut "En ligne" fige a ete retire : il n'y a pas
                    // encore de vrai suivi de presence par conversation.
                }
            }
        }

        // Bandeau d'erreur d'envoi (masque par defaut, cf. sendErrorMessage)
        Rectangle {
            id: sendErrorBanner
            Layout.fillWidth: true
            Layout.preferredHeight: visible ? 36 : 0
            visible: false
            color: "#D93025"
            clip: true

            Behavior on Layout.preferredHeight { NumberAnimation { duration: 120 } }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.spacingMedium
                anchors.rightMargin: Theme.spacingMedium
                spacing: Theme.spacingSmall

                Label {
                    Layout.fillWidth: true
                    text: root.sendErrorMessage
                    color: "#FFFFFF"
                    font.pixelSize: Theme.fontSizeCaption
                    font.family: Theme.fontFamily
                    elide: Text.ElideRight
                }

                Text {
                    text: "\u2715"
                    color: "#FFFFFF"
                    font.pixelSize: 12

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -6
                        cursorShape: Qt.PointingHandCursor
                        onClicked: sendErrorBanner.visible = false
                    }
                }
            }
        }

        // Liste des messages
        ListView {
            id: messageListView
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: Theme.spacingMedium
            spacing: Theme.spacingSmall
            clip: true
            verticalLayoutDirection: ListView.TopToBottom

            model: messagingContext ? messagingContext.messageModel : null

            // CORRECTIF : on capture "etait en bas ?" AVANT que contentHeight
            // ne grandisse avec le nouveau message. Tester la condition dans
            // onCountChanged (ou apres, via callLater) est trop tard : le
            // modele a deja grandi et contentY n'a pas encore ete recalcule,
            // ce qui fausse le test pile pour l'utilisateur qui est en bas.
            // onModelAboutToBeReset n'est pas suffisant ici car l'ajout d'un
            // message declenche un insert, pas un reset ; on ecoute donc le
            // rowsAboutToBeInserted du modele sous-jacent.
            property bool wasAtBottom: true
            readonly property int autoScrollTolerance: 50

            Connections {
                target: messageListView.model
                function onRowsAboutToBeInserted() {
                    messageListView.wasAtBottom =
                        messageListView.contentY >= messageListView.contentHeight - messageListView.height - messageListView.autoScrollTolerance
                }
                function onModelAboutToBeReset() {
                    // Chargement d'une nouvelle conversation (setMessages) :
                    // on veut toujours atterrir en bas de l'historique.
                    messageListView.wasAtBottom = true
                }
            }

            onCountChanged: Qt.callLater(function() {
                if (messageListView.wasAtBottom) {
                    messageListView.positionViewAtEnd()
                }
            })

            delegate: Column {
                id: messageDelegate
                readonly property bool isMine: senderId === root.currentUserId
                width: messageListView.width
                spacing: Theme.spacingXs

                // Separateur de date : affiche si la date change par rapport au message precedent
                Label {
                    id: dateSeparator
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: {
                        if (!timestamp) return ""
                        const dateStr = Qt.formatDate(timestamp, "dd MMMM yyyy")
                        const prevIndex = index - 1
                        if (prevIndex >= 0 && messagingContext) {
                            const prevTimestamp = messagingContext.messageModel.get(prevIndex).timestamp
                            if (prevTimestamp) {
                                const prevDateStr = Qt.formatDate(prevTimestamp, "dd MMMM yyyy")
                                if (dateStr === prevDateStr) return ""
                            }
                        }
                        return dateStr
                    }
                    visible: text.length > 0
                    font.pixelSize: Theme.fontSizeCaption
                    font.family: Theme.fontFamily
                    color: Theme.textTertiary
                    topPadding: Theme.spacingSmall
                    bottomPadding: Theme.spacingSmall
                }

                Row {
                    anchors.right: messageDelegate.isMine ? parent.right : undefined
                    anchors.left: messageDelegate.isMine ? undefined : parent.left
                    width: Math.min(bubbleColumn.implicitWidth + 2 * Theme.spacingMedium,
                                    messageListView.width * 0.72)
                    spacing: Theme.spacingXs

                    Rectangle {
                        id: bubble
                        width: parent.width
                        height: bubbleColumn.implicitHeight + 2 * Theme.spacingSmall
                        radius: Theme.radiusLarge
                        color: messageDelegate.isMine ? Theme.primary : Theme.surface
                        border.width: messageDelegate.isMine ? 0 : 1
                        border.color: Theme.border

                        ColumnLayout {
                            id: bubbleColumn
                            anchors.fill: parent
                            anchors.margins: Theme.spacingSmall
                            spacing: 2

                            Label {
                                Layout.fillWidth: true
                                text: messagingContext ? messagingContext.userName(senderId) : ""
                                visible: !messageDelegate.isMine
                                font.pixelSize: Theme.fontSizeCaption
                                font.bold: true
                                font.family: Theme.fontFamily
                                color: Theme.colorForName(messagingContext ? messagingContext.userName(senderId) : "")
                            }

                            Label {
                                Layout.fillWidth: true
                                text: content
                                wrapMode: Text.WordWrap
                                color: messageDelegate.isMine ? "#FFFFFF" : Theme.text
                                font.pixelSize: Theme.fontSizeBody
                                font.family: Theme.fontFamily
                            }

                            Label {
                                Layout.alignment: Qt.AlignRight
                                text: timestamp ? Qt.formatDateTime(timestamp, "hh:mm") : ""
                                font.pixelSize: Theme.fontSizeCaption
                                font.family: Theme.fontFamily
                                color: messageDelegate.isMine ? "#FFFFFFB0" : Theme.textTertiary
                            }
                        }
                    }
                }
            }

            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
            }
        }

        // Zone de saisie de message
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 76
            color: Theme.surface

            Rectangle {
                anchors.top: parent.top
                width: parent.width
                height: 1
                color: Theme.border
            }

            RowLayout {
                anchors.fill: parent
                anchors.margins: Theme.spacingMedium
                spacing: Theme.spacingSmall

                TextField {
                    id: messageInput
                    Layout.fillWidth: true
                    Layout.preferredHeight: 44
                    placeholderText: qsTr("Ecrivez votre message...")
                    color: Theme.text
                    font.pixelSize: Theme.fontSizeBody
                    font.family: Theme.fontFamily
                    leftPadding: Theme.spacingMedium
                    rightPadding: Theme.spacingMedium
                    selectByMouse: true

                    background: Rectangle {
                        color: Theme.background
                        radius: Theme.radiusPill
                        border.color: messageInput.activeFocus ? Theme.primary : Theme.border
                        border.width: messageInput.activeFocus ? 2 : 1
                        Behavior on border.color { ColorAnimation { duration: 100 } }
                    }

                    onAccepted: sendButton.clicked()
                }

                Rectangle {
                    id: sendButton
                    Layout.preferredWidth: 44
                    Layout.preferredHeight: 44
                    radius: Theme.radiusPill
                    color: messageInput.text.trim().length > 0
                           ? (sendArea.pressed ? Theme.primaryHover : Theme.primary)
                           : Theme.surfaceAlt
                    Behavior on color { ColorAnimation { duration: 100 } }

                    Text {
                        anchors.centerIn: parent
                        text: "\u27A4"
                        color: messageInput.text.trim().length > 0 ? "#FFFFFF" : Theme.textTertiary
                        font.pixelSize: 16
                    }

                    MouseArea {
                        id: sendArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (messageInput.text.trim() !== "" && messagingContext) {
                                messagingContext.sendMessage(messageInput.text)
                                messageInput.text = ""
                                messageInput.forceActiveFocus()
                            }
                        }
                    }
                }
            }
        }
    }

    // Charger la conversation lorsque conversationId change
    onConversationIdChanged: {
        if (messagingContext && conversationId > 0) {
            messagingContext.setConversation(conversationId)
        }
    }

    // Charger la conversation au demarrage
    Component.onCompleted: {
        if (messagingContext && conversationId > 0) {
            messagingContext.setConversation(conversationId)
        }
    }
}
