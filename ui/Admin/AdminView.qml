import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import Themes

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
 */
Item {
    id: root

    signal backRequested()

    property int currentTab: 0  // 0 = Audit log, 1 = Machines autorisées, 2 = Utilisateurs, 3 = Paramètres, 4 = Bascule serveur

    // Historique des bascules (ServerElectionLog), pour l'onglet "Bascule
    // serveur" (HYBRID_SERVER_FAILOVER.md section 9, etape 5). Pas de
    // signal de changement cote C++ (simple Q_INVOKABLE) : on rafraichit
    // explicitement (bouton, ouverture de l'onglet, et un Timer discret
    // pendant que l'onglet est actif) plutot que de tout faire reposer sur
    // le binding reactif comme pour electionService.
    property var electionHistoryEntries: []

    function refreshElectionHistory() {
        if (typeof application !== "undefined" && application)
            root.electionHistoryEntries = application.electionHistory(100)
    }

    onCurrentTabChanged: {
        if (currentTab === 4)
            refreshElectionHistory()
    }

    Timer {
        interval: 5000
        running: root.currentTab === 4
        repeat: true
        onTriggered: root.refreshElectionHistory()
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.background
    }

    // Vérification des permissions admin (issue #67)
    Component.onCompleted: {
        if (!userManager.currentUserIsAdmin) {
            accessDeniedDialog.open()
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Barre superieure
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 64
            color: Theme.surface

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.spacingMedium
                anchors.rightMargin: Theme.spacingMedium
                spacing: Theme.spacingMedium

                Button {
                    text: "← Retour"
                    onClicked: root.backRequested()
                }

                ButtonGroup {
                    id: tabGroup
                    buttons: tabButtons.children
                }

                Row {
                    id: tabButtons
                    spacing: Theme.spacingSmall

                    Button {
                        text: "Journal d'audit"
                        checkable: true
                        checked: root.currentTab === 0
                        onClicked: root.currentTab = 0
                    }

                    Button {
                        text: "Machines autorisées"
                        checkable: true
                        checked: root.currentTab === 1
                        onClicked: root.currentTab = 1
                    }

                    Button {
                        text: "Utilisateurs"
                        checkable: true
                        checked: root.currentTab === 2
                        onClicked: root.currentTab = 2
                    }

                    Button {
                        text: "Paramètres"
                        checkable: true
                        checked: root.currentTab === 3
                        onClicked: root.currentTab = 3
                    }

                    Button {
                        text: "Bascule serveur"
                        checkable: true
                        checked: root.currentTab === 4
                        onClicked: root.currentTab = 4
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                Button {
                    text: "Exporter CSV"
                    visible: root.currentTab === 0
                    onClicked: exportDialog.open()
                }

                Button {
                    text: "Ajouter machine"
                    visible: root.currentTab === 1
                    onClicked: addMachineDialog.open()
                }

                Button {
                    text: "Ajouter utilisateur"
                    visible: root.currentTab === 2
                    onClicked: addUserDialog.open()
                }

                Button {
                    text: "Rafraîchir"
                    visible: root.currentTab === 4
                    onClicked: root.refreshElectionHistory()
                }
            }
        }

        // Contenu de l'onglet Journal d'audit
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.currentTab === 0

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                // Filtres
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 80
                    color: Theme.surfaceAlt

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.spacingMedium
                        spacing: Theme.spacingMedium

                        Label {
                            text: "Type:"
                            color: Theme.text
                        }

                        ComboBox {
                            id: eventTypeFilter
                            Layout.preferredWidth: 150
                            model: ["Tous", "connection", "message", "transfer", "call", "access_denied"]
                            onCurrentTextChanged: {
                                if (currentIndex === 0)
                                    auditLogModel.clearFilters()
                                else
                                    auditLogModel.setEventTypeFilter(currentText)
                            }
                        }

                        Label {
                            text: "Du:"
                            color: Theme.text
                        }

                        TextField {
                            id: dateFrom
                            Layout.preferredWidth: 120
                            placeholderText: "YYYY-MM-DD"
                        }

                        Label {
                            text: "Au:"
                            color: Theme.text
                        }

                        TextField {
                            id: dateTo
                            Layout.preferredWidth: 120
                            placeholderText: "YYYY-MM-DD"
                        }

                        Button {
                            text: "Filtrer"
                            onClicked: auditLogModel.setDateRange(dateFrom.text, dateTo.text)
                        }

                        Button {
                            text: "Réinitialiser"
                            onClicked: {
                                eventTypeFilter.currentIndex = 0
                                dateFrom.text = ""
                                dateTo.text = ""
                                auditLogModel.clearFilters()
                            }
                        }

                        Item {
                            Layout.fillWidth: true
                        }
                    }
                }

                // Liste des entrées d'audit
                ScrollView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    ListView {
                        id: auditListView
                        model: auditLogModel
                        delegate: Rectangle {
                            width: auditListView.width
                            height: 80
                            color: index % 2 === 0 ? Theme.background : Theme.surfaceAlt

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: Theme.spacingMedium
                                spacing: Theme.spacingMedium

                                ColumnLayout {
                                    Layout.preferredWidth: 150
                                    spacing: 4

                                    Label {
                                        text: model.timestamp
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.textSecondary
                                    }

                                    Label {
                                        text: model.eventType
                                        font.pixelSize: Theme.fontSizeSmall
                                        font.bold: true
                                        color: Theme.primary
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 4

                                    Label {
                                        text: model.description
                                        font.pixelSize: Theme.fontSizeBody
                                        color: Theme.text
                                        wrapMode: Text.WordWrap
                                        Layout.fillWidth: true
                                    }

                                    Label {
                                        text: "Acteur: " + (model.actorLabel || "N/A")
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.textSecondary
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // Contenu de l'onglet Machines autorisées (issue #68)
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.currentTab === 1

            ScrollView {
                anchors.fill: parent

                ListView {
                    id: machinesListView
                    model: authorizedMachineModel
                    delegate: Rectangle {
                        width: machinesListView.width
                        height: 60
                        color: index % 2 === 0 ? Theme.background : Theme.surfaceAlt

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: Theme.spacingMedium
                            spacing: Theme.spacingMedium

                            ColumnLayout {
                                Layout.preferredWidth: 150
                                spacing: 4

                                Label {
                                    text: model.ipAddress
                                    font.pixelSize: Theme.fontSizeBody
                                    font.bold: true
                                    color: Theme.text
                                }

                                Label {
                                    text: model.hostname || "N/A"
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.textSecondary
                                }
                            }

                            ColumnLayout {
                                Layout.preferredWidth: 100
                                spacing: 4

                                Label {
                                    text: model.authorized ? "Autorisée" : "Révoquée"
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: model.authorized ? Theme.success : Theme.error
                                }

                                Label {
                                    text: "Ajoutée: " + model.addedAt
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.textSecondary
                                }
                            }

                            Item {
                                Layout.fillWidth: true
                            }

                            Button {
                                text: model.authorized ? "Révoquer" : "Autoriser"
                                onClicked: {
                                    if (model.authorized) {
                                        authorizedMachineModel.revokeMachine(model.id, "Révoqué par admin")
                                    } else {
                                        authorizedMachineModel.authorizeMachine(model.id, "Autorisé par admin")
                                    }
                                }
                            }

                            Button {
                                text: "Supprimer"
                                onClicked: {
                                    authorizedMachineModel.removeMachine(model.id)
                                }
                            }
                        }
                    }
                }
            }
        }

        // Contenu de l'onglet Gestion des utilisateurs (issue #69)
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.currentTab === 2

            ScrollView {
                anchors.fill: parent

                ListView {
                    id: usersListView
                    model: userManagementModel
                    delegate: Rectangle {
                        width: usersListView.width
                        height: 70
                        color: index % 2 === 0 ? Theme.background : Theme.surfaceAlt

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: Theme.spacingMedium
                            spacing: Theme.spacingMedium

                            ColumnLayout {
                                Layout.preferredWidth: 150
                                spacing: 4

                                Label {
                                    text: model.name
                                    font.pixelSize: Theme.fontSizeBody
                                    font.bold: true
                                    color: Theme.text
                                }

                                Label {
                                    text: model.ipAddress || "N/A"
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.textSecondary
                                }
                            }

                            ColumnLayout {
                                Layout.preferredWidth: 100
                                spacing: 4

                                Label {
                                    text: model.role === "admin" ? "Admin" : "Utilisateur"
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: model.isAdmin ? Theme.primary : Theme.text
                                }

                                Label {
                                    text: "Statut: " + model.status
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.textSecondary
                                }
                            }

                            Item {
                                Layout.fillWidth: true
                            }

                            Button {
                                text: model.isAdmin ? "Rétrograder" : "Promouvoir"
                                onClicked: {
                                    userManagementModel.changeRole(model.id, !model.isAdmin)
                                }
                            }

                            Button {
                                text: "Supprimer"
                                onClicked: {
                                    userManagementModel.deleteUser(model.id)
                                }
                            }
                        }
                    }
                }
            }
        }

        // Contenu de l'onglet Paramètres globaux (issue #69)
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.currentTab === 3

            ScrollView {
                anchors.fill: parent

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingLarge
                    spacing: Theme.spacingLarge

                    Label {
                        text: "Paramètres globaux"
                        font.pixelSize: Theme.fontSizeHeading
                        font.bold: true
                        color: Theme.text
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 1
                        color: Theme.border
                    }

                    // Organisation
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingSmall

                        Label {
                            text: "Nom de l'organisation:"
                            color: Theme.text
                        }

                        TextField {
                            Layout.fillWidth: true
                            text: settingsModel.organizationName
                            onTextChanged: settingsModel.organizationName = text
                        }
                    }

                    // Téléchargements
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingSmall

                        Label {
                            text: "Répertoire de téléchargement par défaut:"
                            color: Theme.text
                        }

                        RowLayout {
                            spacing: Theme.spacingSmall

                            TextField {
                                Layout.fillWidth: true
                                text: settingsModel.defaultDownloadPath
                                onTextChanged: settingsModel.defaultDownloadPath = text
                            }

                            Button {
                                text: "Parcourir..."
                                onClicked: folderDialog.open()
                            }
                        }
                    }

                    // Notifications
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingSmall

                        Label {
                            text: "Notifications:"
                            color: Theme.text
                        }

                        CheckBox {
                            text: "Activer les notifications"
                            checked: settingsModel.enableNotifications
                            onCheckedChanged: settingsModel.enableNotifications = checked
                        }

                        CheckBox {
                            text: "Activer les sons"
                            checked: settingsModel.enableSounds
                            onCheckedChanged: settingsModel.enableSounds = checked
                        }
                    }

                    // Ports réseau
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingSmall

                        Label {
                            text: "Ports réseau:"
                            color: Theme.text
                        }

                        RowLayout {
                            spacing: Theme.spacingMedium

                            Label {
                                text: "Port messagerie:"
                                color: Theme.text
                            }

                            SpinBox {
                                from: 1024
                                to: 65535
                                value: settingsModel.messagingPort
                                onValueChanged: settingsModel.messagingPort = value
                            }
                        }

                        RowLayout {
                            spacing: Theme.spacingMedium

                            Label {
                                text: "Port découverte:"
                                color: Theme.text
                            }

                            SpinBox {
                                from: 1024
                                to: 65535
                                value: settingsModel.discoveryPort
                                onValueChanged: settingsModel.discoveryPort = value
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 1
                        color: Theme.border
                    }

                    RowLayout {
                        spacing: Theme.spacingMedium

                        Item {
                            Layout.fillWidth: true
                        }

                        Button {
                            text: "Annuler"
                            onClicked: settingsModel.load()
                        }

                        Button {
                            text: "Enregistrer"
                            onClicked: settingsModel.save()
                        }
                    }

                    Item {
                        Layout.fillHeight: true
                    }
                }
            }
        }

        // Contenu de l'onglet "Bascule serveur" (HYBRID_SERVER_FAILOVER.md
        // section 9, etape 5) : historique des elections/reconciliations
        // (ServerElectionLog), utile pour diagnostiquer une instabilite
        // reseau.
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.currentTab === 4

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.spacingLarge
                spacing: Theme.spacingMedium

                Label {
                    text: "Historique des bascules"
                    font.pixelSize: Theme.fontSizeHeading
                    font.bold: true
                    color: Theme.text
                }

                Label {
                    text: "Chaque ligne correspond a un evenement du protocole d'election (perte de heartbeat, promotion en serveur de secours, reconciliation, reprise du serveur officiel)."
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeSmall
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: Theme.border
                }

                Label {
                    visible: root.electionHistoryEntries.length === 0
                    text: "Aucun evenement enregistre pour l'instant."
                    color: Theme.textSecondary
                }

                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    visible: root.electionHistoryEntries.length > 0
                    model: root.electionHistoryEntries

                    delegate: Rectangle {
                        width: ListView.view ? ListView.view.width : 0
                        height: entryRow.implicitHeight + Theme.spacingMedium
                        color: index % 2 === 0 ? Theme.surface : Theme.surfaceAlt
                        border.width: 1
                        border.color: Theme.border

                        RowLayout {
                            id: entryRow
                            anchors.fill: parent
                            anchors.margins: Theme.spacingSmall
                            spacing: Theme.spacingMedium

                            Rectangle {
                                width: 10
                                height: 10
                                radius: 5
                                Layout.alignment: Qt.AlignVCenter
                                color: {
                                    switch (modelData.event) {
                                    case "HEARTBEAT_LOST": return Theme.error
                                    case "TEMP_PROMOTED": return Theme.warning
                                    case "SERVER_RECONCILED": return Theme.primary
                                    case "SERVER_RESTORED": return Theme.success
                                    default: return Theme.textSecondary
                                    }
                                }
                            }

                            Label {
                                text: modelData.event
                                color: Theme.text
                                font.bold: true
                                Layout.preferredWidth: 180
                            }

                            Label {
                                text: "epoch " + modelData.epoch
                                color: Theme.textSecondary
                                Layout.preferredWidth: 80
                            }

                            Label {
                                text: modelData.machineUuid
                                color: Theme.textSecondary
                                elide: Text.ElideMiddle
                                Layout.fillWidth: true
                            }

                            Label {
                                text: modelData.createdAt
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontSizeSmall
                            }
                        }
                    }
                }
            }
        }
    }

    FileDialog {
        id: exportDialog
        title: "Exporter le journal d'audit"
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

    Dialog {
        id: addMachineDialog
        title: "Ajouter une machine autorisée"
        modal: true
        anchors.centerIn: parent

        ColumnLayout {
            spacing: Theme.spacingMedium

            Label {
                text: "Adresse IP:"
                color: Theme.text
            }

            TextField {
                id: newMachineIp
                Layout.preferredWidth: 200
                placeholderText: "192.168.1.x"
            }

            Label {
                text: "Nom d'hôte (optionnel):"
                color: Theme.text
            }

            TextField {
                id: newMachineHostname
                Layout.preferredWidth: 200
                placeholderText: "Nom de la machine"
            }

            RowLayout {
                spacing: Theme.spacingMedium

                Button {
                    text: "Annuler"
                    onClicked: addMachineDialog.close()
                }

                Button {
                    text: "Ajouter"
                    onClicked: {
                        authorizedMachineModel.addMachine(newMachineIp.text, newMachineHostname.text, "Ajouté par admin")
                        addMachineDialog.close()
                    }
                }
            }
        }
    }

    Dialog {
        id: addUserDialog
        title: "Ajouter un utilisateur"
        modal: true
        anchors.centerIn: parent

        ColumnLayout {
            spacing: Theme.spacingMedium

            Label {
                text: "Nom d'utilisateur:"
                color: Theme.text
            }

            TextField {
                id: newUserName
                Layout.preferredWidth: 200
                placeholderText: "Nom d'utilisateur"
            }

            Label {
                text: "Mot de passe:"
                color: Theme.text
            }

            TextField {
                id: newUserPassword
                Layout.preferredWidth: 200
                placeholderText: "Mot de passe"
                echoMode: TextInput.Password
            }

            Label {
                text: "Rôle:"
                color: Theme.text
            }

            ComboBox {
                id: newUserRole
                Layout.preferredWidth: 200
                model: ["Utilisateur", "Administrateur"]
            }

            RowLayout {
                spacing: Theme.spacingMedium

                Button {
                    text: "Annuler"
                    onClicked: addUserDialog.close()
                }

                Button {
                    text: "Ajouter"
                    onClicked: {
                        const isAdmin = newUserRole.currentIndex === 1
                        userManagementModel.createUser(newUserName.text, newUserPassword.text, isAdmin)
                        addUserDialog.close()
                    }
                }
            }
        }
    }

    Dialog {
        id: accessDeniedDialog
        title: "Accès refusé"
        modal: true
        anchors.centerIn: parent

        Label {
            text: "Vous n'avez pas les droits administrateur pour accéder à cette page."
            color: Theme.text
        }

        Button {
            text: "OK"
            onClicked: {
                accessDeniedDialog.close()
                root.backRequested()
            }
        }
    }

    FolderDialog {
        id: folderDialog
        title: "Sélectionner le répertoire de téléchargement"
        currentFolder: settingsModel.defaultDownloadPath
        onAccepted: {
            settingsModel.defaultDownloadPath = selectedFolder
        }
    }
}

