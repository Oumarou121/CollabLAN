import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import Themes
import "../Components"

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

    property int currentTab: 0  // 0 = Audit log, 1 = Machines autorisées, 2 = Utilisateurs, 3 = Bascule serveur
    // Note : l'onglet "Paramètres" (Préférences / Ports
    // réseau) a été retiré d'ici et déplacé dans SettingsView.qml,
    // désormais accessible à tous les utilisateurs depuis le menu profil
    // de HomeView (Ports réseau y reste réservé aux
    // administrateurs).

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
                spacing: Theme.spacingMedium

                Rectangle {
                    Layout.preferredWidth: 36
                    Layout.preferredHeight: 36
                    radius: Theme.radiusMedium
                    color: backArea.containsMouse ? Theme.surfaceHover : "transparent"

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

                Label {
                    text: qsTr("Administration")
                    font.pixelSize: Theme.fontSizeSubheading
                    font.bold: true
                    font.family: Theme.fontFamily
                    color: Theme.text
                    Layout.rightMargin: Theme.spacingMedium
                }

                Rectangle {
                    Layout.preferredHeight: 40
                    Layout.fillWidth: false
                    implicitWidth: tabRow.implicitWidth + Theme.spacingXs * 2
                    radius: Theme.radiusPill
                    color: Theme.surfaceAlt

                    Row {
                        id: tabRow
                        anchors.centerIn: parent
                        spacing: 2

                        TabPill { label: qsTr("Journal d'audit"); active: root.currentTab === 0; onClicked: root.currentTab = 0 }
                        TabPill { label: qsTr("Machines autorisées"); active: root.currentTab === 1; onClicked: root.currentTab = 1 }
                        TabPill { label: qsTr("Utilisateurs"); active: root.currentTab === 2; onClicked: root.currentTab = 2 }
                        TabPill { label: qsTr("Bascule serveur"); active: root.currentTab === 3; onClicked: root.currentTab = 3 }
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                AppButton {
                    variant: "secondary"
                    iconGlyph: "\u21E9"
                    text: qsTr("Exporter CSV")
                    visible: root.currentTab === 0
                    onClicked: exportDialog.open()
                }

                AppButton {
                    variant: "primary"
                    iconGlyph: "+"
                    text: qsTr("Ajouter machine")
                    visible: root.currentTab === 1
                    onClicked: addMachineDialog.open()
                }

                AppButton {
                    variant: "primary"
                    iconGlyph: "+"
                    text: qsTr("Ajouter utilisateur")
                    visible: root.currentTab === 2
                    onClicked: addUserDialog.open()
                }

                AppButton {
                    variant: "secondary"
                    iconGlyph: "\u21BB"
                    text: qsTr("Rafraîchir")
                    visible: root.currentTab === 3
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
                    Layout.preferredHeight: 72
                    color: Theme.surfaceAlt

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.spacingMedium
                        spacing: Theme.spacingSmall

                        Label {
                            text: qsTr("Type :")
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeSmall
                            font.family: Theme.fontFamily
                        }

                        ComboBox {
                            id: eventTypeFilter
                            Layout.preferredWidth: 160
                            Layout.preferredHeight: 36
                            model: ["Tous", "connection", "message", "transfer", "call", "access_denied"]
                            background: Rectangle {
                                radius: Theme.radiusMedium
                                color: Theme.surface
                                border.width: 1
                                border.color: Theme.border
                            }
                            onCurrentTextChanged: {
                                if (currentIndex === 0)
                                    auditLogModel.clearFilters()
                                else
                                    auditLogModel.setEventTypeFilter(currentText)
                            }
                        }

                        Label {
                            text: qsTr("Du :")
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeSmall
                            font.family: Theme.fontFamily
                        }

                        TextField {
                            id: dateFrom
                            Layout.preferredWidth: 130
                            Layout.preferredHeight: 36
                            placeholderText: "YYYY-MM-DD"
                            color: Theme.text
                            font.pixelSize: Theme.fontSizeSmall
                            leftPadding: Theme.spacingSmall
                            background: Rectangle {
                                radius: Theme.radiusMedium
                                color: Theme.surface
                                border.width: dateFrom.activeFocus ? 2 : 1
                                border.color: dateFrom.activeFocus ? Theme.primary : Theme.border
                            }
                        }

                        Label {
                            text: qsTr("Au :")
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeSmall
                            font.family: Theme.fontFamily
                        }

                        TextField {
                            id: dateTo
                            Layout.preferredWidth: 130
                            Layout.preferredHeight: 36
                            placeholderText: "YYYY-MM-DD"
                            color: Theme.text
                            font.pixelSize: Theme.fontSizeSmall
                            leftPadding: Theme.spacingSmall
                            background: Rectangle {
                                radius: Theme.radiusMedium
                                color: Theme.surface
                                border.width: dateTo.activeFocus ? 2 : 1
                                border.color: dateTo.activeFocus ? Theme.primary : Theme.border
                            }
                        }

                        AppButton {
                            variant: "primary"
                            text: qsTr("Filtrer")
                            onClicked: auditLogModel.setDateRange(dateFrom.text, dateTo.text)
                        }

                        AppButton {
                            variant: "ghost"
                            text: qsTr("Réinitialiser")
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
                        spacing: Theme.spacingXs
                        delegate: Rectangle {
                            width: auditListView.width
                            height: 78
                            radius: Theme.radiusMedium
                            color: Theme.surface
                            border.width: 1
                            border.color: Theme.border

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

                                    Rectangle {
                                        implicitWidth: eventTypeLabel.implicitWidth + Theme.spacingSmall
                                        implicitHeight: 20
                                        radius: Theme.radiusSmall
                                        color: Theme.primaryMuted

                                        Label {
                                            id: eventTypeLabel
                                            anchors.centerIn: parent
                                            text: model.eventType
                                            font.pixelSize: Theme.fontSizeCaption
                                            font.bold: true
                                            color: Theme.primary
                                        }
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
                                        text: qsTr("Acteur : %1").arg(model.actorLabel || "N/A")
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
                contentWidth: availableWidth

                ListView {
                    id: machinesListView
                    model: authorizedMachineModel
                    spacing: Theme.spacingXs
                    delegate: Rectangle {
                        width: machinesListView.width
                        height: 64
                        radius: Theme.radiusMedium
                        color: Theme.surface
                        border.width: 1
                        border.color: Theme.border

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: Theme.spacingMedium
                            spacing: Theme.spacingMedium

                            ColumnLayout {
                                Layout.preferredWidth: 160
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
                                Layout.preferredWidth: 130
                                spacing: 4

                                Rectangle {
                                    implicitWidth: statusLabel.implicitWidth + Theme.spacingSmall
                                    implicitHeight: 20
                                    radius: Theme.radiusSmall
                                    color: model.authorized ? Theme.successMuted : Theme.errorMuted

                                    Label {
                                        id: statusLabel
                                        anchors.centerIn: parent
                                        text: model.authorized ? qsTr("Autorisée") : qsTr("Révoquée")
                                        font.pixelSize: Theme.fontSizeCaption
                                        font.bold: true
                                        color: model.authorized ? Theme.success : Theme.error
                                    }
                                }

                                Label {
                                    text: qsTr("Ajoutée : %1").arg(model.addedAt)
                                    font.pixelSize: Theme.fontSizeCaption
                                    color: Theme.textTertiary
                                }
                            }

                            Item {
                                Layout.fillWidth: true
                            }

                            AppButton {
                                variant: "secondary"
                                text: model.authorized ? qsTr("Révoquer") : qsTr("Autoriser")
                                onClicked: {
                                    if (model.authorized) {
                                        authorizedMachineModel.revokeMachine(model.id, "Révoqué par admin")
                                    } else {
                                        authorizedMachineModel.authorizeMachine(model.id, "Autorisé par admin")
                                    }
                                }
                            }

                            AppButton {
                                variant: "danger"
                                text: qsTr("Supprimer")
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
                contentWidth: availableWidth

                ListView {
                    id: usersListView
                    model: userManagementModel
                    spacing: Theme.spacingXs
                    delegate: Rectangle {
                        width: usersListView.width
                        height: 68
                        radius: Theme.radiusMedium
                        color: Theme.surface
                        border.width: 1
                        border.color: Theme.border

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: Theme.spacingMedium
                            spacing: Theme.spacingMedium

                            Avatar {
                                name: model.name
                                size: 36
                            }

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
                                Layout.preferredWidth: 110
                                spacing: 4

                                Rectangle {
                                    implicitWidth: roleLabel.implicitWidth + Theme.spacingSmall
                                    implicitHeight: 20
                                    radius: Theme.radiusSmall
                                    color: model.isAdmin ? Theme.primaryMuted : Theme.surfaceAlt

                                    Label {
                                        id: roleLabel
                                        anchors.centerIn: parent
                                        text: model.role === "admin" ? qsTr("Admin") : qsTr("Utilisateur")
                                        font.pixelSize: Theme.fontSizeCaption
                                        font.bold: true
                                        color: model.isAdmin ? Theme.primary : Theme.textSecondary
                                    }
                                }

                                Label {
                                    text: qsTr("Statut : %1").arg(model.status)
                                    font.pixelSize: Theme.fontSizeCaption
                                    color: Theme.textTertiary
                                }
                            }

                            Item {
                                Layout.fillWidth: true
                            }

                            AppButton {
                                variant: "secondary"
                                text: model.isAdmin ? qsTr("Rétrograder") : qsTr("Promouvoir")
                                onClicked: {
                                    userManagementModel.changeRole(model.id, !model.isAdmin)
                                }
                            }

                            AppButton {
                                variant: "danger"
                                text: qsTr("Supprimer")
                                onClicked: {
                                    userManagementModel.deleteUser(model.id)
                                }
                            }
                        }
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
            visible: root.currentTab === 3

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
                    spacing: Theme.spacingXs
                    visible: root.electionHistoryEntries.length > 0
                    model: root.electionHistoryEntries

                    delegate: Rectangle {
                        width: ListView.view ? ListView.view.width : 0
                        height: entryRow.implicitHeight + Theme.spacingMedium
                        radius: Theme.radiusMedium
                        color: Theme.surface
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
        title: qsTr("Ajouter une machine autorisée")
        modal: true
        anchors.centerIn: parent
        padding: Theme.spacingLarge

        background: Rectangle {
            radius: Theme.radiusLarge
            color: Theme.surface
            border.width: 1
            border.color: Theme.border
        }

        ColumnLayout {
            spacing: Theme.spacingSmall

            Label {
                text: qsTr("Adresse IP")
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.textSecondary
            }

            TextField {
                id: newMachineIp
                Layout.preferredWidth: 260
                Layout.preferredHeight: 40
                placeholderText: "192.168.1.x"
                color: Theme.text
                leftPadding: Theme.spacingMedium
                background: Rectangle {
                    radius: Theme.radiusMedium
                    color: Theme.background
                    border.width: 1
                    border.color: Theme.border
                }
            }

            Label {
                text: qsTr("Nom d'hôte (optionnel)")
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.textSecondary
                Layout.topMargin: Theme.spacingSmall
            }

            TextField {
                id: newMachineHostname
                Layout.preferredWidth: 260
                Layout.preferredHeight: 40
                placeholderText: qsTr("Nom de la machine")
                color: Theme.text
                leftPadding: Theme.spacingMedium
                background: Rectangle {
                    radius: Theme.radiusMedium
                    color: Theme.background
                    border.width: 1
                    border.color: Theme.border
                }
            }

            RowLayout {
                Layout.topMargin: Theme.spacingMedium
                Layout.alignment: Qt.AlignRight
                spacing: Theme.spacingSmall

                AppButton {
                    variant: "ghost"
                    text: qsTr("Annuler")
                    onClicked: addMachineDialog.close()
                }

                AppButton {
                    variant: "primary"
                    text: qsTr("Ajouter")
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
        title: qsTr("Ajouter un utilisateur")
        modal: true
        anchors.centerIn: parent
        padding: Theme.spacingLarge

        background: Rectangle {
            radius: Theme.radiusLarge
            color: Theme.surface
            border.width: 1
            border.color: Theme.border
        }

        ColumnLayout {
            spacing: Theme.spacingSmall

            Label {
                text: qsTr("Nom d'utilisateur")
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.textSecondary
            }

            TextField {
                id: newUserName
                Layout.preferredWidth: 260
                Layout.preferredHeight: 40
                placeholderText: qsTr("Nom d'utilisateur")
                color: Theme.text
                leftPadding: Theme.spacingMedium
                background: Rectangle {
                    radius: Theme.radiusMedium
                    color: Theme.background
                    border.width: 1
                    border.color: Theme.border
                }
            }

            Label {
                text: qsTr("Mot de passe")
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.textSecondary
                Layout.topMargin: Theme.spacingSmall
            }

            TextField {
                id: newUserPassword
                Layout.preferredWidth: 260
                Layout.preferredHeight: 40
                placeholderText: qsTr("Mot de passe")
                echoMode: TextInput.Password
                color: Theme.text
                leftPadding: Theme.spacingMedium
                background: Rectangle {
                    radius: Theme.radiusMedium
                    color: Theme.background
                    border.width: 1
                    border.color: Theme.border
                }
            }

            Label {
                text: qsTr("Rôle")
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.textSecondary
                Layout.topMargin: Theme.spacingSmall
            }

            ComboBox {
                id: newUserRole
                Layout.preferredWidth: 260
                Layout.preferredHeight: 40
                model: [qsTr("Utilisateur"), qsTr("Administrateur")]
                background: Rectangle {
                    radius: Theme.radiusMedium
                    color: Theme.background
                    border.width: 1
                    border.color: Theme.border
                }
            }

            RowLayout {
                Layout.topMargin: Theme.spacingMedium
                Layout.alignment: Qt.AlignRight
                spacing: Theme.spacingSmall

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
}

