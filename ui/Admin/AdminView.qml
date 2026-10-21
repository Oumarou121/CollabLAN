import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import Themes
import "../Components"
import "../Dashboard" as Dash

/*
 * AdminView - ecran "Admin" (issues #65, #68)
 *
 * Consultation et export du journal d'audit.
 * Liste filtrable par type d'événement, utilisateur et plage de dates.
 * Export CSV du journal complet ou filtré.
 *
 * Gestion des machines autorisées/révoquées (issue #68).
 *
 * Accès réservé aux administrateurs (issue #67).
 *
 * Refonte design (juillet 2026) : alignement sur le style deja retenu
 * pour Login/Home/Settings/Users -- header en deux lignes (actions puis
 * onglets), contenu centre a largeur maximale (comme les autres ecrans),
 * grilles de cartes responsives (1/2/3 colonnes, memes seuils 900/560 que
 * HomeView/UsersView) pour "Machines autorisées" et "Utilisateurs" au lieu
 * de lignes de tableau a colonnes figees, et entrees empilees verticalement
 * (au lieu de colonnes de largeur fixe) pour le journal d'audit et
 * l'historique de bascule, afin que rien ne se chevauche ni ne soit
 * tronque, y compris a la largeur minimale de la fenetre (640px, cf.
 * Main.qml). Les boutons d'action de l'en-tete masquent leur libelle sous
 * ~700px pour ne garder que l'icone.
 */
