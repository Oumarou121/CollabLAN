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
 * Design v2 (split-screen) : remplace la carte flottante par une mise en
 * page en deux volets - panneau de marque (contexte produit) a gauche,
 * formulaire epure sans carte a droite. Repli responsive sous 900px :
 * le panneau de marque disparait, seul le formulaire reste visible.
 * Toute la logique d'authentification ci-dessous est inchangee ; seules
 * les proprietes visuelles ont ete retravaillees.
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

        const username = usernameField.text.trim()
        const password = passwordField.text

        if (username.length === 0 || password.length === 0) {
            errorLabel.text = qsTr("Merci de renseigner un nom d'utilisateur et un mot de passe.")
            root.errorPulse = !root.errorPulse
            return
        }

        errorLabel.text = ""
        root.manualLoginPending = true
        userManager.login(username, password)
    }

    // ---- Jetons locaux (palette pro/corporate, sensibles au theme) ----
    readonly property color paper: Theme.background
    readonly property color ink: Theme.text
    readonly property color inkMuted: Theme.textSecondary
    readonly property color inkFaint: Theme.textTertiary
    readonly property color blue700: Theme.primaryDeep
    readonly property color blue600: Theme.primary
    readonly property color borderCol: Theme.border
    readonly property color errorText: Theme.darkMode ? "#FF9A8A" : "#E5484D"
    readonly property color onAccent: "#FFFFFF"
    readonly property color disabledBg: Theme.darkMode ? "#3A4048" : "#9CA3AF"

    // Panneau de marque : bleu profond institutionnel, quasi noir en dark mode.
    readonly property color brandBg: Theme.darkMode ? "#0F1720" : "#1E3A5F"
    readonly property color brandInk: "#F5F7FA"
    readonly property color brandInkMuted: "#AEC2D4"
    readonly property color accentSky: "#4FC3F7"

    // Police d'accent embarquee (evite les alea de resolution de "serif"
    // selon les postes / OS constate en test).
    FontLoader {
        id: serifFont
        source: "../Assets/fonts/PTSerif-Bold.ttf"
    }
    readonly property string displayFont: serifFont.status === FontLoader.Ready ? serifFont.name : "serif"

    Rectangle {
        anchors.fill: parent
        color: root.paper
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
            usernameField.text = remembered
            root.rememberMe = true
            Qt.callLater(passwordField.forceActiveFocus)
        } else {
            Qt.callLater(usernameField.forceActiveFocus)
        }
    }

    ThemeToggleButton {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: Theme.spacingLarge
        z: 10
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
            Layout.preferredWidth: root.width * 0.42
            color: root.brandBg

            // Texture "grille" discrete, coherente avec l'identite
            // "dossier / portail institutionnel" du projet.
            Canvas {
                anchors.fill: parent
                opacity: 0.5
                onPaint: {
                    const ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    ctx.strokeStyle = "rgba(79,195,247,0.08)"
                    ctx.lineWidth = 1
                    const step = 28
                    for (let x = 0; x <= width; x += step) {
                        ctx.beginPath(); ctx.moveTo(x + 0.5, 0); ctx.lineTo(x + 0.5, height); ctx.stroke()
                    }
                    for (let y = 0; y <= height; y += step) {
                        ctx.beginPath(); ctx.moveTo(0, y + 0.5); ctx.lineTo(width, y + 0.5); ctx.stroke()
                    }
                }
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
            }

            // Liseré or vertical côté formulaire, seule touche de couleur
            // vive du panneau.
            Rectangle {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 3
                color: root.accentSky
            }

            ColumnLayout {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Theme.spacingXl * 1.4
                anchors.rightMargin: Theme.spacingXl * 1.4
                spacing: Theme.spacingXl

                RowLayout {
                    spacing: Theme.spacingSmall

                    BrandMark {
                        size: 56
                    }

                    Label {
                        text: "Collab LAN"
                        font.pixelSize: 28
                        font.family: root.displayFont
                        color: root.brandInk
                    }
                }

                Label {
                    text: qsTr("La collaboration de votre équipe, entièrement sur votre réseau local.")
                    font.pixelSize: 20
                    font.family: root.displayFont
                    color: root.brandInk
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                    lineHeight: 1.25
                }

                Label {
                    text: qsTr("Aucune dépendance à Internet. Vos données restent sur votre réseau.")
                    font.pixelSize: Theme.fontSizeBody
                    font.family: Theme.fontFamily
                    color: root.brandInkMuted
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                ColumnLayout {
                    Layout.topMargin: Theme.spacingMedium
                    spacing: Theme.spacingMedium

                    Repeater {
                        model: [
                            qsTr("Découverte automatique des collègues sur le réseau"),
                            qsTr("Messagerie individuelle et de groupe"),
                            qsTr("Partage de fichiers et de dossiers"),
                            qsTr("Appels vocaux intégrés")
                        ]

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacingSmall

                            Rectangle {
                                Layout.preferredWidth: 20
                                Layout.preferredHeight: 20
                                radius: 4
                                color: "transparent"
                                border.width: 1.4
                                border.color: root.accentSky

                                Text {
                                    anchors.centerIn: parent
                                    text: "\u2713"
                                    color: root.accentSky
                                    font.pixelSize: 12
                                    font.bold: true
                                }
                            }

                            Label {
                                text: modelData
                                font.pixelSize: Theme.fontSizeSmall
                                font.family: Theme.fontFamily
                                color: root.brandInkMuted
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }
                        }
                    }
                }
            }

            Label {
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.margins: Theme.spacingXl * 1.4
                text: qsTr("Connexion sécurisée sur votre réseau local").toUpperCase()
                font.pixelSize: 10
                font.family: "monospace"
                font.letterSpacing: 0.6
                color: root.brandInkMuted
            }
        }

        // ---------------------------------------------------------------
        // Panneau droit : formulaire presente dans une carte (ombre legere,
        // coins arrondis), plutot que directement sur le fond.
        // ---------------------------------------------------------------
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // Ombre portee : rectangle legerement plus grand, decale,
            // avec une opacite faible - simule une elevation douce sans
            // dependre d'un effet graphique externe.
            Rectangle {
                anchors.centerIn: formCard
                width: formCard.width + 8
                height: formCard.height + 8
                radius: Theme.radiusMedium + 4
                color: Theme.darkMode ? "#00000000" : "#0F1E30"
                opacity: Theme.darkMode ? 0 : 0.06
                y: formCard.y + 6
            }

            Rectangle {
                id: formCard
                anchors.centerIn: parent
                width: Math.min(420, parent.width - Theme.spacingXl * 2)
                height: formColumn.implicitHeight + Theme.spacingXl * 2.2
                radius: Theme.radiusMedium + 4
                color: Theme.darkMode ? "#1C232D" : "#FFFFFF"
                border.width: 1
                border.color: root.borderCol

                ColumnLayout {
                id: formColumn
                anchors.centerIn: parent
                width: Math.min(380, parent.width - Theme.spacingXl * 2)
                spacing: Theme.spacingMedium

                // En-tete visible uniquement quand le panneau de marque est
                // replie, pour ne pas perdre l'identite produit.
                RowLayout {
                    visible: !root.showBrandPanel
                    Layout.bottomMargin: Theme.spacingLarge
                    Layout.alignment: Qt.AlignHCenter
                    spacing: Theme.spacingSmall

                    BrandMark {
                        size: 44
                    }

                    Label {
                        text: "Collab LAN"
                        font.pixelSize: 22
                        font.family: root.displayFont
                        color: root.ink
                    }
                }

                Label {
                    text: qsTr("Connexion")
                    font.pixelSize: 24
                    font.family: root.displayFont
                    color: root.ink
                }

                Label {
                    text: qsTr("Connectez-vous à votre espace")
                    font.pixelSize: Theme.fontSizeBody
                    font.family: Theme.fontFamily
                    color: root.inkMuted
                    Layout.bottomMargin: Theme.spacingMedium
                }

                Label {
                    text: qsTr("Nom d'utilisateur")
                    font.pixelSize: Theme.fontSizeSmall
                    font.family: Theme.fontFamily
                    color: root.inkMuted
                    font.bold: true
                }

                Item {
                    id: usernameFieldWrapper
                    Layout.fillWidth: true
                    Layout.preferredHeight: 48

                    TextField {
                        id: usernameField
                        anchors.fill: parent
                        placeholderText: qsTr("Votre nom d'utilisateur")
                        selectByMouse: true
                        color: root.ink
                        font.pixelSize: Theme.fontSizeBody
                        font.family: Theme.fontFamily
                        leftPadding: 12
                        rightPadding: 12
                        onAccepted: passwordField.forceActiveFocus()

                        background: Rectangle {
                            radius: Theme.radiusSmall
                            color: Theme.surface
                            border.width: (usernameField.activeFocus || errorLabel.text.length > 0) ? 2 : 1
                            border.color: usernameField.activeFocus
                                   ? root.blue600
                                   : (errorLabel.text.length > 0 ? root.errorText : root.borderCol)
                            Behavior on border.color { ColorAnimation { duration: 100 } }
                        }
                    }
                }

                Label {
                    text: qsTr("Mot de passe")
                    font.pixelSize: Theme.fontSizeSmall
                    font.family: Theme.fontFamily
                    color: root.inkMuted
                    font.bold: true
                    Layout.topMargin: Theme.spacingSmall
                }

                Item {
                    id: passwordFieldWrapper
                    Layout.fillWidth: true
                    Layout.preferredHeight: 48

                    TextField {
                        id: passwordField
                        anchors.fill: parent
                        placeholderText: qsTr("Votre mot de passe")
                        echoMode: root.showPassword ? TextInput.Normal : TextInput.Password
                        selectByMouse: true
                        color: root.ink
                        font.pixelSize: Theme.fontSizeBody
                        font.family: Theme.fontFamily
                        leftPadding: 12
                        rightPadding: 40
                        onAccepted: root.attemptLogin()

                        background: Rectangle {
                            radius: Theme.radiusSmall
                            color: Theme.surface
                            border.width: (passwordField.activeFocus || errorLabel.text.length > 0) ? 2 : 1
                            border.color: passwordField.activeFocus
                                   ? root.blue600
                                   : (errorLabel.text.length > 0 ? root.errorText : root.borderCol)
                            Behavior on border.color { ColorAnimation { duration: 100 } }
                        }
                    }

                    // Bascule "afficher / masquer le mot de passe" - icone
                    // oeil dessinee en vectoriel (pas d'emoji : ignore la
                    // couleur du theme).
                    Item {
                        width: 32
                        height: parent.height
                        anchors.right: parent.right

                        // Zone cliquable circulaire avec effet de survol,
                        // plus grande que l'icone pour un meilleur ciblage.
                        Rectangle {
                            id: eyeHoverBg
                            width: 30
                            height: 30
                            radius: width / 2
                            anchors.centerIn: parent
                            color: root.blue600
                            opacity: eyeMouseArea.containsMouse ? (Theme.darkMode ? 0.16 : 0.08) : 0
                            Behavior on opacity { NumberAnimation { duration: 120 } }
                        }

                        Canvas {
                            id: eyeIcon
                            width: 18
                            height: 18
                            anchors.centerIn: parent
                            property color strokeColor: root.showPassword ? root.blue600 : root.inkFaint
                            Component.onCompleted: requestPaint()
                            onPaint: {
                                const ctx = getContext("2d")
                                ctx.clearRect(0, 0, width, height)
                                ctx.strokeStyle = strokeColor
                                ctx.lineWidth = 1.5
                                ctx.lineJoin = "round"
                                ctx.lineCap = "round"

                                if (root.showPassword) {
                                    // Mot de passe visible : oeil ouvert plein.
                                    ctx.beginPath()
                                    ctx.moveTo(1.2, 9)
                                    ctx.quadraticCurveTo(9, 1.8, 16.8, 9)
                                    ctx.quadraticCurveTo(9, 16.2, 1.2, 9)
                                    ctx.closePath()
                                    ctx.stroke()
                                    ctx.beginPath()
                                    ctx.arc(9, 9, 2.6, 0, Math.PI * 2)
                                    ctx.stroke()
                                } else {
                                    // Mot de passe masque : paupiere fermee
                                    // (courbe simple) + barre diagonale, a la
                                    // maniere de l'icone "eye-off" standard.
                                    ctx.beginPath()
                                    ctx.moveTo(1.2, 10.5)
                                    ctx.quadraticCurveTo(9, 4.5, 16.8, 10.5)
                                    ctx.stroke()
                                    ctx.beginPath()
                                    ctx.moveTo(2.2, 2.2)
                                    ctx.lineTo(15.8, 15.8)
                                    ctx.stroke()
                                }
                            }
                            Behavior on strokeColor { ColorAnimation { duration: 120 } }
                            onStrokeColorChanged: requestPaint()
                            Connections {
                                target: root
                                function onShowPasswordChanged() { eyeIcon.requestPaint() }
                            }
                        }

                        MouseArea {
                            id: eyeMouseArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.showPassword = !root.showPassword
                        }
                    }
                }

                Item {
                    Layout.topMargin: Theme.spacingSmall
                    Layout.fillWidth: true
                    Layout.preferredHeight: rememberRow.implicitHeight

                    RowLayout {
                        id: rememberRow
                        anchors.left: parent.left
                        anchors.right: parent.right
                        spacing: Theme.spacingSmall

                        Rectangle {
                            id: rememberCheckbox
                            Layout.preferredWidth: 18
                            Layout.preferredHeight: 18
                            radius: 4
                            color: root.rememberMe ? root.blue700 : "transparent"
                            border.width: 1.4
                            border.color: root.rememberMe ? root.blue700 : root.borderCol
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Behavior on border.color { ColorAnimation { duration: 150 } }

                            Text {
                                anchors.centerIn: parent
                                text: "\u2713"
                                color: root.onAccent
                                font.pixelSize: 11
                                font.bold: true
                                visible: root.rememberMe
                            }
                        }

                        Label {
                            text: qsTr("Se souvenir de moi")
                            font.pixelSize: Theme.fontSizeSmall
                            font.family: Theme.fontFamily
                            color: root.inkMuted
                        }

                        Item { Layout.fillWidth: true }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.rememberMe = !root.rememberMe
                    }
                }

                RowLayout {
                    visible: errorLabel.text.length > 0
                    Layout.topMargin: Theme.spacingSmall
                    Layout.fillWidth: true
                    spacing: Theme.spacingXs

                    Rectangle {
                        Layout.preferredWidth: 4
                        Layout.preferredHeight: errorLabel.implicitHeight
                        radius: 2
                        color: root.errorText
                    }

                    Label {
                        id: errorLabel
                        text: ""
                        color: root.errorText
                        font.pixelSize: Theme.fontSizeSmall
                        font.family: Theme.fontFamily
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                }

                Label {
                    visible: errorLabel.text.length === 0
                    Layout.topMargin: Theme.spacingSmall
                    Layout.preferredHeight: errorLabel.implicitHeight
                }

                Rectangle {
                    id: loginButton
                    Layout.topMargin: Theme.spacingMedium
                    Layout.fillWidth: true
                    Layout.preferredHeight: 44
                    radius: Theme.radiusSmall
                    color: userManager.busy ? root.disabledBg : (loginMouseArea.containsMouse ? root.blue600 : root.blue700)
                    Behavior on color { ColorAnimation { duration: 100 } }

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 8

                        Item {
                            visible: userManager.busy
                            Layout.preferredWidth: 15
                            Layout.preferredHeight: 15

                            Canvas {
                                id: spinnerCanvas
                                anchors.fill: parent
                                onPaint: {
                                    const ctx = getContext("2d")
                                    ctx.clearRect(0, 0, width, height)
                                    ctx.lineWidth = 2
                                    ctx.lineCap = "round"
                                    ctx.strokeStyle = root.onAccent
                                    ctx.beginPath()
                                    ctx.arc(width / 2, height / 2, width / 2 - 1.5, 0, Math.PI * 1.4)
                                    ctx.stroke()
                                }
                            }

                            RotationAnimation on rotation {
                                target: spinnerCanvas
                                running: userManager.busy
                                loops: Animation.Infinite
                                from: 0
                                to: 360
                                duration: 700
                            }
                        }

                        Text {
                            text: userManager.busy ? qsTr("Connexion...") : qsTr("Se connecter")
                            color: root.onAccent
                            font.pixelSize: Theme.fontSizeBody
                            font.bold: true
                            font.family: Theme.fontFamily
                        }
                    }

                    MouseArea {
                        id: loginMouseArea
                        anchors.fill: parent
                        enabled: !userManager.busy
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.attemptLogin()
                    }
                }

                Label {
                    Layout.topMargin: Theme.spacingSmall
                    Layout.alignment: Qt.AlignHCenter
                    text: qsTr("Mot de passe oublié ?")
                    font.pixelSize: Theme.fontSizeSmall
                    font.family: Theme.fontFamily
                    color: root.blue700

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                    }
                }
                }
            }
        }
    }

    // Secousse rapide des deux champs pour localiser visuellement l'erreur.
    SequentialAnimation {
        id: shakeAnim
        loops: 1
        NumberAnimation { target: usernameFieldWrapper; property: "x"; to: -8; duration: 55; easing.type: Easing.OutQuad }
        NumberAnimation { target: usernameFieldWrapper; property: "x"; to: 8; duration: 55; easing.type: Easing.InOutQuad }
        NumberAnimation { target: usernameFieldWrapper; property: "x"; to: -5; duration: 55; easing.type: Easing.InOutQuad }
        NumberAnimation { target: usernameFieldWrapper; property: "x"; to: 5; duration: 55; easing.type: Easing.InOutQuad }
        NumberAnimation { target: usernameFieldWrapper; property: "x"; to: 0; duration: 55; easing.type: Easing.InQuad }
    }
    SequentialAnimation {
        id: shakeAnimPassword
        loops: 1
        NumberAnimation { target: passwordFieldWrapper; property: "x"; to: -8; duration: 55; easing.type: Easing.OutQuad }
        NumberAnimation { target: passwordFieldWrapper; property: "x"; to: 8; duration: 55; easing.type: Easing.InOutQuad }
        NumberAnimation { target: passwordFieldWrapper; property: "x"; to: -5; duration: 55; easing.type: Easing.InOutQuad }
        NumberAnimation { target: passwordFieldWrapper; property: "x"; to: 5; duration: 55; easing.type: Easing.InOutQuad }
        NumberAnimation { target: passwordFieldWrapper; property: "x"; to: 0; duration: 55; easing.type: Easing.InQuad }
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
            passwordField.text = ""

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
