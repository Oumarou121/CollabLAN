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
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 64
            color: Theme.surface

            // Séparateur bas
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

                // Navigation compacte : retour, onglets, actions
                RowLayout {
                    Layout.fillWidth: false
                    Layout.preferredHeight: 48
                    spacing: Theme.spacingMedium

                    IconButton {
                        variant: "ghost"
                        glyph: "\uf060"
                        size: 40
                        onClicked: root.backRequested()
                    }

                    ColumnLayout {
                        visible: false
                        Layout.fillWidth: false
                        spacing: Theme.spacingXs

                        Text {
                            text: qsTr("Administration")
                            font.pixelSize: Theme.fontSizeHeading
                            font.bold: true
                            font.family: Theme.fontFamily
                            color: Theme.text
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        Text {
                            text: qsTr("Supervisez les activités et la sécurité du réseau")
                            font.pixelSize: Theme.fontSizeSmall
                            font.family: Theme.fontFamily
                            color: Theme.textSecondary
                            elide: Text.ElideRight
                            visible: !root.headerCompact
                            Layout.fillWidth: true
                        }
                    }

                    RowLayout {
                        visible: false
                        spacing: Theme.spacingSmall

                        Rectangle {
                            visible: false
                            implicitWidth: adminBadge.implicitWidth + Theme.spacingMedium * 2
                            implicitHeight: 30
                            radius: Theme.radiusPill
                            color: Theme.primaryMuted

                            Label {
                                id: adminBadge
                                anchors.centerIn: parent
                                text: qsTr("ADMINISTRATEUR")
                                color: Theme.primary
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeCaption
                                font.bold: true
                            }
                        }

                        IconButton {
                            variant: "secondary"
                            glyph: "\u21E9"
                            size: 36
                            visible: root.currentTab === 0
                            onClicked: exportDialog.open()
                        }

                        IconButton {
                            variant: "primary"
                            glyph: "+"
                            size: 36
                            visible: root.currentTab === 1
                            onClicked: addMachineDialog.open()
                        }

                        IconButton {
                            variant: "primary"
                            glyph: "+"
                            size: 36
                            visible: root.currentTab === 2
                            onClicked: addUserDialog.open()
                        }

                        IconButton {
                            variant: "secondary"
                            glyph: "\u21BB"
                            size: 36
                            visible: root.currentTab === 3
                            onClicked: root.refreshElectionHistory()
                        }
                    }
                }

                // Ligne inférieure : onglets
                Rectangle {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredHeight: 48
                    Layout.minimumHeight: 48
                    Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
                    radius: Theme.radiusMedium
                    color: Theme.surfaceAlt
                    clip: true

                    Flickable {
                        anchors.fill: parent
                        anchors.margins: Theme.spacingXs
                        contentWidth: Math.max(width, tabRow.implicitWidth)
                        contentHeight: height
                        clip: true
                        interactive: tabRow.implicitWidth > width
                        boundsBehavior: Flickable.StopAtBounds

                        Row {
                            id: tabRow
                            anchors.centerIn: parent
                            spacing: 2

                            TabPill { glyph: "\uf1ea"; label: qsTr("Journal d'audit"); active: root.currentTab === 0; onClicked: root.currentTab = 0 }
                            TabPill { glyph: "\uf233"; label: qsTr("Machines autorisées"); active: root.currentTab === 1; onClicked: root.currentTab = 1 }
                            TabPill { glyph: "\uf0c0"; label: qsTr("Utilisateurs"); active: root.currentTab === 2; onClicked: root.currentTab = 2 }
                            TabPill { glyph: "\uf021"; label: qsTr("Bascule serveur"); active: root.currentTab === 3; onClicked: root.currentTab = 3 }
                        }
                    }
                }

                // Actions toujours alignées à l'extrémité droite.
                RowLayout {
                    Layout.alignment: Qt.AlignVCenter
                    spacing: Theme.spacingSmall

                    AppButton {
                        variant: "secondary"
                        iconGlyph: "\u21E9"
                        text: root.headerCompact ? "" : qsTr("Exporter")
                        visible: root.currentTab === 0
                        onClicked: exportDialog.open()
                    }

                    AppButton {
                        variant: "primary"
                        iconGlyph: "+"
                        text: root.headerCompact ? "" : qsTr("Ajouter")
                        visible: root.currentTab === 1
                        onClicked: addMachineDialog.open()
                    }

                    AppButton {
                        variant: "primary"
                        iconGlyph: "+"
                        text: root.headerCompact ? "" : qsTr("Ajouter")
                        visible: root.currentTab === 2
                        onClicked: addUserDialog.open()
                    }

                    AppButton {
                        variant: "secondary"
                        iconGlyph: "\u21BB"
                        text: root.headerCompact ? "" : qsTr("Actualiser")
                        visible: root.currentTab === 3
                        onClicked: root.refreshElectionHistory()
                    }
                }
            }
        }

        // ---- Contenu de l'onglet Journal d'audit --------------------------
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.currentTab === 0

            ColumnLayout {
                width: Math.min(parent.width - 2 * Theme.spacingLarge, 1200)
                height: parent.height - Theme.spacingLarge
                x: (parent.width - width) / 2
                y: Theme.spacingMedium
                spacing: Theme.spacingMedium

                // Filtres : Flow plutot que RowLayout, pour que les
                // groupes label+champ passent a la ligne des que la
                // largeur disponible ne suffit plus (au lieu de deborder
                // ou de se tasser illisiblement sur un petit ecran).
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: filterFlow.height + Theme.spacingMedium * 2
                    radius: Theme.radiusLarge
                    color: Theme.surface
                    border.width: 1
                    border.color: Theme.border

                    Flow {
                        id: filterFlow
                        x: Theme.spacingMedium
                        y: Theme.spacingMedium
                        width: parent.width - Theme.spacingMedium * 2
                        spacing: Theme.spacingMedium

                        RowLayout {
                            spacing: Theme.spacingSmall
                            Label {
                                Layout.alignment: Qt.AlignVCenter
                                text: qsTr("Type")
                                color: Theme.text
                                font.pixelSize: Theme.fontSizeSmall
                                font.family: Theme.fontFamily
                                font.bold: true
                            }
                            ComboBox {
                                id: eventTypeFilter
                                palette.window: Theme.surface
                                palette.base: Theme.surfaceAlt
                                palette.button: Theme.surfaceAlt
                                palette.text: Theme.text
                                palette.buttonText: Theme.text
                                palette.highlight: Theme.primary
                                palette.highlightedText: Theme.primaryText
                                Layout.alignment: Qt.AlignVCenter
                                Layout.preferredWidth: 180
                                Layout.preferredHeight: 40
                                model: ["Tous", "connection", "message", "transfer", "call", "access_denied"]
                                background: Rectangle {
                                    radius: Theme.radiusMedium
                                    color: Theme.background
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
                        }

                        RowLayout {
                            spacing: Theme.spacingSmall
                            Label {
                                Layout.alignment: Qt.AlignVCenter
                                text: qsTr("Du")
                                color: Theme.text
                                font.pixelSize: Theme.fontSizeSmall
                                font.family: Theme.fontFamily
                                font.bold: true
                            }
                            TextField {
                                id: dateFrom
                                Layout.alignment: Qt.AlignVCenter
                                Layout.preferredWidth: 150
                                Layout.preferredHeight: 40
                                placeholderText: "YYYY-MM-DD"
                                color: Theme.text
                                font.pixelSize: Theme.fontSizeSmall
                                leftPadding: Theme.spacingMedium
                                background: Rectangle {
                                    radius: Theme.radiusMedium
                                    color: Theme.background
                                    border.width: dateFrom.activeFocus ? 2 : 1
                                    border.color: dateFrom.activeFocus ? Theme.primary : Theme.border
                                }
                            }
                        }

                        RowLayout {
                            spacing: Theme.spacingSmall
                            Label {
                                Layout.alignment: Qt.AlignVCenter
                                text: qsTr("Au")
                                color: Theme.text
                                font.pixelSize: Theme.fontSizeSmall
                                font.family: Theme.fontFamily
                                font.bold: true
                            }
                            TextField {
                                id: dateTo
                                Layout.alignment: Qt.AlignVCenter
                                Layout.preferredWidth: 150
                                Layout.preferredHeight: 40
                                placeholderText: "YYYY-MM-DD"
                                color: Theme.text
                                font.pixelSize: Theme.fontSizeSmall
                                leftPadding: Theme.spacingMedium
                                background: Rectangle {
                                    radius: Theme.radiusMedium
                                    color: Theme.background
                                    border.width: dateTo.activeFocus ? 2 : 1
                                    border.color: dateTo.activeFocus ? Theme.primary : Theme.border
                                }
                            }
                        }

                        RowLayout {
                            spacing: Theme.spacingSmall
                            AppButton {
                                Layout.alignment: Qt.AlignVCenter
                                variant: "primary"
                                text: qsTr("Filtrer")
                                onClicked: auditLogModel.setDateRange(dateFrom.text, dateTo.text)
                            }
                            AppButton {
                                Layout.alignment: Qt.AlignVCenter
                                variant: "ghost"
                                text: qsTr("Réinitialiser")
                                onClicked: {
                                    eventTypeFilter.currentIndex = 0
                                    dateFrom.text = ""
                                    dateTo.text = ""
                                    auditLogModel.clearFilters()
                                }
                            }
                        }
                    }
                }

                // Liste des entrées d'audit : chaque entree est empilee
                // verticalement (horodatage + type, description, acteur)
                // plutot que reparties sur des colonnes de largeur fixe,
                // et la hauteur suit le contenu (le texte peut s'etaler
                // sur plusieurs lignes sans etre tronque a l'ecran).
                ScrollView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentWidth: availableWidth
                    clip: true

                    ListView {
                        id: auditListView
                        anchors.fill: parent
                        model: auditLogModel
                        spacing: Theme.spacingMedium
                        clip: true
                        delegate: Rectangle {
                            width: auditListView.width
                            height: auditEntryColumn.implicitHeight + Theme.spacingLarge * 2
                            radius: Theme.radiusLarge
                            color: Theme.surface
                            border.width: 1
                            border.color: Theme.border

                            ColumnLayout {
                                id: auditEntryColumn
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: Theme.spacingLarge
                                spacing: Theme.spacingSmall

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Theme.spacingSmall

                                    Label {
                                        text: model.timestamp
                                        font.pixelSize: Theme.fontSizeCaption
                                        color: Theme.textTertiary
                                        font.family: Theme.fontFamily
                                    }

                                    Rectangle {
                                        implicitWidth: eventTypeLabel.implicitWidth + Theme.spacingMedium
                                        implicitHeight: 24
                                        radius: Theme.radiusPill
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

                                    Item { Layout.fillWidth: true }
                                }

                                Label {
                                    text: model.description
                                    font.pixelSize: Theme.fontSizeBody
                                    color: Theme.text
                                    wrapMode: Text.WordWrap
                                    Layout.fillWidth: true
                                    font.family: Theme.fontFamily
                                }

                                Label {
                                    text: qsTr("Acteur : %1").arg(model.actorLabel || "N/A")
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.textSecondary
                                    font.family: Theme.fontFamily
                                    Layout.topMargin: Theme.spacingXs
                                }
                            }
                        }
                    }
                }
            }
        }

        // ---- Contenu de l'onglet Machines autorisées (issue #68) ---------
        // Grille de cartes (au lieu d'un tableau a colonnes figees), sur le
        // meme principe que la grille "Postes connectés" de UsersView :
        // 3/2/1 colonnes selon la largeur disponible.
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.currentTab === 1

            Item {
                width: Math.min(parent.width - 2 * Theme.spacingLarge, 1200)
                height: parent.height - Theme.spacingLarge
                x: (parent.width - width) / 2
                y: Theme.spacingMedium

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.radiusLarge
                    color: Theme.surface
                    border.width: 1
                    border.color: Theme.border
                    clip: true

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: Theme.spacingMedium
                        visible: machinesGrid.count === 0
                        width: parent.width * 0.6

                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: 80
                            Layout.preferredHeight: 80
                            radius: 40
                            color: Theme.surfaceAlt

                            Text {
                                anchors.centerIn: parent
                                text: "\uf109"
                                font.family: root.iconFontFamily
                                font.pixelSize: 32
                                color: Theme.textSecondary
                            }
                        }

                        Label {
                            Layout.alignment: Qt.AlignHCenter
                            text: qsTr("Aucune machine autorisée")
                            font.pixelSize: Theme.fontSizeSubheading
                            font.bold: true
                            font.family: Theme.fontFamily
                            color: Theme.text
                            horizontalAlignment: Text.AlignHCenter
                        }

                        Label {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.fillWidth: true
                            text: qsTr("Utilisez le bouton « Ajouter machine » pour autoriser un certificat connu.")
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeSmall
                            font.family: Theme.fontFamily
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                        }
                    }

                    GridView {
                        id: machinesGrid
                        anchors.fill: parent
                        anchors.margins: Theme.spacingMedium
                        clip: true
                        model: authorizedMachineModel

                        readonly property int columns: width > 900 ? 3 : (width > 560 ? 2 : 1)
                        cellWidth: width / columns
                        cellHeight: 200

                        delegate: Item {
                            width: machinesGrid.cellWidth
                            height: machinesGrid.cellHeight

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: Theme.spacingSmall / 2
                                radius: Theme.radiusLarge
                                color: Theme.surface
                                border.width: 1
                                border.color: Theme.border

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: Theme.spacingLarge
                                    spacing: Theme.spacingMedium

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Theme.spacingMedium

                                        Rectangle {
                                            Layout.preferredWidth: 48
                                            Layout.preferredHeight: 48
                                            radius: Theme.radiusMedium
                                            color: Theme.surfaceAlt

                                            Text {
                                                anchors.centerIn: parent
                                                text: "\uf109"
                                                font.family: root.iconFontFamily
                                                font.pixelSize: 20
                                                color: Theme.textSecondary
                                            }
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 2

                                            Label {
                                                text: model.hostname || model.machineUuid || qsTr("Machine inconnue")
                                                font.pixelSize: Theme.fontSizeBody
                                                font.bold: true
                                                font.family: Theme.fontFamily
                                                color: Theme.text
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }

                                            Label {
                                                text: model.lastIpAddress || model.ipAddress || "N/A"
                                                font.pixelSize: Theme.fontSizeSmall
                                                font.family: Theme.fontFamily
                                                color: Theme.textSecondary
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                        }

                                        Rectangle {
                                            Layout.alignment: Qt.AlignTop
                                            implicitWidth: machineStatusLabel.implicitWidth + Theme.spacingMedium
                                            implicitHeight: 24
                                            radius: Theme.radiusPill
                                            color: model.status === "pending" ? Theme.warningMuted
                                                   : (model.status === "authorized" ? Theme.successMuted : Theme.errorMuted)

                                            Label {
                                                id: machineStatusLabel
                                                anchors.centerIn: parent
                                                text: model.status === "pending" ? qsTr("En attente")
                                                      : (model.status === "authorized" ? qsTr("Autorisée") : qsTr("Révoquée"))
                                                font.pixelSize: Theme.fontSizeCaption
                                                font.bold: true
                                                color: model.status === "pending" ? Theme.warning
                                                       : (model.status === "authorized" ? Theme.success : Theme.error)
                                            }
                                        }
                                    }

                                    Label {
                                        visible: model.status === "pending"
                                        text: qsTr("Machine détectée — autorisation requise")
                                        font.pixelSize: Theme.fontSizeCaption
                                        font.italic: true
                                        color: Theme.warning
                                        wrapMode: Text.WordWrap
                                        Layout.fillWidth: true
                                    }

                                    Label {
                                        text: qsTr("Ajoutée le %1").arg(model.addedAt)
                                        font.pixelSize: Theme.fontSizeCaption
                                        font.family: Theme.fontFamily
                                        color: Theme.textTertiary
                                    }

                                    Label {
                                        text: model.certificateFingerprint
                                              ? qsTr("Certificat : %1…").arg(model.certificateFingerprint.substring(0, 12))
                                              : qsTr("Certificat non enregistré")
                                        font.pixelSize: Theme.fontSizeCaption
                                        color: Theme.textTertiary
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }

                                    Item { Layout.fillHeight: true }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Theme.spacingSmall

                                        AppButton {
                                            variant: "secondary"
                                            fullWidth: true
                                            text: model.status === "pending" ? qsTr("Autoriser")
                                                  : (model.status === "authorized" ? qsTr("Révoquer") : qsTr("Réautoriser"))
                                            onClicked: {
                                                if (model.status === "authorized") {
                                                    authorizedMachineModel.revokeMachine(model.id, "Révoqué par admin")
                                                } else {
                                                    authorizedMachineModel.authorizeMachine(model.id, "Autorisé par admin")
                                                }
                                            }
                                        }

                                        AppButton {
                                            variant: "secondary"
                                            text: qsTr("Copier")
                                            onClicked: {
                                                fingerprintCopyField.text = model.certificateFingerprint
                                                fingerprintCopyField.selectAll()
                                                fingerprintCopyField.copy()
                                            }
                                        }

                                        AppButton {
                                            variant: "danger"
                                            text: qsTr("Supprimer")
                                            onClicked: authorizedMachineModel.removeMachine(model.id)
                                        }
                                    }

                                    TextEdit {
                                        id: fingerprintCopyField
                                        visible: false
                                        text: ""
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // ---- Contenu de l'onglet Gestion des utilisateurs (issue #69) ----
        // Meme principe de grille responsive que l'onglet Machines.
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.currentTab === 2

            Item {
                width: Math.min(parent.width - 2 * Theme.spacingLarge, 1200)
                height: parent.height - Theme.spacingLarge
                x: (parent.width - width) / 2
                y: Theme.spacingMedium

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.radiusLarge
                    color: Theme.surface
                    border.width: 1
                    border.color: Theme.border
                    clip: true

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: Theme.spacingMedium
                        visible: usersGrid.count === 0
                        width: parent.width * 0.6

                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: 80
                            Layout.preferredHeight: 80
                            radius: 40
                            color: Theme.surfaceAlt

                            Text {
                                anchors.centerIn: parent
                                text: "\uf234"
                                font.family: root.iconFontFamily
                                font.pixelSize: 32
                                color: Theme.textSecondary
                            }
                        }

                        Label {
                            Layout.alignment: Qt.AlignHCenter
                            text: qsTr("Aucun utilisateur")
                            font.pixelSize: Theme.fontSizeSubheading
                            font.bold: true
                            font.family: Theme.fontFamily
                            color: Theme.text
                            horizontalAlignment: Text.AlignHCenter
                        }

                        Label {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.fillWidth: true
                            text: qsTr("Utilisez le bouton « Ajouter utilisateur » pour créer un compte.")
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeSmall
                            font.family: Theme.fontFamily
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                        }
                    }

                    GridView {
                        id: usersGrid
                        anchors.fill: parent
                        anchors.margins: Theme.spacingMedium
                        clip: true
                        model: userManagementModel

                        readonly property int columns: width > 900 ? 3 : (width > 560 ? 2 : 1)
                        cellWidth: width / columns
                        cellHeight: 200

                        delegate: Item {
                            width: usersGrid.cellWidth
                            height: usersGrid.cellHeight

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: Theme.spacingSmall / 2
                                radius: Theme.radiusLarge
                                color: Theme.surface
                                border.width: 1
                                border.color: Theme.border

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: Theme.spacingLarge
                                    spacing: Theme.spacingMedium

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Theme.spacingMedium

                                        Avatar {
                                            name: model.name
                                            size: 48
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
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
                                                text: model.ipAddress || "N/A"
                                                font.pixelSize: Theme.fontSizeSmall
                                                font.family: Theme.fontFamily
                                                color: Theme.textSecondary
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                        }

                                        Rectangle {
                                            Layout.alignment: Qt.AlignTop
                                            implicitWidth: roleLabel.implicitWidth + Theme.spacingMedium
                                            implicitHeight: 24
                                            radius: Theme.radiusPill
                                            color: model.isAdmin ? Theme.primaryMuted : Theme.surfaceAlt

                                            Label {
                                                id: roleLabel
                                                anchors.centerIn: parent
                                                text: model.isAdmin ? qsTr("Admin") : qsTr("Utilisateur")
                                                font.pixelSize: Theme.fontSizeCaption
                                                font.bold: true
                                                color: model.isAdmin ? Theme.primary : Theme.textSecondary
                                            }
                                        }
                                    }

                                    Label {
                                        text: qsTr("Statut : %1").arg(model.status)
                                        font.pixelSize: Theme.fontSizeCaption
                                        font.family: Theme.fontFamily
                                        color: Theme.textTertiary
                                    }

                                    Item { Layout.fillHeight: true }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Theme.spacingSmall

                                        AppButton {
                                            variant: "secondary"
                                            fullWidth: true
                                            text: model.isAdmin ? qsTr("Rétrograder") : qsTr("Promouvoir")
                                            onClicked: userManagementModel.changeRole(model.id, !model.isAdmin)
                                        }

                                        AppButton {
                                            variant: "danger"
                                            text: qsTr("Supprimer")
                                            onClicked: userManagementModel.deleteUser(model.id)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // ---- Contenu de l'onglet "Bascule serveur" ------------------------
        // (HYBRID_SERVER_FAILOVER.md section 9, etape 5) : historique des
        // elections/reconciliations (ServerElectionLog), utile pour
        // diagnostiquer une instabilite reseau. Entrees empilees
        // verticalement (au lieu de colonnes de largeur fixe) pour rester
        // lisibles a toute largeur.
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.currentTab === 3

            ColumnLayout {
                width: Math.min(parent.width - 2 * Theme.spacingLarge, 1200)
                height: parent.height - Theme.spacingLarge
                x: (parent.width - width) / 2
                y: Theme.spacingMedium
                spacing: Theme.spacingMedium

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
                            font.pixelSize: 32
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
        id: addMachineDialog
        title: qsTr("Ajouter une machine autorisée")
        headerIcon: "\uf109"
        dialogWidth: 500
        dialogHeight: 600

        ScrollView {
            anchors.fill: parent
            clip: true
            contentWidth: availableWidth

            ColumnLayout {
                width: parent.width
                spacing: Theme.spacingSmall

            Label {
                text: qsTr("Postes détectés")
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.textSecondary
            }

            ComboBox {
                id: detectedMachineSelector
                Layout.fillWidth: true
                model: (typeof discoveryService !== "undefined" && discoveryService)
                       ? discoveryService.machineCandidates() : []
                textRole: "name"
                displayText: currentIndex >= 0 && currentIndex < count
                             ? (model[currentIndex].name + " — " + model[currentIndex].ip) : qsTr("Sélectionner un poste détecté")
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
                text: qsTr("Empreinte SHA-256 du certificat")
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.textSecondary
            }

            TextField {
                id: newMachineFingerprint
                Layout.fillWidth: true
                Layout.preferredHeight: 40
                placeholderText: qsTr("empreinte SHA-256 complète")
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

            Label {
                text: qsTr("UUID de la machine")
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.textSecondary
                Layout.topMargin: Theme.spacingSmall
            }

            TextField {
                id: newMachineUuid
                Layout.fillWidth: true
                Layout.preferredHeight: 40
                placeholderText: qsTr("UUID annoncé par le poste")
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
                text: qsTr("Dernière adresse IP (optionnel)")
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.textSecondary
                Layout.topMargin: Theme.spacingSmall
            }

            TextField {
                id: newMachineIp
                Layout.fillWidth: true
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
                Layout.fillWidth: true
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
                Layout.fillWidth: true
                Layout.topMargin: Theme.spacingMedium
                spacing: Theme.spacingSmall

                Item { Layout.fillWidth: true }

                AppButton {
                    variant: "ghost"
                    text: qsTr("Annuler")
                    onClicked: addMachineDialog.close()
                }

                AppButton {
                    variant: "primary"
                    text: qsTr("Ajouter")
                    onClicked: {
                        authorizedMachineModel.addMachineByCertificate(
                            newMachineFingerprint.text, newMachineUuid.text,
                            newMachineIp.text, newMachineHostname.text,
                            "Ajouté par admin")
                        addMachineDialog.close()
                    }
                }
            }
        }
    }
    }

    AppDialog {
        id: addUserDialog
        title: qsTr("Ajouter un utilisateur")
        headerIcon: "\uf234"
        dialogWidth: 340

        ColumnLayout {
            anchors.fill: parent
            spacing: Theme.spacingSmall

            Label {
                text: qsTr("Nom d'utilisateur")
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.textSecondary
            }

            TextField {
                id: newUserName
                Layout.fillWidth: true
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
                Layout.fillWidth: true
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
                palette.window: Theme.surface
                palette.base: Theme.surfaceAlt
                palette.button: Theme.surfaceAlt
                palette.text: Theme.text
                palette.buttonText: Theme.text
                palette.highlight: Theme.primary
                palette.highlightedText: Theme.primaryText
                Layout.fillWidth: true
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
                Layout.fillWidth: true
                Layout.topMargin: Theme.spacingMedium
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
                        userManagementModel.createUser(newUserName.text, newUserPassword.text, isAdmin)
                        addUserDialog.close()
                    }
                }
            }
        }
    }

    AppDialog {
        id: accessDeniedDialog
        title: qsTr("Accès refusé")
        headerIcon: "\uf071"
        dialogWidth: 360
        showCloseButton: false
        closePolicy: Popup.NoAutoClose

        ColumnLayout {
            anchors.fill: parent
            spacing: Theme.spacingMedium

            Label {
                Layout.fillWidth: true
                text: qsTr("Vous n'avez pas les droits administrateur pour accéder à cette page.")
                color: Theme.text
                font.pixelSize: Theme.fontSizeBody
                font.family: Theme.fontFamily
                wrapMode: Text.WordWrap
            }

            AppButton {
                Layout.alignment: Qt.AlignRight
                variant: "primary"
                text: qsTr("OK")
                onClicked: {
                    accessDeniedDialog.close()
                    root.backRequested()
                }
            }
        }
    }
}