Item {
    id: root
    objectName: "adminView"

    // Police d'icone (Font Awesome) utilisee dans les etats vides
    readonly property string iconFontFamily: "FontAwesome"

    signal backRequested()

    property int currentTab: 0  // 0 = Audit log, 1 = Machines autorisées, 2 = Utilisateurs, 3 = Bascule serveur
    // Section "Journal d audit" de la navigation (onglet 0) : pas d onglets.
    readonly property bool journalMode: root.currentTab === 0
    // Note : l'onglet "Paramètres" (Préférences / Ports
    // réseau) a été retiré d'ici et déplacé dans SettingsView.qml,
    // désormais accessible à tous les utilisateurs depuis le menu profil
    // de HomeView (Ports réseau y reste réservé aux
    // administrateurs).

    // Sous ce seuil, les boutons d'action de l'en-tete masquent leur texte
    // pour ne garder que l'icone (fenetre partagee / petits ecrans).
    readonly property bool headerCompact: root.width < 700

    // Historique des bascules (ServerElectionLog), pour l'onglet "Bascule
    // serveur" (HYBRID_SERVER_FAILOVER.md section 9, etape 5). Pas de
    // signal de changement cote C++ (simple Q_INVOKABLE) : on rafraichit
    // explicitement (bouton, ouverture de l'onglet, et un Timer discret
    // pendant que l'onglet est actif) plutot que de tout faire reposer sur
    // le binding reactif comme pour electionService.
    property var electionHistoryEntries: []
    property int passwordResetUserId: -1
    property string passwordResetUsername: ""

    function liveUserStatus(userName, userUuid) {
        if (typeof userManager !== "undefined"
                && userManager.authenticated
                && userManager.currentUsername === userName) {
            return "online"
        }

        if (typeof peersModel !== "undefined" && peersModel) {
            for (let i = 0; i < peersModel.count; ++i) {
                const index = peersModel.index(i, 0)
                const peerUserUuid = peersModel.data(index, peersModel.UserUuidRole || Qt.UserRole + 3)
                if (peerUserUuid === userUuid)
                    return peersModel.data(index, peersModel.StatusRole || Qt.UserRole + 4) || "offline"
            }
        }
        return "offline"
    }

    Timer {
        interval: 2000
        running: root.currentTab === 2
        repeat: true
        onTriggered: usersGrid.forceLayout()
    }

    function refreshElectionHistory() {
        if (typeof application !== "undefined" && application)
            root.electionHistoryEntries = application.electionHistory(100)
    }

    function electionEventColor(eventName) {
        switch (eventName) {
        case "HEARTBEAT_LOST": return Theme.error
        case "TEMP_PROMOTED": return Theme.warning
        case "SERVER_RECONCILED": return Theme.primary
        case "SERVER_RESTORED": return Theme.success
        default: return Theme.textSecondary
        }
    }

    function eventTypeLabel(eventType) {
        switch (eventType) {
        case "connection": return qsTr("Connexion")
        case "message": return qsTr("Message")
        case "transfer": return qsTr("Transfert")
        case "call": return qsTr("Appel")
        case "access_denied": return qsTr("Accès refusé")
        default: return eventType
        }
    }

    // ---- Machines : actions sensibles toujours confirmees ---------------
    // Autoriser donne a un poste le droit d'echanger avec le reseau :
    // l'empreinte du certificat est affichee pour verification avant de
    // confirmer. Revoquer et supprimer sont confirmes comme destructeurs.
    function askMachineAction(action, machineId, machineName, fingerprint) {
        machineConfirm.action = action
        machineConfirm.machineId = machineId
        if (action === "authorize") {
            machineConfirm.title = qsTr("Autoriser %1 ?").arg(machineName)
            machineConfirm.message = qsTr("Ce poste pourra échanger messages, fichiers et appels avec le réseau. Vérifiez que l'empreinte ci-dessous correspond bien à celle affichée sur le poste.")
            machineConfirm.detail = fingerprint.length > 0 ? fingerprint : qsTr("Aucune empreinte enregistrée pour ce poste.")
            machineConfirm.confirmText = qsTr("Autoriser")
            machineConfirm.destructive = false
        } else if (action === "revoke") {
            machineConfirm.title = qsTr("Révoquer %1 ?").arg(machineName)
            machineConfirm.message = qsTr("Ce poste ne pourra plus communiquer avec le réseau tant qu'il n'aura pas été réautorisé.")
            machineConfirm.detail = ""
            machineConfirm.confirmText = qsTr("Révoquer")
            machineConfirm.destructive = true
        } else {
            machineConfirm.title = qsTr("Supprimer %1 ?").arg(machineName)
            machineConfirm.message = qsTr("La machine sera retirée de la liste. Si elle se reconnecte, elle réapparaîtra en attente d'autorisation.")
            machineConfirm.detail = ""
            machineConfirm.confirmText = qsTr("Supprimer")
            machineConfirm.destructive = true
        }
        machineConfirm.open()
    }

    function copyToClipboard(text) {
        clipboardHelper.text = text
        clipboardHelper.selectAll()
        clipboardHelper.copy()
    }

    TextEdit {
        id: clipboardHelper
        visible: false
    }

    ConfirmDialog {
        id: machineConfirm
        property string action: ""
        property var machineId: -1
        onConfirmed: {
            let ok = false
            if (action === "authorize")
                ok = authorizedMachineModel.authorizeMachine(machineId, "Autorisé par admin")
            else if (action === "revoke")
                ok = authorizedMachineModel.revokeMachine(machineId, "Révoqué par admin")
            else if (action === "remove")
                ok = authorizedMachineModel.removeMachine(machineId)
            // Le modele ne signale pas ses echecs autrement : sans ce message,
            // un refus metier passait inapercu.
            if (!ok)
                root.showAdminNotice(action === "authorize" ? qsTr("La machine n'a pas pu être autorisée.")
                                   : action === "revoke" ? qsTr("La machine n'a pas pu être révoquée.")
                                   : qsTr("La machine n'a pas pu être retirée."))
        }
    }

    AppMenu {
        id: machineMenu
        property var machineId: -1
        property string machineName: ""
        property string fingerprint: ""

        AppMenuItem {
            text: qsTr("Copier l'empreinte")
            iconGlyph: ""
            enabled: machineMenu.fingerprint.length > 0
            onTriggered: root.copyToClipboard(machineMenu.fingerprint)
        }
        AppMenuSeparator {}
        AppMenuItem {
            text: qsTr("Supprimer la machine")
            iconGlyph: ""
            danger: true
            onTriggered: root.askMachineAction("remove", machineMenu.machineId, machineMenu.machineName, "")
        }
    }

    // ---- Comptes : role et suppression confirmes, refus metier affiches -
    // Les regles (dernier administrateur, compte courant...) restent
    // appliquees cote metier : l'interface se contente d'en rendre compte.
    property string adminNotice: ""

    function askUserAction(action, userId, userName, isAdmin) {
        userConfirm.action = action
        userConfirm.userId = userId
        userConfirm.userIsAdmin = isAdmin
        if (action === "role") {
            userConfirm.title = isAdmin ? qsTr("Retirer les droits d'administration de %1 ?").arg(userName)
                                        : qsTr("Nommer %1 administrateur ?").arg(userName)
            userConfirm.message = isAdmin
                ? qsTr("%1 n'aura plus accès au journal d'audit ni à l'administration.").arg(userName)
                : qsTr("%1 pourra autoriser des machines, gérer les comptes et consulter le journal d'audit.").arg(userName)
            userConfirm.confirmText = isAdmin ? qsTr("Retirer les droits") : qsTr("Nommer administrateur")
            userConfirm.destructive = isAdmin
        } else {
            userConfirm.title = qsTr("Supprimer le compte de %1 ?").arg(userName)
            userConfirm.message = qsTr("Cette personne ne pourra plus se connecter. Cette action est définitive.")
            userConfirm.confirmText = qsTr("Supprimer le compte")
            userConfirm.destructive = true
        }
        userConfirm.open()
    }

    Timer {
        id: adminNoticeTimer
        interval: 6000
        onTriggered: root.adminNotice = ""
    }

    function showAdminNotice(text) {
        root.adminNotice = text
        adminNoticeTimer.restart()
    }

    ConfirmDialog {
        id: userConfirm
        property string action: ""
        property var userId: -1
        property bool userIsAdmin: false
        onConfirmed: {
            if (action === "role") {
                if (!userManagementModel.changeRole(userId, !userIsAdmin))
                    root.showAdminNotice(qsTr("Le rôle n'a pas été modifié : il doit toujours rester au moins un administrateur."))
            } else if (action === "delete") {
                if (!userManagementModel.deleteUser(userId))
                    root.showAdminNotice(qsTr("Le compte n’a pas été supprimé : il doit toujours rester au moins un administrateur."))
            }
        }
    }

    AppMenu {
        id: userMenu
        property var userId: -1
        property string userName: ""
        property bool userIsAdmin: false
        property bool isSelf: false

        AppMenuItem {
            text: userMenu.userIsAdmin ? qsTr("Retirer les droits d'administration") : qsTr("Nommer administrateur")
            iconGlyph: ""
            enabled: !userMenu.isSelf
            onTriggered: root.askUserAction("role", userMenu.userId, userMenu.userName, userMenu.userIsAdmin)
        }
        AppMenuSeparator {}
        AppMenuItem {
            text: qsTr("Supprimer le compte")
            iconGlyph: ""
            danger: true
            enabled: !userMenu.isSelf
            onTriggered: root.askUserAction("delete", userMenu.userId, userMenu.userName, userMenu.userIsAdmin)
        }
    }

    // ---- Journal : recherche locale, selection, presentation ------------
    property string auditSearch: ""
    property var selectedAudit: null

    // Ton + icone par type : un refus d'acces ne doit pas ressembler a un
    // message (le statut n'est jamais porte par la couleur seule).
    function eventTypeTone(eventType) {
        switch (eventType) {
        case "access_denied": return "danger"
        case "connection": return "success"
        case "transfer": return "accent"
        case "call": return "call"
        default: return "neutral"
        }
    }
    function eventTypeGlyph(eventType) {
        switch (eventType) {
        case "access_denied": return ""
        case "connection": return ""
        case "transfer": return ""
        case "call": return ""
        case "message": return ""
        default: return ""
        }
    }
    // Horodatage ISO du modele -> "20 oct. 18:41" (aujourd'hui : "18:41").
    function auditDateLabel(iso) {
        const d = new Date(iso)
        if (isNaN(d.getTime()))
            return iso || ""
        const now = new Date()
        const time = d.toLocaleTimeString(Qt.locale(), "HH:mm")
        if (d.toDateString() === now.toDateString())
            return qsTr("Aujourd'hui %1").arg(time)
        return d.toLocaleDateString(Qt.locale(), "d MMM yyyy") + " " + time
    }
    function auditFullDate(iso) {
        const d = new Date(iso)
        if (isNaN(d.getTime()))
            return iso || ""
        const s = d.toLocaleDateString(Qt.locale(), "dddd d MMMM yyyy")
        return s.charAt(0).toUpperCase() + s.slice(1) + qsTr(" à ") + d.toLocaleTimeString(Qt.locale(), "HH:mm:ss")
    }

    function auditDescriptionLabel(description) {
        let value = description || ""
        const labels = {
            "in_progress": qsTr("En cours"),
            "pending": qsTr("En attente"),
            "completed": qsTr("Terminé"),
            "missed": qsTr("Manqué"),
            "rejected": qsTr("Refusé"),
            "cancelled": qsTr("Annulé"),
            "failed": qsTr("Échoué"),
            "outgoing": qsTr("Sortant"),
            "incoming": qsTr("Entrant")
        }
        for (const key in labels)
            value = value.replace(new RegExp("\\b" + key + "\\b", "g"), labels[key])
        return value
    }

    // Resout un libelle d'acteur lisible pour une entree d'audit. La
    // plupart des evenements authentifies (message, transfert...) ne
    // renseignent que userId (pas d'etiquette libre type IP), donc
    // afficher uniquement actorLabel comme avant affichait "N/A" a tort
    // des qu'un utilisateur connu avait agi. On resout ici le nom via
    // userManagementModel (deja charge pour l'onglet Utilisateurs) avant
    // de retomber sur "N/A" si vraiment aucun acteur n'est identifiable
    // (ex : compte supprime depuis, ou tentative non authentifiee sans
    // adresse).
    function actorLabelFor(entryModel) {
        if (entryModel.actorLabel && entryModel.actorLabel.length > 0)
            return entryModel.actorLabel
        if (entryModel.userId && entryModel.userId > 0) {
            for (let i = 0; i < userManagementModel.rowCount(); ++i) {
                const idx = userManagementModel.index(i, 0)
                if (userManagementModel.data(idx, Qt.UserRole + 1) === entryModel.userId)
                    return userManagementModel.data(idx, Qt.UserRole + 2)
            }
        }
        return qsTr("N/A")
    }


    onCurrentTabChanged: {
        if (currentTab === 3)
            refreshElectionHistory()
    }

    Timer {
        interval: 5000
        running: root.currentTab === 3
        repeat: true
        onTriggered: root.refreshElectionHistory()
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.background
    }

    // Vérification des permissions admin (issue #67)
    Component.onCompleted: {
        auditLogModel.refresh()
        if (!userManager.currentUserIsAdmin) {
            accessDeniedDialog.open()
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ---- Header personnalisé pour Administration -----------------------
        // ---- En-tete de page --------------------------------------------
        // Le journal d'audit et l'administration sont deux sections de la
        // navigation : en mode journal (onglet 0), pas d'onglets ; en mode
        // administration, onglets Machines / Utilisateurs / Bascule.
        AppHeader {
            title: root.journalMode ? qsTr("Journal d'audit") : qsTr("Administration")
            subtitle: root.journalMode
                      ? qsTr("Historique des connexions, transferts, appels et accès refusés sur ce réseau.")
                      : root.currentTab === 1 ? qsTr("Seules les machines autorisées peuvent échanger avec ce poste. Toute nouvelle machine reste en attente jusqu'à validation.")
                      : root.currentTab === 2 ? qsTr("Comptes utilisateurs de l'espace et leurs rôles.")
                      : qsTr("Historique des élections et bascules du serveur du réseau local.")
            bottomPadding: root.journalMode ? 14 : 10

            AppButton {
                visible: root.currentTab === 0
                text: root.headerCompact ? "" : qsTr("Exporter en CSV")
                tooltip: qsTr("Exporter le journal en CSV")
                iconGlyph: ""
                variant: "secondary"
                onClicked: exportDialog.open()
            }
            AppButton {
                visible: root.currentTab === 1
                text: root.headerCompact ? "" : qsTr("Ajouter une machine")
                tooltip: qsTr("Ajouter une machine")
                iconGlyph: ""
                variant: "primary"
                onClicked: addMachineDialog.open()
            }
            AppButton {
                visible: root.currentTab === 2
                text: root.headerCompact ? "" : qsTr("Nouvel utilisateur")
                tooltip: qsTr("Nouvel utilisateur")
                iconGlyph: ""
                variant: "primary"
                onClicked: addUserDialog.open()
            }
            AppButton {
                visible: root.currentTab === 3
                text: root.headerCompact ? "" : qsTr("Actualiser")
                tooltip: qsTr("Actualiser l'historique")
                iconGlyph: ""
                variant: "secondary"
                onClicked: root.refreshElectionHistory()
            }
        }

        AppSegmentedControl {
            visible: !root.journalMode
            Layout.leftMargin: Theme.pagePadding
            Layout.bottomMargin: Theme.spacingMedium
            stretch: false
            model: [
                { label: qsTr("Machines autorisées"), glyph: "" },
                { label: qsTr("Utilisateurs"), glyph: "" },
                { label: qsTr("Bascule serveur"), glyph: "" }
            ]
            currentIndex: Math.max(0, root.currentTab - 1)
            onActivated: function(index) { root.currentTab = index + 1 }
        }

        // Refus metier d une action d administration (role, suppression).
        Rectangle {
            visible: root.adminNotice.length > 0
            Layout.fillWidth: true
            Layout.leftMargin: Theme.pagePadding
            Layout.rightMargin: Theme.pagePadding
            Layout.bottomMargin: Theme.spacingMedium
            implicitHeight: noticeRow.implicitHeight + 20
            radius: Theme.radiusControl
            color: Theme.warningSoft
            border.width: 1
            border.color: Theme.alpha(Theme.warningColor, 0.35)

            RowLayout {
                id: noticeRow
                anchors.fill: parent
                anchors.margins: 10
                anchors.leftMargin: 14
                spacing: 10
                FaIcon {
                    glyph: ""
                    color: Theme.warningInk
                    font.pixelSize: Theme.fs(13)
                }
                Text {
                    Layout.fillWidth: true
                    text: root.adminNotice
                    color: Theme.warningInk
                    font.pixelSize: Theme.fs(13)
                    font.family: Theme.fontFamily
                    wrapMode: Text.WordWrap
                }
                IconButton {
                    glyph: ""
                    size: 26
                    iconSize: Theme.fs(11)
                    tooltip: qsTr("Fermer")
                    onClicked: root.adminNotice = ""
                }
            }
        }

        // ==================================================================
        // Journal d'audit
        // ==================================================================
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.currentTab === 0

            ColumnLayout {
                width: parent.width - 2 * Theme.pagePadding
                height: parent.height - Theme.pagePadding
                x: Theme.pagePadding
                y: 0
                spacing: Theme.spacingMedium

                // ---- Filtres ----
                Flow {
                    Layout.fillWidth: true
                    spacing: 10

                    AppSearchField {
                        width: 260
                        placeholderText: qsTr("Rechercher un événement ou un acteur")
                        onTextChanged: root.auditSearch = text.trim().toLowerCase()
                    }

                    AppComboBox {
                        id: eventTypeFilter
                        width: 190
                        textRole: "label"
                        valueRole: "value"
                        model: [
                            { value: "", label: qsTr("Tous les types") },
                            { value: "connection", label: qsTr("Connexions") },
                            { value: "message", label: qsTr("Messages") },
                            { value: "transfer", label: qsTr("Transferts") },
                            { value: "call", label: qsTr("Appels") },
                            { value: "access_denied", label: qsTr("Accès refusés") }
                        ]
                        onActivated: function(index) {
                            const value = eventTypeFilter.model[index].value
                            if (value.length === 0)
                                auditLogModel.clearFilters()
                            else
                                auditLogModel.setEventTypeFilter(value)
                        }
                    }

                    AppTextField {
                        id: dateFrom
                        width: 150
                        placeholderText: qsTr("Du (AAAA-MM-JJ)")
                    }
                    AppTextField {
                        id: dateTo
                        width: 150
                        placeholderText: qsTr("Au (AAAA-MM-JJ)")
                        onAccepted: auditLogModel.setDateRange(dateFrom.text, dateTo.text)
                    }
                    AppButton {
                        variant: "secondary"
                        text: qsTr("Appliquer la période")
                        enabled: dateFrom.text.length > 0 || dateTo.text.length > 0
                        onClicked: auditLogModel.setDateRange(dateFrom.text, dateTo.text)
                    }
                    AppButton {
                        variant: "ghost"
                        text: qsTr("Réinitialiser")
                        visible: eventTypeFilter.currentIndex > 0 || dateFrom.text.length > 0
                                 || dateTo.text.length > 0
                        onClicked: {
                            eventTypeFilter.currentIndex = 0
                            dateFrom.text = ""
                            dateTo.text = ""
                            auditLogModel.clearFilters()
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: Theme.spacingGutter

                    // ---- Tableau ----
                    Card {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentPadding: 0
                        clip: true

                        TableHeader {
                            Layout.fillWidth: true
                            columns: [
                                { title: qsTr("Date"), width: 120 },
                                { title: qsTr("Type"), width: 140 },
                                { title: qsTr("Événement"), fill: true },
                                { title: qsTr("Acteur"), width: 170, visible: root.width >= 1000 }
                            ]
                        }

                        ListView {
                            id: auditListView
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            model: auditLogModel
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            ScrollBar.vertical: ScrollBar {}

                            delegate: ItemDelegate {
                                id: auditRow
                                required property int index
                                required property var model

                                readonly property string actor: root.actorLabelFor(auditRow.model)
                                readonly property string label: root.auditDescriptionLabel(auditRow.model.description)
                                readonly property bool matches: root.auditSearch.length === 0
                                    || auditRow.label.toLowerCase().indexOf(root.auditSearch) >= 0
                                    || auditRow.actor.toLowerCase().indexOf(root.auditSearch) >= 0
                                readonly property bool selected: root.selectedAudit !== null
                                                                 && root.selectedAudit.id === auditRow.model.id

                                visible: auditRow.matches
                                width: ListView.view.width
                                height: auditRow.matches ? Theme.rowHeight - 4 : 0
                                leftPadding: Theme.cardPadding
                                rightPadding: Theme.cardPadding
                                hoverEnabled: true
                                Accessible.name: root.eventTypeLabel(auditRow.model.eventType) + ", " + auditRow.label
                                onClicked: root.selectedAudit = {
                                    id: auditRow.model.id, eventType: auditRow.model.eventType,
                                    timestamp: auditRow.model.timestamp, description: auditRow.label,
                                    actor: auditRow.actor
                                }

                                HoverHandler { cursorShape: Qt.PointingHandCursor }

                                background: Rectangle {
                                    color: auditRow.selected ? Theme.accentSoft : (auditRow.hovered ? Theme.hover : "transparent")
                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        height: 1
                                        color: Theme.line
                                    }
                                }

                                contentItem: RowLayout {
                                    spacing: 12

                                    Text {
                                        Layout.preferredWidth: 120
                                        Layout.minimumWidth: 120
                                        text: root.auditDateLabel(auditRow.model.timestamp)
                                        color: Theme.ink2
                                        font.pixelSize: Theme.fs(12)
                                        font.family: Theme.fontFamily
                                        font.features: ({ "tnum": 1 })
                                    }
                                    Item {
                                        Layout.preferredWidth: 140
                                        Layout.minimumWidth: 140
                                        Layout.fillHeight: true
                                        StatusBadge {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: root.eventTypeLabel(auditRow.model.eventType)
                                            tone: root.eventTypeTone(auditRow.model.eventType)
                                            glyph: root.eventTypeGlyph(auditRow.model.eventType)
                                            compact: true
                                        }
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        Layout.preferredWidth: 100
                                        text: auditRow.label
                                        color: Theme.ink
                                        font.pixelSize: Theme.fs(13)
                                        font.family: Theme.fontFamily
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        visible: root.width >= 1000
                                        Layout.preferredWidth: 170
                                        Layout.minimumWidth: 170
                                        text: auditRow.actor
                                        color: Theme.ink2
                                        font.pixelSize: Theme.fs(12)
                                        font.family: Theme.fontFamily
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }

                        EmptyState {
                            visible: auditListView.count === 0
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            iconName: "log"
                            title: eventTypeFilter.currentIndex > 0 || dateFrom.text.length > 0
                                   ? qsTr("Aucun événement pour ces filtres")
                                   : qsTr("Aucun événement enregistré")
                            description: eventTypeFilter.currentIndex > 0 || dateFrom.text.length > 0
                                         ? qsTr("Élargissez la période ou choisissez un autre type.")
                                         : qsTr("Les connexions, transferts, appels et refus d'accès apparaîtront ici.")
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 1
                            color: Theme.line
                        }
                        Text {
                            Layout.fillWidth: true
                            Layout.margins: 10
                            Layout.leftMargin: Theme.cardPadding
                            text: auditLogModel.count === 1 ? qsTr("1 événement") : qsTr("%1 événements").arg(auditLogModel.count)
                            color: Theme.ink3
                            font.pixelSize: Theme.fs(12)
                            font.family: Theme.fontFamily
                        }
                    }

                    // ---- Detail de l'evenement selectionne ----
                    Card {
                        visible: root.selectedAudit !== null && root.width >= 900
                        Layout.preferredWidth: 320
                        Layout.fillHeight: true
                        title: qsTr("Détail de l'événement")
                        headerActions: [
                            IconButton {
                                glyph: ""
                                size: 28
                                iconSize: Theme.fs(11)
                                tooltip: qsTr("Fermer le détail")
                                onClicked: root.selectedAudit = null
                            }
                        ]

                        StatusBadge {
                            text: root.selectedAudit ? root.eventTypeLabel(root.selectedAudit.eventType) : ""
                            tone: root.selectedAudit ? root.eventTypeTone(root.selectedAudit.eventType) : "neutral"
                            glyph: root.selectedAudit ? root.eventTypeGlyph(root.selectedAudit.eventType) : ""
                        }

                        Text {
                            Layout.fillWidth: true
                            Layout.topMargin: 6
                            text: root.selectedAudit ? root.selectedAudit.description : ""
                            color: Theme.ink
                            font.pixelSize: Theme.fs(14)
                            font.family: Theme.fontFamily
                            wrapMode: Text.WordWrap
                        }

                        Repeater {
                            model: root.selectedAudit ? [
                                { k: qsTr("Date"), v: root.auditFullDate(root.selectedAudit.timestamp) },
                                { k: qsTr("Acteur"), v: root.selectedAudit.actor },
                                { k: qsTr("Référence"), v: "#" + root.selectedAudit.id }
                            ] : []
                            delegate: ColumnLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.topMargin: 8
                                spacing: 2
                                Text {
                                    text: modelData.k
                                    color: Theme.ink3
                                    font.pixelSize: Theme.fs(11)
                                    font.weight: Theme.weightSemibold
                                    font.family: Theme.fontFamily
                                }
                                TextEdit {
                                    Layout.fillWidth: true
                                    text: modelData.v
                                    readOnly: true
                                    selectByMouse: true
                                    wrapMode: Text.Wrap
                                    color: Theme.ink
                                    font.pixelSize: Theme.fs(13)
                                    font.family: Theme.fontFamily
                                }
                            }
                        }

                        Item { Layout.fillHeight: true }
                    }
                }
            }
        }

        // ==================================================================
        // Machines autorisees
        // ==================================================================
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.currentTab === 1

            Card {
                width: parent.width - 2 * Theme.pagePadding
                height: parent.height - Theme.pagePadding
                x: Theme.pagePadding
                y: 0
                contentPadding: 0
                clip: true

                TableHeader {
                    visible: machinesList.count > 0
                    Layout.fillWidth: true
                    columns: [
                        { title: qsTr("Machine"), fill: true },
                        { title: qsTr("Adresse"), width: 130, visible: root.width >= 900 },
                        { title: qsTr("État"), width: 120 },
                        { title: qsTr("Ajoutée"), width: 140, visible: root.width >= 1100 },
                        { title: qsTr("Empreinte du certificat"), width: 170, visible: root.width >= 1000 },
                        { title: "", width: 168 }
                    ]
                }

                ListView {
                    id: machinesList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    model: authorizedMachineModel
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar {}

                    delegate: ItemDelegate {
                        id: machineRow
                        required property var model
                        readonly property string machineName: machineRow.model.hostname || machineRow.model.machineUuid || qsTr("Machine inconnue")
                        readonly property string fingerprint: machineRow.model.certificateFingerprint || ""
                        readonly property string status: machineRow.model.status || ""

                        width: ListView.view.width
                        height: Theme.rowHeight + 6
                        leftPadding: Theme.cardPadding
                        rightPadding: Theme.cardPadding
                        hoverEnabled: true
                        Accessible.name: machineRow.machineName

                        background: Rectangle {
                            color: machineRow.status === "pending" ? Theme.alpha(Theme.warningColor, 0.06)
                                   : (machineRow.hovered ? Theme.hover : "transparent")
                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                height: 1
                                color: Theme.line
                            }
                        }

                        contentItem: RowLayout {
                            spacing: 12

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.preferredWidth: 100
                                spacing: 10

                                Rectangle {
                                    Layout.preferredWidth: 32
                                    Layout.preferredHeight: 32
                                    radius: 8
                                    color: Theme.sunken
                                    FaIcon {
                                        anchors.centerIn: parent
                                        glyph: ""
                                        color: Theme.ink2
                                        font.pixelSize: Theme.fs(13)
                                    }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1
                                    Text {
                                        text: machineRow.machineName
                                        color: Theme.ink
                                        font.pixelSize: Theme.fs(13)
                                        font.weight: Theme.weightMedium
                                        font.family: Theme.fontFamily
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                    Text {
                                        visible: root.width < 900
                                        text: machineRow.model.lastIpAddress || machineRow.model.ipAddress || ""
                                        color: Theme.ink3
                                        font.pixelSize: Theme.fs(11)
                                        font.family: Theme.fontFamily
                                    }
                                }
                            }

                            Text {
                                visible: root.width >= 900
                                Layout.preferredWidth: 130
                                Layout.minimumWidth: 130
                                text: machineRow.model.lastIpAddress || machineRow.model.ipAddress || "—"
                                color: Theme.ink2
                                font.pixelSize: Theme.fs(12)
                                font.family: Theme.fontFamily
                                font.features: ({ "tnum": 1 })
                            }

                            Item {
                                Layout.preferredWidth: 120
                                Layout.minimumWidth: 120
                                Layout.fillHeight: true
                                StatusBadge {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: machineRow.status === "pending" ? qsTr("En attente")
                                        : machineRow.status === "authorized" ? qsTr("Autorisée") : qsTr("Révoquée")
                                    tone: machineRow.status === "pending" ? "warning"
                                        : machineRow.status === "authorized" ? "success" : "danger"
                                    glyph: machineRow.status === "pending" ? ""
                                         : machineRow.status === "authorized" ? "" : ""
                                    compact: true
                                }
                            }

                            Text {
                                visible: root.width >= 1100
                                Layout.preferredWidth: 140
                                Layout.minimumWidth: 140
                                text: root.auditDateLabel(machineRow.model.addedAt)
                                color: Theme.ink3
                                font.pixelSize: Theme.fs(12)
                                font.family: Theme.fontFamily
                            }

                            RowLayout {
                                visible: root.width >= 1000
                                Layout.preferredWidth: 170
                                Layout.minimumWidth: 170
                                Layout.maximumWidth: 170
                                spacing: 4
                                Text {
                                    Layout.fillWidth: true
                                    text: machineRow.fingerprint.length > 0
                                          ? machineRow.fingerprint.substring(0, 17) + "…" : qsTr("Non enregistrée")
                                    color: machineRow.fingerprint.length > 0 ? Theme.ink2 : Theme.ink3
                                    font.pixelSize: Theme.fs(12)
                                    font.family: "Consolas"
                                    elide: Text.ElideRight
                                }
                                IconButton {
                                    visible: machineRow.fingerprint.length > 0
                                    glyph: ""
                                    size: 26
                                    iconSize: Theme.fs(11)
                                    tooltip: qsTr("Copier l'empreinte complète")
                                    onClicked: root.copyToClipboard(machineRow.fingerprint)
                                }
                            }

                            RowLayout {
                                Layout.preferredWidth: 168
                                Layout.minimumWidth: 168
                                Layout.maximumWidth: 168
                                spacing: 4

                                Item { Layout.fillWidth: true }

                                AppButton {
                                    size: "small"
                                    text: machineRow.status === "authorized" ? qsTr("Révoquer")
                                        : machineRow.status === "pending" ? qsTr("Autoriser") : qsTr("Réautoriser")
                                    variant: machineRow.status === "authorized" ? "dangerGhost"
                                           : machineRow.status === "pending" ? "primary" : "secondary"
                                    onClicked: root.askMachineAction(
                                                   machineRow.status === "authorized" ? "revoke" : "authorize",
                                                   machineRow.model.id, machineRow.machineName, machineRow.fingerprint)
                                }
                                IconButton {
                                    glyph: ""
                                    size: 30
                                    iconSize: Theme.fs(13)
                                    tooltip: qsTr("Plus d'actions")
                                    onClicked: {
                                        machineMenu.machineId = machineRow.model.id
                                        machineMenu.machineName = machineRow.machineName
                                        machineMenu.fingerprint = machineRow.fingerprint
                                        machineMenu.popup()
                                    }
                                }
                            }
                        }
                    }
                }

                EmptyState {
                    visible: machinesList.count === 0
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    iconName: "lock"
                    title: qsTr("Aucune machine enregistrée")
                    description: qsTr("Les postes qui tentent de rejoindre le réseau apparaissent ici en attente. Vous pouvez aussi ajouter une machine à partir de l'empreinte de son certificat.")
                    actionText: qsTr("Ajouter une machine")
                    onActionClicked: addMachineDialog.open()
                }
            }
        }

        // ==================================================================
        // Utilisateurs
        // ==================================================================
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.currentTab === 2

            Card {
                width: parent.width - 2 * Theme.pagePadding
                height: parent.height - Theme.pagePadding
                x: Theme.pagePadding
                y: 0
                contentPadding: 0
                clip: true

                TableHeader {
                    visible: usersGrid.count > 0
                    Layout.fillWidth: true
                    columns: [
                        { title: qsTr("Utilisateur"), fill: true },
                        { title: qsTr("Rôle"), width: 140 },
                        { title: qsTr("Présence"), width: 130 },
                        { title: "", width: 250 }
                    ]
                }

                ListView {
                    // Id conserve : le Timer de presence force un relayout.
                    id: usersGrid
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    model: userManagementModel
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar {}

                    delegate: ItemDelegate {
                        id: userRow
                        required property var model
                        readonly property bool isSelf: typeof userManager !== "undefined"
                                                       && userManager.currentUsername === userRow.model.name
                        readonly property string presence: root.liveUserStatus(userRow.model.name, userRow.model.uuid)

                        width: ListView.view.width
                        height: Theme.rowHeight + 4
                        leftPadding: Theme.cardPadding
                        rightPadding: Theme.cardPadding
                        hoverEnabled: true
                        Accessible.name: userRow.model.name

                        background: Rectangle {
                            color: userRow.hovered ? Theme.hover : "transparent"
                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                height: 1
                                color: Theme.line
                            }
                        }

                        contentItem: RowLayout {
                            spacing: 12

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.preferredWidth: 100
                                spacing: 10
                                Avatar {
                                    name: userRow.model.name
                                    size: 32
                                }
                                Text {
                                    text: userRow.model.name
                                    color: Theme.ink
                                    font.pixelSize: Theme.fs(13)
                                    font.weight: Theme.weightMedium
                                    font.family: Theme.fontFamily
                                    elide: Text.ElideRight
                                }
                                StatusBadge {
                                    visible: userRow.isSelf
                                    text: qsTr("Vous")
                                    showDot: false
                                    compact: true
                                }
                                Item { Layout.fillWidth: true }
                            }

                            Item {
                                Layout.preferredWidth: 140
                                Layout.minimumWidth: 140
                                Layout.fillHeight: true
                                StatusBadge {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: userRow.model.isAdmin ? qsTr("Administrateur") : qsTr("Utilisateur")
                                    tone: userRow.model.isAdmin ? "accent" : "neutral"
                                    glyph: userRow.model.isAdmin ? "" : ""
                                    compact: true
                                }
                            }

                            Item {
                                Layout.preferredWidth: 130
                                Layout.minimumWidth: 130
                                Layout.fillHeight: true
                                StatusBadge {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: userRow.presence === "online" ? qsTr("En ligne")
                                        : userRow.presence === "away" ? qsTr("Absent")
                                        : userRow.presence === "busy" ? qsTr("Occupé") : qsTr("Hors ligne")
                                    tone: userRow.presence === "online" ? "success"
                                        : (userRow.presence === "away" || userRow.presence === "busy") ? "warning" : "neutral"
                                    compact: true
                                }
                            }

                            RowLayout {
                                Layout.preferredWidth: 250
                                Layout.minimumWidth: 250
                                Layout.maximumWidth: 250
                                spacing: 4

                                Item { Layout.fillWidth: true }

                                IconButton {
                                    glyph: ""
                                    size: 30
                                    iconSize: Theme.fs(13)
                                    tooltip: qsTr("Réinitialiser le mot de passe de %1").arg(userRow.model.name)
                                    Accessible.name: tooltip
                                    onClicked: {
                                        root.passwordResetUserId = userRow.model.id
                                        root.passwordResetUsername = userRow.model.name
                                        resetPasswordDialog.open()
                                    }
                                }
                                IconButton {
                                    glyph: ""
                                    size: 30
                                    iconSize: Theme.fs(13)
                                    tooltip: qsTr("Plus d'actions pour %1").arg(userRow.model.name)
                                    onClicked: {
                                        userMenu.userId = userRow.model.id
                                        userMenu.userName = userRow.model.name
                                        userMenu.userIsAdmin = userRow.model.isAdmin
                                        userMenu.isSelf = userRow.isSelf
                                        userMenu.popup()
                                    }
                                }
                            }
                        }
                    }
                }

                EmptyState {
                    visible: usersGrid.count === 0
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    iconName: "users"
                    title: qsTr("Aucun utilisateur")
                    description: qsTr("Créez les comptes de votre équipe pour qu'ils puissent se connecter depuis leur poste.")
                    actionText: qsTr("Nouvel utilisateur")
                    onActionClicked: addUserDialog.open()
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.currentTab === 3

ColumnLayout {
    width: parent.width - 2 * Theme.pagePadding
    height: parent.height - Theme.pagePadding
    x: Theme.pagePadding
    y: 0
    spacing: Theme.spacingMedium

    // Bloc titre + sous-titre : espacement resserré, indépendant
    // du spacing du ColumnLayout externe.
    ColumnLayout {
        Layout.fillWidth: true
        spacing: Theme.spacingXs

        Label {
            text: qsTr("Historique des bascules")
            font.pixelSize: Theme.fontSizeHeading
            font.bold: true
            font.family: Theme.fontFamily
            color: Theme.text
        }

        Label {
            text: qsTr("Chaque ligne correspond à un événement du protocole d'élection (perte de heartbeat, promotion en serveur de secours, réconciliation, reprise du serveur officiel).")
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSizeSmall
            font.family: Theme.fontFamily
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: Theme.border
    }

                ColumnLayout {
                    visible: root.electionHistoryEntries.length === 0
                    spacing: Theme.spacingMedium
                    Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter

                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: 80
                        Layout.preferredHeight: 80
                        radius: 40
                        color: Theme.surfaceAlt

                        Text {
                            anchors.centerIn: parent
                            text: "\uf021"
                            font.family: root.iconFontFamily
                            font.pixelSize: Theme.fs(32)
                            color: Theme.textSecondary
                        }
                    }

                    Label {
                        Layout.alignment: Qt.AlignHCenter
                        text: qsTr("Aucun événement enregistré")
                        color: Theme.text
                        font.pixelSize: Theme.fontSizeSubheading
                        font.bold: true
                        font.family: Theme.fontFamily
                    }

                    Label {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.fillWidth: true
                        text: qsTr("L'historique des bascules de serveur apparaîtra ici dès qu'un événement d'élection se produira.")
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeSmall
                        font.family: Theme.fontFamily
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                    }
                }

                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: Theme.spacingSmall
                    visible: root.electionHistoryEntries.length > 0
                    model: root.electionHistoryEntries

                    delegate: Rectangle {
                        width: ListView.view ? ListView.view.width : 0
                        height: electionEntryColumn.implicitHeight + Theme.spacingLarge * 2
                        radius: Theme.radiusLarge
                        color: Theme.surface
                        border.width: 1
                        border.color: Theme.border

                        ColumnLayout {
                            id: electionEntryColumn
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: Theme.spacingLarge
                            spacing: Theme.spacingSmall

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Theme.spacingMedium

                                Rectangle {
                                    Layout.preferredWidth: 12
                                    Layout.preferredHeight: 12
                                    Layout.alignment: Qt.AlignVCenter
                                    radius: 6
                                    color: root.electionEventColor(modelData.event)
                                }

                                Label {
                                    text: modelData.event
                                    color: Theme.text
                                    font.bold: true
                                    font.family: Theme.fontFamily
                                    elide: Text.ElideRight
                                    font.pixelSize: Theme.fontSizeBody
                                }

                                Item { Layout.fillWidth: true }

                                Label {
                                    text: qsTr("epoch %1").arg(modelData.epoch)
                                    color: Theme.textSecondary
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.family: Theme.fontFamily
                                }
                            }

                            Label {
                                text: modelData.machineUuid
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontSizeSmall
                                font.family: Theme.fontFamily
                                elide: Text.ElideMiddle
                                Layout.fillWidth: true
                            }

                            Label {
                                text: modelData.createdAt
                                color: Theme.textTertiary
                                font.pixelSize: Theme.fontSizeCaption
                                font.family: Theme.fontFamily
                                Layout.topMargin: Theme.spacingXs
                            }
                        }
                    }
                }
            }
        }
    }

    FileDialog {
        id: exportDialog
        title: qsTr("Exporter le journal d'audit")
        nameFilters: ["Fichiers CSV (*.csv)"]
        onAccepted: {
            const filePath = selectedFile
            const result = auditLogModel.exportToCsv(filePath)
            if (result) {
                console.log("Export réussi:", result)
            } else {
                console.log("Export échoué")
            }
        }
    }

    AppDialog {
        id: resetPasswordDialog
        title: qsTr("Réinitialiser le mot de passe")
        headerIcon: "\uf084"
        dialogWidth: 400
        dialogHeight: resetPasswordColumn.implicitHeight + Theme.spacingMedium * 2
        standardButtons: Dialog.NoButton

        onOpened: {
            resetPasswordField.text = ""
            confirmPasswordField.text = ""
        }

        ColumnLayout {
            id: resetPasswordColumn
            width: parent.width
            spacing: Theme.spacingMedium

            Label {
                Layout.fillWidth: true
                text: qsTr("Définir un nouveau mot de passe pour « %1 ». L'ancien mot de passe ne peut pas être affiché.").arg(root.passwordResetUsername)
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.WordWrap
            }

            AppPasswordField {
                id: resetPasswordField
                Layout.fillWidth: true
                label: qsTr("Nouveau mot de passe")
                placeholderText: qsTr("4 caractères minimum")
            }

            AppPasswordField {
                id: confirmPasswordField
                Layout.fillWidth: true
                label: qsTr("Confirmer le mot de passe")
                placeholderText: qsTr("Répétez le nouveau mot de passe")
            }

            Label {
                visible: resetPasswordField.text.length > 0
                         && resetPasswordField.text !== confirmPasswordField.text
                text: qsTr("Les mots de passe ne correspondent pas.")
                color: Theme.error
                font.pixelSize: Theme.fontSizeCaption
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingSmall

                Item { Layout.fillWidth: true }

                AppButton {
                    variant: "ghost"
                    text: qsTr("Annuler")
                    onClicked: resetPasswordDialog.close()
                }

                AppButton {
                    variant: "primary"
                    text: qsTr("Réinitialiser")
                    enabled: resetPasswordField.text.length >= 4
                             && resetPasswordField.text === confirmPasswordField.text
                    onClicked: {
                        if (userManagementModel.resetPassword(root.passwordResetUserId,
                                                              resetPasswordField.text)) {
                            resetPasswordDialog.close()
                        }
                    }
                }
            }
        }
    }

    AppDialog {
        id: addMachineDialog
        property string errorText: ""
        onAboutToShow: errorText = ""
        title: qsTr("Ajouter une machine autorisée")
        headerIcon: "\uf109"
        dialogWidth: 460
        // CORRECTIF (grand vide sous les boutons) : une hauteur figee
        // (600) laissait un espace mort des que le contenu reel etait
        // plus court que ca -- ce qui est desormais toujours le cas
        // depuis la reorganisation en maquette. On se cale sur la
        // hauteur naturelle du formulaire (mainColumn.implicitHeight),
        // plafonnee a 560 pour garder un filet de securite (scroll) sur
        // les petites fenetres/hauts de casse imprevus.
        dialogHeight: Math.min(mainColumn.implicitHeight + Theme.spacingMedium * 2, 560)

        ScrollView {
            anchors.fill: parent
            clip: true
            contentWidth: availableWidth

            ColumnLayout {
                id: mainColumn
                width: parent.width
                spacing: Theme.spacingMedium

                // ---- Section "detection auto" : mise en avant dans une
                // carte a part, car c'est le chemin rapide dans l'immense
                // majorite des cas (poste deja visible sur le LAN). ----
                Rectangle {
                    Layout.fillWidth: true
                    radius: Theme.radiusMedium
                    color: Theme.background
                    implicitHeight: detectedColumn.implicitHeight + Theme.spacingMedium * 2

                    ColumnLayout {
                        id: detectedColumn
                        anchors.fill: parent
                        anchors.margins: Theme.spacingMedium
                        spacing: Theme.spacingXs

                        Label {
                            text: qsTr("Poste détecté sur le réseau")
                            font.pixelSize: Theme.fontSizeSmall
                            font.family: Theme.fontFamily
                            color: Theme.textSecondary
                        }

                        AppComboBox {
                            id: detectedMachineSelector
                            Layout.fillWidth: true
                            Accessible.name: qsTr("Poste détecté sur le réseau")
                            model: ((typeof discoveryService !== "undefined" && discoveryService)
                                    ? discoveryService.machineCandidates() : [])
                                   .map(function(c) { return Object.assign({}, c, { label: c.name + " — " + c.ip }) })
                            textRole: "label"
                            currentIndex: -1
                            displayText: currentIndex >= 0 ? currentText : qsTr("Sélectionner un poste détecté")
                            onActivated: {
                                const candidate = model[index]
                                if (!candidate) return
                                newMachineFingerprint.text = candidate.fingerprint || ""
                                newMachineUuid.text = candidate.id || ""
                                newMachineIp.text = candidate.ip || ""
                                newMachineHostname.text = candidate.name || ""
                            }
                        }

                        Label {
                            Layout.topMargin: 4
                            Layout.fillWidth: true
                            text: qsTr("Pré-remplit l'empreinte, l'UUID, l'IP et le nom automatiquement")
                            font.pixelSize: Theme.fontSizeCaption
                            font.family: Theme.fontFamily
                            color: Theme.textTertiary
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                AppDivider {
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.spacingXs
                    label: qsTr("ou saisir manuellement")
                }

                AppTextField {
                    id: newMachineFingerprint
                    Layout.fillWidth: true
                    label: qsTr("Empreinte SHA-256 du certificat")
                    placeholderText: qsTr("empreinte SHA-256 complète")
                }

                AppTextField {
                    id: newMachineUuid
                    Layout.fillWidth: true
                    label: qsTr("UUID de la machine")
                    placeholderText: qsTr("UUID annoncé par le poste")
                }

                // Hote + IP sur une meme ligne : deux champs courts et
                // apparentes, inutile de leur donner chacun une ligne
                // pleine largeur comme c'etait le cas avant.
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingSmall

                    AppTextField {
                        id: newMachineHostname
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        label: qsTr("Nom d'hôte")
                        placeholderText: qsTr("DESKTOP-DG")
                    }

                    AppTextField {
                        id: newMachineIp
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        label: qsTr("Dernière IP")
                        placeholderText: "192.168.1.x"
                    }
                }

                Label {
                    Layout.fillWidth: true
                    text: qsTr("Nom d'hôte et IP sont optionnels — utiles pour retrouver ce poste plus tard.")
                    font.pixelSize: Theme.fontSizeCaption
                    font.family: Theme.fontFamily
                    color: Theme.textTertiary
                    wrapMode: Text.WordWrap
                }

                Dash.InlineAlert {
                    visible: text.length > 0
                    Layout.fillWidth: true
                    text: addMachineDialog.errorText
                    onCloseRequested: addMachineDialog.errorText = ""
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.spacingSmall
                    spacing: Theme.spacingSmall

                    Item { Layout.fillWidth: true }

                    AppButton {
                        variant: "ghost"
                        text: qsTr("Annuler")
                        onClicked: addMachineDialog.close()
                    }

                    AppButton {
                        variant: "primary"
                        text: qsTr("Ajouter la machine")
                        onClicked: {
                            const ok = authorizedMachineModel.addMachineByCertificate(
                                newMachineFingerprint.text, newMachineUuid.text,
                                newMachineIp.text, newMachineHostname.text,
                                "Ajouté par admin")
                            // En cas de refus, la saisie est conservee et l'erreur affichee.
                            if (ok)
                                addMachineDialog.close()
                            else
                                addMachineDialog.errorText = qsTr("La machine n'a pas été ajoutée : l'empreinte du certificat est obligatoire. Si elle est renseignée, l'enregistrement a échoué ; réessayez.")
                        }
                    }
                }
            }
        }
    }

    AppDialog {
        id: addUserDialog
        property string errorText: ""
        onAboutToShow: errorText = ""
        title: qsTr("Ajouter un utilisateur")
        headerIcon: "\uf234"
        dialogWidth: 380
        // Hauteur calculee sur le contenu reel (meme principe que la
        // modale "Ajouter une machine" juste au-dessus). contentColumn
        // n'utilise que `width: parent.width` (pas anchors.fill), donc
        // son implicitHeight ne depend que de son propre contenu -- pas
        // de dependance circulaire.
        dialogHeight: contentColumn.implicitHeight + Theme.spacingMedium * 2

        ColumnLayout {
            id: contentColumn
            width: parent.width
            spacing: Theme.spacingMedium

            AppTextField {
                id: newUserName
                Layout.fillWidth: true
                label: qsTr("Nom d'utilisateur")
                placeholderText: qsTr("loukmane")
            }

            AppPasswordField {
                id: newUserPassword
                Layout.fillWidth: true
                label: qsTr("Mot de passe")
                placeholderText: qsTr("8 caratères minimum")
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingXs

                Label {
                    text: qsTr("Rôle")
                    font.pixelSize: Theme.fontSizeSmall
                    font.family: Theme.fontFamily
                    color: Theme.textSecondary
                }

                AppSegmentedControl {
                    id: newUserRole
                    Layout.fillWidth: true
                    model: [
                        { label: qsTr("Utilisateur"), glyph: "\uf007" },
                        { label: qsTr("Administrateur"), glyph: "\uf132" }
                    ]
                    currentIndex: 0
                }
            }

            Dash.InlineAlert {
                visible: text.length > 0
                Layout.fillWidth: true
                text: addUserDialog.errorText
                onCloseRequested: addUserDialog.errorText = ""
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingSmall

                Item { Layout.fillWidth: true }

                AppButton {
                    variant: "ghost"
                    text: qsTr("Annuler")
                    onClicked: addUserDialog.close()
                }

                AppButton {
                    variant: "primary"
                    text: qsTr("Ajouter")
                    onClicked: {
                        const isAdmin = newUserRole.currentIndex === 1
                        const ok = userManagementModel.createUser(newUserName.text, newUserPassword.text, isAdmin)
                        if (ok)
                            addUserDialog.close()
                        else
                            addUserDialog.errorText = qsTr("Le compte n'a pas été créé. Vérifiez que le nom est renseigné et pas déjà utilisé, et que le mot de passe contient au moins 4 caractères.")
                    }
                }
            }
        }
    }

    AppDialog {
        id: accessDeniedDialog
        // Modale d'alerte pure (pas un formulaire) : pas de barre
        // d'en-tete Label+icone+croix comme les autres dialogs, l'icone
        // est integree en grand format au centre du contenu -- plus
        // lisible pour un message court et bloquant.
        dialogWidth: 340
        showHeader: false
        showCloseButton: false
        closePolicy: Popup.NoAutoClose
        // Meme principe que les 2 dialogs precedents : showHeader:false
        // donc pas de +60, juste le contenu + le padding du Dialog.
        dialogHeight: alertColumn.implicitHeight + Theme.spacingMedium * 2

        FontLoader {
            id: accessDeniedIconFont
            source: "../Assets/fonts/fontawesome-webfont.ttf"
        }

        ColumnLayout {
            id: alertColumn
            width: parent.width
            spacing: Theme.spacingMedium

            Item { Layout.preferredHeight: Theme.spacingXs }

            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 48
                Layout.preferredHeight: 48
                radius: width / 2
                color: Theme.errorMuted

                Text {
                    anchors.centerIn: parent
                    text: "\uf023"
                    font.family: accessDeniedIconFont.name
                    font.pixelSize: Theme.fs(20)
                    color: Theme.error
                }
            }

            Label {
                Layout.fillWidth: true
                Layout.topMargin: Theme.spacingXs
                text: qsTr("Accès refusé")
                horizontalAlignment: Text.AlignHCenter
                color: Theme.text
                font.pixelSize: Theme.fontSizeHeading
                font.bold: true
                font.family: Theme.fontFamily
            }

            Label {
                Layout.fillWidth: true
                text: qsTr("Vous n'avez pas les droits administrateur pour accéder à cette page.")
                horizontalAlignment: Text.AlignHCenter
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeBody
                font.family: Theme.fontFamily
                wrapMode: Text.WordWrap
            }

            AppButton {
                Layout.fillWidth: true
                Layout.topMargin: Theme.spacingXs
                variant: "primary"
                text: qsTr("Retour")
                onClicked: {
                    accessDeniedDialog.close()
                    root.backRequested()
                }
            }
        }
    }
}
