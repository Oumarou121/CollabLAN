import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import Themes
import "../Components"

/*
 * SettingsView - page Parametres (tous utilisateurs), organisee en
 * categories : navigation laterale (liste deroulante en fenetre etroite)
 * et contenu en colonne de largeur maximale.
 *
 *   - Apparence : theme clair/sombre/systeme, couleur d'accent, taille du
 *     texte, densite, barre laterale reduite. Applique immediatement et
 *     persiste par le singleton Theme (QSettings "Appearance").
 *   - Ce poste et dossiers : nom du poste, repertoires par defaut.
 *     defaultDownloadPath est applique a network::TransferService (voir
 *     main.cpp) ; defaultSharedFolderPath est propose a la creation d'un
 *     dossier partage.
 *   - Notifications et sons : enableNotifications (settingsModel, branche
 *     sur core::NotificationManager) ; sons et volume via audioService,
 *     appliques immediatement.
 *   - Compte et securite : changement du mot de passe (verification cote
 *     UserManager::changeOwnPassword).
 *   - Reseau : role du poste (promotion/retour client, confirmes) et ports
 *     reseau, ces derniers reserves aux administrateurs.
 *
 * Les reglages portes par settingsModel ne sont ecrits qu'a
 * l'enregistrement : une seule barre "Annuler / Enregistrer" en bas de
 * page, affichee seulement pour les categories concernees (save()/load()
 * portent sur l'integralite des reglages).
 *
 * La section "Bascule automatique de serveur" reste masquee (visible:
 * false) sur demande.
 */
