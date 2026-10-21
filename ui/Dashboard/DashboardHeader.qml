import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import "../Components"

/*
 * DashboardHeader - barre de contexte de LocaLink (Ligne claire A2).
 *
 * Gauche  : titre de la page en PT Serif (premier segment du fil d'Ariane),
 *           suivi de l'element ouvert ; bouton de menu quand la barre
 *           laterale est repliee en rail sur une fenetre etroite.
 * Droite  : recherche globale, etat du reseau (role reel dans l'election,
 *           forme + libelle), centre de notifications. La bascule de theme
 *           vit dans Parametres > Apparence (showThemeToggle).
 *
 * La recherche interroge des donnees reelles : les sections de
 * l'application, les postes decouverts (peersModel) et les conversations
 * (messagingContext.conversationsList()). Ctrl+K ou "/" pour l'ouvrir.
 *
 * Le centre de notifications liste les evenements recus pendant la session
 * (fournis par l'hote, voir AppShell) : aucune notification fictive.
 */
Item {
    id: root
    implicitHeight: Theme.topbarHeight
    height: Theme.topbarHeight

    // Fil d'Ariane : "Section / Element" (compatibilite) ou section + leaf.
    property string breadcrumb: ""
    readonly property var breadcrumbParts: root.breadcrumb.length > 0 ? root.breadcrumb.split(" / ") : []

    property bool showSearch: true
    property bool showNotifications: true
    property bool showThemeToggle: false
    // Bouton « afficher la navigation » (rail sur fenetre etroite).
    property bool showMenuButton: false
    property bool menuOpen: false
    property bool isAdmin: false

    // Etat reseau
    property string networkLabel: ""
    property color networkColor: Theme.successColor
    // "server" | "backup" | "client" : la forme du repere double la couleur.
    property string networkState: "server"

    // Notifications de session : [{ title, message, category, time (Date),
    // conversationId, read }]
    property var notifications: []
    property int notificationCount: 0

    signal searchRequested(string query)
    signal notificationsRequested()
    signal segmentClicked(int index, string label)
    signal navigateRequested(string route)
    signal conversationRequested(int conversationId)
    signal notificationActivated(int index)
    signal markAllRead()
    signal clearNotifications()
    signal menuRequested()
    // Poste choisi dans la recherche (identifiant peersModel).
    signal peerRequested(string peerId, string peerName)

    Rectangle {
        anchors.fill: parent
        color: Theme.bg

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            color: Theme.line
        }
    }

    Shortcut {
        sequences: ["Ctrl+K"]
        enabled: root.showSearch && root.visible
        onActivated: root.openSearch()
    }

    function openSearch() {
        searchField.forceActiveFocus()
        searchField.selectAll()
        searchPopup.open()
    }

    // ---- Recherche : resultats calcules a la demande -------------------
    readonly property var sections: {
        const list = [
            { route: "home",     label: qsTr("Vue d'ensemble"),     glyph: "", keywords: "accueil tableau bord dashboard" },
            { route: "chat",     label: qsTr("Discussions"),        glyph: "", keywords: "messages messagerie conversation" },
            { route: "transfer", label: qsTr("Transferts"),         glyph: "", keywords: "fichiers envoyer recevoir" },
            { route: "folder",   label: qsTr("Dossiers partagés"),  glyph: "", keywords: "partage synchronisation" },
            { route: "call",     label: qsTr("Appels"),             glyph: "", keywords: "voix telephone" },
            { route: "peers",    label: qsTr("Postes"),             glyph: "", keywords: "machines ordinateurs reseau" },
            { route: "settings", label: qsTr("Paramètres"),         glyph: "", keywords: "apparence theme compte reseau" }
        ]
        if (root.isAdmin) {
            list.push({ route: "journal", label: qsTr("Journal d'audit"), glyph: "", keywords: "audit evenements securite" })
            list.push({ route: "admin",   label: qsTr("Administration"),  glyph: "", keywords: "comptes utilisateurs autorisations machines" })
        }
        return list
    }

    function normalize(s) {
        return (s || "").toString().toLowerCase()
            .normalize("NFD").replace(/[̀-ͯ]/g, "")
    }

    property var results: []

    function runSearch(text) {
        const q = root.normalize(text.trim())
        const out = []
        if (q.length === 0) {
            root.results = []
            return
        }
        for (let i = 0; i < root.sections.length; i++) {
            const s = root.sections[i]
            if (root.normalize(s.label).indexOf(q) >= 0 || s.keywords.indexOf(q) >= 0)
                out.push({ kind: "section", group: qsTr("Sections"), label: s.label, detail: "", glyph: s.glyph, route: s.route })
        }
        if (typeof peersModel !== "undefined" && peersModel) {
            let found = 0
            for (let p = 0; p < peersModel.count && found < 6; p++) {
                const idx = peersModel.index(p, 0)
                const pid = peersModel.data(idx, 257) || ""
                const name = peersModel.data(idx, 258) || ""
                const addr = peersModel.data(idx, 261) || ""
                if (root.normalize(name).indexOf(q) >= 0 || addr.indexOf(q) >= 0) {
                    out.push({ kind: "peer", group: qsTr("Postes"), label: name || addr, detail: addr, peerId: pid, glyph: "", route: "peers" })
                    found++
                }
            }
        }
        if (typeof messagingContext !== "undefined" && messagingContext) {
            const convs = messagingContext.conversationsList() || []
            let found = 0
            for (let c = 0; c < convs.length && found < 6; c++) {
                // Champs de MessagingContext::conversationsList() :
                // conversationId, name, lastMessage, timestamp, unreadCount.
                const conv = convs[c]
                const title = conv.name || ""
                const convId = conv.conversationId || 0
                if (title.length > 0 && root.normalize(title).indexOf(q) >= 0) {
                    out.push({ kind: "conversation", group: qsTr("Conversations"), label: title,
                               detail: conv.unreadCount > 0 ? qsTr("%1 non lu(s)").arg(conv.unreadCount) : "",
                               glyph: messagingContext.isGroupConversation(convId) ? "" : "",
                               conversationId: convId })
                    found++
                }
            }
        }
        root.results = out
        resultsList.currentIndex = out.length > 0 ? 0 : -1
    }

    function activateResult(item) {
        if (!item)
            return
        searchPopup.close()
        searchField.text = ""
        searchField.focus = false
        if (item.kind === "conversation" && item.conversationId > 0)
            root.conversationRequested(item.conversationId)
        else if (item.kind === "peer" && item.peerId)
            root.peerRequested(item.peerId, item.label)
        else
            root.navigateRequested(item.route)
    }

    function timeLabel(d) {
        if (!d)
            return ""
        const seconds = Math.max(0, Math.round((Date.now() - d.getTime()) / 1000))
        if (seconds < 60) return qsTr("à l'instant")
        const minutes = Math.round(seconds / 60)
        if (minutes < 60) return qsTr("il y a %1 min").arg(minutes)
        return d.toLocaleTimeString(Qt.locale(), "HH:mm")
    }

    function categoryGlyph(category) {
        switch (category) {
        case "message": return ""
        case "transfer": return ""
        case "folder": return ""
        case "connection": return ""
        case "disconnection": return ""
        case "group": return ""
        case "call": return ""
        default: return ""
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.pagePadding
        anchors.rightMargin: Theme.pagePadding - 8
        anchors.bottomMargin: 1
        spacing: 10

        // ---- Menu (rail sur fenetre etroite) ----------------------------
        AbstractButton {
            id: menuButton
            visible: root.showMenuButton
            Layout.preferredWidth: 34
            Layout.preferredHeight: 34
            Layout.leftMargin: -8
            hoverEnabled: true
            focusPolicy: Qt.TabFocus
            Accessible.name: root.menuOpen ? qsTr("Masquer la navigation") : qsTr("Afficher la navigation")
            onClicked: root.menuRequested()
            HoverHandler { cursorShape: Qt.PointingHandCursor }

            background: Rectangle {
                radius: 17
                color: menuButton.hovered || root.menuOpen ? Theme.selectWash : "transparent"
                border.width: menuButton.visualFocus ? 2 : 0
                border.color: Theme.focusRing
            }
            contentItem: Item {
                LineIcon {
                    anchors.centerIn: parent
                    path: "M4 6.5h16 M4 12h16 M4 17.5h16"
                    size: 18
                    strokeWidth: 1.7
                    color: Theme.ink2
                }
            }
        }

        // ---- Titre de la page + element ouvert -----------------------------
        Row {
            spacing: 10
            Layout.fillWidth: true
            Layout.minimumWidth: 80
            clip: true

            Text {
                id: pageTitle
                anchors.verticalCenter: parent.verticalCenter
                text: root.breadcrumbParts.length > 0 ? root.breadcrumbParts[0] : ""
                color: Theme.ink
                font.pixelSize: Theme.fontSizePageTitle
                font.weight: Theme.weightBold
                font.family: Theme.fontFamilySerif
                font.underline: root.breadcrumbParts.length > 1 && titleHover.hovered
                elide: Text.ElideRight
                Accessible.role: Accessible.Heading

                HoverHandler {
                    id: titleHover
                    enabled: root.breadcrumbParts.length > 1
                    cursorShape: Qt.PointingHandCursor
                }
                TapHandler {
                    enabled: root.breadcrumbParts.length > 1
                    onTapped: root.segmentClicked(0, pageTitle.text)
                }
            }

            Repeater {
                model: root.breadcrumbParts.slice(1)

                delegate: Row {
                    id: crumb
                    required property int index
                    required property string modelData
                    readonly property bool isLast: crumb.index === root.breadcrumbParts.length - 2
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    Text {
                        text: "/"
                        color: Theme.inkDisabled
                        font.pixelSize: Theme.fs(13)
                        font.family: Theme.fontFamily
                    }
                    Text {
                        text: crumb.modelData
                        color: crumb.isLast ? Theme.ink2 : (crumbHover.hovered ? Theme.ink : Theme.ink3)
                        font.pixelSize: Theme.fs(13)
                        font.weight: crumb.isLast ? Theme.weightMedium : Theme.weightRegular
                        font.family: Theme.fontFamily
                        font.underline: !crumb.isLast && crumbHover.hovered
                        elide: Text.ElideRight

                        HoverHandler {
                            id: crumbHover
                            enabled: !crumb.isLast
                            cursorShape: Qt.PointingHandCursor
                        }
                        TapHandler {
                            enabled: !crumb.isLast
                            onTapped: root.segmentClicked(crumb.index + 1, crumb.modelData)
                        }
                    }
                }
            }
        }

        // ---- Recherche ---------------------------------------------------
        Rectangle {
            id: searchBox
            // Fenetre etroite : la recherche se replie en loupe et se deplie
            // a la prise de focus (clic ou Ctrl+K).
            readonly property bool collapsed: root.width < 860 && !searchField.activeFocus
                                              && searchField.text.length === 0
            visible: root.showSearch
            Layout.preferredWidth: collapsed ? Theme.controlHeightEditorial : (root.width < 1180 ? 220 : 260)
            Layout.preferredHeight: Theme.controlHeightEditorial
            radius: height / 2
            color: searchField.activeFocus ? Theme.surface0 : "transparent"
            border.width: 1
            border.color: searchField.activeFocus ? Theme.ink : Theme.lineStrong
            Behavior on Layout.preferredWidth { NumberAnimation { duration: Theme.durationNormal; easing.type: Easing.OutCubic } }

            TapHandler { enabled: searchBox.collapsed; onTapped: root.openSearch() }
            HoverHandler { enabled: searchBox.collapsed; cursorShape: Qt.PointingHandCursor }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: searchBox.collapsed ? 0 : 12
                anchors.rightMargin: searchBox.collapsed ? 0 : 7
                spacing: 8

                FaIcon {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.fillWidth: searchBox.collapsed
                    horizontalAlignment: Text.AlignHCenter
                    glyph: ""
                    color: Theme.ink3
                    font.pixelSize: Theme.fs(12)
                }

                TextField {
                    id: searchField
                    visible: !searchBox.collapsed
                    Layout.fillWidth: true
                    placeholderText: qsTr("Rechercher un poste…")
                    placeholderTextColor: Theme.ink3
                    color: Theme.ink
                    font.pixelSize: Theme.fs(13)
                    font.family: Theme.fontFamily
                    background: Item {}
                    leftPadding: 0
                    rightPadding: 0
                    verticalAlignment: TextInput.AlignVCenter
                    selectByMouse: true
                    Accessible.name: qsTr("Recherche globale")

                    onTextEdited: {
                        root.runSearch(text)
                        if (text.length > 0 && !searchPopup.opened)
                            searchPopup.open()
                    }
                    onActiveFocusChanged: if (activeFocus && text.length > 0) searchPopup.open()
                    onAccepted: {
                        root.searchRequested(text)
                        if (resultsList.currentIndex >= 0)
                            root.activateResult(root.results[resultsList.currentIndex])
                    }
                    Keys.onDownPressed: if (resultsList.count > 0) resultsList.currentIndex = Math.min(resultsList.count - 1, resultsList.currentIndex + 1)
                    Keys.onUpPressed: if (resultsList.count > 0) resultsList.currentIndex = Math.max(0, resultsList.currentIndex - 1)
                    Keys.onEscapePressed: { searchPopup.close(); text = ""; focus = false }
                }

                Rectangle {
                    visible: !searchField.activeFocus && !searchBox.collapsed && searchBox.width >= 240
                    Layout.preferredWidth: kbd.implicitWidth + 10
                    Layout.preferredHeight: 18
                    radius: 4
                    color: "transparent"
                    border.width: 1
                    border.color: Theme.lineStrong

                    Text {
                        id: kbd
                        anchors.centerIn: parent
                        text: "Ctrl K"
                        color: Theme.ink3
                        font.pixelSize: Theme.fs(10)
                        font.weight: Theme.weightMedium
                        font.family: Theme.fontFamily
                    }
                }
            }

            Popup {
                id: searchPopup
                y: searchBox.height + 6
                x: Math.min(0, root.width - searchBox.x - width - 16)
                width: Math.max(searchBox.width, 380)
                padding: 6
                closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent

                background: Rectangle {
                    radius: Theme.radiusSheet
                    color: Theme.surface0
                    border.width: 1
                    border.color: Theme.line

                    Rectangle {
                        z: -1
                        anchors.fill: parent
                        anchors.topMargin: 4
                        anchors.bottomMargin: -8
                        radius: parent.radius + 2
                        color: Theme.shadowColor
                    }
                }

                contentItem: ColumnLayout {
                    spacing: 0

                    Text {
                        visible: root.results.length === 0
                        Layout.fillWidth: true
                        Layout.margins: 12
                        text: searchField.text.trim().length === 0
                              ? qsTr("Tapez le nom d'une section, d'un poste ou d'une conversation.")
                              : qsTr("Aucun résultat pour « %1 ».").arg(searchField.text.trim())
                        color: Theme.ink3
                        font.pixelSize: Theme.fs(13)
                        font.family: Theme.fontFamily
                        wrapMode: Text.WordWrap
                    }

                    ListView {
                        id: resultsList
                        visible: root.results.length > 0
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.min(contentHeight, 360)
                        clip: true
                        model: root.results
                        section.property: "group"
                        section.delegate: Text {
                            required property string section
                            width: ListView.view ? ListView.view.width : 0
                            leftPadding: 10
                            topPadding: 8
                            bottomPadding: 4
                            text: section
                            color: Theme.ink3
                            font.pixelSize: Theme.fs(11)
                            font.weight: Theme.weightSemibold
                            font.family: Theme.fontFamily
                        }

                        delegate: ItemDelegate {
                            id: resultRow
                            required property int index
                            required property var modelData
                            width: ListView.view.width
                            height: 36
                            highlighted: ListView.isCurrentItem
                            onClicked: root.activateResult(resultRow.modelData)
                            HoverHandler { cursorShape: Qt.PointingHandCursor }

                            background: Rectangle {
                                radius: Theme.radiusSmall
                                color: resultRow.highlighted || resultRow.hovered ? Theme.hover : "transparent"
                            }

                            contentItem: RowLayout {
                                spacing: 10

                                FaIcon {
                                    Layout.preferredWidth: 18
                                    glyph: resultRow.modelData.glyph
                                    color: Theme.ink2
                                    font.pixelSize: Theme.fs(13)
                                }
                                Text {
                                    text: resultRow.modelData.label
                                    color: Theme.ink
                                    font.pixelSize: Theme.fs(13)
                                    font.family: Theme.fontFamily
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                                Text {
                                    visible: text.length > 0
                                    text: resultRow.modelData.detail || ""
                                    color: Theme.ink3
                                    font.pixelSize: Theme.fs(12)
                                    font.family: Theme.fontFamily
                                }
                            }
                        }
                    }
                }
            }
        }

        // ---- Etat reseau (forme + libelle) ---------------------------------
        Row {
            id: netState
            visible: root.networkLabel.length > 0
            spacing: 8
            Layout.leftMargin: 6
            Layout.rightMargin: 4
            Accessible.role: Accessible.StaticText
            Accessible.name: qsTr("État du réseau : %1").arg(root.networkLabel)

            // Serveur : disque plein ; secours : losange ambre ; client : anneau.
            Item {
                width: 10
                height: 10
                anchors.verticalCenter: parent.verticalCenter

                Rectangle {
                    anchors.centerIn: parent
                    width: root.networkState === "backup" ? 7 : 8
                    height: width
                    radius: root.networkState === "backup" ? 1 : width / 2
                    rotation: root.networkState === "backup" ? 45 : 0
                    color: root.networkState === "client" ? "transparent"
                         : root.networkState === "backup" ? Theme.warningColor : Theme.successColor
                    border.width: root.networkState === "client" ? 2 : 0
                    border.color: Theme.successColor
                }
            }
            Text {
                visible: root.width > 760
                anchors.verticalCenter: parent.verticalCenter
                text: root.networkLabel
                color: root.networkState === "backup" ? Theme.warningInk : Theme.ink2
                font.pixelSize: Theme.fs(12.5)
                font.weight: Theme.weightMedium
                font.family: Theme.fontFamily
            }

            HoverHandler { id: netHover }
            ToolTip.visible: netHover.hovered && root.width <= 760
            ToolTip.text: root.networkLabel
        }

        // ---- Bascule de theme --------------------------------------------
        IconButton {
            visible: root.showThemeToggle
            glyph: Theme.darkMode ? "" : ""
            size: Theme.controlHeightSmall + 2
            iconSize: Theme.fs(14)
            tooltip: Theme.darkMode ? qsTr("Passer au thème clair") : qsTr("Passer au thème sombre")
            onClicked: Theme.toggle()
        }

        // ---- Notifications -----------------------------------------------
        IconButton {
            id: bellButton
            visible: root.showNotifications
            glyph: ""
            size: Theme.controlHeightSmall + 2
            iconSize: Theme.fs(14)
            tooltip: root.notificationCount > 0
                     ? qsTr("Notifications (%1 non lues)").arg(root.notificationCount)
                     : qsTr("Notifications")
            onClicked: {
                root.notificationsRequested()
                notificationsPopup.opened ? notificationsPopup.close() : notificationsPopup.open()
            }

            // Compteur en exposant, chiffres serif (comme la navigation).
            Text {
                visible: root.notificationCount > 0
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.rightMargin: 1
                anchors.topMargin: 1
                text: root.notificationCount > 9 ? "9+" : root.notificationCount
                color: Theme.navActiveInk
                font.pixelSize: Theme.fs(11)
                font.weight: Theme.weightBold
                font.family: Theme.fontFamilySerif
            }

            Popup {
                id: notificationsPopup
                y: bellButton.height + 8
                x: bellButton.width - width
                width: 360
                padding: 0
                closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
                onOpened: root.markAllRead()

                background: Rectangle {
                    radius: Theme.radiusSheet
                    color: Theme.surface0
                    border.width: 1
                    border.color: Theme.line

                    Rectangle {
                        z: -1
                        anchors.fill: parent
                        anchors.topMargin: 4
                        anchors.bottomMargin: -8
                        radius: parent.radius + 2
                        color: Theme.shadowColor
                    }
                }

                contentItem: ColumnLayout {
                    spacing: 0

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.margins: 14
                        Layout.bottomMargin: 10

                        Text {
                            text: qsTr("Notifications")
                            color: Theme.ink
                            font.pixelSize: Theme.fs(14)
                            font.weight: Theme.weightSemibold
                            font.family: Theme.fontFamily
                            Layout.fillWidth: true
                        }

                        AppButton {
                            visible: root.notifications.length > 0
                            text: qsTr("Effacer")
                            variant: "ghost"
                            size: "small"
                            onClicked: root.clearNotifications()
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 1
                        color: Theme.line
                    }

                    // Etat vide
                    ColumnLayout {
                        visible: root.notifications.length === 0
                        Layout.fillWidth: true
                        Layout.margins: 24
                        spacing: 6

                        FaIcon {
                            Layout.alignment: Qt.AlignHCenter
                            glyph: ""
                            color: Theme.inkDisabled
                            font.pixelSize: Theme.fs(20)
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: qsTr("Aucune notification")
                            color: Theme.ink
                            font.pixelSize: Theme.fs(13)
                            font.weight: Theme.weightSemibold
                            font.family: Theme.fontFamily
                        }
                        Text {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: qsTr("Les messages, transferts et connexions de cette session apparaîtront ici.")
                            color: Theme.ink3
                            font.pixelSize: Theme.fs(12)
                            font.family: Theme.fontFamily
                            wrapMode: Text.WordWrap
                        }
                    }

                    ListView {
                        visible: root.notifications.length > 0
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.min(contentHeight, 380)
                        clip: true
                        model: root.notifications

                        delegate: ItemDelegate {
                            id: notifRow
                            required property int index
                            required property var modelData
                            width: ListView.view.width
                            padding: 12
                            onClicked: {
                                notificationsPopup.close()
                                root.notificationActivated(notifRow.index)
                            }
                            HoverHandler { cursorShape: Qt.PointingHandCursor }

                            background: Rectangle {
                                color: notifRow.hovered ? Theme.hover : "transparent"
                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    height: 1
                                    color: Theme.line
                                }
                            }

                            contentItem: RowLayout {
                                spacing: 10

                                Rectangle {
                                    Layout.alignment: Qt.AlignTop
                                    Layout.preferredWidth: 28
                                    Layout.preferredHeight: 28
                                    radius: 8
                                    color: Theme.sunken

                                    FaIcon {
                                        anchors.centerIn: parent
                                        glyph: root.categoryGlyph(notifRow.modelData.category)
                                        color: Theme.ink2
                                        font.pixelSize: Theme.fs(12)
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    Text {
                                        text: notifRow.modelData.title
                                        color: Theme.ink
                                        font.pixelSize: Theme.fs(13)
                                        font.weight: Theme.weightSemibold
                                        font.family: Theme.fontFamily
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                    Text {
                                        visible: text.length > 0
                                        text: notifRow.modelData.message || ""
                                        color: Theme.ink2
                                        font.pixelSize: Theme.fs(12)
                                        font.family: Theme.fontFamily
                                        wrapMode: Text.WordWrap
                                        maximumLineCount: 2
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                    Text {
                                        text: root.timeLabel(notifRow.modelData.time)
                                        color: Theme.ink3
                                        font.pixelSize: Theme.fs(11)
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
