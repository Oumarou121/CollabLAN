import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import "../Components"

/*
 * AboutView - ecran "A propos" (version 1).
 *
 * Meme squelette que les autres ecrans secondaires (AppHeader + colonne
 * centree en cartes SettingsSectionCard, cf. SettingsView.qml) pour rester
 * visuellement coherent avec le reste de l'application. Contenu 100%
 * statique (pas de dependance backend) : nom/version de l'app, editeur
 * (NEXIS), description courte, liste des fonctionnalites principales,
 * pile technique et mentions legales.
 */
Item {
    id: root
    objectName: "aboutView"

    signal backRequested()

    // ---- Constantes de contenu (version 1) --------------------------------
    readonly property string appName: "LocaLink"
    readonly property string appVersion: "1.0.0"
    readonly property string companyName: "NEXIS"
    readonly property string companyFullName: "Next Intelligent Systems"
    readonly property int copyrightYear: 2026

    FontLoader {
        id: iconFont
        source: "../Assets/fonts/fontawesome-webfont.ttf"
    }
    readonly property string iconFontFamily: iconFont.name

    readonly property var features: [
        { icon: "\uf0c0", title: qsTr("Découverte automatique"), desc: qsTr("Les postes du réseau local se détectent et se connectent sans configuration.") },
        { icon: "\uf086", title: qsTr("Messagerie"), desc: qsTr("Conversations individuelles et de groupe en temps réel, avec historique local.") },
        { icon: "\uf095", title: qsTr("Appels vocaux"), desc: qsTr("Appels pair-à-pair chiffrés, sans passer par un serveur externe.") },
        { icon: "\uf0c6", title: qsTr("Transfert de fichiers"), desc: qsTr("Envoi direct entre postes, avec reprise automatique après coupure.") },
        { icon: "\uf07c", title: qsTr("Dossiers partagés"), desc: qsTr("Synchronisation continue entre postes, avec permissions par dossier.") },
        { icon: "\uf132", title: qsTr("Sécurité"), desc: qsTr("Connexions authentifiées par certificat et chiffrées (TLS).") }
    ]

    readonly property var techStack: ["C++23", "Qt 6 / QML", "SQLite", "TCP / UDP", "WebSocket", "WebRTC", "OpenSSL (TLS)"]

    Rectangle {
        anchors.fill: parent
        color: Theme.background
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        AppHeader {
            title: qsTr("À propos")
            onBackRequested: root.backRequested()
        }

        Flickable {
            id: aboutFlickable
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

                // --- En-tete : logo, nom, version, editeur ------------------
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: heroColumn.implicitHeight + Theme.spacingXl * 2
                    radius: Theme.radiusLarge
                    color: Theme.surface
                    border.width: 1
                    border.color: Theme.border
                    antialiasing: true

                    // Bandeau degrade discret en fond, dans l'esprit des
                    // DashboardCard de l'accueil.
                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.radiusLarge
                        antialiasing: true
                        gradient: Gradient {
                            orientation: Gradient.Vertical
                            GradientStop { position: 0.0; color: Theme.primaryMuted }
                            GradientStop { position: 1.0; color: Theme.surface }
                        }
                        opacity: 0.6
                    }

                    ColumnLayout {
                        id: heroColumn
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.top
                        anchors.topMargin: Theme.spacingXl
                        width: parent.width - Theme.spacingXl * 2
                        spacing: Theme.spacingSmall

                        BrandMark {
                            size: 72
                            Layout.alignment: Qt.AlignHCenter
                        }

                        Label {
                            text: root.appName
                            Layout.alignment: Qt.AlignHCenter
                            font.pixelSize: Theme.fontSizeTitle
                            font.bold: true
                            font.family: Theme.fontFamily
                            color: Theme.text
                        }

                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            radius: Theme.radiusPill
                            color: Theme.primaryMuted
                            implicitWidth: versionLabel.implicitWidth + Theme.spacingMedium * 2
                            implicitHeight: versionLabel.implicitHeight + Theme.spacingXs * 2

                            Label {
                                id: versionLabel
                                anchors.centerIn: parent
                                text: qsTr("Version %1").arg(root.appVersion)
                                font.pixelSize: Theme.fontSizeSmall
                                font.bold: true
                                font.family: Theme.fontFamily
                                color: Theme.primary
                            }
                        }

                        Label {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.topMargin: Theme.spacingSmall
                            Layout.maximumWidth: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            text: qsTr("Application de collaboration d'équipe fonctionnant entièrement sur réseau local, sans dépendance à Internet.")
                            font.pixelSize: Theme.fontSizeBody
                            font.family: Theme.fontFamily
                            color: Theme.textSecondary
                        }

                        Label {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.topMargin: Theme.spacingXs
                            text: qsTr("Développé par %1 — %2").arg(root.companyName).arg(root.companyFullName)
                            font.pixelSize: Theme.fontSizeSmall
                            font.family: Theme.fontFamily
                            color: Theme.textTertiary
                        }
                    }
                }

                // --- Fonctionnalites principales ----------------------------
                // SettingsSectionCard {
                //     Layout.fillWidth: true
                //     icon: "\uf00a"
                //     title: qsTr("Fonctionnalités principales")
                //     subtitle: qsTr("Ce que propose cette première version de l'application.")

                //     GridLayout {
                //         Layout.fillWidth: true
                //         columns: width > 520 ? 2 : 1
                //         columnSpacing: Theme.spacingLarge
                //         rowSpacing: Theme.spacingMedium

                //         Repeater {
                //             model: root.features

                //             RowLayout {
                //                 Layout.fillWidth: true
                //                 Layout.alignment: Qt.AlignTop
                //                 spacing: Theme.spacingSmall

                //                 Rectangle {
                //                     Layout.preferredWidth: 32
                //                     Layout.preferredHeight: 32
                //                     Layout.alignment: Qt.AlignTop
                //                     radius: Theme.radiusMedium
                //                     color: Theme.primaryMuted

                //                     Text {
                //                         anchors.centerIn: parent
                //                         text: modelData.icon
                //                         font.family: root.iconFontFamily
                //                         font.pixelSize: Theme.fs(13)
                //                         color: Theme.primary
                //                     }
                //                 }

                //                 ColumnLayout {
                //                     Layout.fillWidth: true
                //                     spacing: 1

                //                     Label {
                //                         text: modelData.title
                //                         font.pixelSize: Theme.fontSizeBody
                //                         font.bold: true
                //                         font.family: Theme.fontFamily
                //                         color: Theme.text
                //                     }
                //                     Label {
                //                         text: modelData.desc
                //                         font.pixelSize: Theme.fontSizeSmall
                //                         font.family: Theme.fontFamily
                //                         color: Theme.textTertiary
                //                         wrapMode: Text.WordWrap
                //                         Layout.fillWidth: true
                //                     }
                //                 }
                //             }
                //         }
                //     }
                // }

                // --- Editeur / mentions legales -------------------------------
                SettingsSectionCard {
                    Layout.fillWidth: true
                    icon: "\uf1ad"
                    title: qsTr("Éditeur")

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingXs

                        Label {
                            text: qsTr("%1 (%2)").arg(root.companyName).arg(root.companyFullName)
                            font.pixelSize: Theme.fontSizeBody
                            font.bold: true
                            font.family: Theme.fontFamily
                            color: Theme.text
                        }
                        Label {
                            text: qsTr("© %1 %2. Tous droits réservés.").arg(root.copyrightYear).arg(root.companyName)
                            font.pixelSize: Theme.fontSizeSmall
                            font.family: Theme.fontFamily
                            color: Theme.textTertiary
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 1
                            Layout.topMargin: Theme.spacingSmall
                            Layout.bottomMargin: Theme.spacingSmall
                            color: Theme.border
                        }

                        Label {
                            text: qsTr("Distribué sous licence MIT.")
                            font.pixelSize: Theme.fontSizeSmall
                            font.family: Theme.fontFamily
                            color: Theme.textTertiary
                        }
                    }
                }

                Item { Layout.preferredHeight: Theme.spacingSmall }
            }
        }
    }
}
