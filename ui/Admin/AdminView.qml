import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import Themes
import "../Components"

/*
 * AdminView - ecran "Admin"
 *
 * CORRECTIF (refonte) : les onglets "Journal d'audit" et "Machines
 * autorisees" ont ete retires -- ils n'etaient consommes que par cette
 * UI (AuditLogModel / AuthorizedMachineModel), jamais utilises ailleurs
 * dans l'application, et n'apportaient pas de valeur au quotidien. Les
 * mecanismes de securite sous-jacents (journalisation des tentatives
 * refusees via AuditManager, verification des machines autorisees via
 * PermissionManager) restent actifs cote reseau : seule leur vitrine
 * d'administration disparait.
 *
 * Les trois onglets restants (Utilisateurs, Parametres, Bascule serveur)
 * ont ete redesignes pour une hierarchie visuelle plus claire : en-tetes
 * de section avec icone, cartes plus respirees, etats vides explicites,
 * et une recherche sur la liste des utilisateurs.
 *
 * Accès réservé aux administrateurs.
 */
Item {
    id: root

    signal backRequested()

    property int currentTab: 0  // 0 = Utilisateurs, 1 = Parametres, 2 = Bascule serveur
    property string userSearchQuery: ""

    // Historique des bascules (ServerElectionLog), pour l'onglet "Bascule
    // serveur". Pas de signal de changement cote C++ (simple Q_INVOKABLE) :
    // on rafraichit explicitement (bouton, ouverture de l'onglet, et un
    // Timer discret pendant que l'onglet est actif) plutot que de tout
    // faire reposer sur le binding reactif comme pour electionService.
    property var electionHistoryEntries: []

    function refreshElectionHistory() {
        if (typeof application !== "undefined" && application)
            root.electionHistoryEntries = application.electionHistory(100)
    }

    onCurrentTabChanged: {
        if (currentTab === 2)
            refreshElectionHistory()
    }

    Timer {
        interval: 5000
        running: root.currentTab === 2
        repeat: true
        onTriggered: root.refreshElectionHistory()
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.background
    }

    // Vérification des permissions admin
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

                        TabPill { label: qsTr("Utilisateurs"); active: root.currentTab === 0; onClicked: root.currentTab = 0 }
                        TabPill { label: qsTr("Paramètres"); active: root.currentTab === 1; onClicked: root.currentTab = 1 }
                        TabPill { label: qsTr("Bascule serveur"); active: root.currentTab === 2; onClicked: root.currentTab = 2 }
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                AppButton {
                    variant: "primary"
                    iconGlyph: "+"
                    text: qsTr("Ajouter utilisateur")
                    visible: root.currentTab === 0
                    onClicked: addUserDialog.open()
                }

                AppButton {
                    variant: "secondary"
                    iconGlyph: "\u21BB"
                    text: qsTr("Rafraîchir")
                    visible: root.currentTab === 2
                    onClicked: root.refreshElectionHistory()
                }
            }
        }

        // ============================================================
        // Onglet Utilisateurs
        // ============================================================
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.currentTab === 0

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                // Bandeau de section : titre + compteur + recherche, dans
                // le meme esprit que les autres listes de l'application
                // (barre de recherche persistante plutot qu'un filtre a
                // ouvrir/fermer).
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 72
                    color: Theme.surfaceAlt

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.spacingMedium
                        spacing: Theme.spacingMedium

                        ColumnLayout {
                            spacing: 0
                            Label {
                                text: qsTr("Comptes de l'organisation")
                                font.pixelSize: Theme.fontSizeSubheading
                                font.bold: true
                                font.family: Theme.fontFamily
                                color: Theme.text
                            }
                            Label {
                                text: qsTr("%1 utilisateur(s)").arg(usersListView.count)
                                font.pixelSize: Theme.fontSizeSmall
                                font.family: Theme.fontFamily
                                color: Theme.textSecondary
                            }
                        }

                        Item { Layout.fillWidth: true }

                        TextField {
                            id: userSearchField
                            Layout.preferredWidth: 260
                            Layout.preferredHeight: 40
                            placeholderText: qsTr("Rechercher un utilisateur...")
                            color: Theme.text
                            font.pixelSize: Theme.fontSizeBody
                            font.family: Theme.fontFamily
                            leftPadding: Theme.spacingLarge
                            selectByMouse: true

                            background: Rectangle {
                                color: Theme.surface
                                radius: Theme.radiusPill
                                border.width: userSearchField.activeFocus ? 2 : 1
                                border.color: userSearchField.activeFocus ? Theme.primary : Theme.border
                            }

                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: Theme.spacingMedium
                                anchors.verticalCenter: parent.verticalCenter
                                text: "\u2315"
                                color: Theme.textTertiary
                                font.pixelSize: 14
                            }

                            onTextChanged: root.userSearchQuery = text.toLowerCase()
                        }
                    }
                }

                ScrollView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentWidth: availableWidth

                    ListView {
                        id: usersListView
                        anchors.margins: Theme.spacingMedium
                        model: userManagementModel
                        spacing: Theme.spacingSmall
                        topMargin: Theme.spacingMedium
                        leftMargin: Theme.spacingMedium
                        rightMargin: Theme.spacingMedium
                        bottomMargin: Theme.spacingMedium

                        delegate: Rectangle {
                            id: userDelegate
                            readonly property bool matchesSearch: root.userSearchQuery.length === 0
                                    || model.name.toLowerCase().indexOf(root.userSearchQuery) !== -1
                            width: usersListView.width - usersListView.leftMargin - usersListView.rightMargin
                            height: matchesSearch ? 72 : 0
                            visible: matchesSearch
                            radius: Theme.radiusLarge
                            color: userMouse.containsMouse ? Theme.surfaceHover : Theme.surface
                            border.width: 1
                            border.color: Theme.border

                            Behavior on color { ColorAnimation { duration: 100 } }

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: Theme.spacingMedium
                                spacing: Theme.spacingMedium

                                Avatar {
                                    name: model.name
                                    size: 40
                                }

                                ColumnLayout {
                                    Layout.preferredWidth: 170
                                    spacing: 2

                                    Label {
                                        text: model.name
                                        font.pixelSize: Theme.fontSizeBody
                                        font.bold: true
                                        font.family: Theme.fontFamily
                                        color: Theme.text
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }

                                    Label {
                                        text: model.ipAddress || qsTr("Adresse inconnue")
                                        font.pixelSize: Theme.fontSizeSmall
                                        font.family: Theme.fontFamily
                                        color: Theme.textSecondary
                                    }
                                }

                                // Badge de role
                                Rectangle {
                                    Layout.preferredWidth: roleLabel.implicitWidth + Theme.spacingMedium
                                    Layout.preferredHeight: 24
                                    radius: Theme.radiusPill
                                    color: model.isAdmin ? Theme.primaryMuted : Theme.surfaceAlt

                                    Label {
                                        id: roleLabel
                                        anchors.centerIn: parent
                                        text: model.role === "admin" ? qsTr("Administrateur") : qsTr("Utilisateur")
                                        font.pixelSize: Theme.fontSizeCaption
                                        font.bold: true
                                        font.family: Theme.fontFamily
                                        color: model.isAdmin ? Theme.primary : Theme.textSecondary
                                    }
                                }

                                // Badge de statut (en ligne / hors ligne / etc., selon model.status)
                                Rectangle {
                                    Layout.preferredWidth: statusLabel.implicitWidth + Theme.spacingMedium
                                    Layout.preferredHeight: 24
                                    radius: Theme.radiusPill
                                    color: Theme.surfaceAlt

                                    RowLayout {
                                        anchors.centerIn: parent
                                        spacing: 4

                                        Rectangle {
                                            width: 6
                                            height: 6
                                            radius: 3
                                            Layout.alignment: Qt.AlignVCenter
                                            color: model.status === "online" ? Theme.success : Theme.textTertiary
                                        }

                                        Label {
                                            id: statusLabel
                                            text: model.status
                                            font.pixelSize: Theme.fontSizeCaption
                                            font.family: Theme.fontFamily
                                            color: Theme.textSecondary
                                        }
                                    }
                                }

                                Item { Layout.fillWidth: true }

                                AppButton {
                                    variant: "secondary"
                                    text: model.isAdmin ? qsTr("Rétrograder") : qsTr("Promouvoir")
                                    onClicked: userManagementModel.changeRole(model.id, !model.isAdmin)
                                }

                                AppButton {
                                    variant: "danger"
                                    text: qsTr("Supprimer")
                                    onClicked: userManagementModel.deleteUser(model.id)
                                }
                            }

                            MouseArea {
                                id: userMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.NoButton
                                z: -1
                            }
                        }

                        // Etat vide : aucun utilisateur du tout, ou aucun
                        // ne correspond a la recherche en cours.
                        Label {
                            anchors.centerIn: parent
                            readonly property int matchCount: {
                                const _dep = usersListView.count // force la reevaluation quand le modele change
                                if (!userManagementModel) return 0
                                const allNames = userManagementModel.names()
                                if (root.userSearchQuery.length === 0) return allNames.length
                                let n = 0
                                for (let i = 0; i < allNames.length; ++i) {
                                    if (allNames[i].toLowerCase().indexOf(root.userSearchQuery) !== -1) n++
                                }
                                return n
                            }
                            visible: matchCount === 0
                            text: root.userSearchQuery.length > 0
                                  ? qsTr("Aucun utilisateur ne correspond à votre recherche.")
                                  : qsTr("Aucun utilisateur pour le moment.")
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeBody
                            font.family: Theme.fontFamily
                        }
                    }
                }
            }
        }

        // ============================================================
        // Onglet Paramètres globaux
        // ============================================================
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.currentTab === 1

            ScrollView {
                anchors.fill: parent
                contentWidth: availableWidth

                ColumnLayout {
                    width: parent.width
                    spacing: Theme.spacingLarge

                    Item { Layout.preferredHeight: Theme.spacingLarge }

                    ColumnLayout {
                        Layout.leftMargin: Theme.spacingLarge
                        Layout.rightMargin: Theme.spacingLarge
                        spacing: 2

                        Label {
                            text: qsTr("Paramètres globaux")
                            font.pixelSize: Theme.fontSizeHeading
                            font.bold: true
                            font.family: Theme.fontFamily
                            color: Theme.text
                        }

                        Label {
                            text: qsTr("Ces réglages s'appliquent à l'ensemble de l'organisation.")
                            font.pixelSize: Theme.fontSizeSmall
                            font.family: Theme.fontFamily
                            color: Theme.textSecondary
                        }
                    }

                    // Organisation
                    SettingsSectionCard {
                        Layout.fillWidth: true
                        Layout.leftMargin: Theme.spacingLarge
                        Layout.rightMargin: Theme.spacingLarge
                        icon: "\u2699"
                        title: qsTr("Organisation")

                        Label {
                            text: qsTr("Nom de l'organisation")
                            font.pixelSize: Theme.fontSizeSmall
                            font.family: Theme.fontFamily
                            color: Theme.textSecondary
                        }

                        TextField {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 40
                            text: settingsModel.organizationName
                            color: Theme.text
                            font.pixelSize: Theme.fontSizeBody
                            leftPadding: Theme.spacingMedium
                            onTextChanged: settingsModel.organizationName = text

                            background: Rectangle {
                                radius: Theme.radiusMedium
                                color: Theme.background
                                border.width: 1
                                border.color: Theme.border
                            }
                        }
                    }

                    // Telechargements + Notifications
                    SettingsSectionCard {
                        Layout.fillWidth: true
                        Layout.leftMargin: Theme.spacingLarge
                        Layout.rightMargin: Theme.spacingLarge
                        icon: "\u2601"
                        title: qsTr("Préférences")

                        Label {
                            text: qsTr("Répertoire de téléchargement par défaut")
                            font.pixelSize: Theme.fontSizeSmall
                            font.family: Theme.fontFamily
                            color: Theme.textSecondary
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacingSmall

                            TextField {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 40
                                text: settingsModel.defaultDownloadPath
                                color: Theme.text
                                font.pixelSize: Theme.fontSizeBody
                                leftPadding: Theme.spacingMedium
                                onTextChanged: settingsModel.defaultDownloadPath = text

                                background: Rectangle {
                                    radius: Theme.radiusMedium
                                    color: Theme.background
                                    border.width: 1
                                    border.color: Theme.border
                                }
                            }

                            AppButton {
                                variant: "secondary"
                                text: qsTr("Parcourir...")
                                onClicked: folderDialog.open()
                            }
                        }

                        Label {
                            text: qsTr("Notifications")
                            font.pixelSize: Theme.fontSizeSmall
                            font.family: Theme.fontFamily
                            color: Theme.textSecondary
                            Layout.topMargin: Theme.spacingSmall
                        }

                        RowLayout {
                            spacing: Theme.spacingLarge

                            CheckBox {
                                checked: settingsModel.enableNotifications
                                onCheckedChanged: settingsModel.enableNotifications = checked
                                contentItem: Label {
                                    text: qsTr("Activer les notifications")
                                    color: Theme.text
                                    font.pixelSize: Theme.fontSizeBody
                                    font.family: Theme.fontFamily
                                    leftPadding: 28
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }

                            CheckBox {
                                checked: settingsModel.enableSounds
                                onCheckedChanged: settingsModel.enableSounds = checked
                                contentItem: Label {
                                    text: qsTr("Activer les sons")
                                    color: Theme.text
                                    font.pixelSize: Theme.fontSizeBody
                                    font.family: Theme.fontFamily
                                    leftPadding: 28
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }
                        }
                    }

                    // Ports reseau
                    SettingsSectionCard {
                        Layout.fillWidth: true
                        Layout.leftMargin: Theme.spacingLarge
                        Layout.rightMargin: Theme.spacingLarge
                        icon: "\u21C4"
                        title: qsTr("Ports réseau")

                        RowLayout {
                            spacing: Theme.spacingMedium

                            Label {
                                text: qsTr("Port messagerie")
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontSizeSmall
                                font.family: Theme.fontFamily
                                Layout.preferredWidth: 140
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
                                text: qsTr("Port découverte")
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontSizeSmall
                                font.family: Theme.fontFamily
                                Layout.preferredWidth: 140
                            }

                            SpinBox {
                                from: 1024
                                to: 65535
                                value: settingsModel.discoveryPort
                                onValueChanged: settingsModel.discoveryPort = value
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: Theme.spacingLarge
                        Layout.rightMargin: Theme.spacingLarge
                        spacing: Theme.spacingMedium

                        Item { Layout.fillWidth: true }

                        AppButton {
                            variant: "ghost"
                            text: qsTr("Annuler")
                            onClicked: settingsModel.load()
                        }

                        AppButton {
                            variant: "primary"
                            text: qsTr("Enregistrer")
                            onClicked: settingsModel.save()
                        }
                    }

                    Item { Layout.preferredHeight: Theme.spacingLarge }
                }
            }
        }

        // ============================================================
        // Onglet "Bascule serveur" : historique des elections/reconciliations
        // (ServerElectionLog), utile pour diagnostiquer une instabilite reseau.
        // ============================================================
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.currentTab === 2

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.spacingLarge
                spacing: Theme.spacingMedium

                ColumnLayout {
                    spacing: 2

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

                // En-tete de colonnes -- absent de l'ancienne version, ce qui
                // rendait les lignes difficiles a scanner sans savoir ce que
                // chaque champ representait.
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32
                    radius: Theme.radiusMedium
                    color: Theme.listHeaderBackground
                    visible: root.electionHistoryEntries.length > 0

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.spacingMedium + 14
                        anchors.rightMargin: Theme.spacingMedium
                        spacing: Theme.spacingMedium

                        Label {
                            text: qsTr("Événement")
                            font.pixelSize: Theme.fontSizeCaption
                            font.bold: true
                            font.family: Theme.fontFamily
                            color: Theme.textSecondary
                            Layout.preferredWidth: 180
                        }
                        Label {
                            text: qsTr("Époque")
                            font.pixelSize: Theme.fontSizeCaption
                            font.bold: true
                            font.family: Theme.fontFamily
                            color: Theme.textSecondary
                            Layout.preferredWidth: 80
                        }
                        Label {
                            text: qsTr("Machine")
                            font.pixelSize: Theme.fontSizeCaption
                            font.bold: true
                            font.family: Theme.fontFamily
                            color: Theme.textSecondary
                            Layout.fillWidth: true
                        }
                        Label {
                            text: qsTr("Date")
                            font.pixelSize: Theme.fontSizeCaption
                            font.bold: true
                            font.family: Theme.fontFamily
                            color: Theme.textSecondary
                        }
                    }
                }

                Label {
                    visible: root.electionHistoryEntries.length === 0
                    text: qsTr("Aucun événement enregistré pour l'instant.")
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeBody
                    font.family: Theme.fontFamily
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
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSmall
                                Layout.preferredWidth: 170
                            }

                            Label {
                                text: "#" + modelData.epoch
                                color: Theme.textSecondary
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSmall
                                Layout.preferredWidth: 80
                            }

                            Label {
                                text: modelData.machineUuid
                                color: Theme.textSecondary
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSmall
                                elide: Text.ElideMiddle
                                Layout.fillWidth: true
                            }

                            Label {
                                text: modelData.createdAt
                                color: Theme.textTertiary
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeCaption
                            }
                        }
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

    FolderDialog {
        id: folderDialog
        title: "Sélectionner le répertoire de téléchargement"
        currentFolder: settingsModel.defaultDownloadPath
        onAccepted: {
            settingsModel.defaultDownloadPath = selectedFolder
        }
    }
}
