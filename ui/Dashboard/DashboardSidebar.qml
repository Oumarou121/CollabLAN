import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import "../Components"
import "../Components/icons.js" as Icons

/*
 * DashboardSidebar - navigation principale de LocaLink, Ligne claire A2.
 *
 * Meme papier que la page, separee du contenu par un filet d'encre. Trois
 * rubriques en petites capitales : Espace de travail, Supervision
 * (administrateurs) et Parametres. L'element actif est repere sans la
 * couleur seule : filet d'encre au bord, feuille, graisse. Les compteurs
 * sont en chiffres PT Serif : encre de marque pour ce qui attend
 * l'utilisateur (non-lus, transferts en cours), ambre pour une decision ou
 * un conflit, gris pour une simple quantite.
 *
 * isCompact = rail d'icones (64 px) : preference utilisateur
 * (Theme.sidebarCollapsed) ou fenetre etroite, decide par l'hote
 * (AppShell), qui peut aussi deplier la barre en surimpression.
 *
 * NOTE : NavEntry est un composant en ligne, il ne voit pas l'id `root` ;
 * tout passe par proprietes et par le signal activated().
 */
Item {
    id: root
    width: implicitWidth
    implicitWidth: isCompact ? Theme.sidebarWidthCollapsed : Theme.sidebarWidth

    Behavior on implicitWidth { NumberAnimation { duration: Theme.durationNormal; easing.type: Easing.OutCubic } }

    property bool isCompact: false
    // La reduction est-elle forcee par la largeur de fenetre ? (le bouton
    // "Reduire" est alors masque : il n'aurait aucun effet visible).
    property bool compactForced: false
    // Barre depliee par-dessus le contenu (fenetre etroite).
    property bool overlay: false
    property string username: ""
    property bool isAdmin: false
    property string activeRoute: "home"

    // Compteurs reels fournis par l'hote.
    property int unreadMessages: 0
    property int activeTransfers: 0
    property int pendingAdmin: 0
    property int folderConflicts: 0
    property int peersCount: 0
    property bool callActive: false

    // Conserves pour compatibilite d'API (non affiches).
    property string serverStatus: ""
    property color serverStatusColor: Theme.successColor

    signal homeRequested()
    signal chatRequested()
    signal transferRequested()
    signal foldersRequested()
    signal callRequested()
    signal peersRequested()
    signal journalRequested()
    signal adminRequested()
    signal settingsRequested()
    signal aboutRequested()
    signal logoutRequested()

    readonly property string localStatus: (typeof discoveryService !== "undefined" && discoveryService)
                                          ? discoveryService.localStatus : "online"
    readonly property string localStatusLabel: localStatus === "away" ? qsTr("Absent")
                                             : localStatus === "busy" ? qsTr("Occupé")
                                             : qsTr("En ligne")
    readonly property color localStatusColor: localStatus === "online" ? Theme.successColor
                                                                       : Theme.markAway

    Rectangle {
        anchors.fill: parent
        color: Theme.navBg

        Rectangle {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 1
            color: Theme.navLine
        }
    }

    // --- Entree de navigation ---------------------------------------------
    component NavEntry: Button {
        id: entry

        property bool compact: false
        property bool active: false
        property string iconPath: ""
        property string label: ""
        property int count: 0
        // "hot" (attend l'utilisateur) | "warn" (decision, conflit) | "muted"
        property string countTone: "muted"
        property bool dot: false

        signal activated()

        Layout.fillWidth: true
        Layout.leftMargin: entry.compact ? 10 : 12
        Layout.rightMargin: entry.compact ? 10 : 12
        Layout.preferredHeight: entry.compact ? 40 : Theme.navItemHeight

        text: label
        hoverEnabled: true
        focusPolicy: Qt.TabFocus
        padding: 0
        Accessible.name: entry.count > 0 ? entry.label + ", " + entry.count : entry.label
        onClicked: entry.activated()

        HoverHandler { cursorShape: Qt.PointingHandCursor }

        readonly property color tone: entry.active || entry.hovered ? Theme.ink : Theme.navInk
        readonly property color countColor: entry.countTone === "hot" ? Theme.navActiveInk
                                          : entry.countTone === "warn" ? Theme.warningInk
                                          : Theme.ink3

        background: Rectangle {
            radius: Theme.radiusSheet
            color: entry.active ? Theme.surface0
                                : (entry.hovered ? Theme.navHover : "transparent")
            border.width: entry.active ? 1 : 0
            border.color: Theme.line
            Behavior on color { ColorAnimation { duration: Theme.durationFast } }

            // Filet d'encre au bord de la barre : l'element actif se lit sans couleur.
            Rectangle {
                visible: entry.active
                x: entry.compact ? -10 : -12
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.topMargin: 6
                anchors.bottomMargin: 6
                width: 3
                color: Theme.ruleInk
            }

            Rectangle {
                anchors.fill: parent
                anchors.margins: -2
                radius: parent.radius + 2
                color: "transparent"
                border.width: 2
                border.color: Theme.focusRing
                visible: entry.visualFocus
            }
        }

        contentItem: Item {
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: entry.compact ? 0 : 10
                anchors.rightMargin: entry.compact ? 0 : 10
                spacing: 12

                Item {
                    Layout.fillWidth: entry.compact
                    Layout.preferredWidth: entry.compact ? -1 : 18
                    Layout.fillHeight: true

                    LineIcon {
                        anchors.centerIn: parent
                        path: entry.iconPath
                        size: 18
                        strokeWidth: 1.6
                        color: entry.active || entry.hovered ? Theme.ink : Theme.ink3
                    }
                }

                Text {
                    visible: !entry.compact
                    text: entry.label
                    color: entry.tone
                    font.pixelSize: Theme.fs(13.5)
                    font.weight: entry.active ? Theme.weightSemibold : Theme.weightMedium
                    font.family: Theme.fontFamily
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                Text {
                    visible: !entry.compact && entry.count > 0
                    text: entry.count > 99 ? "99+" : entry.count
                    color: entry.countColor
                    font.pixelSize: Theme.fs(13)
                    font.weight: entry.countTone === "muted" ? Theme.weightRegular : Theme.weightBold
                    font.family: Theme.fontFamilySerif
                    font.features: ({ "tnum": 1 })
                }

                // Appel en cours : point sans compteur.
                Rectangle {
                    visible: !entry.compact && entry.dot && entry.count === 0
                    Layout.preferredWidth: 8
                    Layout.preferredHeight: 8
                    radius: 4
                    color: Theme.callColor
                }
            }

            // Rail : le compteur passe en exposant, l'appel en point.
            Text {
                visible: entry.compact && entry.count > 0
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.rightMargin: 3
                anchors.topMargin: 2
                text: entry.count > 99 ? "99+" : entry.count
                color: entry.countColor
                font.pixelSize: Theme.fs(11)
                font.weight: Theme.weightBold
                font.family: Theme.fontFamilySerif
            }
            Rectangle {
                visible: entry.compact && entry.dot && entry.count === 0
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.rightMargin: 8
                anchors.topMargin: 7
                width: 8
                height: 8
                radius: 4
                color: Theme.callColor
                border.width: 2
                border.color: Theme.navBg
            }
        }

        ToolTip.visible: entry.compact && entry.hovered
        ToolTip.text: entry.count > 0 ? entry.label + " (" + entry.count + ")" : entry.label
        ToolTip.delay: 250
    }

    // Rubrique : petites capitales en barre depliee, simple filet en rail.
    component Rubric: Item {
        id: rubric
        property string text: ""
        property bool compact: false
        property bool first: false
        Layout.fillWidth: true
        Layout.preferredHeight: compact ? (first ? 14 : 25) : (first ? 34 : 44)

        CapsLabel {
            visible: !rubric.compact
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: 22
            anchors.bottomMargin: 8
            text: rubric.text
        }
        Rectangle {
            visible: rubric.compact && !rubric.first
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            height: 1
            color: Theme.line
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.rightMargin: 1
        spacing: 0

        // ---- Marque (meme hauteur que la barre de contexte) ---------------
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.topbarHeight

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: root.isCompact ? 0 : 22
                anchors.rightMargin: root.isCompact ? 0 : 12
                spacing: 10

                Item {
                    Layout.fillWidth: root.isCompact
                    Layout.preferredWidth: root.isCompact ? -1 : 26
                    Layout.fillHeight: true

                    BrandMark {
                        anchors.centerIn: parent
                        size: 26
                    }
                }

                Text {
                    visible: !root.isCompact
                    text: "LocaLink"
                    color: Theme.ink
                    font.pixelSize: Theme.fs(19)
                    font.weight: Theme.weightBold
                    font.family: Theme.fontFamilySerif
                    Layout.fillWidth: true
                }
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 1
                color: Theme.line
            }
        }

        // ---- Rubriques ----------------------------------------------------
        Flickable {
            id: navFlick
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: width
            contentHeight: navColumn.implicitHeight + 12
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            ColumnLayout {
                id: navColumn
                width: navFlick.width
                spacing: 2

                Rubric { text: qsTr("Espace de travail"); compact: root.isCompact; first: true }

                NavEntry {
                    compact: root.isCompact
                    active: root.activeRoute === "home"
                    iconPath: Icons.overview
                    label: qsTr("Vue d'ensemble")
                    onActivated: root.homeRequested()
                }
                NavEntry {
                    compact: root.isCompact
                    active: root.activeRoute === "chat"
                    iconPath: Icons.messageCircle
                    label: qsTr("Discussions")
                    count: root.unreadMessages
                    countTone: "hot"
                    onActivated: root.chatRequested()
                }
                NavEntry {
                    compact: root.isCompact
                    active: root.activeRoute === "transfer"
                    iconPath: Icons.exchange
                    label: qsTr("Transferts")
                    count: root.activeTransfers
                    countTone: "hot"
                    onActivated: root.transferRequested()
                }
                NavEntry {
                    compact: root.isCompact
                    active: root.activeRoute === "folder"
                    iconPath: Icons.folder
                    label: qsTr("Dossiers partagés")
                    count: root.folderConflicts
                    countTone: "warn"
                    onActivated: root.foldersRequested()
                }
                NavEntry {
                    compact: root.isCompact
                    active: root.activeRoute === "call"
                    iconPath: Icons.phone
                    label: qsTr("Appels")
                    dot: root.callActive
                    onActivated: root.callRequested()
                }
                NavEntry {
                    compact: root.isCompact
                    active: root.activeRoute === "peers"
                    iconPath: Icons.monitor
                    label: qsTr("Postes")
                    // Simple quantite : pas de compteur en rail (il y passerait
                    // pour une alerte).
                    count: root.isCompact ? 0 : root.peersCount
                    countTone: "muted"
                    onActivated: root.peersRequested()
                }

                Rubric { visible: root.isAdmin; text: qsTr("Supervision"); compact: root.isCompact }

                NavEntry {
                    visible: root.isAdmin
                    compact: root.isCompact
                    active: root.activeRoute === "journal"
                    iconPath: Icons.journal
                    label: qsTr("Journal d'audit")
                    onActivated: root.journalRequested()
                }
                NavEntry {
                    visible: root.isAdmin
                    compact: root.isCompact
                    active: root.activeRoute === "admin"
                    iconPath: Icons.shield
                    label: qsTr("Administration")
                    count: root.pendingAdmin
                    countTone: "warn"
                    onActivated: root.adminRequested()
                }

                Rubric { text: qsTr("Paramètres"); compact: root.isCompact }

                NavEntry {
                    compact: root.isCompact
                    active: root.activeRoute === "settings"
                    iconPath: Icons.sliders
                    label: qsTr("Paramètres")
                    onActivated: root.settingsRequested()
                }
                NavEntry {
                    compact: root.isCompact
                    active: root.activeRoute === "about"
                    iconPath: Icons.info
                    label: qsTr("À propos")
                    onActivated: root.aboutRequested()
                }
                // Reduire / deplier (preference memorisee).
                NavEntry {
                    visible: !root.compactForced && !root.overlay
                    compact: root.isCompact
                    iconPath: root.isCompact ? Icons.chevronRight : Icons.chevronLeft
                    label: root.isCompact ? qsTr("Déplier le menu") : qsTr("Réduire le menu")
                    onActivated: Theme.setSidebarCollapsed(!Theme.sidebarCollapsed)
                }
            }
        }

        // ---- Compte -------------------------------------------------------
        Rectangle {
            Layout.fillWidth: true
            Layout.leftMargin: root.isCompact ? 10 : 12
            Layout.rightMargin: root.isCompact ? 10 : 12
            Layout.preferredHeight: 1
            color: Theme.line
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: root.isCompact ? 10 : 12
            Layout.rightMargin: root.isCompact ? 10 : 12
            Layout.topMargin: 8
            Layout.bottomMargin: 10
            spacing: 4

            Button {
                id: accountButton
                Layout.fillWidth: true
                Layout.preferredHeight: 46
                hoverEnabled: true
                focusPolicy: Qt.TabFocus
                padding: 0
                Accessible.name: qsTr("Compte de %1, %2").arg(root.username).arg(root.localStatusLabel)
                onClicked: accountMenu.popup(accountButton, 0, -accountMenu.implicitHeight - 4)

                HoverHandler { cursorShape: Qt.PointingHandCursor }

                background: Rectangle {
                    radius: Theme.radiusSheet
                    color: accountButton.hovered || accountMenu.visible ? Theme.navHover : "transparent"

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: -2
                        radius: parent.radius + 2
                        color: "transparent"
                        border.width: 2
                        border.color: Theme.focusRing
                        visible: accountButton.visualFocus
                    }
                }

                contentItem: RowLayout {
                    spacing: 10

                    Item {
                        Layout.fillWidth: root.isCompact
                        Layout.preferredWidth: root.isCompact ? -1 : 32
                        Layout.leftMargin: root.isCompact ? 0 : 6
                        Layout.preferredHeight: 32

                        // Initiales sur disque d'encre (Ligne claire).
                        Rectangle {
                            anchors.centerIn: parent
                            width: 32
                            height: 32
                            radius: 16
                            color: Theme.ink

                            Text {
                                anchors.centerIn: parent
                                text: {
                                    const parts = (root.username || "?").trim().split(/\s+/)
                                    return (parts[0].charAt(0) + (parts.length > 1 ? parts[1].charAt(0) : parts[0].charAt(1) || "")).toUpperCase()
                                }
                                color: Theme.inkOnInk
                                font.family: Theme.fontFamilySerif
                                font.pixelSize: Theme.fs(12)
                                font.weight: Theme.weightBold
                            }
                        }

                        Rectangle {
                            x: parent.width / 2 + 7
                            y: parent.height / 2 + 6
                            width: 11
                            height: 11
                            radius: 5.5
                            color: root.localStatusColor
                            border.width: 2
                            border.color: Theme.navBg
                        }
                    }

                    ColumnLayout {
                        visible: !root.isCompact
                        Layout.fillWidth: true
                        spacing: 1

                        Text {
                            text: root.username.length > 0 ? root.username : qsTr("Utilisateur")
                            color: Theme.ink
                            font.pixelSize: Theme.fs(13)
                            font.weight: Theme.weightSemibold
                            font.family: Theme.fontFamily
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        Text {
                            // La presence est portee par la pastille de l'avatar (et le menu).
                            text: root.isAdmin ? qsTr("Administrateur") : qsTr("Utilisateur")
                            color: Theme.navInkMuted
                            font.pixelSize: Theme.fs(11.5)
                            font.family: Theme.fontFamily
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }
                }

                ToolTip.visible: root.isCompact && accountButton.hovered && !accountMenu.visible
                ToolTip.text: root.username
                ToolTip.delay: 250
            }

            AbstractButton {
                id: logoutButton
                visible: !root.isCompact
                Layout.preferredWidth: 34
                Layout.preferredHeight: 34
                hoverEnabled: true
                focusPolicy: Qt.TabFocus
                Accessible.name: qsTr("Se déconnecter")
                onClicked: root.logoutRequested()

                HoverHandler { cursorShape: Qt.PointingHandCursor }
                ToolTip.visible: logoutButton.hovered
                ToolTip.text: qsTr("Se déconnecter")
                ToolTip.delay: 400

                background: Rectangle {
                    radius: 17
                    color: logoutButton.hovered ? Theme.navHover : "transparent"
                    border.width: logoutButton.visualFocus ? 2 : 0
                    border.color: Theme.focusRing
                }
                contentItem: Item {
                    LineIcon {
                        anchors.centerIn: parent
                        path: Icons.logout
                        size: 17
                        strokeWidth: 1.6
                        color: logoutButton.hovered ? Theme.ink : Theme.ink3
                    }
                }
            }
        }
    }

    AppMenu {
        id: accountMenu

        AppMenuItem {
            text: qsTr("En ligne")
            checkable: true
            checked: root.localStatus === "online"
            enabled: typeof discoveryService !== "undefined"
            onTriggered: discoveryService.localStatus = "online"
        }
        AppMenuItem {
            text: qsTr("Absent")
            checkable: true
            checked: root.localStatus === "away"
            enabled: typeof discoveryService !== "undefined"
            onTriggered: discoveryService.localStatus = "away"
        }
        AppMenuItem {
            text: qsTr("Occupé")
            checkable: true
            checked: root.localStatus === "busy"
            enabled: typeof discoveryService !== "undefined"
            onTriggered: discoveryService.localStatus = "busy"
        }
        // Parametres et A propos sont dans la navigation : pas de doublon ici.
        AppMenuSeparator {}
        AppMenuItem {
            text: qsTr("Se déconnecter")
            iconGlyph: ""
            danger: true
            onTriggered: root.logoutRequested()
        }
    }
}
