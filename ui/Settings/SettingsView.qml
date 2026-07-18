import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import Themes
import "../Components"

/*
 * SettingsView - Parametres accessibles a tous les utilisateurs depuis le
 * menu profil de HomeView (anciennement onglet "Parametres" reserve aux
 * administrateurs dans AdminView).
 *
 * Refonte design (juillet 2026) : alignement complet sur le style
 * "corporate" bleu-gris deja utilise pour LoginView/HomeView -- cartes
 * SettingsSectionCard avec icone Font Awesome (meme composant que
 * DashboardCard sur l'accueil), contenu centre en colonne unique avec
 * largeur maximale (comme .card-grid sur HomeView) plutot qu'etire sur
 * toute la largeur de l'ecran, et grille de champs qui se reorganise
 * selon la largeur disponible (utile en fenetre partagee / multi-ecrans
 * desktop, cf. seuils GridLayout ci-dessous).
 *
 * Contenu :
 *   - Preferences generales (telechargement, partage) : tous utilisateurs.
 *     defaultDownloadPath est applique en temps reel a
 *     network::TransferService (voir main.cpp) ; defaultSharedFolderPath
 *     est propose par defaut a la creation d'un nouveau dossier partage
 *     (SharedFolderView.qml).
 *   - Notifications & sons : tous utilisateurs. enableNotifications est
 *     branche sur core::NotificationManager::setNotificationsEnabled()
 *     (voir main.cpp). Le son (audioService.soundEnabled/volume) est la
 *     seule source de verite pour l'activation des sons -- l'ancienne
 *     case a cocher settingsModel.enableSounds, qui ne pilotait rien
 *     reellement, a ete retiree (doublon).
 *   - Ports reseau : reserve aux administrateurs
 *     (userManager.currentUserIsAdmin), simplement masque pour les
 *     autres utilisateurs.
 *   - Une seule barre d'actions "Annuler / Enregistrer", fixe en bas de
 *     l'ecran plutot que dupliquee par carte : settingsModel.save()/load()
 *     portent de toute facon sur l'integralite des reglages (meme
 *     QSettings), donc plusieurs boutons qui font strictement la meme
 *     chose n'apportaient rien et pretaient a confusion (ex. cliquer
 *     "Enregistrer" sous Ports reseau sauvegardait aussi silencieusement
 *     les Preferences).
 *   - La section "Bascule automatique de serveur" (etat + reglages
 *     priorite/timeout) est masquee (visible: false) sur demande - le
 *     code reste en place si on souhaite la reactiver plus tard.
 */
