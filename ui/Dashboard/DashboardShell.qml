import QtQuick
import QtQuick.Layouts
import Themes

/*
 * DashboardShell - conteneur de contenu d'une page.
 *
 * Historique : cette coquille embarquait sa propre navigation laterale et
 * sa barre superieure, dupliquees dans chaque ecran qui l'utilisait. Depuis
 * la refonte 2026, la navigation est fournie UNE fois par AppShell ; ce
 * composant ne garde que la zone de contenu (ColumnLayout). Ses proprietes
 * et signaux sont conserves pour compatibilite avec les ecrans qui les
 * renseignent encore (FileTransferView), mais n'ont plus d'effet visuel.
 */
Item {
    id: root

    // ---- compatibilite (sans effet visuel) ----
    property bool sidebarCompact: false
    property string username: ""
    property string serverStatus: ""
    property color serverStatusColor: Theme.successColor
    property int unreadMessages: 0
    property int activeTransfers: 0
    property int pendingAdmin: 0
    property bool isAdmin: false
    property string activeRoute: "home"
    property string breadcrumb: ""
    property bool showSearch: true
    property bool showNotifications: true

    signal homeRequested()
    signal chatRequested()
    signal transferRequested()
    signal foldersRequested()
    signal callRequested()
    signal peersRequested()
    signal journalRequested()
    signal adminRequested()
    signal settingsRequested()
    signal logoutRequested()
    signal searchRequested(string query)
    signal notificationsRequested()
    signal breadcrumbSegmentClicked(int index, string label)

    // Tout enfant declare dans `DashboardShell { ... }` est reparente dans
    // ce ColumnLayout (Layout.fillWidth / fillHeight s'appliquent).
    default property alias content: contentColumn.data

    ColumnLayout {
        id: contentColumn
        anchors.fill: parent
        spacing: 0
        clip: true
    }
}
