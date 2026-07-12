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
 */
Item {
    id: root

    signal loginSucceeded(string username)

    // Fond degrade discret, coherent avec le theme courant
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0.0; color: Theme.darkMode ? "#181B2A" : "#EEF0FB" }
            GradientStop { position: 1.0; color: Theme.background }
        }
    }

    // Formes discretes en arriere-plan pour donner du relief sans distraire
    Rectangle {
        width: 420
        height: 420
        radius: width / 2
        color: Theme.primary
        opacity: Theme.darkMode ? 0.10 : 0.07
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.horizontalCenterOffset: -260
        anchors.top: parent.top
        anchors.topMargin: -160
    }
    Rectangle {
        width: 320
        height: 320
        radius: width / 2
        color: Theme.primary
        opacity: Theme.darkMode ? 0.08 : 0.05
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.horizontalCenterOffset: 300
        anchors.bottom: parent.bottom
        anchors.bottomMargin: -140
    }

    ThemeToggleButton {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: Theme.spacingLarge
    }

    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(400, root.width - 2 * Theme.spacingLarge)
        spacing: Theme.spacingXl

        // En-tete : logo + titre
        ColumnLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Theme.spacingSmall

            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                width: 60
                height: 60
                radius: Theme.radiusLarge
                color: Theme.primary

                Text {
                    anchors.centerIn: parent
                    text: "CL"
                    color: Theme.primaryText
                    font.pixelSize: 22
                    font.bold: true
                    font.family: Theme.fontFamily
                }
            }

            Label {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: Theme.spacingSmall
                text: "CollabLAN"
                font.pixelSize: Theme.fontSizeTitle
                font.bold: true
                font.family: Theme.fontFamily
                color: Theme.text
            }

            Label {
                Layout.alignment: Qt.AlignHCenter
                text: qsTr("Collaborez sur votre reseau local")
                font.pixelSize: Theme.fontSizeSmall
                font.family: Theme.fontFamily
                color: Theme.textSecondary
            }
        }

        // Carte de connexion, avec une legere ombre portee simulee
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: cardColumn.implicitHeight + 2 * Theme.spacingXl

            Rectangle {
                anchors.fill: parent
                anchors.topMargin: 6
                radius: Theme.radiusLarge
                color: Theme.shadow
            }

            Rectangle {
                anchors.fill: parent
                radius: Theme.radiusLarge
                color: Theme.surface
                border.color: Theme.border
                border.width: 1

                ColumnLayout {
                    id: cardColumn
                    anchors.fill: parent
                    anchors.margins: Theme.spacingXl
                    spacing: Theme.spacingSmall

                    Label {
                        text: qsTr("Nom d'utilisateur")
                        font.pixelSize: Theme.fontSizeSmall
                        font.family: Theme.fontFamily
                        color: Theme.textSecondary
                    }

                    TextField {
                        id: usernameField
                        Layout.fillWidth: true
                        Layout.preferredHeight: 44
                        placeholderText: qsTr("Votre nom d'utilisateur")
                        selectByMouse: true
                        color: Theme.text
                        font.pixelSize: Theme.fontSizeBody
                        font.family: Theme.fontFamily
                        leftPadding: Theme.spacingMedium
                        onAccepted: passwordField.forceActiveFocus()

                        background: Rectangle {
                            radius: Theme.radiusMedium
                            color: Theme.background
                            border.width: usernameField.activeFocus ? 2 : 1
                            border.color: usernameField.activeFocus ? Theme.primary : Theme.border
                            Behavior on border.color { ColorAnimation { duration: 100 } }
                        }
                    }

                    Label {
                        text: qsTr("Mot de passe")
                        font.pixelSize: Theme.fontSizeSmall
                        font.family: Theme.fontFamily
                        color: Theme.textSecondary
                        Layout.topMargin: Theme.spacingMedium
                    }

                    TextField {
                        id: passwordField
                        Layout.fillWidth: true
                        Layout.preferredHeight: 44
                        placeholderText: qsTr("Votre mot de passe")
                        echoMode: TextInput.Password
                        selectByMouse: true
                        color: Theme.text
                        font.pixelSize: Theme.fontSizeBody
                        font.family: Theme.fontFamily
                        leftPadding: Theme.spacingMedium
                        onAccepted: loginButton.clicked()

                        background: Rectangle {
                            radius: Theme.radiusMedium
                            color: Theme.background
                            border.width: passwordField.activeFocus ? 2 : 1
                            border.color: passwordField.activeFocus ? Theme.primary : Theme.border
                            Behavior on border.color { ColorAnimation { duration: 100 } }
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
                            color: Theme.error
                        }

                        Label {
                            id: errorLabel
                            text: ""
                            color: Theme.error
                            font.pixelSize: Theme.fontSizeSmall
                            font.family: Theme.fontFamily
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                    }

                    AppButton {
                        id: loginButton
                        variant: "primary"
                        fullWidth: true
                        Layout.fillWidth: true
                        Layout.topMargin: Theme.spacingMedium
                        implicitHeight: 46
                        text: userManager.busy ? qsTr("Connexion...") : qsTr("Se connecter")
                        enabled: !userManager.busy

                        onClicked: {
                            const username = usernameField.text.trim()
                            const password = passwordField.text

                            if (username.length === 0 || password.length === 0) {
                                errorLabel.text = qsTr("Merci de renseigner un nom d'utilisateur et un mot de passe.")
                                return
                            }

                            errorLabel.text = ""
                            userManager.login(username, password)
                        }
                    }
                }
            }
        }

        Label {
            Layout.alignment: Qt.AlignHCenter
            text: qsTr("Connexion securisee sur votre reseau local")
            font.pixelSize: Theme.fontSizeCaption
            font.family: Theme.fontFamily
            color: Theme.textTertiary
        }
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
        }
    }
}
