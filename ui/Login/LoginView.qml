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
 * Design revu (juillet) : identite visuelle "dossier / portail institutionnel"
 * alignee sur le portail web de reference (palette bleu + or, coin "replie"
 * repris sur la carte, logo de marque commun via BrandMark, police PT Serif
 * embarquee pour un rendu identique quel que soit le poste). Toute la
 * logique d'authentification ci-dessous est inchangee ; seules les
 * proprietes visuelles ont ete retravaillees.
 */
Item {
    id: root

    signal loginSucceeded(string username)

    // Bascule "afficher le mot de passe"
    property bool showPassword: false

    // Bascule a chaque nouvelle erreur : sert de "trigger" pour lancer le
    // shake + la surbrillance rouge des champs (voir shakeAnim ci-dessous).
    property bool errorPulse: false

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
        userManager.login(username, password)
    }

    // ---- Jetons locaux (palette institutionnelle, sensibles au theme) ----
    readonly property color paper: Theme.darkMode ? "#12151B" : "#EEF1EC"
    readonly property color cardSurface: Theme.darkMode ? "#1D2027" : "#FFFFFF"
    readonly property color ink: Theme.darkMode ? "#F2F3F7" : "#101B2D"
    readonly property color inkMuted: Theme.darkMode ? "#9AA0B2" : "#4B5C70"
    readonly property color inkFaint: Theme.darkMode ? "#6E7486" : "#8695A8"
    readonly property color blue700: Theme.darkMode ? "#5B8FB0" : "#2A5C85"
    readonly property color blue600: Theme.darkMode ? "#79A8C6" : "#336F9E"
    readonly property color blueTint: Theme.darkMode ? "#20303D" : "#E4EDF3"
    readonly property color gold600: Theme.darkMode ? "#D6A94F" : "#B6862F"
    readonly property color borderCol: Theme.darkMode ? "#2E323C" : Qt.alpha(blue700, 0.16)
    readonly property color errorBg: Theme.darkMode ? "#3A2229" : "#FDF2F0"
    readonly property color errorBorder: Theme.darkMode ? "#5C333B" : "#E8B3AB"
    readonly property color errorText: Theme.darkMode ? "#FF9A8A" : "#A83E2C"

    // Police d'accent embarquee (evite les alea de resolution de "serif"
    // selon les postes / OS constate en test).
    FontLoader {
        id: serifFont
        source: "../Assets/fonts/PTSerif-Bold.ttf"
    }
    readonly property string displayFont: serifFont.status === FontLoader.Ready ? serifFont.name : "serif"

    // Fond "papier quadrille" - cote document officiel, discret.
    Rectangle {
        anchors.fill: parent
        color: root.paper
    }
    Canvas {
        anchors.fill: parent
        opacity: Theme.darkMode ? 0.5 : 1
        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            ctx.strokeStyle = Theme.darkMode ? "rgba(121,168,198,0.06)" : "rgba(42,92,133,0.07)"
            ctx.lineWidth = 1
            const step = 24
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

    ThemeToggleButton {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: Theme.spacingLarge
    }

    // Bloc marque (logo + nom + accroche) - en dehors de la carte, au-dessus.
    ColumnLayout {
        id: brandBlock
        anchors.horizontalCenter: card.horizontalCenter
        anchors.bottom: card.top
        anchors.bottomMargin: Theme.spacingLarge
        spacing: Theme.spacingXs

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Theme.spacingSmall

            BrandMark {
                size: 40
            }

            Label {
                text: "Collab LAN"
                font.pixelSize: 26
                font.family: root.displayFont
                color: root.ink
            }
        }

        Label {
            Layout.alignment: Qt.AlignHCenter
            text: qsTr("Connectez-vous à votre espace")
            font.pixelSize: Theme.fontSizeBody
            font.family: Theme.fontFamily
            color: root.inkMuted
        }
    }

    // Formulaire de connexion centre
    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(450, root.width - Theme.spacingXl * 2)
        height: formColumn.implicitHeight + Theme.spacingXl * 2
        radius: Theme.radiusLarge
        color: root.cardSurface
        border.width: 1
        border.color: root.borderCol
        clip: true

        ColumnLayout {
            id: formColumn
            anchors.fill: parent
            anchors.margins: Theme.spacingXl
            spacing: Theme.spacingMedium

            Label {
                text: qsTr("Nom d'utilisateur")
                font.pixelSize: Theme.fontSizeSmall
                font.family: Theme.fontFamily
                color: root.inkMuted
                font.bold: true
                Layout.topMargin: Theme.spacingSmall
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
                    leftPadding: 42
                    onAccepted: passwordField.forceActiveFocus()

                    background: Rectangle {
                        radius: Theme.radiusMedium
                        color: Theme.darkMode ? "#171A20" : "#FBFCFA"
                        border.width: (usernameField.activeFocus || errorLabel.text.length > 0) ? 2 : 1
                        border.color: usernameField.activeFocus
                                      ? root.blue600
                                      : (errorLabel.text.length > 0 ? root.errorText : root.borderCol)
                        Behavior on border.color { ColorAnimation { duration: 100 } }
                    }
                }

                // Icone "utilisateur" dessinee en vectoriel (evite les
                // emojis multicolores, qui ignorent la couleur du theme).
                Canvas {
                    id: userIcon
                    width: 16
                    height: 16
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    Component.onCompleted: requestPaint()
                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)
                        ctx.fillStyle = root.inkFaint
                        ctx.beginPath(); ctx.arc(8, 5, 3.1, 0, Math.PI * 2); ctx.fill()
                        ctx.beginPath()
                        ctx.moveTo(2.2, 15)
                        ctx.quadraticCurveTo(2.2, 9.2, 8, 9.2)
                        ctx.quadraticCurveTo(13.8, 9.2, 13.8, 15)
                        ctx.closePath()
                        ctx.fill()
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
                    leftPadding: 42
                    rightPadding: 40
                    onAccepted: root.attemptLogin()

                    background: Rectangle {
                        radius: Theme.radiusMedium
                        color: Theme.darkMode ? "#171A20" : "#FBFCFA"
                        border.width: (passwordField.activeFocus || errorLabel.text.length > 0) ? 2 : 1
                        border.color: passwordField.activeFocus
                                      ? root.blue600
                                      : (errorLabel.text.length > 0 ? root.errorText : root.borderCol)
                        Behavior on border.color { ColorAnimation { duration: 100 } }
                    }
                }

                // Icone "cadenas" dessinee en vectoriel, meme logique.
                Canvas {
                    id: lockIcon
                    width: 16
                    height: 16
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    Component.onCompleted: requestPaint()
                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)
                        ctx.strokeStyle = root.inkFaint
                        ctx.lineWidth = 1.6
                        ctx.beginPath()
                        ctx.arc(8, 6.4, 3.4, Math.PI, 0, false)
                        ctx.stroke()
                        ctx.fillStyle = root.inkFaint
                        ctx.fillRect(2.6, 6.8, 10.8, 7.6)
                    }
                }

                // Bascule "afficher / masquer le mot de passe" - icone oeil
                // dessinee en vectoriel, meme logique que les autres icones
                // du formulaire (pas d'emoji, sensible au theme).
                Item {
                    width: 32
                    height: parent.height
                    anchors.right: parent.right

                    Canvas {
                        id: eyeIcon
                        width: 18
                        height: 18
                        anchors.centerIn: parent
                        Component.onCompleted: requestPaint()
                        onPaint: {
                            const ctx = getContext("2d")
                            ctx.clearRect(0, 0, width, height)
                            ctx.strokeStyle = root.inkFaint
                            ctx.lineWidth = 1.4
                            ctx.lineJoin = "round"
                            ctx.lineCap = "round"
                            // Contour de l'oeil
                            ctx.beginPath()
                            ctx.moveTo(1.5, 9)
                            ctx.quadraticCurveTo(9, 1.5, 16.5, 9)
                            ctx.quadraticCurveTo(9, 16.5, 1.5, 9)
                            ctx.closePath()
                            ctx.stroke()
                            // Pupille
                            ctx.beginPath()
                            ctx.arc(9, 9, 2.6, 0, Math.PI * 2)
                            ctx.stroke()
                            if (!root.showPassword) {
                                // Mot de passe masque : barre diagonale
                                ctx.beginPath()
                                ctx.moveTo(2, 16)
                                ctx.lineTo(16, 2)
                                ctx.stroke()
                            }
                        }
                        Connections {
                            target: root
                            function onShowPasswordChanged() { eyeIcon.requestPaint() }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.showPassword = !root.showPassword
                    }
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

            RowLayout {
                Layout.topMargin: Theme.spacingMedium
                Layout.fillWidth: true
                spacing: Theme.spacingMedium

                Label {
                    text: qsTr("Mot de passe oublié ?")
                    font.pixelSize: Theme.fontSizeSmall
                    font.family: Theme.fontFamily
                    color: root.blue700

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                    }
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    id: loginButton
                    Layout.preferredWidth: loginButtonContent.implicitWidth + Theme.spacingXl * 2
                    Layout.preferredHeight: 42
                    radius: Theme.radiusMedium
                    color: userManager.busy ? "#9ca3af" : (loginMouseArea.containsMouse ? root.blue600 : root.blue700)
                    Behavior on color { ColorAnimation { duration: 100 } }

                    RowLayout {
                        id: loginButtonContent
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
                                    ctx.strokeStyle = "#ffffff"
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
                            visible: !userManager.busy
                            text: "→"
                            color: "#ffffff"
                            font.pixelSize: 15
                            font.bold: true
                        }

                        Text {
                            text: userManager.busy ? qsTr("Connexion...") : qsTr("Se connecter")
                            color: "#ffffff"
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
            }
        }
    }

    // Mention securite - en dehors de la carte, en dessous.
    Label {
        anchors.horizontalCenter: card.horizontalCenter
        anchors.top: card.bottom
        anchors.topMargin: Theme.spacingLarge
        text: qsTr("Connexion sécurisée sur votre réseau local").toUpperCase()
        font.pixelSize: 10
        font.family: "monospace"
        font.letterSpacing: 0.6
        color: root.inkFaint
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
            errorLabel.text = ""
            passwordField.text = ""
            root.loginSucceeded(username)
        }

        function onLoginFailed(reason) {
            errorLabel.text = reason
            root.errorPulse = !root.errorPulse
        }
    }
}
