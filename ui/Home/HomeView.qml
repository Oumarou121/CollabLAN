import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import "../Components"

/*
 * HomeView - ecran "Home" (issue #6 : navigation de base Login -> Home)
 *
 * Point d'entree apres connexion. Tableau de bord avec acces rapides sous
 * forme de cartes.
 *
 * Design revu (juillet) : identite visuelle "dossier / portail institutionnel"
 * alignee sur le portail web de reference (bandeau bleu + accents or, pastilles
 * façon puce documentaire, cartes DashboardCard a bandeau colore). Tous les
 * signaux et proprietes exposes par cet ecran restent inchanges.
 */
Item {
    id: root

    property string username: ""

    signal logoutRequested()
    signal usersRequested()
    signal chatRequested()
    signal fileTransferRequested()
    signal callRequested()
    signal adminRequested()
    signal sharedFoldersRequested()

    // Nombre de postes detectes sur le reseau local (network::PeersModel,
    // cf. app/main.cpp). Repli a 0 en contexte preview/design sans backend.
    readonly property int peersCount: (typeof peersModel !== "undefined" && peersModel) ? peersModel.count : 0

    // ---- Jetons locaux (accents institutionnels, sensibles au theme) ----
    readonly property color blue700: Theme.darkMode ? "#5B8FB0" : "#2A5C85"
    readonly property color blue600: Theme.darkMode ? "#79A8C6" : "#336F9E"
    readonly property color blueTint: Theme.darkMode ? "#20303D" : "#E4EDF3"
    readonly property color gold600: Theme.darkMode ? "#D6A94F" : "#B6862F"

    // Meme police d'accent embarquee que LoginView, pour un rendu identique
    // quel que soit le poste.
    FontLoader {
        id: serifFont
        source: "../Assets/fonts/PTSerif-Bold.ttf"
    }
    readonly property string displayFont: serifFont.status === FontLoader.Ready ? serifFont.name : "serif"

    Rectangle {
        anchors.fill: parent
        color: Theme.background
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ---- En-tete : marque, badges de statut, profil -------------------
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 76
            color: Theme.surface
            border.width: 1
            border.color: Theme.border

            RowLayout {
                anchors.fill: parent
                anchors.margins: Theme.spacingLarge
                spacing: Theme.spacingMedium

                BrandMark { size: 40 }

                Label {
                    text: qsTr("CollabLAN")
                    font.pixelSize: Theme.fontSizeHeading
                    font.bold: true
                    font.family: root.displayFont
                    color: Theme.text
                }

                Item { Layout.preferredWidth: Theme.spacingMedium }

                // Badge : nombre de postes detectes sur le reseau local.
                Rectangle {
                    Layout.preferredHeight: 30
                    implicitWidth: peersPillContent.implicitWidth + Theme.spacingMedium * 2
                    radius: height / 2
                    color: root.blueTint
                    border.width: 1
                    border.color: root.blue700

                    RowLayout {
                        id: peersPillContent
                        anchors.centerIn: parent
                        spacing: 6

                        Rectangle {
                            width: 7
                            height: 7
                            radius: 3.5
                            color: root.blue700
                            Layout.alignment: Qt.AlignVCenter
                        }

                        Label {
                            text: qsTr("%1 poste(s) en ligne").arg(root.peersCount)
                            font.pixelSize: Theme.fontSizeSmall
                            font.family: "monospace"
                            color: root.blue700
                        }
                    }
                }

                // Badge : etat de la bascule automatique de serveur
                // (reutilise ServerStatusIndicator, deja au bon format
                // "pastille + texte").
                ServerStatusIndicator {}

                Item { Layout.fillWidth: true }

                ThemeToggleButton {
                    Layout.preferredWidth: 36
                    Layout.preferredHeight: 36
                }

                // ---- Profil (avatar + nom + chevron), menu deroulant ------
                Rectangle {
                    id: profileButton
                    Layout.preferredHeight: 40
                    implicitWidth: profileRow.implicitWidth + Theme.spacingMedium * 2
                    radius: height / 2
                    color: (profileArea.containsMouse || menuPopup.visible) ? Theme.surfaceAlt : Theme.surface
                    border.width: 1
                    border.color: Theme.border
                    Behavior on color { ColorAnimation { duration: 100 } }

                    RowLayout {
                        id: profileRow
                        anchors.centerIn: parent
                        spacing: Theme.spacingSmall

                        Avatar {
                            name: root.username
                            size: 28
                        }

                        Label {
                            text: root.username
                            color: Theme.text
                            font.bold: true
                            font.pixelSize: Theme.fontSizeSmall
                            font.family: Theme.fontFamily
                        }

                        Text {
                            text: menuPopup.visible ? "\u25B4" : "\u25BE"
                            color: Theme.textSecondary
                            font.pixelSize: 10
                        }
                    }

                    MouseArea {
                        id: profileArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: menuPopup.visible = !menuPopup.visible
                    }

                    Popup {
                        id: menuPopup
                        y: profileButton.height + 6
                        x: profileButton.width - width
                        width: 200
                        padding: 6
                        modal: false
                        focus: true
                        closePolicy: Popup.CloseOnPressOutside | Popup.CloseOnEscape

                        background: Rectangle {
                            radius: Theme.radiusMedium
                            color: Theme.surface
                            border.width: 1
                            border.color: Theme.border
                        }

                        contentItem: ColumnLayout {
                            spacing: 2

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 32
                                Layout.margins: Theme.spacingSmall
                                spacing: 6

                                Rectangle {
                                    width: 8
                                    height: 8
                                    radius: 4
                                    color: Theme.success
                                }

                                Label {
                                    text: qsTr("En ligne")
                                    color: Theme.textSecondary
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.family: Theme.fontFamily
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 1
                                color: Theme.border
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 38
                                radius: Theme.radiusSmall
                                color: logoutArea.containsMouse ? Theme.errorMuted : "transparent"
                                Behavior on color { ColorAnimation { duration: 100 } }

                                Label {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.leftMargin: Theme.spacingSmall
                                    text: qsTr("Se déconnecter")
                                    color: Theme.error
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.bold: true
                                    font.family: Theme.fontFamily
                                }

                                MouseArea {
                                    id: logoutArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        menuPopup.close()
                                        root.logoutRequested()
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // ---- Contenu principal --------------------------------------------
        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            contentHeight: contentColumn.implicitHeight + 2 * Theme.spacingXl
            clip: true

            ColumnLayout {
                id: contentColumn
                width: Math.min(parent.width - 2 * Theme.spacingXl, 1200)
                x: Theme.spacingXl
                y: Theme.spacingXl
                spacing: Theme.spacingLarge

                // Bienvenue
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingXs

                    Label {
                        text: qsTr("Bienvenue, %1").arg(root.username)
                        font.pixelSize: 32
                        font.bold: true
                        font.family: root.displayFont
                        color: Theme.text
                    }

                    Label {
                        text: qsTr("Voici un aperçu de votre réseau local.")
                        font.pixelSize: Theme.fontSizeBody
                        font.family: Theme.fontFamily
                        color: Theme.textSecondary
                    }
                }

                // Section Acces rapide
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingSmall

                    Label {
                        text: qsTr("Accès rapide")
                        font.pixelSize: Theme.fontSizeSubheading
                        font.bold: true
                        font.family: Theme.fontFamily
                        color: Theme.text
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: root.width > 1000 ? 4 : (root.width > 700 ? 3 : 2)
                        columnSpacing: Theme.spacingMedium
                        rowSpacing: Theme.spacingMedium

                        DashboardCard {
                            Layout.fillWidth: true
                            icon: "\u2709"
                            title: qsTr("Discussions")
                            description: qsTr("Retrouvez vos conversations et groupes.")
                            onClicked: root.chatRequested()
                        }
                        DashboardCard {
                            Layout.fillWidth: true
                            icon: "\u25CE"
                            title: qsTr("Postes connectes")
                            description: qsTr("Voir qui est present sur le reseau.")
                            onClicked: root.usersRequested()
                        }
                        DashboardCard {
                            Layout.fillWidth: true
                            icon: "\u21C5"
                            title: qsTr("Transfert de fichiers")
                            description: qsTr("Envoyez et recevez des fichiers.")
                            onClicked: root.fileTransferRequested()
                        }
                        DashboardCard {
                            Layout.fillWidth: true
                            icon: "\u260E"
                            title: qsTr("Appels")
                            description: qsTr("Demarrez un appel ou consultez votre historique.")
                            onClicked: root.callRequested()
                        }
                        DashboardCard {
                            Layout.fillWidth: true
                            icon: "📂\uFE0E"
                            title: qsTr("Dossiers partagés")
                            description: qsTr("Partagez un dossier local avec votre réseau.")
                            onClicked: root.sharedFoldersRequested()
                        }
                        DashboardCard {
                            Layout.fillWidth: true
                            icon: "\u2699"
                            title: qsTr("Administration")
                            description: qsTr("Gerez les utilisateurs et les postes.")
                            onClicked: root.adminRequested()
                        }
                    }
                }

            }
        }
    }
}
