import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import Core
import "../Components"

/*
 * ChatView - Interface de conversation individuelle
 * Branchee sur MessagingManager via MessagingContext
 *
 * REFONTE (alignement design system) : header et zone de saisie flottants
 * avec ombre douce plutot que des filets 1px, bulles regroupees par
 * expediteur (WhatsApp/Telegram-like) avec avatar affiche uniquement sur
 * le dernier message d'un groupe, separateurs de date en "pilule", et
 * etat vide illustre. Aucune logique metier modifiee.
 */
Item {
    id: root

    property var messagingContext: null
    property var conversationId: 0
    property string name: ""
    // Une instance de ChatView peut rester vivante sous une autre page du
    // StackView. Dans ce cas elle ne doit surtout pas faire croire au modele
    // que l'utilisateur lit encore la conversation.
    property bool conversationActive: true
    property int currentUserId: messagingContext ? messagingContext.currentUserId() : 0
    readonly property bool isGroup: messagingContext ? messagingContext.isGroupConversation(conversationId) : false

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

    function activateConversationIfVisible() {
        if (conversationActive && messagingContext && conversationId > 0)
            messagingContext.setConversation(conversationId)
    }

    // Statut de presence de l'autre participant (conversation individuelle
    // uniquement -- une conversation de groupe n'a pas de statut unique).
    // Rafraichi manuellement via refreshPresence(), car userStatus()/
    // otherParticipantId() sont des Q_INVOKABLE sans NOTIFY : un binding
    // direct ne se reevaluerait pas quand le statut change cote C++.
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
        default: return qsTr("Hors ligne")
        }
    }

    function presenceColor(status) {
        switch (status) {
        case "online": return Theme.success
        case "away": return Theme.warning
        default: return Theme.textTertiary
        }
    }

    // Le statut peut changer (login/logout/mise en veille d'un autre
    // poste) pendant que la conversation reste ouverte -- on ecoute donc
    // le meme signal qu'utilise availableUsers() (emis par UserManager a
    // chaque userUpdated/usersChanged) plutot que de ne rafraichir qu'a
    // l'ouverture.
    Connections {
        target: messagingContext
        function onAvailableUsersChanged() { root.refreshPresence() }
        function onPresenceChanged() { root.refreshPresence() }
    }

    onConversationIdChanged: {
        root.refreshPresence()
        root.activateConversationIfVisible()
    }
    onConversationActiveChanged: root.activateConversationIfVisible()
    onIsGroupChanged: root.refreshPresence()

    // Police d'icones Font Awesome 4.7.0 pour l'illustration de l'etat vide
    // (meme police que IconButton/Avatar, chargee ici car ce glyphe est
    // utilise en dehors de ces composants).
    FontLoader {
        id: emptyStateIconFont
        source: "../Assets/fonts/fontawesome-webfont.ttf"
    }

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

    // Fond legerement teinte (au lieu d'un blanc/gris plat) pour donner de
    // la profondeur derriere les bulles, a la maniere des messageries
    // modernes -- tres subtil, reste dans la palette du theme.
    Rectangle {
        anchors.fill: parent
        color: Theme.background
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Header de la conversation -- flotte au-dessus de la liste avec
        // une ombre douce plutot qu'un filet 1px, pour un rendu plus
        // "carte" et moins tableur.
        Rectangle {
            id: header
            Layout.fillWidth: true
            Layout.preferredHeight: 72
            color: Theme.surface
            z: 2

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.bottom
                height: 8
                z: -1
                gradient: Gradient {
                    orientation: Gradient.Vertical
                    GradientStop { position: 0.0; color: Theme.shadowSoft }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.spacingMedium
                anchors.rightMargin: Theme.spacingMedium
                spacing: Theme.spacingMedium

                IconButton {
                    glyph: "\uf060"
                    variant: "ghost"
                    visible: root.showBackButton
                    onClicked: root.backRequested()
                }

                // Avatar + nom regroupes cote a cote (meme cluster, faible
                // espacement) plutot qu'espaces uniformement avec le
                // bouton retour -- rendu "identite du contact" a la
                // WhatsApp Web, ou l'avatar colle au nom.
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingSmall

                    Avatar {
                        name: root.displayName
                        size: 40
                        showStatus: !root.isGroup
                        online: root.otherUserStatus === "online"
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
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        // Statut de presence reel de l'autre participant
                        // (UserManager), absent pour les conversations de
                        // groupe qui n'ont pas d'interlocuteur unique.
                        Label {
                            visible: !root.isGroup
                            text: root.presenceLabel(root.otherUserStatus)
                            font.pixelSize: Theme.fontSizeCaption
                            font.family: Theme.fontFamily
                            color: root.presenceColor(root.otherUserStatus)
                        }
                    }
                }
            }
        }

        // Bandeau d'erreur d'envoi (masque par defaut, cf. sendErrorMessage)
        Rectangle {
            id: sendErrorBanner
            Layout.fillWidth: true
            Layout.preferredHeight: visible ? 36 : 0
            visible: false
            color: Theme.error
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
                    color: Theme.primaryText
                    font.pixelSize: Theme.fontSizeCaption
                    font.family: Theme.fontFamily
                    elide: Text.ElideRight
                }

                Text {
                    text: "\u2715"
                    color: Theme.primaryText
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
            spacing: 0
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
                spacing: 2

                // Le message precedent (meme expediteur, meme jour) : sert a
                // regrouper visuellement une rafale de messages consecutifs
                // (moins d'espace entre eux, nom/avatar affiches une seule
                // fois) plutot que de repeter l'en-tete a chaque bulle.
                readonly property var prevItem: (index > 0 && messagingContext)
                    ? messagingContext.messageModel.get(index - 1) : null
                readonly property var nextItem: (messagingContext && index < messagingContext.messageModel.count - 1)
                    ? messagingContext.messageModel.get(index + 1) : null

                readonly property bool sameSenderAsPrev: prevItem && prevItem.senderId === senderId
                readonly property bool sameSenderAsNext: nextItem && nextItem.senderId === senderId

                // Separateur de date : affiche si la date change par rapport au message precedent
                Item {
                    width: parent.width
                    height: dateSeparator.visible ? dateSeparator.implicitHeight + Theme.spacingMedium * 2 : 0

                    readonly property string dateText: {
                        if (!timestamp) return ""
                        const dateStr = Qt.formatDate(timestamp, "dd MMMM yyyy")
                        if (messageDelegate.prevItem && messageDelegate.prevItem.timestamp) {
                            const prevDateStr = Qt.formatDate(messageDelegate.prevItem.timestamp, "dd MMMM yyyy")
                            if (dateStr === prevDateStr) return ""
                        }
                        return dateStr
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        visible: dateSeparator.visible
                        radius: Theme.radiusPill
                        color: Theme.surfaceAlt
                        width: dateSeparator.implicitWidth + Theme.spacingMedium * 2
                        height: dateSeparator.implicitHeight + Theme.spacingXs * 2

                        Label {
                            id: dateSeparator
                            anchors.centerIn: parent
                            text: parent.parent.dateText
                            visible: text.length > 0
                            font.pixelSize: Theme.fontSizeCaption
                            font.bold: true
                            font.family: Theme.fontFamily
                            color: Theme.textSecondary
                        }
                    }
                }

                // Espace entre groupes de messages : resserre au sein d'une
                // meme rafale (meme expediteur, meme jour), plus genereux
                // entre deux interlocuteurs differents.
                Item {
                    width: 1
                    height: (messageDelegate.sameSenderAsPrev && dateSeparator.text.length === 0)
                            ? Theme.spacingXs
                            : Theme.spacingMedium
                }

                RowLayout {
                    id: messageRow
                    anchors.right: messageDelegate.isMine ? parent.right : undefined
                    anchors.left: messageDelegate.isMine ? undefined : parent.left
                    spacing: Theme.spacingXs
                    layoutDirection: messageDelegate.isMine ? Qt.RightToLeft : Qt.LeftToRight

                    // Avatar affiche uniquement sur le dernier message d'une
                    // rafale (comme WhatsApp) : evite de repeter la meme
                    // pastille a cote de chaque ligne d'une meme personne.
                    // Un espaceur invisible de meme largeur garde les bulles
                    // alignees pour le reste de la rafale.
                    Avatar {
                        Layout.alignment: Qt.AlignBottom
                        visible: !messageDelegate.isMine && root.isGroup
                        name: messagingContext ? messagingContext.userName(senderId) : ""
                        size: 26
                        opacity: !messageDelegate.sameSenderAsNext ? 1 : 0
                    }

                    // Plafond absolu (640px) en plus du pourcentage : sur un
                    // ecran desktop tres large, une bulle a 72% de la
                    // largeur de la liste peut depasser 1000px et devenir
                    // difficile a lire malgre le wrapMode.
                    Rectangle {
                        id: bubble
                        Layout.preferredWidth: Math.min(bubbleColumn.implicitWidth + 2 * Theme.spacingMedium,
                                                         Math.min(messageListView.width * 0.72, 640))
                        Layout.preferredHeight: bubbleColumn.implicitHeight + 2 * Theme.spacingSmall
                        radius: Theme.radiusMedium
                        color: messageDelegate.isMine ? Theme.primary : Theme.surface
                        border.width: messageDelegate.isMine ? 0 : 1
                        border.color: Theme.border

                        // Ombre douce simulee (meme technique que Toast.qml)
                        // plutot qu'une bordure epaisse -- donne du relief
                        // aux bulles sans alourdir visuellement le fil.
                        Rectangle {
                            anchors.fill: parent
                            anchors.topMargin: 2
                            radius: parent.radius
                            color: Theme.shadowSoft
                            z: -1
                        }

                        ColumnLayout {
                            id: bubbleColumn
                            anchors.fill: parent
                            anchors.margins: Theme.spacingSmall
                            spacing: 2

                            Label {
                                Layout.fillWidth: true
                                text: messagingContext ? messagingContext.userName(senderId) : ""
                                // Uniquement sur le premier message d'une rafale : le
                                // nom de l'expediteur n'a pas besoin d'etre repete
                                // sur chaque ligne d'une meme personne.
                                visible: !messageDelegate.isMine && root.isGroup && !messageDelegate.sameSenderAsPrev
                                font.pixelSize: Theme.fontSizeCaption
                                font.bold: true
                                font.family: Theme.fontFamily
                                color: Theme.colorForName(messagingContext ? messagingContext.userName(senderId) : "")
                            }

                            Label {
                                Layout.fillWidth: true
                                text: content
                                wrapMode: Text.WordWrap
                                color: messageDelegate.isMine ? Theme.primaryText : Theme.text
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

            // Etat vide : premiere ouverture d'une conversation sans historique.
            ColumnLayout {
                anchors.centerIn: parent
                visible: messageListView.count === 0
                spacing: Theme.spacingSmall

                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    width: 64
                    height: 64
                    radius: 32
                    color: Theme.surfaceAlt

                    Text {
                        anchors.centerIn: parent
                        text: "\uf0e6"
                        font.family: emptyStateIconFont.name
                        font.pixelSize: 24
                        color: Theme.textTertiary
                    }
                }

                Label {
                    Layout.alignment: Qt.AlignHCenter
                    text: qsTr("Aucun message pour le moment")
                    font.pixelSize: Theme.fontSizeBody
                    font.bold: true
                    font.family: Theme.fontFamily
                    color: Theme.textSecondary
                }

                Label {
                    Layout.alignment: Qt.AlignHCenter
                    text: qsTr("Envoyez le premier message pour demarrer la conversation.")
                    font.pixelSize: Theme.fontSizeSmall
                    font.family: Theme.fontFamily
                    color: Theme.textTertiary
                }
            }
        }

        // Zone de saisie de message -- pilule flottante (fond distinct du
        // champ) plutot qu'un simple champ carre pose sur un filet, pour un
        // rendu plus proche des messageries actuelles.
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 80
            color: Theme.surface
            z: 2

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.top
                height: 8
                z: -1
                gradient: Gradient {
                    orientation: Gradient.Vertical
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 1.0; color: Theme.shadowSoft }
                }
            }

            RowLayout {
                anchors.fill: parent
                anchors.margins: Theme.spacingMedium
                spacing: Theme.spacingSmall

                AppTextField {
                    id: messageInput
                    Layout.fillWidth: true
                    placeholderText: qsTr("Ecrivez votre message...")
                    onAccepted: sendButton.clicked()
                }

                IconButton {
                    id: sendButton
                    size: 44
                    radius: Theme.radiusMedium
                    variant: "primary"
                    glyph: "\uf1d8"
                    enabledLook: messageInput.text.trim().length > 0
                    onClicked: {
                        if (messageInput.text.trim() !== "" && messagingContext) {
                            messagingContext.sendMessage(messageInput.text)
                            messageInput.text = ""
                            messageInput.field.forceActiveFocus()
                        }
                    }
                }
            }
        }
    }

    // Charger la conversation au demarrage
    Component.onCompleted: {
        root.activateConversationIfVisible()
        root.refreshPresence()
    }
}
