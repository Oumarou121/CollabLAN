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
 *
 * Grille realignee sur admin-home.component.scss :
 * max-width 1400px, gap 20px, 3 colonnes par defaut, 2 sous 980px, 1 sous 560px.
 */
Item {
    id: root

    property string username: ""

    // Reserve l'acces a la carte "Administration" aux administrateurs
    // (les autres utilisateurs ne doivent plus la voir sur le Home).
    readonly property bool isAdmin: (typeof userManager !== "undefined" && userManager) ? userManager.currentUserIsAdmin : false

    signal logoutRequested()
    signal usersRequested()
    signal chatRequested()
    signal fileTransferRequested()
    signal callRequested()
    signal adminRequested()
    signal settingsRequested()
    signal sharedFoldersRequested()
    signal aboutRequested()

    // Nombre de postes detectes sur le reseau local (network::PeersModel,
    // cf. app/main.cpp). Repli a 0 en contexte preview/design sans backend.
    readonly property int peersCount: (typeof peersModel !== "undefined" && peersModel) ? peersModel.count : 0

    // Etat de la bascule automatique de serveur (electionService, cf.
    // app/main.cpp) - affiche desormais dans le menu profil plutot qu'en
    // badge separe dans l'en-tete.
    readonly property var election: (typeof electionService !== "undefined") ? electionService : null
    property bool serverReconnecting: false

    Connections {
        target: root.election
        function onHeartbeatLost() { root.serverReconnecting = true }
        function onRoleChanged() { root.serverReconnecting = false }
    }

    readonly property string serverStatusLabel: {
        if (!root.election)
            return ""
        if (root.serverReconnecting)
            return qsTr("Reconnexion en cours...")
        if (root.election.roleLabel === "TEMP_SERVER")
            return qsTr("Mode secours (serveur de secours actif)")
        if (root.election.roleLabel === "SERVER")
            return qsTr("Serveur actif")
        return qsTr("Connecté au serveur")
    }

    readonly property color serverStatusColor: {
        if (!root.election)
            return Theme.textSecondary
        if (root.serverReconnecting)
            return Theme.warning
        if (root.election.roleLabel === "TEMP_SERVER")
            return Theme.warning
        return Theme.success
    }

    // ---- Jetons locaux (alignes sur LoginView, meme palette navy) ----
    readonly property color blue700: Theme.darkMode ? "#3E6C99" : "#1E3A5F"
    readonly property color blue600: Theme.darkMode ? "#4E86B8" : "#2E6BAA"
    readonly property color blueTint: Theme.darkMode ? "#1B2531" : "#E8F1F9"
    readonly property color accentSky: "#4FC3F7"

    // Meme police d'accent embarquee que LoginView, pour un rendu identique
    // quel que soit le poste.
    FontLoader {
        id: serifFont
        source: "../Assets/fonts/PTSerif-Bold.ttf"
    }
    readonly property string displayFont: serifFont.status === FontLoader.Ready ? serifFont.name : "serif"

    // Le badge "postes en ligne" est centre sur toute la largeur de
    // l'en-tete (anchors.centerIn), independamment du lockup a gauche et
    // du profil a droite : sous une certaine largeur de fenetre (proche du
    // minimumWidth de 640px defini dans Main.qml), son texte le plus long
    // ("Recherche des postes...") peut chevaucher ces deux blocs. Sous ce
    // seuil, on bascule sur une version compacte (pastille seule, sans
    // libelle) pour eviter tout chevauchement visuel.
    readonly property bool showPeersLabel: root.width >= 760

    Rectangle {
        anchors.fill: parent
        color: Theme.background
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ---- En-tete : marque, badge central, profil -----------------------
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 72
            color: Theme.surface
            border.width: 1
            border.color: Theme.border

            Item {
                anchors.fill: parent
                anchors.margins: Theme.spacingLarge

                // ---- Lockup de marque (logo + nom), aligne a gauche -------
                RowLayout {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingSmall

                    Rectangle {
                        width: 44
                        height: 44
                        radius: Theme.radiusMedium
                        color: root.blue700

                        Image {
                            anchors.fill: parent
                            anchors.margins: 9
                            source: "../Assets/logo.png"
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                            mipmap: true
                        }
                    }

                    ColumnLayout {
                        spacing: -2

                        Label {
                            text: qsTr("CollabLAN")
                            font.pixelSize: 19
                            font.bold: true
                            font.family: root.displayFont
                            font.letterSpacing: 0.4
                            color: Theme.text
                        }

                        Label {
                            text: qsTr("Réseau local")
                            font.pixelSize: 11
                            font.family: Theme.fontFamily
                            color: root.blue600
                        }
                    }
                }

                // ---- Badge central : nombre de postes en ligne ------------
                Rectangle {
                    id: peersBadge
                    anchors.centerIn: parent
                    height: 30
                    implicitWidth: peersPillContent.implicitWidth + Theme.spacingMedium * 2
                    radius: height / 2
                    color: peersBadgeArea.containsMouse ? root.blue700 : root.blueTint
                    border.width: 1
                    border.color: root.blue700
                    Behavior on color { ColorAnimation { duration: 150 } }

                    RowLayout {
                        id: peersPillContent
                        anchors.centerIn: parent
                        spacing: 6

                        Rectangle {
                            id: peersDot
                            width: 7
                            height: 7
                            radius: 3.5
                            color: peersBadgeArea.containsMouse ? "#ffffff" : root.blue700
                            Layout.alignment: Qt.AlignVCenter
                            Behavior on color { ColorAnimation { duration: 150 } }

                            // Pastille pulsante tant qu'aucun poste n'est
                            // encore detecte sur le reseau (decouverte en
                            // cours), pour eviter l'impression d'un badge
                            // fige/casse a "0 poste(s) en ligne".
                            SequentialAnimation on opacity {
                                running: root.peersCount === 0
                                loops: Animation.Infinite
                                NumberAnimation { to: 0.25; duration: 650; easing.type: Easing.InOutQuad }
                                NumberAnimation { to: 1.0; duration: 650; easing.type: Easing.InOutQuad }
                                onRunningChanged: if (!running) peersDot.opacity = 1.0
                            }
                        }

                        Label {
                            visible: root.showPeersLabel
                            text: root.peersCount === 0
                                  ? qsTr("Recherche des postes...")
                                  : qsTr("%1 poste(s) en ligne").arg(root.peersCount)
                            font.pixelSize: Theme.fontSizeSmall
                            font.family: "monospace"
                            color: peersBadgeArea.containsMouse ? "#ffffff" : root.blue700
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }
                    }

                    MouseArea {
                        id: peersBadgeArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.usersRequested()

                        ToolTip.visible: !root.showPeersLabel && containsMouse
                        ToolTip.delay: 300
                        ToolTip.text: root.peersCount === 0
                                      ? qsTr("Recherche des postes...")
                                      : qsTr("%1 poste(s) en ligne").arg(root.peersCount)
                    }
                }

                // ---- Profil (avatar + nom + chevron), menu deroulant ------
                Rectangle {
                    id: profileButton
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: 44
                    implicitWidth: profileRow.implicitWidth + Theme.spacingMedium * 2
                    radius: height / 2
                    color: (profileArea.containsMouse || menuPopup.visible) ? Theme.surfaceAlt : Theme.surface
                    border.width: 1
                    border.color: Theme.border
                    Behavior on color { ColorAnimation { duration: 150 } }

                    RowLayout {
                        id: profileRow
                        anchors.centerIn: parent
                        spacing: Theme.spacingSmall

                        Avatar {
                            name: root.username
                            size: 30
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
                        width: 230
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

                            // Statut du compte
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

                            // Statut de la bascule automatique de serveur
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 32
                                Layout.margins: Theme.spacingSmall
                                spacing: 6
                                visible: root.serverStatusLabel.length > 0

                                Rectangle {
                                    width: 8
                                    height: 8
                                    radius: 4
                                    color: root.serverStatusColor
                                }

                                Label {
                                    text: root.serverStatusLabel
                                    color: Theme.textSecondary
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.family: Theme.fontFamily
                                    wrapMode: Text.WordWrap
                                    Layout.fillWidth: true
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 1
                                Layout.topMargin: 2
                                Layout.bottomMargin: 2
                                color: Theme.border
                            }

                            // Bascule theme clair / sombre
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 36
                                Layout.margins: Theme.spacingSmall
                                spacing: 6

                                Label {
                                    text: Theme.darkMode ? qsTr("Thème sombre") : qsTr("Thème clair")
                                    color: Theme.text
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.family: Theme.fontFamily
                                    Layout.fillWidth: true
                                }

                                Rectangle {
                                    id: themeSwitchTrack
                                    width: 38
                                    height: 22
                                    radius: 11
                                    color: Theme.darkMode ? root.blue600 : Theme.border
                                    Behavior on color { ColorAnimation { duration: 150 } }

                                    Rectangle {
                                        width: 18
                                        height: 18
                                        radius: 9
                                        color: "#FFFFFF"
                                        anchors.verticalCenter: parent.verticalCenter
                                        x: Theme.darkMode ? parent.width - width - 2 : 2
                                        Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: Theme.toggle()
                                    }
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 1
                                color: Theme.border
                            }

                            // Acces aux parametres (issue : disponible a
                            // tous les utilisateurs, plus seulement aux
                            // administrateurs - Ports
                            // reseau restent filtres dans SettingsView).
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 38
                                radius: Theme.radiusSmall
                                color: settingsArea.containsMouse ? Theme.surfaceHover : "transparent"
                                Behavior on color { ColorAnimation { duration: 150 } }

                                Label {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.leftMargin: Theme.spacingSmall
                                    text: qsTr("Paramètres")
                                    color: Theme.text
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.family: Theme.fontFamily
                                }

                                MouseArea {
                                    id: settingsArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        menuPopup.close()
                                        root.settingsRequested()
                                    }
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 1
                                color: Theme.border
                            }

                            // Acces a l'ecran "A propos" (nom/version de
                            // l'application, editeur NEXIS, fonctionnalites).
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 38
                                radius: Theme.radiusSmall
                                color: aboutArea.containsMouse ? Theme.surfaceHover : "transparent"
                                Behavior on color { ColorAnimation { duration: 150 } }

                                Label {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.leftMargin: Theme.spacingSmall
                                    text: qsTr("À propos")
                                    color: Theme.text
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.family: Theme.fontFamily
                                }

                                MouseArea {
                                    id: aboutArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        menuPopup.close()
                                        root.aboutRequested()
                                    }
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
                                Behavior on color { ColorAnimation { duration: 150 } }

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
                // max-width: 1400px comme la reference SCSS (.card-grid)
                width: Math.min(parent.width - 2 * Theme.spacingXl, 1400)
                // Centre horizontalement le bloc de contenu (margin: 0 auto)
                x: (parent.width - width) / 2
                y: Theme.spacingXl
                    spacing: Theme.spacingXl

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingLarge

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        spacing: Theme.spacingXs

                        Label {
                            text: root.username.length > 0
                                  ? qsTr("Bonjour, %1").arg(root.username)
                                  : qsTr("Bienvenue dans CollabLAN")
                            font.pixelSize: Theme.fontSizeTitle
                            font.bold: true
                            font.family: Theme.fontFamily
                            color: Theme.text
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        Label {
                            text: qsTr("Retrouvez vos équipes et vos fichiers sur votre réseau local.")
                            font.pixelSize: Theme.fontSizeBody
                            font.family: Theme.fontFamily
                            color: Theme.textSecondary
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                    }

                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        Layout.preferredHeight: 36
                        implicitWidth: networkStatusRow.implicitWidth + Theme.spacingMedium * 2
                        radius: Theme.radiusSmall
                        color: Theme.surface
                        border.width: 1
                        border.color: Theme.border

                        RowLayout {
                            id: networkStatusRow
                            anchors.centerIn: parent
                            spacing: Theme.spacingSmall

                            Rectangle {
                                Layout.preferredWidth: 8
                                Layout.preferredHeight: 8
                                radius: 4
                                color: root.serverStatusColor
                            }

                            Label {
                                text: root.peersCount > 0
                                      ? qsTr("%1 poste(s) en ligne").arg(root.peersCount)
                                      : qsTr("Réseau local")
                                font.pixelSize: Theme.fontSizeSmall
                                font.bold: true
                                font.family: Theme.fontFamily
                                color: Theme.textSecondary
                            }
                        }
                    }
                }

                // Grille d'acces rapide
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingSmall

                    Label {
                        text: qsTr("Accès rapides")
                        font.pixelSize: Theme.fontSizeHeading
                        font.bold: true
                        font.family: Theme.fontFamily
                        color: Theme.text
                        Layout.bottomMargin: 4
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        // Seuils alignes sur .card-grid : 3 colonnes par
                        // defaut, 2 sous 980px, 1 sous 560px.
                        columns: contentColumn.width > 980 ? 3 : (contentColumn.width > 560 ? 2 : 1)
                        columnSpacing: Theme.spacingMedium
                        rowSpacing: Theme.spacingMedium

                        DashboardCard {
                            Layout.fillWidth: true
                            icon: "\uf0e0"
                            title: qsTr("Discussions")
                            description: qsTr("Retrouvez vos conversations et groupes.")
                            onClicked: root.chatRequested()
                        }
                        DashboardCard {
                            Layout.fillWidth: true
                            icon: "\uf0ec"
                            title: qsTr("Transfert de fichiers")
                            description: qsTr("Envoyez et recevez des fichiers.")
                            onClicked: root.fileTransferRequested()
                        }
                        DashboardCard {
                            Layout.fillWidth: true
                            icon: "\uf095"
                            title: qsTr("Appels")
                            description: qsTr("Demarrez un appel ou consultez votre historique.")
                            onClicked: root.callRequested()
                        }
                        DashboardCard {
                            Layout.fillWidth: true
                            icon: "\uf07c"
                            title: qsTr("Dossiers partagés")
                            description: qsTr("Partagez un dossier local avec votre réseau.")
                            onClicked: root.sharedFoldersRequested()
                        }
                        DashboardCard {
                            Layout.fillWidth: true
                            visible: root.isAdmin
                            icon: "\uf013"
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
