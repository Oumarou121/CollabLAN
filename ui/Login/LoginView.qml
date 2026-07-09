import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import "../Components"

/*
 * LoginView - ecran "Login" (issue #6 : navigation de base Login -> Home)
 *
 * Emet loginSucceeded(username) lorsque l'utilisateur valide le formulaire.
 * L'authentification reelle (UserManager / SecurityService) sera branchee
 * dans une issue ulterieure ; pour l'instant, un nom d'utilisateur et un
 * mot de passe non vides suffisent a valider le formulaire.
 */
Item {
    id: root

    signal loginSucceeded(string username)

    // Fond degrade discret, coherent avec le theme courant
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0.0; color: Theme.background }
            GradientStop { position: 1.0; color: Theme.surfaceAlt }
        }
    }

    ThemeToggleButton {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: Theme.spacingLarge
    }

    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(400, root.width - 2 * Theme.spacingLarge)
        spacing: Theme.spacingLarge

        // En-tete : logo + titre
        ColumnLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Theme.spacingSmall

            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                width: 64
                height: 64
                radius: 18
                color: Theme.primary

                Text {
                    anchors.centerIn: parent
                    text: "CL"
                    color: Theme.primaryText
                    font.pixelSize: 24
                    font.bold: true
                    font.family: Theme.fontFamily
                }
            }

            Label {
                Layout.alignment: Qt.AlignHCenter
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
                color: Theme.textSecondary
            }
        }

        // Carte de connexion, avec une legere ombre portee simulee
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: cardColumn.implicitHeight + 2 * Theme.spacingLarge

            Rectangle {
                anchors.fill: parent
                anchors.topMargin: 4
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
                    anchors.margins: Theme.spacingLarge
                    spacing: Theme.spacingMedium

                    Label {
                        text: qsTr("Nom d'utilisateur")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.textSecondary
                    }

                    TextField {
                        id: usernameField
                        Layout.fillWidth: true
                        placeholderText: qsTr("Votre nom d'utilisateur")
                        selectByMouse: true
                        font.pixelSize: Theme.fontSizeBody
                        onAccepted: passwordField.forceActiveFocus()

                        background: Rectangle {
                            radius: Theme.radiusSmall
                            color: Theme.background
                            border.width: 1
                            border.color: usernameField.activeFocus ? Theme.primary : Theme.border
                        }
                    }

                    Label {
                        text: qsTr("Mot de passe")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.textSecondary
                        Layout.topMargin: Theme.spacingSmall
                    }

                    TextField {
                        id: passwordField
                        Layout.fillWidth: true
                        placeholderText: qsTr("Votre mot de passe")
                        echoMode: TextInput.Password
                        selectByMouse: true
                        font.pixelSize: Theme.fontSizeBody
                        onAccepted: loginButton.clicked()

                        background: Rectangle {
                            radius: Theme.radiusSmall
                            color: Theme.background
                            border.width: 1
                            border.color: passwordField.activeFocus ? Theme.primary : Theme.border
                        }
                    }

                    Label {
                        id: errorLabel
                        visible: text.length > 0
                        text: ""
                        color: Theme.error
                        font.pixelSize: Theme.fontSizeSmall
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }

                    Button {
                        id: loginButton
                        text: qsTr("Se connecter")
                        Layout.fillWidth: true
                        Layout.topMargin: Theme.spacingSmall
                        Layout.preferredHeight: 44

                        background: Rectangle {
                            radius: Theme.radiusSmall
                            color: loginButton.pressed ? Theme.primaryHover : Theme.primary
                        }

                        contentItem: Text {
                            text: loginButton.text
                            color: Theme.primaryText
                            font.pixelSize: Theme.fontSizeBody
                            font.bold: true
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }

                        onClicked: {
                            const username = usernameField.text.trim()
                            const password = passwordField.text

                            if (username.length === 0 || password.length === 0) {
                                errorLabel.text = qsTr("Merci de renseigner un nom d'utilisateur et un mot de passe.")
                                return
                            }

                            errorLabel.text = ""
                            root.loginSucceeded(username)
                        }
                    }
                }
            }
        }
    }
}
