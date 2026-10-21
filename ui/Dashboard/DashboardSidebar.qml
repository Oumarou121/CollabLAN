import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import "../Components"

/*
 * DashboardSidebar - navigation principale de LocaLink (refonte 2026).
 *
 * Surface claire separee du contenu par un filet (plus de bloc sombre
 * massif), deux sections ("Espace de travail", "Supervision" pour les
 * administrateurs), etat actif en voile d'accent, badges alimentes par des
 * donnees reelles uniquement. Le profil, le statut de presence, les
 * parametres et la deconnexion sont regroupes dans le menu du compte, en
 * pied : la hauteur utile va a la navigation.
 *
 * isCompact = barre reduite a un rail d'icones (64 px) : preference
 * utilisateur (Theme.sidebarCollapsed) ou fenetre etroite, decide par
 * l'hote (AppShell).
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
    property string username: ""
    property bool isAdmin: false
    property string activeRoute: "home"

    // Compteurs reels fournis par l'hote.
    property int unreadMessages: 0
    property int activeTransfers: 0
    property int pendingAdmin: 0
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
        Layout.fillWidth: true
        Layout.preferredHeight: Theme.navItemHeight

        property bool compact: false
        property bool active: false
        property string glyph: ""
        property string label: ""
        property int badgeCount: 0
        // "accent" (a traiter : messages non lus) | "neutral" (information)
        // | "warning" (demandes en attente)
        property string badgeTone: "neutral"
        property bool dot: false

        signal activated()

        text: label
        hoverEnabled: true
        focusPolicy: Qt.TabFocus
        padding: 0
        Accessible.name: entry.badgeCount > 0 ? entry.label + ", " + entry.badgeCount : entry.label
        onClicked: entry.activated()

        HoverHandler { cursorShape: Qt.PointingHandCursor }

        readonly property color tone: entry.active ? Theme.navActiveInk
                                                   : (entry.hovered ? Theme.ink : Theme.navInk)

        background: Rectangle {
            radius: Theme.radiusControl
            color: entry.active ? Theme.navActive
                                : (entry.hovered ? Theme.navHover : "transparent")
            Behavior on color { ColorAnimation { duration: Theme.durationFast } }

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
                anchors.rightMargin: entry.compact ? 0 : 8
                spacing: 10

                Item {
                    Layout.fillWidth: entry.compact
                    Layout.preferredWidth: entry.compact ? -1 : 18
                    Layout.fillHeight: true

                    FaIcon {
                        anchors.centerIn: parent
                        glyph: entry.glyph
                        color: entry.tone
                        font.pixelSize: Theme.fs(15)
                    }
                }

                Text {
                    visible: !entry.compact
                    text: entry.label
                    color: entry.tone
                    font.pixelSize: Theme.fs(13)
                    font.weight: entry.active ? Theme.weightSemibold : Theme.weightMedium
                    font.family: Theme.fontFamily
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                // Compteur
                Rectangle {
                    visible: !entry.compact && entry.badgeCount > 0
                    Layout.preferredWidth: Math.max(20, countText.implicitWidth + 12)
                    Layout.preferredHeight: 18
                    radius: 9
                    color: entry.badgeTone === "accent" ? Theme.accentColor
                         : entry.badgeTone === "warning" ? Theme.warningSoft
                         : Theme.sunken

                    Text {
                        id: countText
                        anchors.centerIn: parent
                        text: entry.badgeCount > 99 ? "99+" : entry.badgeCount
                        color: entry.badgeTone === "accent" ? Theme.accentInk
                             : entry.badgeTone === "warning" ? Theme.warningInk
                             : Theme.ink2
                        font.pixelSize: Theme.fs(11)
                        font.weight: Theme.weightSemibold
                        font.family: Theme.fontFamily
                        font.features: ({ "tnum": 1 })
                    }
                }

                // Point d'activite (ex. appel en cours) sans compteur.
                Rectangle {
                    visible: !entry.compact && entry.dot && entry.badgeCount === 0
                    Layout.preferredWidth: 8
                    Layout.preferredHeight: 8
                    radius: 4
                    color: Theme.callColor
                }
            }

            // Rail : le compteur devient un point.
            Rectangle {
                visible: entry.compact && (entry.badgeCount > 0 || entry.dot)
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.rightMargin: 10
                anchors.topMargin: 5
                width: 9
                height: 9
                radius: 4.5
                color: entry.dot && entry.badgeCount === 0 ? Theme.callColor
                     : entry.badgeTone === "warning" ? Theme.warningColor
                     : Theme.accentColor
                border.width: 2
                border.color: Theme.navBg
            }
        }

        ToolTip.visible: entry.compact && entry.hovered
        ToolTip.text: entry.badgeCount > 0 ? entry.label + " (" + entry.badgeCount + ")" : entry.label
        ToolTip.delay: 250
    }

    component SectionLabel: Text {
        Layout.fillWidth: true
        Layout.leftMargin: 10
        Layout.topMargin: 14
        Layout.bottomMargin: 4
        color: Theme.navInkMuted
        font.pixelSize: Theme.fs(11)
        font.weight: Theme.weightSemibold
        font.family: Theme.fontFamily
        elide: Text.ElideRight
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: 14
        anchors.bottomMargin: 12
        anchors.leftMargin: root.isCompact ? 10 : 12
        anchors.rightMargin: root.isCompact ? 11 : 13
        spacing: 2

        // ---- Marque -------------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: root.isCompact ? 0 : 6
            Layout.bottomMargin: 6
            Layout.preferredHeight: 36
            spacing: 10

            Item {
                Layout.fillWidth: root.isCompact
                Layout.preferredWidth: root.isCompact ? -1 : 30
                Layout.preferredHeight: 30

                BrandMark {
                    anchors.centerIn: parent
                    size: 30
                }
            }

            ColumnLayout {
                visible: !root.isCompact
                Layout.fillWidth: true
                spacing: 0

                Text {
                    text: "LocaLink"
                    color: Theme.ink
                    font.pixelSize: Theme.fs(15)
                    font.weight: Theme.weightBold
                    font.letterSpacing: -0.2
                    font.family: Theme.fontFamily
                }
                Text {
                    text: qsTr("Réseau local")
                    color: Theme.navInkMuted
                    font.pixelSize: Theme.fs(11)
                    font.family: Theme.fontFamily
                }
            }
        }

        // ---- Espace de travail -------------------------------------------
        SectionLabel {
            text: qsTr("Espace de travail")
            visible: !root.isCompact
        }
        Item { Layout.preferredHeight: 10; visible: root.isCompact }

        NavEntry {
            compact: root.isCompact
            active: root.activeRoute === "home"
            glyph: ""
            label: qsTr("Vue d'ensemble")
            onActivated: root.homeRequested()
        }
        NavEntry {
            compact: root.isCompact
            active: root.activeRoute === "chat"
            glyph: ""
            label: qsTr("Discussions")
            badgeCount: root.unreadMessages
            badgeTone: "accent"
            onActivated: root.chatRequested()
        }
        NavEntry {
            compact: root.isCompact
            active: root.activeRoute === "transfer"
            glyph: ""
            label: qsTr("Transferts")
            badgeCount: root.activeTransfers
            onActivated: root.transferRequested()
        }
        NavEntry {
            compact: root.isCompact
            active: root.activeRoute === "folder"
            glyph: ""
            label: qsTr("Dossiers partagés")
            onActivated: root.foldersRequested()
        }
        NavEntry {
            compact: root.isCompact
            active: root.activeRoute === "call"
            glyph: ""
            label: qsTr("Appels")
            dot: root.callActive
            onActivated: root.callRequested()
        }
        NavEntry {
            compact: root.isCompact
            active: root.activeRoute === "peers"
            glyph: ""
            label: qsTr("Postes")
            onActivated: root.peersRequested()
        }

        // ---- Supervision (administrateur) ---------------------------------
        SectionLabel {
            text: qsTr("Supervision")
            visible: !root.isCompact && root.isAdmin
        }
        Rectangle {
            visible: root.isCompact && root.isAdmin
            Layout.fillWidth: true
            Layout.topMargin: 8
            Layout.bottomMargin: 8
            Layout.preferredHeight: 1
            color: Theme.line
        }

        NavEntry {
            visible: root.isAdmin
            compact: root.isCompact
            active: root.activeRoute === "journal"
            glyph: ""
            label: qsTr("Journal d'audit")
            onActivated: root.journalRequested()
        }
        NavEntry {
            visible: root.isAdmin
            compact: root.isCompact
            active: root.activeRoute === "admin"
            glyph: ""
            label: qsTr("Administration")
            badgeCount: root.pendingAdmin
            badgeTone: "warning"
            onActivated: root.adminRequested()
        }

        Item { Layout.fillHeight: true; Layout.minimumHeight: 12 }

        NavEntry {
            compact: root.isCompact
            active: root.activeRoute === "settings"
            glyph: ""
            label: qsTr("Paramètres")
            onActivated: root.settingsRequested()
        }

        // Reduire / deplier (preference memorisee).
        NavEntry {
            visible: !root.compactForced
            compact: root.isCompact
            glyph: root.isCompact ? "" : ""
            label: root.isCompact ? qsTr("Déplier le menu") : qsTr("Réduire le menu")
            onActivated: Theme.setSidebarCollapsed(!Theme.sidebarCollapsed)
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 6
            Layout.bottomMargin: 6
            Layout.preferredHeight: 1
            color: Theme.line
        }

        // ---- Compte -------------------------------------------------------
        Button {
            id: accountButton
            Layout.fillWidth: true
            Layout.preferredHeight: 44
            hoverEnabled: true
            focusPolicy: Qt.TabFocus
            padding: 0
            Accessible.name: qsTr("Compte de %1, %2").arg(root.username).arg(root.localStatusLabel)
            onClicked: accountMenu.popup(accountButton, 0, -accountMenu.implicitHeight - 4)

            HoverHandler { cursorShape: Qt.PointingHandCursor }

            background: Rectangle {
                radius: Theme.radiusControl
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
                    Layout.leftMargin: root.isCompact ? 0 : 4
                    Layout.preferredHeight: 32

                    Avatar {
                        anchors.centerIn: parent
                        name: root.username
                        size: 30
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
                    spacing: 0

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
                        text: (root.isAdmin ? qsTr("Administrateur") : qsTr("Utilisateur"))
                              + " · " + root.localStatusLabel
                        color: Theme.navInkMuted
                        font.pixelSize: Theme.fs(11)
                        font.family: Theme.fontFamily
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }

                FaIcon {
                    visible: !root.isCompact
                    glyph: ""
                    color: Theme.navInkMuted
                    font.pixelSize: Theme.fs(11)
                    Layout.rightMargin: 4
                }
            }

            ToolTip.visible: root.isCompact && accountButton.hovered && !accountMenu.visible
            ToolTip.text: root.username
            ToolTip.delay: 250
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
        AppMenuSeparator {}
        AppMenuItem {
            text: qsTr("Paramètres")
            iconGlyph: ""
            onTriggered: root.settingsRequested()
        }
        AppMenuItem {
            text: qsTr("À propos de LocaLink")
            iconGlyph: ""
            onTriggered: root.aboutRequested()
        }
        AppMenuSeparator {}
        AppMenuItem {
            text: qsTr("Se déconnecter")
            iconGlyph: ""
            danger: true
            onTriggered: root.logoutRequested()
        }
    }
}