Item {
    id: root
    objectName: "settingsView"

    signal backRequested()

    property bool isAdmin: (typeof userManager !== "undefined" && userManager) ? userManager.currentUserIsAdmin : false
    property var election: (typeof electionService !== "undefined") ? electionService : null
    property var app: (typeof application !== "undefined") ? application : null

    // Categorie affichee (navigation laterale de la page).
    property string category: "appearance"

    readonly property var categories: [
        { key: "appearance", label: qsTr("Apparence"), glyph: "",
          hint: qsTr("Thème, couleur d'accent, taille du texte et densité") },
        { key: "machine", label: qsTr("Ce poste et dossiers"), glyph: "",
          hint: qsTr("Nom du poste, dossiers de téléchargement et de partage") },
        { key: "notifications", label: qsTr("Notifications et sons"), glyph: "",
          hint: qsTr("Alertes du bureau, sons et volume") },
        { key: "account", label: qsTr("Compte et sécurité"), glyph: "",
          hint: qsTr("Mot de passe de votre compte") },
        { key: "network", label: qsTr("Réseau"), glyph: "",
          hint: root.isAdmin ? qsTr("Rôle du poste et ports réseau") : qsTr("Rôle du poste sur le réseau") }
    ]

    readonly property int currentCategoryIndex: {
        for (let i = 0; i < categories.length; i++)
            if (categories[i].key === category) return i
        return 0
    }
    readonly property var currentCategory: categories[currentCategoryIndex]

    // Fil d'Ariane (AppShell) : Parametres > <categorie>.
    readonly property string breadcrumbLeaf: currentCategory.label

    // Les reglages de ces categories passent par settingsModel et ne sont
    // ecrits qu'a l'enregistrement ; Apparence, sons et mot de passe
    // s'appliquent immediatement.
    readonly property bool usesSaveBar: category === "machine" || category === "notifications"
                                        || (category === "network" && isAdmin)

    readonly property bool narrow: width < 860

    Rectangle {
        anchors.fill: parent
        color: Theme.bg
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        AppHeader {
            Layout.fillWidth: true
            title: qsTr("Paramètres")
            subtitle: root.currentCategory.hint
        }

        // Navigation par categorie en fenetre etroite : liste deroulante.
        AppComboBox {
            visible: root.narrow
            Layout.fillWidth: true
            Layout.leftMargin: Theme.pagePadding
            Layout.rightMargin: Theme.pagePadding
            Layout.bottomMargin: Theme.spacingMedium
            model: root.categories
            textRole: "label"
            valueRole: "key"
            currentIndex: root.currentCategoryIndex
            Accessible.name: qsTr("Catégorie de paramètres")
            onActivated: function(index) { root.category = root.categories[index].key }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Theme.spacingLarge

            // Navigation par categorie : liste a gauche.
            Column {
                id: categoryNav
                visible: !root.narrow
                Layout.preferredWidth: 236
                Layout.fillHeight: true
                Layout.leftMargin: Theme.pagePadding
                spacing: 2

                Accessible.role: Accessible.List
                Accessible.name: qsTr("Catégories de paramètres")

                Repeater {
                    model: root.categories

                    delegate: AbstractButton {
                        id: catItem
                        required property var modelData
                        readonly property bool current: root.category === catItem.modelData.key

                        width: categoryNav.width
                        height: Theme.navItemHeight
                        hoverEnabled: true
                        focusPolicy: Qt.TabFocus
                        Accessible.role: Accessible.PageTab
                        Accessible.name: catItem.modelData.label
                        Accessible.selected: catItem.current
                        onClicked: root.category = catItem.modelData.key

                        HoverHandler { cursorShape: Qt.PointingHandCursor }

                        background: Rectangle {
                            radius: Theme.radiusControl
                            color: catItem.current ? Theme.accentSoft
                                 : (catItem.hovered ? Theme.hover : "transparent")

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: -2
                                radius: parent.radius + 2
                                color: "transparent"
                                border.width: 2
                                border.color: Theme.focusRing
                                visible: catItem.visualFocus
                            }
                        }

                        contentItem: RowLayout {
                            spacing: 10
                            FaIcon {
                                Layout.leftMargin: 12
                                Layout.preferredWidth: 18
                                glyph: catItem.modelData.glyph
                                color: catItem.current ? Theme.navActiveInk : Theme.ink3
                                font.pixelSize: Theme.fs(14)
                                horizontalAlignment: Text.AlignHCenter
                            }
                            Text {
                                Layout.fillWidth: true
                                text: catItem.modelData.label
                                color: catItem.current ? Theme.navActiveInk : Theme.ink2
                                font.pixelSize: Theme.fs(13)
                                font.weight: catItem.current ? Theme.weightSemibold : Theme.weightRegular
                                font.family: Theme.fontFamily
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }

        Flickable {
            id: settingsFlickable
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            contentHeight: contentColumn.implicitHeight + Theme.spacingXl
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            // Retour en haut a chaque changement de categorie.
            Connections {
                target: root
                function onCategoryChanged() { settingsFlickable.contentY = 0 }
            }

            ColumnLayout {
                id: contentColumn
                width: Math.min(parent.width - (root.narrow ? 2 : 1) * Theme.pagePadding, 760)
                x: root.narrow ? Theme.pagePadding : 0
                y: 0
                spacing: Theme.spacingLarge

                AppearanceSettings {
                    visible: root.category === "appearance"
                    Layout.fillWidth: true
                }

                // --- Preferences generales (telechargement + partage) ------
                SettingsSectionCard {
                    visible: root.category === "machine"
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

                            AppTextField {
                                Layout.fillWidth: true
                                text: settingsModel.defaultDownloadPath
                                onTextChanged: settingsModel.defaultDownloadPath = text
                            }

                            AppButton {
                                text: qsTr("Parcourir…")
                                tooltip: qsTr("Choisir un dossier")
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

                            AppTextField {
                                Layout.fillWidth: true
                                text: settingsModel.defaultSharedFolderPath
                                onTextChanged: settingsModel.defaultSharedFolderPath = text
                            }

                            AppButton {
                                text: qsTr("Parcourir…")
                                tooltip: qsTr("Choisir un dossier")
                                onClicked: settingsSharedFolderDialog.open()
                            }
                        }
                    }
                }

                // --- Identite du poste + theme -----------------------------
                // Le README annonce depuis le debut des reglages "nom du poste"
                // et "theme" : le theme existait (Theme.darkMode, persiste) mais
                // n'etait accessible que via le bouton d'en-tete, et le nom du
                // poste n'existait pas du tout (QHostInfo::localHostName() fige,
                // donc deux "DESKTOP-xxxx" indiscernables dans la liste des pairs).
                SettingsSectionCard {
                    visible: root.category === "machine"
                    Layout.fillWidth: true
                    icon: "\uf109"
                    title: qsTr("Ce poste")
                    subtitle: qsTr("Nom affiché aux autres postes du réseau local.")

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingSmall

                        AppTextField {
                            Layout.fillWidth: true
                            label: qsTr("Nom du poste")
                            placeholderText: Qt.application.name
                            text: settingsModel.machineName
                            onTextChanged: settingsModel.machineName = text
                        }

                        Label {
                            text: qsTr("Laissé vide, le nom réseau de la machine est utilisé.")
                            color: Theme.textTertiary
                            font.pixelSize: Theme.fontSizeCaption
                            font.family: Theme.fontFamily
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }

                    }
                }

                // --- Notifications -------------------------------------------
                // Reorganisation : une carte par sujet (Notifications / Sons /
                // Son par categorie) plutot qu'une seule carte melangeant les
                // trois, pour rester scannable en un coup d'oeil.
                SettingsSectionCard {
                    visible: root.category === "notifications"
                    Layout.fillWidth: true
                    icon: "\uf0f3"
                    title: qsTr("Notifications")
                    subtitle: qsTr("Contrôlez les alertes affichées pour les nouveaux messages, transferts et connexions.")

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

                        AppSwitch {
                            checked: settingsModel.enableNotifications
                            onCheckedChanged: settingsModel.enableNotifications = checked
                        }
                    }
                }

                // --- Sons : activation + volume --------------------------------
                SettingsSectionCard {
                    visible: root.category === "notifications"
                    Layout.fillWidth: true
                    icon: "\uf028"
                    title: qsTr("Sons")
                    subtitle: qsTr("Activez les sons et réglez leur volume.")

                    // (audioService : switch + volume, seule source de verite -
                    // anciennement dupliquee avec une case a cocher
                    // settingsModel.enableSounds qui ne pilotait rien)
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
                        AppSwitch {
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

                        AppSlider {
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

                // --- Son par categorie (3 variantes chacune) --------------------
                // Sa propre carte : c'est un choix (quel son) distinct de
                // l'interrupteur general "Sons actives" de la carte precedente,
                // donc plus facile a retrouver separement. Design maquette
                // validee : icone + selecteur segmente "pilule" + bouton
                // d'ecoute separe. Un clic sur une option selectionne la
                // variante (persistee via audioService.set*Sound, cf.
                // AudioService.cpp) ; le bouton lecteur joue un apercu sans
                // changer la selection courante (previewSound, ignore
                // soundEnabled pour permettre l'ecoute meme interrupteur
                // desactive).
                SettingsSectionCard {
                    visible: root.category === "notifications"
                    Layout.fillWidth: true
                    icon: "\uf001"
                    title: qsTr("Son par catégorie")
                    subtitle: qsTr("Choisissez le son joué pour chaque type d'événement, et écoutez-le avant de valider.")

                    // Regroupes dans un Item neutre : SettingsSectionCard expose
                    // sa propriete par defaut via ".children" (Item uniquement),
                    // alors que FontLoader et Component ne sont pas des Item -
                    // en enfants directs de la carte ca fait planter le
                    // chargement QML ("Cannot assign ... to list property
                    // content"). Un Item wrapper utilise "data" (accepte tout
                    // QObject) et n'affecte pas la mise en page (taille 0x0).
                    Item {
                        FontLoader {
                            id: soundIconFont
                            source: "../Assets/fonts/fontawesome-webfont.ttf"
                        }

                        Component {
                            id: soundCategoryRow

                            ColumnLayout {
                                property string categoryIcon: ""
                                property string categoryLabel: ""
                                property var eventType
                                property var variantLabels: ({})
                                property string currentValue: ""
                                property var selectHandler: function(id) {}

                                Layout.fillWidth: true
                                Layout.topMargin: Theme.spacingSmall
                                Layout.bottomMargin: Theme.spacingSmall
                                spacing: Theme.spacingXs

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Theme.spacingMedium

                                    Rectangle {
                                        Layout.preferredWidth: 32
                                        Layout.preferredHeight: 32
                                        radius: Theme.radiusSmall
                                        color: Theme.surfaceAlt

                                        Label {
                                            anchors.centerIn: parent
                                            text: categoryIcon
                                            font.family: soundIconFont.name
                                            font.pixelSize: Theme.fs(14)
                                            color: Theme.textSecondary
                                        }
                                    }

                                    Label {
                                        Layout.fillWidth: true
                                        text: categoryLabel
                                        color: Theme.text
                                        font.pixelSize: Theme.fontSizeSmall
                                        font.family: Theme.fontFamily
                                    }
                                }

                                // Chaque variante de son est sa propre rangee
                                // (style radio) : un clic sur la rangee
                                // selectionne la variante, et le bouton ▶ de
                                // CETTE rangee ecoute TOUJOURS le son de CETTE
                                // rangee (modelData), jamais currentValue --
                                // c'etait le bug precedent (le bouton jouait
                                // systematiquement la variante selectionnee
                                // au lieu de celle sur laquelle on cliquait).
                                //
                                // On utilise des Item ancres plutot que des
                                // MouseArea anchors.fill: parent posees
                                // directement comme enfants d'un RowLayout :
                                // RowLayout documente ce cas comme "undefined
                                // behavior" pour ses enfants geres, ce qui
                                // pouvait faire mal resoudre les clics.
                                Repeater {
                                    model: (typeof audioService !== "undefined") ? audioService.soundVariants(eventType) : []

                                    Item {
                                        id: variantRow
                                        readonly property bool selected: modelData === currentValue
                                        Layout.fillWidth: true
                                        Layout.leftMargin: 40
                                        Layout.preferredHeight: 34

                                        Rectangle {
                                            anchors.fill: parent
                                            radius: Theme.radiusSmall
                                            color: variantRow.selected ? Theme.surfaceAlt : "transparent"
                                        }

                                        Rectangle {
                                            id: radioOuter
                                            anchors.left: parent.left
                                            anchors.leftMargin: 8
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 16
                                            height: 16
                                            radius: 8
                                            color: "transparent"
                                            border.width: 1.5
                                            border.color: variantRow.selected ? Theme.primary : Theme.border

                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: 8
                                                height: 8
                                                radius: 4
                                                color: Theme.primary
                                                visible: variantRow.selected
                                            }
                                        }

                                        Label {
                                            anchors.left: radioOuter.right
                                            anchors.leftMargin: 10
                                            anchors.right: previewButton.left
                                            anchors.rightMargin: 10
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: variantLabels[modelData] || modelData
                                            font.pixelSize: Theme.fontSizeSmall
                                            font.family: Theme.fontFamily
                                            font.weight: variantRow.selected ? Font.Medium : Font.Normal
                                            color: variantRow.selected ? Theme.text : Theme.textSecondary
                                            elide: Text.ElideRight
                                        }

                                        Item {
                                            anchors.left: parent.left
                                            anchors.right: previewButton.left
                                            anchors.top: parent.top
                                            anchors.bottom: parent.bottom

                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: selectHandler(modelData)
                                            }
                                        }

                                        Rectangle {
                                            id: previewButton
                                            anchors.right: parent.right
                                            anchors.rightMargin: 8
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 26
                                            height: 26
                                            radius: 13
                                            color: Theme.surface
                                            border.width: 1
                                            border.color: Theme.border

                                            Label {
                                                anchors.centerIn: parent
                                                anchors.horizontalCenterOffset: 1
                                                text: "\u25B6"
                                                font.pixelSize: Theme.fontSizeCaption
                                                color: Theme.text
                                            }

                                            MouseArea {
                                                id: previewArea
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                hoverEnabled: true
                                                onClicked: {
                                                    if (typeof audioService !== "undefined")
                                                        audioService.previewSound(eventType, modelData)
                                                }
                                            }
                                            ToolTip.visible: previewArea.containsMouse
                                            ToolTip.text: qsTr("Écouter")
                                        }
                                    }
                                }
                            }
                        }
                    }

                        Loader {
                            sourceComponent: soundCategoryRow
                            Layout.fillWidth: true
                            onLoaded: {
                                item.categoryIcon = "\uf075" /* fa-comment */
                                item.categoryLabel = qsTr("Message")
                                item.eventType = 0 /* AudioService.EventType.Message */
                                item.variantLabels = ({
                                    "soft": qsTr("Douce"),
                                    "pop": qsTr("Pop"),
                                    "bell": qsTr("Clochette")
                                })
                                item.currentValue = Qt.binding(function() {
                                    return (typeof audioService !== "undefined") ? audioService.messageSound : ""
                                })
                                item.selectHandler = function(id) {
                                    if (typeof audioService !== "undefined")
                                        audioService.messageSound = id
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 1
                            color: Theme.line
                        }

                        Loader {
                            sourceComponent: soundCategoryRow
                            Layout.fillWidth: true
                            onLoaded: {
                                item.categoryIcon = "\uf0ec" /* fa-exchange */
                                item.categoryLabel = qsTr("Transfert")
                                item.eventType = 1 /* AudioService.EventType.Transfer */
                                item.variantLabels = ({
                                    "rising": qsTr("Montant"),
                                    "ding": qsTr("Ding"),
                                    "done": qsTr("Terminé")
                                })
                                item.currentValue = Qt.binding(function() {
                                    return (typeof audioService !== "undefined") ? audioService.transferSound : ""
                                })
                                item.selectHandler = function(id) {
                                    if (typeof audioService !== "undefined")
                                        audioService.transferSound = id
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 1
                            color: Theme.line
                        }

                        Loader {
                            sourceComponent: soundCategoryRow
                            Layout.fillWidth: true
                            onLoaded: {
                                item.categoryIcon = "\uf095" /* fa-phone */
                                item.categoryLabel = qsTr("Appel")
                                item.eventType = 2 /* AudioService.EventType.Call */
                                item.variantLabels = ({
                                    "classic": qsTr("Classique"),
                                    "soft": qsTr("Douce"),
                                    "upbeat": qsTr("Rythmée")
                                })
                                item.currentValue = Qt.binding(function() {
                                    return (typeof audioService !== "undefined") ? audioService.callSound : ""
                                })
                                item.selectHandler = function(id) {
                                    if (typeof audioService !== "undefined")
                                        audioService.callSound = id
                                }
                            }
                        }
                    }

                // --- Securite du compte : changement de mot de passe -------
                // Jusqu'ici, seul un administrateur pouvait reinitialiser un
                // mot de passe (UserManager::resetPassword) : l'utilisateur
                // devait donc le recevoir de quelqu'un d'autre et ne pouvait
                // jamais en choisir un connu de lui seul. La verification de
                // l'ancien mot de passe et toutes les regles de validation
                // sont faites en C++ (UserManager::changeOwnPassword), qui
                // renvoie le message a afficher, ou "" en cas de succes.
                SettingsSectionCard {
                    Layout.fillWidth: true
                    visible: root.category === "account" && typeof userManager !== "undefined" && userManager && userManager.authenticated
                    icon: "\uf084"
                    title: qsTr("Sécurité du compte")
                    subtitle: qsTr("Changez le mot de passe de votre compte. Il vous sera demandé à la prochaine connexion.")

                    ColumnLayout {
                        id: passwordForm
                        Layout.fillWidth: true
                        spacing: Theme.spacingSmall

                        // Message renvoye par changeOwnPassword() : vide tant
                        // qu'aucune tentative n'a eu lieu.
                        property string feedback: ""
                        property bool feedbackIsError: true

                        function clearFields() {
                            currentPasswordField.text = ""
                            newPasswordField.text = ""
                            confirmPasswordField.text = ""
                        }

                        AppTextField {
                            id: currentPasswordField
                            Layout.fillWidth: true
                            label: qsTr("Mot de passe actuel")
                            echoMode: TextInput.Password
                            onTextChanged: passwordForm.feedback = ""
                        }

                        AppTextField {
                            id: newPasswordField
                            Layout.fillWidth: true
                            label: qsTr("Nouveau mot de passe")
                            echoMode: TextInput.Password
                            onTextChanged: passwordForm.feedback = ""
                        }

                        AppTextField {
                            id: confirmPasswordField
                            Layout.fillWidth: true
                            label: qsTr("Confirmer le nouveau mot de passe")
                            echoMode: TextInput.Password
                            onTextChanged: passwordForm.feedback = ""
                            onAccepted: if (changePasswordButton.enabled) changePasswordButton.clicked()
                        }

                        Label {
                            visible: passwordForm.feedback !== ""
                            text: passwordForm.feedback
                            color: passwordForm.feedbackIsError ? Theme.dangerInk : Theme.successInk
                            font.pixelSize: Theme.fontSizeSmall
                            font.family: Theme.fontFamily
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }

                        AppButton {
                            id: changePasswordButton
                            text: qsTr("Changer le mot de passe")
                            variant: "primary"
                            enabled: currentPasswordField.text !== ""
                                     && newPasswordField.text !== ""
                                     && confirmPasswordField.text !== ""

                            onClicked: {
                                var error = userManager.changeOwnPassword(currentPasswordField.text,
                                                                          newPasswordField.text,
                                                                          confirmPasswordField.text)
                                passwordForm.feedbackIsError = (error !== "")
                                if (error === "") {
                                    passwordForm.feedback = qsTr("Mot de passe modifié.")
                                    passwordForm.clearFields()
                                } else {
                                    passwordForm.feedback = error
                                }
                            }
                        }
                    }
                }

                // --- Ports reseau (reserve aux administrateurs) -------------
                SettingsSectionCard {
                    Layout.fillWidth: true
                    visible: root.isAdmin && root.category === "network"
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
                            AppSpinBox {
                                groupDigits: false
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
                            AppSpinBox {
                                groupDigits: false
                                Layout.fillWidth: true
                                from: 1024
                                to: 65535
                                value: settingsModel.discoveryPort
                                onValueChanged: settingsModel.discoveryPort = value
                            }
                        }
                    }
                }

                // --- Rôle de ce poste (promotion manuelle en serveur) ------
                SettingsSectionCard {
                    visible: root.category === "network"
                    Layout.fillWidth: true
                    icon: "\uf233"
                    title: qsTr("Rôle de ce poste")

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingXs

                        Label {
                            text: qsTr("Détermine si ce poste coordonne le réseau local (serveur) ou se connecte au serveur d'un autre poste (client).")
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeSmall
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }

                        RowLayout {
                            spacing: Theme.spacingSmall
                            Text {
                                text: qsTr("Rôle actuel")
                                color: Theme.ink2
                                font.pixelSize: Theme.fs(13)
                                font.family: Theme.fontFamily
                            }
                            StatusBadge {
                                text: !root.election ? qsTr("Inconnu")
                                    : root.election.roleLabel === "SERVER" ? qsTr("Serveur")
                                    : root.election.roleLabel === "TEMP_SERVER" ? qsTr("Serveur de secours")
                                    : qsTr("Client")
                                tone: root.election && root.election.roleLabel === "TEMP_SERVER" ? "warning"
                                    : (root.election && root.election.roleLabel === "SERVER" ? "accent" : "neutral")
                            }
                        }

                        RowLayout {
                            Layout.topMargin: 6
                            spacing: 8
                            AppButton {
                                text: qsTr("Faire de ce poste le serveur")
                                variant: "secondary"
                                enabled: root.election && root.election.roleLabel !== "SERVER"
                                onClicked: promoteToServerDialog.open()
                            }
                            AppButton {
                                text: qsTr("Redevenir client")
                                variant: "dangerGhost"
                                enabled: root.election && root.election.roleLabel !== "CLIENT"
                                onClicked: demoteToClientDialog.open()
                            }
                        }

                        Label {
                            text: qsTr("Un seul poste devrait avoir ce rôle. Les autres postes doivent rester clients.")
                            color: Theme.textTertiary
                            font.pixelSize: Theme.fontSizeSmall
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                    }
                }

                ConfirmDialog {
                    id: promoteToServerDialog
                    title: qsTr("Faire de ce poste le serveur ?")
                    message: qsTr("Ce poste va accepter les connexions des autres postes. Vérifiez qu'aucun autre poste n'a déjà ce rôle sur le réseau.")
                    confirmText: qsTr("Devenir serveur")
                    onConfirmed: if (root.app) root.app.promoteToServer()
                }

                ConfirmDialog {
                    id: demoteToClientDialog
                    title: qsTr("Redevenir client ?")
                    message: qsTr("Ce poste va cesser d'accepter les connexions. Assurez-vous qu'un autre poste a été désigné serveur, sinon plus aucun poste n'écoutera sur le réseau.")
                    confirmText: qsTr("Redevenir client")
                    destructive: true
                    onConfirmed: if (root.app) root.app.demoteToClient()
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
        }

        // ---- Barre d'actions unique, fixe en bas de l'ecran ----------------
        // settingsModel.save()/load() portent sur l'ensemble des reglages
        // (une seule QSettings) : une seule paire de boutons, affichee
        // uniquement pour les categories concernees.
        Rectangle {
            visible: root.usesSaveBar
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.compact ? 56 : 64
            color: Theme.surface0

            Rectangle {
                anchors.top: parent.top
                width: parent.width
                height: 1
                color: Theme.line
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.pagePadding
                anchors.rightMargin: Theme.pagePadding
                spacing: Theme.spacingMedium

                FaIcon {
                    visible: saveConfirmation.visible
                    glyph: ""
                    color: Theme.successInk
                    font.pixelSize: Theme.fs(13)
                }
                Text {
                    id: saveConfirmation
                    visible: false
                    Layout.fillWidth: true
                    text: qsTr("Paramètres enregistrés")
                    color: Theme.successInk
                    font.pixelSize: Theme.fs(13)
                    font.weight: Theme.weightMedium
                    font.family: Theme.fontFamily
                }
                Text {
                    visible: !saveConfirmation.visible
                    Layout.fillWidth: true
                    text: qsTr("Les modifications de cette page ne sont appliquées qu'après l'enregistrement.")
                    color: Theme.ink3
                    font.pixelSize: Theme.fs(12)
                    font.family: Theme.fontFamily
                    elide: Text.ElideRight
                }

                Timer {
                    id: saveConfirmationTimer
                    interval: 2500
                    onTriggered: saveConfirmation.visible = false
                }

                AppButton {
                    text: qsTr("Annuler les modifications")
                    variant: "ghost"
                    tooltip: qsTr("Recharger les derniers paramètres enregistrés")
                    onClicked: {
                        settingsModel.load()
                        saveConfirmationTimer.stop()
                        saveConfirmation.visible = false
                    }
                }

                AppButton {
                    text: qsTr("Enregistrer")
                    variant: "primary"
                    iconGlyph: ""
                    onClicked: {
                        settingsModel.save()
                        saveConfirmation.visible = true
                        saveConfirmationTimer.restart()
                    }
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
