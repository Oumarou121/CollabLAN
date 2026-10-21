import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import "../Components"

/*
 * LoginView - ecran "Login" (issue #6 : navigation de base Login -> Home)
 *
 * Emet loginSucceeded(username) lorsque l'authentification reussit.
 * Le formulaire delegue la verification a core::UserManager (issue #16),
 * expose depuis app/main.cpp comme propriete de contexte "userManager" :
 * il n'y a plus de validation "mock" locale, seule une authentification
 * reelle contre la base Users permet d'acceder a l'ecran Home.
 *
 * Mise en page en deux volets : panneau de marque a gauche, formulaire
 * dans une carte a droite ; sous 900 px le panneau de marque disparait.
 * Toute la logique d'authentification est inchangee.
 */
Item {
    id: root

    signal loginSucceeded(string username)

    // Bascule "afficher le mot de passe"
    property bool showPassword: false

    // "Se souvenir de moi" - persiste uniquement le nom d'utilisateur
    // (jamais le mot de passe) via core::SettingsModel/QSettings
    // (settingsModel.rememberedUsername, expose depuis app/main.cpp).
    // UserManager::login(username, password) n'a pas de flag de session
    // persistante cote C++ ; ce mecanisme reste donc purement local au
    // formulaire (pre-remplissage du champ, pas de "rester connecte").
    property bool rememberMe: false

    // Garde-fou : ne devient true que le temps d'un login() declenche
    // depuis CE formulaire (attemptLogin ci-dessous). Necessaire car cette
    // instance de LoginView reste vivante (StackView.push ne la detruit
    // pas) meme apres l'auto-login au demarrage (Main.qml) : sans ce
    // garde-fou, ses Connections{ target: userManager } ci-dessous
    // reagiraient AUSSI a l'auto-login (qui emet le meme signal C++
    // loginSucceeded pour que Application/SharedFolderContext s'initialisent),
    // regenerant un jeton "Se souvenir de moi" et re-empilant un second
    // ecran Home a chaque demarrage.
    property bool manualLoginPending: false

    // Bascule a chaque nouvelle erreur : sert de "trigger" pour lancer le
    // shake + la surbrillance rouge des champs (voir shakeAnim ci-dessous).
    property bool errorPulse: false

    // Sous ce seuil, le panneau de marque se replie pour laisser toute la
    // place au formulaire (petite fenetre / usage mobile-like).
    readonly property bool showBrandPanel: root.width >= 900

    // Logique de connexion partagee entre le clic sur le bouton et la
    // touche Entree dans le champ mot de passe (corrige l'appel invalide
    // loginButton.clicked() sur un Rectangle, qui n'a pas ce signal).
    function attemptLogin() {
        if (userManager.busy)
            return

        const username = usernameAppField.text.trim()
        const password = passwordAppField.text

        if (username.length === 0 || password.length === 0) {
            errorLabel.text = qsTr("Merci de renseigner un nom d'utilisateur et un mot de passe.")
            root.errorPulse = !root.errorPulse
            return
        }

        errorLabel.text = ""
        root.manualLoginPending = true
        userManager.login(username, password)
    }

    // ---- Panneau de marque -------------------------------------------------
    // Fond profond et fixe (identite produit), independant du theme ; textes
    // clairs verifies en contraste AA sur ce fond (#F5F7FA : 15.6:1,
    // #B9C6D6 : 9.4:1).
    readonly property color brandBg: Theme.darkMode ? "#121B2E" : "#0F2747"
    readonly property color brandInk: "#F5F7FA"
    readonly property color brandInkMuted: "#B9C6D6"
    readonly property color brandMark: Theme.accentPalettes[Theme.accentName].dark[1]

    readonly property bool hasPendingServer: typeof application !== "undefined" && application
                                             && application.pendingServerFingerprint.length > 0
    readonly property bool needsInitialAdmin: typeof application !== "undefined" && application
                                              && application.needsInitialAdmin
    readonly property bool loginBusy: typeof userManager !== "undefined" && userManager && userManager.busy === true

    Rectangle {
        anchors.fill: parent
        color: Theme.bg
    }

    // Focus automatique sur le champ nom d'utilisateur des l'ouverture de
    // l'ecran, pour eviter a l'utilisateur d'avoir a cliquer avant de
    // pouvoir taper. Qt.callLater garantit que le layout (formCard,
    // formColumn) est bien construit avant de tenter le focus.
    // Pre-remplit aussi le nom d'utilisateur memorise (case "Se souvenir
    // de moi" cochee lors d'une connexion precedente), le cas echeant.
    Component.onCompleted: {
        const remembered = (typeof settingsModel !== "undefined" && settingsModel)
                ? settingsModel.rememberedUsername : ""
        if (remembered.length > 0) {
            usernameAppField.text = remembered
            root.rememberMe = true
            Qt.callLater(passwordAppField.field.forceActiveFocus)
        } else {
            Qt.callLater(usernameAppField.field.forceActiveFocus)
        }
    }

    // ---- Barre d'outils (haut droite) -----------------------------------------
    RowLayout {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: Theme.spacingLarge
        z: 10
        spacing: Theme.spacingSmall

        // Accessible sans session : la confiance envers le certificat d'un
        // serveur est une decision locale de connexion, pas une action d'admin.
        AppButton {
            visible: root.hasPendingServer
            variant: "soft"
            iconGlyph: ""
            text: qsTr("Serveur à approuver")
            tooltip: qsTr("Vérifier le certificat du serveur détecté")
            onClicked: serverTrustDialog.open()
        }

        AppButton {
            variant: "ghost"
            iconGlyph: ""
            text: qsTr("Mode réseau")
            tooltip: qsTr("Rôle de ce poste sur le réseau local")
            onClicked: networkModeDialog.open()
        }

        ThemeToggleButton {}
    }

    // ---- Mode reseau de ce poste ------------------------------------------------
    AppDialog {
        id: networkModeDialog
        title: qsTr("Mode réseau de ce poste")
        headerIcon: ""
        dialogWidth: 480

        readonly property string role: (typeof electionService !== "undefined" && electionService)
                                        ? electionService.roleLabel : ""

        ColumnLayout {
            anchors.fill: parent
            spacing: Theme.spacingMedium

            RowLayout {
                spacing: Theme.spacingSmall
                Text {
                    text: qsTr("Rôle actuel")
                    color: Theme.ink2
                    font.pixelSize: Theme.fs(13)
                    font.family: Theme.fontFamily
                }
                StatusBadge {
                    tone: networkModeDialog.role === "SERVER" ? "accent"
                        : networkModeDialog.role === "TEMP_SERVER" ? "warning"
                        : networkModeDialog.role === "CLIENT" ? "neutral" : "neutral"
                    text: networkModeDialog.role === "SERVER" ? qsTr("Serveur")
                        : networkModeDialog.role === "TEMP_SERVER" ? qsTr("Serveur de secours")
                        : networkModeDialog.role === "CLIENT" ? qsTr("Client") : qsTr("Inconnu")
                }
            }

            Text {
                Layout.fillWidth: true
                text: qsTr("En mode serveur, ce poste accepte les connexions des autres machines du réseau. En mode client, il se connecte au serveur détecté sur le réseau.")
                wrapMode: Text.WordWrap
                color: Theme.ink2
                font.pixelSize: Theme.fs(13)
                font.family: Theme.fontFamily
            }

            Rectangle {
                visible: typeof application !== "undefined" && application && application.pendingClientCount > 0
                Layout.fillWidth: true
                implicitHeight: pendingText.implicitHeight + 20
                radius: Theme.radiusControl
                color: Theme.infoSoft

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8
                    FaIcon {
                        Layout.alignment: Qt.AlignTop
                        glyph: ""
                        color: Theme.infoInk
                        font.pixelSize: Theme.fs(13)
                    }
                    Text {
                        id: pendingText
                        Layout.fillWidth: true
                        text: (typeof application !== "undefined" && application)
                              ? qsTr("%n poste(s) en attente d'autorisation. Connectez-vous avec un compte administrateur pour les examiner.", "", application.pendingClientCount)
                              : ""
                        wrapMode: Text.WordWrap
                        color: Theme.infoInk
                        font.pixelSize: Theme.fs(12)
                        font.family: Theme.fontFamily
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Theme.spacingSmall
                spacing: Theme.spacingSmall

                Item { Layout.fillWidth: true }

                AppButton {
                    text: qsTr("Passer en client")
                    enabled: networkModeDialog.role !== "CLIENT"
                    onClicked: becomeClientConfirm.open()
                }
                AppButton {
                    variant: "primary"
                    text: qsTr("Passer en serveur")
                    enabled: networkModeDialog.role !== "SERVER"
                    onClicked: becomeServerConfirm.open()
                }
            }
        }
    }

    ConfirmDialog {
        id: becomeServerConfirm
        title: qsTr("Faire de ce poste le serveur ?")
        message: qsTr("Les autres postes du réseau se connecteront à cette machine.")
        detail: qsTr("Un seul poste devrait être serveur sur le réseau local.")
        confirmText: qsTr("Passer en serveur")
        onConfirmed: {
            application.promoteToServer()
            networkModeDialog.close()
        }
    }

    ConfirmDialog {
        id: becomeClientConfirm
        title: qsTr("Repasser ce poste en client ?")
        message: qsTr("Ce poste cessera d'accepter les connexions et se connectera au serveur détecté sur le réseau.")
        confirmText: qsTr("Passer en client")
        destructive: true
        onConfirmed: {
            application.demoteToClient()
            networkModeDialog.close()
        }
    }

    // ---- Approbation du certificat d'un serveur inconnu -------------------------
    AppDialog {
        id: serverTrustDialog
        title: qsTr("Approuver ce serveur ?")
        headerIcon: ""
        headerTone: "warning"
        dialogWidth: 540

        ColumnLayout {
            anchors.fill: parent
            spacing: Theme.spacingMedium

            Text {
                Layout.fillWidth: true
                text: qsTr("Ce serveur présente un certificat encore inconnu sur ce poste. Comparez son empreinte avec celle affichée par la personne qui administre le serveur avant de l'approuver.")
                wrapMode: Text.WordWrap
                color: Theme.ink2
                font.pixelSize: Theme.fs(13)
                font.family: Theme.fontFamily
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: Theme.spacingMedium
                rowSpacing: 6

                Text {
                    text: qsTr("Adresse")
                    color: Theme.ink3
                    font.pixelSize: Theme.fs(12)
                    font.family: Theme.fontFamily
                }
                Text {
                    Layout.fillWidth: true
                    text: root.hasPendingServer
                          ? application.pendingServerAddress + ":" + application.pendingServerPort : ""
                    color: Theme.ink
                    font.pixelSize: Theme.fs(13)
                    font.family: Theme.fontFamily
                }
                Text {
                    Layout.alignment: Qt.AlignTop
                    Layout.topMargin: 8
                    text: qsTr("Empreinte")
                    color: Theme.ink3
                    font.pixelSize: Theme.fs(12)
                    font.family: Theme.fontFamily
                }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: fingerprintText.implicitHeight + 16
                    radius: Theme.radiusControl
                    color: Theme.sunken
                    border.width: 1
                    border.color: Theme.line

                    TextEdit {
                        id: fingerprintText
                        anchors.fill: parent
                        anchors.margins: 8
                        text: root.hasPendingServer ? application.pendingServerFingerprint : ""
                        readOnly: true
                        selectByMouse: true
                        wrapMode: TextEdit.WrapAnywhere
                        font.family: "Consolas"
                        font.pixelSize: Theme.fs(12)
                        color: Theme.ink
                        selectionColor: Theme.accentColor
                        selectedTextColor: Theme.accentInk
                        Accessible.name: qsTr("Empreinte du certificat du serveur")
                    }
                }
            }

            Rectangle {
                visible: trustError.text.length > 0
                Layout.fillWidth: true
                implicitHeight: trustError.implicitHeight + 20
                radius: Theme.radiusControl
                color: Theme.dangerSoft

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8
                    FaIcon {
                        Layout.alignment: Qt.AlignTop
                        glyph: ""
                        color: Theme.dangerInk
                        font.pixelSize: Theme.fs(13)
                    }
                    Text {
                        id: trustError
                        Layout.fillWidth: true
                        text: ""
                        color: Theme.dangerInk
                        wrapMode: Text.WordWrap
                        font.pixelSize: Theme.fs(12)
                        font.family: Theme.fontFamily
                        Accessible.role: Accessible.AlertMessage
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Theme.spacingSmall
                spacing: Theme.spacingSmall

                Item { Layout.fillWidth: true }

                AppButton {
                    text: qsTr("Annuler")
                    variant: "ghost"
                    onClicked: serverTrustDialog.close()
                }
                AppButton {
                    variant: "primary"
                    iconGlyph: ""
                    text: qsTr("Approuver ce serveur")
                    // Le dialogue reste ouvert en cas d'echec pour que
                    // l'erreur soit lisible.
                    onClicked: {
                        if (application.approvePendingServerCertificate()) {
                            trustError.text = ""
                            serverTrustDialog.close()
                        } else {
                            trustError.text = qsTr("Impossible d'approuver ce certificat. Relancez la connexion au serveur puis réessayez.")
                        }
                    }
                }
            }
        }
    }

    Connections {
        target: (typeof application !== "undefined") ? application : null

        function onPendingServerChanged() {
            if (application.pendingServerFingerprint.length > 0) {
                trustError.text = ""
                serverTrustDialog.open()
            }
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ---------------------------------------------------------------
        // Panneau gauche : marque + proposition de valeur produit
        // ---------------------------------------------------------------
        Rectangle {
            id: brandPanel
            visible: root.showBrandPanel
            Layout.fillHeight: true
            Layout.preferredWidth: Math.min(root.width * 0.42, 620)
            color: root.brandBg
            clip: true

            // Motif discret de reseau (noeuds relies), rappel de la carte
            // reseau de l'application.
            Canvas {
                anchors.fill: parent
                opacity: 0.55
                onPaint: {
                    const ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    const step = 56
                    ctx.fillStyle = "rgba(185,198,214,0.16)"
                    for (let x = step / 2; x <= width; x += step) {
                        for (let y = step / 2; y <= height; y += step) {
                            ctx.beginPath(); ctx.arc(x, y, 1.4, 0, Math.PI * 2); ctx.fill()
                        }
                    }
                }
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
            }

            ColumnLayout {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 56
                anchors.rightMargin: 56
                spacing: Theme.spacingXl

                RowLayout {
                    spacing: 12

                    BrandMark {
                        size: 48
                    }

                    Text {
                        text: "LocaLink"
                        font.pixelSize: Theme.fs(26)
                        font.weight: Theme.weightBold
                        font.family: Theme.fontFamily
                        color: root.brandInk
                    }
                }

                Text {
                    text: qsTr("La collaboration de votre équipe, entièrement sur votre réseau local.")
                    font.pixelSize: Theme.fs(26)
                    font.weight: Theme.weightSemibold
                    font.family: Theme.fontFamily
                    color: root.brandInk
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                    lineHeight: 1.2
                }

                Text {
                    text: qsTr("Aucune dépendance à Internet : vos messages, fichiers et appels restent sur votre réseau.")
                    font.pixelSize: Theme.fs(15)
                    font.family: Theme.fontFamily
                    color: root.brandInkMuted
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                    lineHeight: 1.3
                }

                ColumnLayout {
                    Layout.topMargin: Theme.spacingSmall
                    spacing: 14

                    Repeater {
                        model: [
                            { glyph: "", label: qsTr("Découverte automatique des postes du réseau") },
                            { glyph: "", label: qsTr("Messagerie individuelle et de groupe") },
                            { glyph: "", label: qsTr("Transferts de fichiers et dossiers partagés") },
                            { glyph: "", label: qsTr("Appels vocaux sur le réseau local") }
                        ]

                        RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 12

                            Rectangle {
                                Layout.preferredWidth: 32
                                Layout.preferredHeight: 32
                                radius: 8
                                color: Qt.rgba(1, 1, 1, 0.08)
                                border.width: 1
                                border.color: Qt.rgba(1, 1, 1, 0.12)

                                FaIcon {
                                    anchors.centerIn: parent
                                    glyph: modelData.glyph
                                    color: root.brandMark
                                    font.pixelSize: Theme.fs(14)
                                }
                            }

                            Text {
                                text: modelData.label
                                font.pixelSize: Theme.fs(14)
                                font.family: Theme.fontFamily
                                color: root.brandInk
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }
                        }
                    }
                }
            }

            RowLayout {
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.leftMargin: 56
                anchors.bottomMargin: 32
                spacing: 8

                FaIcon {
                    glyph: ""
                    color: root.brandInkMuted
                    font.pixelSize: Theme.fs(12)
                }
                Text {
                    text: qsTr("Connexions chiffrées entre les postes autorisés")
                    font.pixelSize: Theme.fs(12)
                    font.family: Theme.fontFamily
                    color: root.brandInkMuted
                }
            }
        }

        // ---------------------------------------------------------------
        // Panneau droit : formulaire dans une carte
        // ---------------------------------------------------------------
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // Premier lancement du serveur principal : aucun compte n'existe encore. Plus de compte
            // "admin"/"admin123" par defaut : la personne qui installe choisit le nom et le mot de
            // passe du premier administrateur (Application::createInitialAdmin).
            Rectangle {
                id: setupCard
                visible: root.needsInitialAdmin
                anchors.centerIn: parent
                width: Math.min(440, parent.width - Theme.spacingXl * 2)
                height: setupColumn.implicitHeight + 72
                radius: Theme.radiusLarge
                color: Theme.surface0
                border.width: 1
                border.color: Theme.line

                function submit() {
                    const error = application.createInitialAdmin(setupName.text, setupPassword.text, setupConfirm.text)
                    setupError.text = error
                    if (error.length === 0) {
                        usernameAppField.text = setupName.text.trim()
                        passwordAppField.text = ""
                    }
                }

                ColumnLayout {
                    id: setupColumn
                    anchors.centerIn: parent
                    width: parent.width - 72
                    spacing: Theme.spacingMedium

                    Rectangle {
                        Layout.preferredWidth: 40
                        Layout.preferredHeight: 40
                        radius: 10
                        color: Theme.accentSoft
                        FaIcon {
                            anchors.centerIn: parent
                            glyph: ""
                            color: Theme.navActiveInk
                            font.pixelSize: Theme.fs(17)
                        }
                    }

                    Text {
                        text: qsTr("Créer le compte administrateur")
                        font.pixelSize: Theme.fs(22)
                        font.weight: Theme.weightSemibold
                        font.family: Theme.fontFamily
                        color: Theme.ink
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                        Accessible.role: Accessible.Heading
                    }
                    Text {
                        text: qsTr("Premier démarrage : choisissez l'identifiant et le mot de passe du premier administrateur du réseau (8 caractères minimum).")
                        font.pixelSize: Theme.fs(13)
                        font.family: Theme.fontFamily
                        color: Theme.ink2
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                        Layout.bottomMargin: Theme.spacingSmall
                    }
                    AppTextField {
                        id: setupName
                        label: qsTr("Nom d'utilisateur")
                        Layout.fillWidth: true
                        onAccepted: setupPassword.field.forceActiveFocus()
                    }
                    AppPasswordField {
                        id: setupPassword
                        label: qsTr("Mot de passe")
                        Layout.fillWidth: true
                        onAccepted: setupConfirm.field.forceActiveFocus()
                    }
                    AppPasswordField {
                        id: setupConfirm
                        label: qsTr("Confirmer le mot de passe")
                        Layout.fillWidth: true
                        onAccepted: setupCard.submit()
                    }
                    Rectangle {
                        visible: setupError.text.length > 0
                        Layout.fillWidth: true
                        implicitHeight: setupError.implicitHeight + 20
                        radius: Theme.radiusControl
                        color: Theme.dangerSoft

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 8
                            FaIcon {
                                Layout.alignment: Qt.AlignTop
                                glyph: ""
                                color: Theme.dangerInk
                                font.pixelSize: Theme.fs(13)
                            }
                            Text {
                                id: setupError
                                Layout.fillWidth: true
                                color: Theme.dangerInk
                                wrapMode: Text.WordWrap
                                font.pixelSize: Theme.fs(12)
                                font.family: Theme.fontFamily
                                Accessible.role: Accessible.AlertMessage
                            }
                        }
                    }
                    AppButton {
                        variant: "primary"
                        size: "large"
                        text: qsTr("Créer le compte")
                        Layout.fillWidth: true
                        Layout.topMargin: Theme.spacingSmall
                        onClicked: setupCard.submit()
                    }
                }
            }

            Rectangle {
                id: formCard
                visible: !root.needsInitialAdmin
                anchors.centerIn: parent
                width: Math.min(420, parent.width - Theme.spacingXl * 2)
                height: formColumn.implicitHeight + 80
                radius: Theme.radiusLarge
                color: Theme.surface0
                border.width: 1
                border.color: Theme.line

                // Elevation douce (deux halos superposes, sans effet graphique).
                Rectangle {
                    z: -1
                    anchors.fill: parent
                    anchors.margins: -1
                    anchors.topMargin: 1
                    anchors.bottomMargin: -3
                    radius: parent.radius + 1
                    color: Theme.alpha(Theme.shadowStrong, 0.10)
                }
                Rectangle {
                    z: -2
                    anchors.fill: parent
                    anchors.margins: -6
                    anchors.topMargin: 2
                    anchors.bottomMargin: -14
                    radius: parent.radius + 6
                    color: Theme.alpha(Theme.shadowStrong, 0.05)
                }

                ColumnLayout {
                    id: formColumn
                    anchors.centerIn: parent
                    width: parent.width - 80
                    spacing: Theme.spacingMedium

                    // Identite produit quand le panneau de marque est replie.
                    RowLayout {
                        visible: !root.showBrandPanel
                        Layout.bottomMargin: Theme.spacingSmall
                        spacing: 10

                        BrandMark {
                            size: 36
                        }

                        Text {
                            text: "LocaLink"
                            font.pixelSize: Theme.fs(20)
                            font.weight: Theme.weightBold
                            font.family: Theme.fontFamily
                            color: Theme.ink
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.bottomMargin: Theme.spacingSmall
                        spacing: 4

                        Text {
                            text: qsTr("Connexion")
                            font.pixelSize: Theme.fs(24)
                            font.weight: Theme.weightSemibold
                            font.family: Theme.fontFamily
                            color: Theme.ink
                            Accessible.role: Accessible.Heading
                        }

                        Text {
                            text: qsTr("Connectez-vous avec votre compte LocaLink.")
                            font.pixelSize: Theme.fs(14)
                            font.family: Theme.fontFamily
                            color: Theme.ink2
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                    }

                    AppTextField {
                        id: usernameAppField
                        label: qsTr("Nom d'utilisateur")
                        placeholderText: qsTr("Votre nom d'utilisateur")
                        hasError: errorLabel.text.length > 0
                        Layout.fillWidth: true
                        onAccepted: passwordAppField.field.forceActiveFocus()
                    }

                    Item {
                        id: passwordFieldContainer
                        Layout.fillWidth: true
                        implicitHeight: passwordAppField.implicitHeight

                        AppPasswordField {
                            id: passwordAppField
                            anchors.left: parent.left
                            anchors.right: parent.right
                            label: qsTr("Mot de passe")
                            placeholderText: qsTr("Votre mot de passe")
                            hasError: errorLabel.text.length > 0
                            onAccepted: root.attemptLogin()
                        }
                    }

                    AppCheckBox {
                        text: qsTr("Se souvenir de moi sur ce poste")
                        checked: root.rememberMe
                        onToggled: root.rememberMe = checked
                    }

                    Rectangle {
                        id: errorRow
                        visible: errorLabel.text.length > 0
                        Layout.fillWidth: true
                        implicitHeight: errorLabel.implicitHeight + 20
                        radius: Theme.radiusControl
                        color: Theme.dangerSoft

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 8
                            FaIcon {
                                Layout.alignment: Qt.AlignTop
                                Layout.topMargin: 1
                                glyph: ""
                                color: Theme.dangerInk
                                font.pixelSize: Theme.fs(13)
                            }
                            Text {
                                id: errorLabel
                                Layout.fillWidth: true
                                text: ""
                                color: Theme.dangerInk
                                wrapMode: Text.WordWrap
                                font.pixelSize: Theme.fs(13)
                                font.family: Theme.fontFamily
                                Accessible.role: Accessible.AlertMessage
                            }
                        }
                    }

                    AppButton {
                        id: loginButton
                        Layout.fillWidth: true
                        Layout.topMargin: Theme.spacingSmall
                        variant: "primary"
                        size: "large"
                        text: root.loginBusy ? qsTr("Connexion…") : qsTr("Se connecter")
                        loading: root.loginBusy
                        onClicked: root.attemptLogin()
                    }
                }
            }
        }
    }

    // Secousse rapide des deux champs pour localiser visuellement l'erreur.
    SequentialAnimation {
        id: shakeAnim
        loops: 1
        NumberAnimation { target: usernameAppField; property: "x"; to: -8; duration: 55; easing.type: Easing.OutQuad }
        NumberAnimation { target: usernameAppField; property: "x"; to: 8; duration: 55; easing.type: Easing.InOutQuad }
        NumberAnimation { target: usernameAppField; property: "x"; to: -5; duration: 55; easing.type: Easing.InOutQuad }
        NumberAnimation { target: usernameAppField; property: "x"; to: 5; duration: 55; easing.type: Easing.InOutQuad }
        NumberAnimation { target: usernameAppField; property: "x"; to: 0; duration: 55; easing.type: Easing.InQuad }
    }
    SequentialAnimation {
        id: shakeAnimPassword
        loops: 1
        NumberAnimation { target: passwordFieldContainer; property: "x"; to: -8; duration: 55; easing.type: Easing.OutQuad }
        NumberAnimation { target: passwordFieldContainer; property: "x"; to: 8; duration: 55; easing.type: Easing.InOutQuad }
        NumberAnimation { target: passwordFieldContainer; property: "x"; to: -5; duration: 55; easing.type: Easing.InOutQuad }
        NumberAnimation { target: passwordFieldContainer; property: "x"; to: 5; duration: 55; easing.type: Easing.InOutQuad }
        NumberAnimation { target: passwordFieldContainer; property: "x"; to: 0; duration: 55; easing.type: Easing.InQuad }
    }

    onErrorPulseChanged: {
        shakeAnim.start()
        shakeAnimPassword.start()
    }

    // Reagit au resultat de l'authentification reelle emis par UserManager
    // (core/UserManager.h) : succes -> navigation vers Home, echec ->
    // affichage du message d'erreur dans errorLabel.
    Connections {
        target: userManager

        function onLoginSucceeded(username) {
            // Ignore les emissions de loginSucceeded qui ne viennent pas
            // d'un attemptLogin() sur CE formulaire (typiquement l'auto-login
            // silencieux de Main.qml au demarrage, qui gere lui-meme sa
            // propre navigation vers Home) : sans cette garde, ce
            // Connections - reste actif meme apres qu'un Home ait ete
            // empile par-dessus - regenererait un jeton et re-empilerait
            // un second Home a chaque auto-login reussi.
            if (!root.manualLoginPending) {
                return
            }
            root.manualLoginPending = false

            errorLabel.text = ""
            passwordAppField.text = ""

            if (typeof settingsModel !== "undefined" && settingsModel) {
                if (root.rememberMe) {
                    // Genere un nouveau jeton d'auto-login (core::UserManager,
                    // migration #026) et ne persiste QUE cote client : la
                    // base ne recoit jamais que son hash SHA-256.
                    const token = userManager.rememberThisDevice()
                    console.log("[LoginView] rememberThisDevice -> tokenPresent=" + (token.length > 0))
                    settingsModel.rememberedUsername = username
                    settingsModel.rememberedSessionToken = token
                } else {
                    // Case decochee : invalide un eventuel jeton laisse par
                    // une session precedente sur ce poste, plutot que de le
                    // laisser trainer en base sans que personne ne s'en serve.
                    if (settingsModel.rememberedSessionToken.length > 0) {
                        userManager.forgetRememberedToken(settingsModel.rememberedSessionToken)
                    }
                    settingsModel.rememberedUsername = ""
                    settingsModel.rememberedSessionToken = ""
                }
                settingsModel.save()
            }

            root.loginSucceeded(username)
        }

        function onLoginFailed(reason) {
            root.manualLoginPending = false
            errorLabel.text = reason
            root.errorPulse = !root.errorPulse
        }
    }
}
