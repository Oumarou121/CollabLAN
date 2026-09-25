import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import "../Components"

/*
 * DashboardShell - Coquille commune à tous les écrans principaux du
 * Dashboard LocaLink (Sidebar + Header + zone de contenu), introduite
 * pour éviter de dupliquer DashboardSidebar/DashboardHeader dans chaque
 * vue (Home, Transferts, puis plus tard Discussions/Postes/Admin/...).
 *
 * Usage :
 *
 *     DashboardShell {
 *         anchors.fill: parent
 *         activeRoute: "transfer"
 *         breadcrumb: "LocaLink / Transferts"
 *         username: ...
 *         // enfants directs = contenu de l'écran, places dans un
 *         // ColumnLayout (comme le ColumnLayout "contenu principal" de
 *         // HomeView) : Layout.fillWidth / Layout.preferredHeight etc.
 *         // s'appliquent donc normalement.
 *         Rectangle { Layout.fillWidth: true; ... }
 *     }
 */
Item {
    id: root

    // ---- passthrough Sidebar ----
    property bool sidebarCompact: false
    property string username: ""
    property string serverStatus: qsTr("Réseau local")
    property color serverStatusColor: "#2E9A66"
    property int unreadMessages: 0
    property int activeTransfers: 0
    property int pendingAdmin: 0
    property bool isAdmin: false
    // Route active dans la navigation Sidebar ("home", "chat", "transfer",
    // "folder", "call", "peers") - ne doit jamais être hardcodée par
    // l'écran hôte : chaque écran migré vers DashboardShell doit fournir
    // sa propre route.
    property string activeRoute: "home"

    // ---- passthrough Header ----
    property string breadcrumb: "LocaLink"
    property bool showSearch: true
    property bool showNotifications: true

    // ---- signaux de navigation Sidebar ----
    signal homeRequested()
    signal chatRequested()
    signal transferRequested()
    signal foldersRequested()
    signal callRequested()
    signal peersRequested()
    signal adminRequested()
    signal settingsRequested()
    signal logoutRequested()

    // ---- signaux Header ----
    signal searchRequested(string query)
    signal notificationsRequested()
    // Remonte le fil d'Ariane cliquable du Header (voir DashboardHeader).
    signal breadcrumbSegmentClicked(int index, string label)

    // Zone de contenu : tout enfant declare directement dans un
    // `DashboardShell { ... }` est reparente ici, dans un ColumnLayout
    // (spacing 0), exactement comme le faisait le ColumnLayout "contenu
    // principal" de HomeView.
    default property alias content: contentColumn.data

    Rectangle {
        anchors.fill: parent
        color: Theme.background
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        DashboardSidebar {
            id: sidebar
            Layout.fillHeight: true
            isCompact: root.sidebarCompact
            username: root.username
            serverStatus: root.serverStatus
            serverStatusColor: root.serverStatusColor
            unreadMessages: root.unreadMessages
            activeTransfers: root.activeTransfers
            pendingAdmin: root.pendingAdmin
            isAdmin: root.isAdmin
            activeRoute: root.activeRoute

            onHomeRequested: root.homeRequested()
            onChatRequested: root.chatRequested()
            onTransferRequested: root.transferRequested()
            onFoldersRequested: root.foldersRequested()
            onCallRequested: root.callRequested()
            onPeersRequested: root.peersRequested()
            onAdminRequested: root.adminRequested()
            onSettingsRequested: root.settingsRequested()
            onLogoutRequested: root.logoutRequested()
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            DashboardHeader {
                Layout.fillWidth: true
                Layout.preferredHeight: 52
                breadcrumb: root.breadcrumb
                showSearch: root.showSearch
                showNotifications: root.showNotifications

                onSearchRequested: function(query) { root.searchRequested(query) }
                onNotificationsRequested: root.notificationsRequested()
                onSegmentClicked: function(index, label) { root.breadcrumbSegmentClicked(index, label) }
            }

            ColumnLayout {
                id: contentColumn
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0
                clip: true
            }
        }
    }
}