Item {
    id: root
    objectName: "settingsView"

    signal backRequested()

    property bool isAdmin: (typeof userManager !== "undefined" && userManager) ? userManager.currentUserIsAdmin : false
    property var election: (typeof electionService !== "undefined") ? electionService : null
    property var app: (typeof application !== "undefined") ? application : null

    Rectangle {
        anchors.fill: parent
        color: Theme.background
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ---- Barre superieure (composant partage, cf. Components/AppHeader.qml) --
        AppHeader {
            title: qsTr("Paramètres")
            onBackRequested: root.backRequested()
        }

        // ---- Contenu principal : colonne centree, largeur maximale --------
        // (meme principe que le card-grid de HomeView : le contenu ne
        // s'etire pas indefiniment sur les grands ecrans, il reste lisible
        // et centre ; en dessous de ~760px il occupe toute la largeur.)
        Flickable {
            id: settingsFlickable
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            contentHeight: contentColumn.implicitHeight + 2 * Theme.spacingXl
            clip: true

            ColumnLayout {
                id: contentColumn
                width: Math.min(parent.width - 2 * Theme.spacingXl, 760)
                x: (parent.width - width) / 2
                y: Theme.spacingXl
                spacing: Theme.spacingLarge

                // --- Preferences generales (telechargement + partage) ------
                SettingsSectionCard {
                    Layout.fillWidth: true
                    icon: "\uf07c"
                    title: qsTr("Préférences générales")
                    subtitle: qsTr("Emplacements par défaut utilisés pour les téléchargements et le partage de dossiers.")

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingXs

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

                            Button {
                                text: qsTr("Parcourir...")
                                Layout.preferredHeight: 40

                                background: Rectangle {
                                    radius: Theme.radiusMedium
                                    color: parent.hovered ? Theme.surfaceAlt : "transparent"
                                    border.width: 1
                                    border.color: Theme.border
                                }
                                contentItem: Text {
                                    text: qsTr("Parcourir...")
                                    color: Theme.text
                                    font.pixelSize: Theme.fontSizeSmall
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }

                                onClicked: settingsFolderDialog.open()
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: Theme.spacingSmall
                        spacing: Theme.spacingXs

                        Label {
                            text: qsTr("Répertoire de partage par défaut")
                            font.pixelSize: Theme.fontSizeSmall
                            font.family: Theme.fontFamily
                            color: Theme.textSecondary
                        }

                        Label {
                            text: qsTr("Dossier proposé par défaut à la création d'un nouveau dossier partagé.")
                            font.pixelSize: Theme.fontSizeCaption
                            font.family: Theme.fontFamily
                            color: Theme.textTertiary
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacingSmall

                            TextField {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 40
                                text: settingsModel.defaultSharedFolderPath
                                color: Theme.text
                                font.pixelSize: Theme.fontSizeBody
                                leftPadding: Theme.spacingMedium
                                onTextChanged: settingsModel.defaultSharedFolderPath = text

                                background: Rectangle {
                                    radius: Theme.radiusMedium
                                    color: Theme.background
                                    border.width: 1
                                    border.color: Theme.border
                                }
                            }

                            Button {
                                text: qsTr("Parcourir...")
                                Layout.preferredHeight: 40

                                background: Rectangle {
                                    radius: Theme.radiusMedium
                                    color: parent.hovered ? Theme.surfaceAlt : "transparent"
                                    border.width: 1
                                    border.color: Theme.border
                                }
                                contentItem: Text {
                                    text: qsTr("Parcourir...")
                                    color: Theme.text
                                    font.pixelSize: Theme.fontSizeSmall
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }

                                onClicked: settingsSharedFolderDialog.open()
                            }
                        }
                    }
                }

                // --- Notifications & sons -----------------------------------
                SettingsSectionCard {
                    Layout.fillWidth: true
                    icon: "\uf0f3"
                    title: qsTr("Notifications & sons")
                    subtitle: qsTr("Contrôlez les alertes affichées et les sons joués lors des événements (messages, transferts, appels...).")

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingMedium

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            Label {
                                text: qsTr("Notifications activées")
                                color: Theme.text
                                font.pixelSize: Theme.fontSizeBody
                                font.family: Theme.fontFamily
                            }
                            Label {
                                text: qsTr("Affiche une alerte pour les nouveaux messages, transferts et connexions.")
                                color: Theme.textTertiary
                                font.pixelSize: Theme.fontSizeCaption
                                font.family: Theme.fontFamily
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }
                        }

                        Switch {
                            checked: settingsModel.enableNotifications
                            onCheckedChanged: settingsModel.enableNotifications = checked
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 1
                        color: Theme.border
                    }

                    // --- Sons (audioService : switch + volume, seule source
                    // de verite - anciennement dupliquee avec une case a
                    // cocher settingsModel.enableSounds qui ne pilotait rien) --
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingMedium

                        Label {
                            text: qsTr("Sons activés")
                            color: Theme.text
                            font.pixelSize: Theme.fontSizeBody
                            font.family: Theme.fontFamily
                            Layout.fillWidth: true
                        }
                        Switch {
                            id: soundSwitch
                            checked: (typeof audioService !== "undefined") && audioService.soundEnabled
                            onCheckedChanged: {
                                if (typeof audioService !== "undefined")
                                    audioService.soundEnabled = checked
                            }
                            // Resynchronise si le backend change la valeur depuis le C++.
                            Connections {
                                target: (typeof audioService !== "undefined") ? audioService : null
                                function onSoundEnabledChanged() {
                                    if (typeof audioService !== "undefined")
                                        soundSwitch.checked = audioService.soundEnabled
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        enabled: soundSwitch.checked
                        opacity: soundSwitch.checked ? 1.0 : 0.4
                        Layout.fillWidth: true
                        spacing: Theme.spacingXs

                        Behavior on opacity { NumberAnimation { duration: 120 } }

                        RowLayout {
                            spacing: Theme.spacingSmall
                            Label {
                                text: qsTr("Volume")
                                color: Theme.text
                                font.pixelSize: Theme.fontSizeSmall
                                font.family: Theme.fontFamily
                            }
                            Item { Layout.fillWidth: true }
                            Label {
                                text: Math.round(volumeSlider.value * 100) + " %"
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontSizeSmall
                                font.family: Theme.fontFamily
                            }
                        }

                        Slider {
                            id: volumeSlider
                            from: 0.0
                            to: 1.0
                            stepSize: 0.05
                            value: (typeof audioService !== "undefined") ? audioService.volume : 1.0
                            Layout.fillWidth: true

                            onMoved: {
                                if (typeof audioService !== "undefined")
                                    audioService.volume = value
                            }

                            Connections {
                                target: (typeof audioService !== "undefined") ? audioService : null
                                function onVolumeChanged() {
                                    if (typeof audioService !== "undefined"
                                            && Math.abs(volumeSlider.value - audioService.volume) > 0.01)
                                        volumeSlider.value = audioService.volume
                                }
                            }
                        }
                    }
                }

                // --- Ports reseau (reserve aux administrateurs) -------------
                SettingsSectionCard {
                    Layout.fillWidth: true
                    visible: root.isAdmin
                    icon: "\uf1e6"
                    title: qsTr("Ports réseau")
                    subtitle: qsTr("Nécessite un redémarrage de l'application pour être appliqué (les sockets déjà ouverts ne peuvent pas changer de port à chaud).")

                    // Grille responsive : 2 colonnes cote a cote sur un
                    // desktop suffisamment large, empilees verticalement en
                    // dessous (fenetre partagee, ecran plus etroit).
                    GridLayout {
                        Layout.fillWidth: true
                        columns: width > 420 ? 2 : 1
                        columnSpacing: Theme.spacingLarge
                        rowSpacing: Theme.spacingSmall

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacingXs

                            Label {
                                text: qsTr("Port messagerie")
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontSizeSmall
                                font.family: Theme.fontFamily
                            }
                            SpinBox {
                                Layout.fillWidth: true
                                from: 1024
                                to: 65535
                                value: settingsModel.messagingPort
                                onValueChanged: settingsModel.messagingPort = value
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacingXs

                            Label {
                                text: qsTr("Port découverte")
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontSizeSmall
                                font.family: Theme.fontFamily
                            }
                            SpinBox {
                                Layout.fillWidth: true
                                from: 1024
                                to: 65535
                                value: settingsModel.discoveryPort
                                onValueChanged: settingsModel.discoveryPort = value
                            }
                        }
                    }
                }

                // --- Etat courant (lecture seule, temps reel) ---------------
                // Masque : la bascule automatique de serveur ne s'affiche plus
                // dans les Parametres (demande explicite). Conserve en place,
                // simplement retabli dans une SettingsSectionCard pour rester
                // coherent avec le reste de l'ecran si un jour reactive.
                SettingsSectionCard {
                    Layout.fillWidth: true
                    visible: false
                    icon: "\uf0e7"
                    title: qsTr("Bascule automatique")

                    RowLayout {
                        spacing: Theme.spacingSmall
                        Label { text: qsTr("Rôle actuel :"); color: Theme.textSecondary }
                        Label {
                            text: root.election ? root.election.roleLabel : ""
                            color: Theme.text
                            font.bold: true
                        }
                    }
                    RowLayout {
                        spacing: Theme.spacingSmall
                        Label { text: qsTr("Epoch :"); color: Theme.textSecondary }
                        Label { text: root.election ? root.election.epoch : ""; color: Theme.text }
                    }
                    RowLayout {
                        spacing: Theme.spacingSmall
                        Label { text: qsTr("Serveur actif :"); color: Theme.textSecondary }
                        Label {
                            text: (root.election && root.election.activeServerUuid.length > 0)
                                  ? root.election.activeServerUuid : qsTr("inconnu")
                            color: Theme.text
                            elide: Text.ElideMiddle
                            Layout.maximumWidth: 260
                        }
                    }
                }

                // --- Reglages (masque : bascule automatique retiree des Parametres) ---
                SettingsSectionCard {
                    Layout.fillWidth: true
                    visible: false
                    icon: "\uf1e6"
                    title: qsTr("Priorité et délai de secours")

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingXs

                        Label {
                            text: qsTr("Priorité de secours")
                            color: Theme.text
                            font.pixelSize: Theme.fontSizeBody
                            font.bold: true
                        }
                        Label {
                            text: qsTr("Plus la valeur est basse, plus ce poste sera choisi en priorité pour prendre le relais en cas de panne du serveur.")
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeSmall
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }

                        RowLayout {
                            spacing: Theme.spacingMedium

                            SpinBox {
                                id: priorityWeightSpin
                                from: 1
                                to: 1000
                                stepSize: 10
                                editable: true
                                value: root.election ? root.election.priorityWeight : 100

                                // On evite d'ecraser la saisie de l'utilisateur par
                                // le binding temps reel : la valeur n'est
                                // resynchronisee sur electionService.priorityWeight
                                // que quand ce dernier change ailleurs (ex. un autre
                                // poste admin a modifie le reglage).
                                Connections {
                                    target: root.election
                                    function onPriorityWeightChanged() {
                                        if (root.election)
                                            priorityWeightSpin.value = root.election.priorityWeight
                                    }
                                }
                            }

                            Button {
                                text: qsTr("Appliquer")
                                Layout.preferredHeight: 32

                                background: Rectangle {
                                    radius: Theme.radiusSmall
                                    color: parent.hovered ? Theme.primaryHover : Theme.primary
                                }
                                contentItem: Text {
                                    text: qsTr("Appliquer")
                                    color: Theme.primaryText
                                    font.pixelSize: Theme.fontSizeSmall
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }

                                onClicked: {
                                    if (root.app)
                                        root.app.setElectionPriorityWeight(priorityWeightSpin.value)
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingXs

                        Label {
                            text: qsTr("Délai avant bascule")
                            color: Theme.text
                            font.pixelSize: Theme.fontSizeBody
                            font.bold: true
                        }
                        Label {
                            text: qsTr("Temps sans nouvelle du serveur avant qu'un poste de secours prenne le relais.")
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeSmall
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }

                        RowLayout {
                            spacing: Theme.spacingMedium

                            SpinBox {
                                id: timeoutSecondsSpin
                                from: 5
                                to: 300
                                stepSize: 5
                                editable: true
                                value: root.election ? Math.round(root.election.heartbeatTimeoutMs / 1000) : 15

                                Connections {
                                    target: root.election
                                    function onHeartbeatTimeoutMsChanged() {
                                        if (root.election)
                                            timeoutSecondsSpin.value = Math.round(root.election.heartbeatTimeoutMs / 1000)
                                    }
                                }
                            }
                            Label { text: qsTr("secondes"); color: Theme.textSecondary }

                            Button {
                                text: qsTr("Appliquer")
                                Layout.preferredHeight: 32

                                background: Rectangle {
                                    radius: Theme.radiusSmall
                                    color: parent.hovered ? Theme.surfaceAlt : "transparent"
                                    border.width: 1
                                    border.color: Theme.border
                                }
                                contentItem: Text {
                                    text: qsTr("Appliquer")
                                    color: Theme.text
                                    font.pixelSize: Theme.fontSizeSmall
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }

                                onClicked: {
                                    if (root.election)
                                        root.election.heartbeatTimeoutMs = timeoutSecondsSpin.value * 1000
                                }
                            }
                        }
                    }
                }

                Item { Layout.preferredHeight: Theme.spacingSmall }
            }
        }

        // ---- Barre d'actions unique, fixe en bas de l'ecran ----------------
        // Remplace les boutons Annuler/Enregistrer auparavant dupliques dans
        // chaque carte : settingsModel.save()/load() portent sur l'ensemble
        // des reglages (une seule QSettings), donc une seule paire de
        // boutons suffit et evite la confusion (cf. commentaire d'en-tete).
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 64
            color: Theme.surface

            Rectangle {
                anchors.top: parent.top
                width: parent.width
                height: 1
                color: Theme.border
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.spacingLarge
                anchors.rightMargin: Theme.spacingLarge
                spacing: Theme.spacingMedium

                Item { Layout.fillWidth: true }

                Button {
                    text: qsTr("Annuler")
                    Layout.preferredHeight: 36
                    Layout.preferredWidth: 110

                    background: Rectangle {
                        radius: Theme.radiusSmall
                        color: parent.hovered ? Theme.surfaceAlt : "transparent"
                        border.width: 1
                        border.color: Theme.border
                    }
                    contentItem: Text {
                        text: qsTr("Annuler")
                        color: Theme.text
                        font.pixelSize: Theme.fontSizeSmall
                        font.family: Theme.fontFamily
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    onClicked: settingsModel.load()
                }

                Button {
                    text: qsTr("Enregistrer")
                    Layout.preferredHeight: 36
                    Layout.preferredWidth: 130

                    background: Rectangle {
                        radius: Theme.radiusSmall
                        color: parent.hovered ? Theme.primaryHover : Theme.primary
                    }
                    contentItem: Text {
                        text: qsTr("Enregistrer")
                        color: Theme.primaryText
                        font.pixelSize: Theme.fontSizeSmall
                        font.family: Theme.fontFamily
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    onClicked: settingsModel.save()
                }
            }
        }
    }

    // Convertit l'URL renvoyee par FolderDialog (ex. "file:///C:/Users/...")
    // en chemin systeme brut - meme logique que SharedFolderView.qml.
    // Necessaire car defaultDownloadPath/defaultSharedFolderPath sont
    // desormais consommes tels quels par du C++ (QDir) et par
    // createDialog.localPath, qui attendent un chemin, pas une URL.
    function pathFromFolderUrl(url) {
        let path = decodeURIComponent(url.toString())
        path = path.replace(/^file:\/\//, "")
        if (/^\/[A-Za-z]:/.test(path)) {
            path = path.substring(1)
        }
        return path
    }

    FolderDialog {
        id: settingsFolderDialog
        title: qsTr("Sélectionner le répertoire de téléchargement")
        currentFolder: settingsModel.defaultDownloadPath
        onAccepted: {
            settingsModel.defaultDownloadPath = root.pathFromFolderUrl(selectedFolder)
        }
    }

    FolderDialog {
        id: settingsSharedFolderDialog
        title: qsTr("Sélectionner le répertoire de partage par défaut")
        currentFolder: settingsModel.defaultSharedFolderPath
        onAccepted: {
            settingsModel.defaultSharedFolderPath = root.pathFromFolderUrl(selectedFolder)
        }
    }
}
