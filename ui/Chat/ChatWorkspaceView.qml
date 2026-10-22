import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import "../Components"
import "../Components/icons.js" as Icons

/*
 * ChatWorkspaceView - ecran « Discussions » en Ligne claire, meme coque que
 * Transferts et Dossiers partages :
 *
 *   [surtitre · phrase-titre (non lus) · qui a ecrit ........ 2 actions]
 *   [Discussions (liste) | conversation ouverte | fiche (repliable)    ]
 *
 * La page ne defile pas : liste et conversation defilent chacune de leur
 * cote. « Nouvelle discussion » et « Nouveau groupe » ouvrent un volet
 * lateral (NewDiscussionPanel) au lieu des anciennes pages.
 *
 * Les lignes de la liste sont preparees ici (apercu « Vous : », presence,
 * nombre de membres) pour que l'en-tete et la liste lisent la meme source.
 */
Item {
    id: root

    property var messagingContext: null

    // Conversation affichee. null/0 = aucune selection.
    property var currentConversationId: null
    property string currentConversationName: ""

    signal backRequested()
    // Conserves pour compatibilite : le volet remplace desormais ces pages.
    signal newConversationRequested()
    signal createGroupRequested()
    // Vers Transferts : envoyer un fichier a une personne, ouvrir son dossier.
    signal fileTransferRequested(var peer)
    signal exchangesRequested(string peerKey)

    // Fil d'Ariane global (AppShell) : "Discussions / <conversation>".
    readonly property bool hasSelection: root.currentConversationId !== null && root.currentConversationId !== undefined
                                         && root.currentConversationId !== 0
    readonly property string breadcrumbLeaf: root.hasSelection ? chatPanel.displayName : ""
    function breadcrumbRootClicked() { root.currentConversationId = null }

    // Le contexte de messagerie est global, alors que cette page peut rester
    // cachee dans le StackView : la conversation active est retiree des que
    // la page n'est plus Active, pour que les messages recus en arriere-plan
    // restent non lus.
    function syncActiveConversation() {
        if (!messagingContext) return
        if (StackView.status === StackView.Active && root.hasSelection)
            messagingContext.setConversation(root.currentConversationId)
        else
            messagingContext.setConversation(0)
    }
    onCurrentConversationIdChanged: root.syncActiveConversation()
    onMessagingContextChanged: { root.syncActiveConversation(); root.reload() }
    StackView.onStatusChanged: root.syncActiveConversation()

    function openConversation(conversationId, name) {
        root.currentConversationId = conversationId
        root.currentConversationName = name || ""
        root.reading = true
        root.reload()
    }

    // ======================================================================
    // Donnees
    // ======================================================================
    property var rawConversations: []
    property var users: []                  // availableUsers()
    property var peers: []                  // postes connectes (peersModel)
    property var groupMembers: ({})         // conversationId -> memberCount

    Instantiator {
        id: groupSource
        model: root.messagingContext ? root.messagingContext.groupModel : null
        delegate: QtObject {
            required property var conversationId
            required property int memberCount
        }
        onObjectAdded: Qt.callLater(root.rebuildGroups)
        onObjectRemoved: Qt.callLater(root.rebuildGroups)
    }
    function rebuildGroups() {
        const m = {}
        for (let i = 0; i < groupSource.count; i++) {
            const o = groupSource.objectAt(i)
            if (o) m[o.conversationId] = o.memberCount
        }
        root.groupMembers = m
    }

    function reload() {
        if (!messagingContext) return
        root.rawConversations = messagingContext.conversationsList() || []
        root.users = messagingContext.availableUsers() || []
        if (messagingContext.loadUserGroups) messagingContext.loadUserGroups()
        root.reloadPeers()
    }
    function reloadPeers() {
        const list = []
        if (typeof peersModel !== "undefined" && peersModel) {
            const n = peersModel.rowCount ? peersModel.rowCount() : (peersModel.count || 0)
            for (let i = 0; i < n; i++) {
                const idx = peersModel.index(i, 0)
                list.push({ id: peersModel.data(idx, 257) || "", name: peersModel.data(idx, 258) || "",
                            userUuid: peersModel.data(idx, 259) || "", status: peersModel.data(idx, 260) || "",
                            address: peersModel.data(idx, 261) || "", signalingPort: peersModel.data(idx, 264) || 0 })
            }
        }
        root.peers = list
    }
    Connections {
        target: root.messagingContext
        ignoreUnknownSignals: true
        function onConversationsChanged() { root.reload() }
        function onAvailableUsersChanged() { root.reload() }
        function onPresenceChanged() { root.reload() }
    }
    Connections {
        target: (typeof peersModel !== "undefined") ? peersModel : null
        ignoreUnknownSignals: true
        function onCountChanged() { root.reloadPeers() }
        function onRowsInserted() { root.reloadPeers() }
        function onRowsRemoved() { root.reloadPeers() }
        function onModelReset() { root.reloadPeers() }
    }
    Component.onCompleted: { root.reload(); root.syncActiveConversation() }

    function userById(id) {
        for (let i = 0; i < root.users.length; i++) if (root.users[i].userId === id) return root.users[i]
        return null
    }
    // Poste d'une personne : le pair du reseau local qui porte son compte.
    function peerForUser(userId) {
        const u = root.userById(userId)
        if (!u || !u.userUuid) return null
        for (let i = 0; i < root.peers.length; i++) if (root.peers[i].userUuid === u.userUuid) return root.peers[i]
        return null
    }
    function esc(t) { return String(t === undefined || t === null ? "" : t).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;") }

    // Apercu : « Vous : » pour ses messages ; rien devant le message de
    // l'interlocuteur (le C++ ecrit « Lui : », faux pour une interlocutrice) ;
    // prenom de l'expediteur dans un groupe.
    function previewOf(text, isGroup) {
        text = text || ""
        if (text.length === 0) return ""
        if (text.indexOf("Moi : ") === 0) return "<font color=\"" + Theme.ink3 + "\">" + qsTr("Vous : ") + "</font>" + root.esc(text.slice(6))
        if (text.indexOf("Lui : ") === 0) return root.esc(text.slice(6))
        const k = text.indexOf(" : ")
        if (isGroup && k > 0) return "<font color=\"" + Theme.ink3 + "\">" + root.esc(text.slice(0, k).split(" ")[0]) + " : </font>" + root.esc(text.slice(k + 3))
        return root.esc(text)
    }

    readonly property var rows: {
        const ctx = root.messagingContext
        const out = []
        for (let i = 0; i < root.rawConversations.length; i++) {
            const c = root.rawConversations[i]
            const isGroup = ctx ? ctx.isGroupConversation(c.conversationId) : false
            let status = ""
            if (!isGroup && ctx) {
                const other = ctx.otherParticipantId(c.conversationId)
                status = other > 0 ? ctx.userStatus(other) : "offline"
            }
            out.push({ conversationId: c.conversationId, name: c.name || "", rawLast: c.lastMessage || "",
                       preview: root.previewOf(c.lastMessage, isGroup), timestamp: c.timestamp || "",
                       unreadCount: c.unreadCount || 0, isGroup: isGroup, status: status,
                       memberCount: root.groupMembers[c.conversationId] || 0 })
        }
        out.sort(function(a, b) {
            const ta = a.timestamp ? new Date(a.timestamp).getTime() : 0, tb = b.timestamp ? new Date(b.timestamp).getTime() : 0
            return tb - ta
        })
        return out
    }
    function rowFor(id) {
        for (let i = 0; i < root.rows.length; i++) if (root.rows[i].conversationId === id) return root.rows[i]
        return null
    }
    readonly property var currentRow: root.hasSelection ? root.rowFor(root.currentConversationId) : null
    readonly property var currentOtherId: root.hasSelection && root.messagingContext && !(root.currentRow && root.currentRow.isGroup)
                                          ? root.messagingContext.otherParticipantId(root.currentConversationId) : 0
    readonly property var currentPeer: root.currentOtherId > 0 ? root.peerForUser(root.currentOtherId) : null

    readonly property int unreadTotal: root.rows.reduce(function(a, r) { return a + r.unreadCount }, 0)

    // ======================================================================
    // Actions
    // ======================================================================
    function callCurrent() {
        const p = root.currentPeer
        if (p && p.address && typeof callContext !== "undefined" && callContext)
            callContext.call(p.address, p.signalingPort || 0)
    }
    function sendFileToCurrent() {
        const p = root.currentPeer
        if (p) root.fileTransferRequested({ id: p.id, name: p.name, address: p.address, status: p.status, userUuid: p.userUuid })
    }
    function exchangesOfCurrent() {
        const u = root.userById(root.currentOtherId)
        if (u && u.userUuid) root.exchangesRequested("user:" + u.userUuid)
    }

    property bool ficheOpen: false
    property bool reading: true
    property bool panelOpen: false
    property string panelError: ""

    function openPanel(mode) {
        root.panelError = ""
        panel.reset(mode)
        root.panelOpen = true
    }
    readonly property var panelPeople: {
        const existing = {}
        const ctx = root.messagingContext
        for (let i = 0; i < root.rawConversations.length; i++) {
            const c = root.rawConversations[i]
            if (ctx && !ctx.isGroupConversation(c.conversationId) && c.lastMessage) {
                const o = ctx.otherParticipantId(c.conversationId)
                if (o > 0) existing[o] = true
            }
        }
        return root.users.map(function(u) {
            const p = root.peerForUser(u.userId)
            return { userId: u.userId, username: u.username, status: ctx ? ctx.userStatus(u.userId) : "",
                     machineName: p ? p.name : "", existing: existing[u.userId] === true }
        })
    }

    // ======================================================================
    // Mise en page
    // ======================================================================
    readonly property real pageW: width - 2 * Theme.pagePadding
    readonly property real listW: pageW > 1240 ? 330 : 290
    readonly property bool ficheDocked: pageW > 1240
    readonly property bool narrow: pageW < 760

    Rectangle { anchors.fill: parent; color: Theme.bg }

    ColumnLayout {
        id: pageColumn
        x: Theme.pagePadding
        y: Theme.compact ? 14 : 18
        width: root.width - 2 * Theme.pagePadding
        height: root.height - y
        spacing: 14

        // ---- En-tete compact ----------------------------------------------
        GridLayout {
            Layout.fillWidth: true
            columns: root.pageW > 900 ? 2 : 1
            columnSpacing: 24
            rowSpacing: 10
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                CapsLabel {
                    Layout.fillWidth: true
                    text: {
                        const d = new Date().toLocaleDateString(Qt.locale(), "dddd d MMMM yyyy")
                        return d + ((typeof settingsModel !== "undefined" && settingsModel && settingsModel.machineName && settingsModel.machineName.length > 0)
                                    ? " · " + settingsModel.machineName : "")
                    }
                }
                Text {
                    Layout.fillWidth: true
                    textFormat: Text.StyledText
                    text: root.rows.length === 0 ? qsTr("Aucune discussion.")
                          : root.unreadTotal === 0 ? qsTr("Tout est lu.")
                          : root.unreadTotal === 1 ? qsTr("<b>1</b> message non lu.")
                          : qsTr("<b>%1</b> messages non lus.").arg(root.unreadTotal)
                    color: Theme.ink
                    font.family: Theme.fontFamilySerif
                    font.pixelSize: root.height < 720 ? Theme.fs(26) : Theme.fs(30)
                    elide: Text.ElideRight
                    Accessible.role: Accessible.Heading
                }
                Text {
                    Layout.fillWidth: true
                    textFormat: Text.StyledText
                    wrapMode: Text.WordWrap
                    color: Theme.ink2
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(14.5)
                    text: {
                        if (root.rows.length === 0)
                            return qsTr("Écrivez à un collègue du réseau local, ou créez un groupe pour un service ou un projet.")
                        const unread = root.rows.filter(function(r) { return r.unreadCount > 0 })
                        if (unread.length === 0) {
                            const g = root.rows.filter(function(r) { return r.isGroup }).length
                            return qsTr("%1 discussions, dont %2 groupe(s).").arg(root.rows.length).arg(g)
                        }
                        const top = unread[0]
                        const when = top.timestamp ? new Date(top.timestamp).toLocaleTimeString(Qt.locale(), "HH:mm") : ""
                        let t
                        if (top.isGroup) {
                            const k = top.rawLast.indexOf(" : ")
                            const who = k > 0 && top.rawLast.indexOf("Moi : ") !== 0 ? top.rawLast.slice(0, k).split(" ")[0] : ""
                            t = who.length ? qsTr("<b>%1</b> a écrit à %2 dans « %3 ».").arg(root.esc(who)).arg(when).arg(root.esc(top.name))
                                           : qsTr("Nouveau message à %1 dans « %2 ».").arg(when).arg(root.esc(top.name))
                        } else {
                            t = qsTr("<b>%1</b> vous a écrit à %2.").arg(root.esc(top.name)).arg(when)
                        }
                        if (unread.length > 1)
                            t += " " + qsTr("Nouveaux messages dans %1.").arg(unread.slice(0, 3).map(function(r) {
                                return "<font color=\"" + Theme.navActiveInk + "\"><b>" + root.esc(r.name) + "</b></font>" }).join(", "))
                        return t
                    }
                }
            }
            Row {
                Layout.alignment: root.pageW > 900 ? (Qt.AlignRight | Qt.AlignBottom) : Qt.AlignLeft
                spacing: 8
                AppButton { variant: "ink"; iconPath: Icons.messageCircle; text: qsTr("Nouvelle discussion"); onClicked: root.openPanel("person") }
                AppButton { variant: "line"; iconPath: Icons.users; text: qsTr("Nouveau groupe"); onClicked: root.openPanel("group") }
            }
        }

        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 2; color: Theme.ruleInk }

        // ---- Liste | conversation | fiche ---------------------------------
        Item {
            id: work
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: -14

            ConversationsView {
                id: listPanel
                visible: !root.narrow || !root.reading || !root.hasSelection
                x: 0
                width: root.narrow ? work.width : root.listW - 18
                height: work.height
                conversations: root.rows
                selectedConversationId: root.currentConversationId
                onConversationSelected: function(conversationId, name) { root.openConversation(conversationId, name) }
            }
            Rectangle {
                visible: !root.narrow
                x: root.listW
                width: 1
                height: work.height
                color: Theme.line
            }

            Item {
                id: threadArea
                visible: !root.narrow || (root.reading && root.hasSelection)
                x: root.narrow ? 0 : root.listW + 1
                width: work.width - x - (root.ficheOpen && root.ficheDocked && root.hasSelection ? 301 : 0)
                height: work.height

                ChatView {
                    id: chatPanel
                    anchors.fill: parent
                    visible: root.hasSelection
                    messagingContext: root.messagingContext
                    conversationId: root.currentConversationId || 0
                    name: root.currentConversationName
                    conversationActive: root.StackView.status === StackView.Active && chatPanel.visible
                    status: root.currentOtherId > 0 && root.messagingContext ? root.messagingContext.userStatus(root.currentOtherId) : "offline"
                    machineName: root.currentPeer ? root.currentPeer.name : ""
                    memberCount: root.currentRow ? root.currentRow.memberCount : 0
                    ficheOpen: root.ficheOpen
                    showBackButton: root.narrow
                    onBackRequested: root.reading = false
                    onCallRequested: root.callCurrent()
                    onSendFileRequested: root.sendFileToCurrent()
                    onFicheToggled: root.ficheOpen = !root.ficheOpen
                }

                // Aucune discussion ouverte
                ColumnLayout {
                    visible: !root.hasSelection
                    anchors.centerIn: parent
                    width: Math.min(parent.width - 48, 420)
                    spacing: 6
                    CapsLabel { Layout.alignment: Qt.AlignHCenter; text: root.rows.length ? qsTr("Aucune discussion ouverte") : qsTr("Pour commencer") }
                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: root.rows.length ? qsTr("Choisissez une discussion.") : qsTr("Écrivez à un collègue.")
                        color: Theme.ink
                        font.family: Theme.fontFamilySerif
                        font.pixelSize: Theme.fs(24)
                    }
                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        text: root.rows.length ? qsTr("Ou démarrez-en une nouvelle avec une personne ou un groupe du réseau local.")
                                               : qsTr("Les messages passent par le réseau local, sans Internet. Une discussion par personne, et autant de groupes que nécessaire.")
                        color: Theme.ink3
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(13)
                    }
                    Row {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 10
                        spacing: 8
                        AppButton { variant: "ink"; iconPath: Icons.messageCircle; text: qsTr("Nouvelle discussion"); onClicked: root.openPanel("person") }
                        AppButton { variant: "line"; iconPath: Icons.users; text: qsTr("Nouveau groupe"); onClicked: root.openPanel("group") }
                    }
                }
            }

            // Fiche : colonne a droite, ou en surimpression quand la place manque.
            Rectangle {
                visible: root.ficheOpen && root.hasSelection
                x: work.width - 300 - (root.ficheDocked ? 1 : 0)
                width: root.ficheDocked ? 1 : 0
                height: work.height
                color: Theme.line
            }
            ChatFiche {
                id: fiche
                visible: root.ficheOpen && root.hasSelection
                x: work.width - width
                width: 300
                height: work.height
                z: 3
                name: chatPanel.displayName
                group: !!root.currentRow && root.currentRow.isGroup
                status: chatPanel.status
                machineName: root.currentPeer ? root.currentPeer.name : ""
                address: root.currentPeer ? root.currentPeer.address : ""
                memberCount: root.currentRow ? root.currentRow.memberCount : 0
                messageCount: chatPanel.messageCount
                unreadCount: root.currentRow ? root.currentRow.unreadCount : 0
                onCallRequested: root.callCurrent()
                onSendFileRequested: root.sendFileToCurrent()
                onExchangesRequested: root.exchangesOfCurrent()
                // Ombre a gauche quand elle passe au-dessus de la conversation.
                Rectangle {
                    visible: !root.ficheDocked
                    x: -24
                    width: 24
                    height: parent.height
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 1.0; color: Theme.shadowStrong }
                    }
                }
            }
        }
    }

    // ---- volet « Nouvelle discussion » -----------------------------------
    Item {
        id: panelHost
        anchors.fill: parent
        z: 30
        visible: root.panelOpen || panel.x < panelHost.width

        Rectangle {
            anchors.fill: parent
            color: Theme.scrim
            opacity: root.panelOpen ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 160 } }
            MouseArea { anchors.fill: parent; enabled: root.panelOpen; onClicked: root.panelOpen = false }
        }
        NewDiscussionPanel {
            id: panel
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: root.narrow ? panelHost.width : Math.min(460, panelHost.width - 48)
            x: root.panelOpen ? panelHost.width - width : panelHost.width
            Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            people: root.panelPeople
            errorText: root.panelError
            onCloseRequested: root.panelOpen = false
            onErrorDismissed: root.panelError = ""
            onPersonChosen: function(userId) {
                if (!root.messagingContext) return
                const id = root.messagingContext.startConversationWith(userId)
                if (id > 0) {
                    root.panelOpen = false
                    const u = root.userById(userId)
                    root.openConversation(id, u ? u.username : "")
                } else {
                    root.panelError = qsTr("La discussion n'a pas pu être ouverte. Vérifiez la connexion au serveur puis réessayez.")
                }
            }
            onGroupRequested: function(name, memberIds) {
                if (!root.messagingContext) return
                const groupId = root.messagingContext.createGroup(name, memberIds)
                if (groupId > 0) {
                    root.panelOpen = false
                    const conv = root.messagingContext.messageModel ? root.messagingContext.messageModel.conversationId : 0
                    root.reload()
                    if (conv > 0) root.openConversation(conv, name)
                } else {
                    root.panelError = qsTr("Le groupe n'a pas pu être créé. Vérifiez votre connexion au serveur puis réessayez.")
                }
            }
        }
    }
    Shortcut {
        sequences: [StandardKey.Cancel]
        enabled: root.panelOpen
        onActivated: root.panelOpen = false
    }
}
