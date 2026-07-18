import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import "../Components"

/*
 * UsersView - liste des postes decouverts en temps reel sur le reseau
 * local (issue #17).
 *
 * La vue est purement reactive : elle se contente d'afficher le contenu
 * du modele QML "peersModel" (network::PeersModel, expose depuis
 * app/main.cpp), lequel est mis a jour ligne par ligne par
 * DiscoveryService a chaque decouverte / mise a jour / perte de poste.
 * Aucune action manuelle (bouton "rafraichir"...) n'est necessaire : la
 * GridView se met a jour automatiquement via les signaux du modele.
 *
 * Refonte design (juillet 2026) : alignement sur le style deja retenu
 * pour LoginView/HomeView/SettingsView -- barre superieure identique
 * (bouton retour circulaire + titre), contenu centre a largeur maximale,
 * et grille de cartes "poste" (au lieu d'une simple liste) qui se
 * reorganise en 1/2/3 colonnes selon la largeur disponible (memes seuils
 * que la grille d'acces rapide de HomeView), pour un rendu adapte aux
 * differentes resolutions/tailles de fenetre sur desktop. Chaque carte
 * reutilise le composant Avatar (pastille de statut incluse) deja
 * partage avec Chat/Call/FileTransfer/SharedFolder.
 */
Item {
    id: root

    // Modele optionnel : permet de charger cette vue dans un contexte de
    // preview/design (Qt Design Studio, tests QML) sans que "peersModel"
    // soit defini dans le contexte racine.
    property var model: (typeof peersModel !== "undefined") ? peersModel : null

    signal backRequested()

    // Libelle + couleurs (badge) associes a un statut de poste.
    function statusLabel(status) {
        switch (status) {
        case "online": return qsTr("En ligne")
        case "busy": return qsTr("Occupé")
        case "away": return qsTr("Absent")
        default: return status
        }
    }
    function statusColor(status) {
        switch (status) {
        case "online": return Theme.success
        case "busy": return Theme.error
        case "away": return Theme.warning
        default: return Theme.textSecondary
        }
    }
    function statusMutedColor(status) {
        switch (status) {
        case "online": return Theme.successMuted
        case "busy": return Theme.errorMuted
        case "away": return Theme.warningMuted
        default: return Theme.surfaceAlt
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.background
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ---- Barre superieure (composant partage, cf. Components/AppHeader.qml) --
        AppHeader {
            title: qsTr("Postes connectés")
            onBackRequested: root.backRequested()

            Rectangle {
                Layout.preferredWidth: countLabel.implicitWidth + Theme.spacingMedium * 2
                Layout.preferredHeight: 28
                radius: height / 2
                color: Theme.surfaceAlt
                border.color: Theme.border
                border.width: 1

                Label {
                    id: countLabel
                    anchors.centerIn: parent
                    text: root.model ? qsTr("%n poste(s)", "", root.model.count) : qsTr("0 poste")
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeSmall
                    font.family: Theme.fontFamily
                }
            }
        }

        // ---- Contenu principal : grille centree, largeur maximale ---------
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ColumnLayout {
                id: contentColumn
                width: Math.min(parent.width - 2 * Theme.spacingXl, 1200)
                height: parent.height - 2 * Theme.spacingLarge
                x: (parent.width - width) / 2
                y: Theme.spacingLarge
                spacing: 0

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Theme.radiusLarge
                    color: Theme.surface
                    border.color: Theme.border
                    border.width: 1
                    clip: true

                    // Etat vide : affiche tant qu'aucun poste n'a ete decouvert.
                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: Theme.spacingSmall
                        visible: gridView.count === 0
                        width: parent.width * 0.6

                        Label {
                            Layout.alignment: Qt.AlignHCenter
                            text: qsTr("Aucun poste détecté pour le moment")
                            font.pixelSize: Theme.fontSizeBody
                            font.bold: true
                            font.family: Theme.fontFamily
                            color: Theme.text
                            horizontalAlignment: Text.AlignHCenter
                        }

                        Label {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.fillWidth: true
                            text: qsTr("Les postes du réseau local apparaissent ici automatiquement dès qu'ils sont détectés.")
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeSmall
                            font.family: Theme.fontFamily
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                        }
                    }

                    GridView {
                        id: gridView
                        anchors.fill: parent
                        anchors.margins: Theme.spacingMedium
                        clip: true
                        model: root.model

                        // Seuils alignes sur la grille d'acces rapide de
                        // HomeView (.card-grid) : 3 colonnes par defaut,
                        // 2 sous 900px, 1 sous 560px - la grille se
                        // reorganise donc selon la resolution/largeur de
                        // fenetre disponible sur desktop.
                        readonly property int columns: width > 900 ? 3 : (width > 560 ? 2 : 1)
                        cellWidth: width / columns
                        cellHeight: 112

                        // Anime discretement les postes qui apparaissent/
                        // disparaissent, pour que la mise a jour "temps
                        // reel" soit lisible a l'oeil.
                        add: Transition {
                            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 150 }
                        }
                        remove: Transition {
                            NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 150 }
                        }
                        displaced: Transition {
                            NumberAnimation { properties: "x,y"; duration: 150 }
                        }

                        delegate: Item {
                            width: gridView.cellWidth
                            height: gridView.cellHeight

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: Theme.spacingSmall / 2
                                radius: Theme.radiusMedium
                                color: Theme.surfaceAlt
                                border.width: 1
                                border.color: Theme.border

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: Theme.spacingMedium
                                    spacing: Theme.spacingMedium

                                    Avatar {
                                        name: model.name
                                        size: 44
                                        showStatus: true
                                        online: model.status === "online"
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 3

                                        Label {
                                            text: model.name
                                            color: Theme.text
                                            font.pixelSize: Theme.fontSizeBody
                                            font.bold: true
                                            font.family: Theme.fontFamily
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }

                                        Label {
                                            text: model.address + (model.port ? (":" + model.port) : "")
                                            color: Theme.textSecondary
                                            font.pixelSize: Theme.fontSizeSmall
                                            font.family: Theme.fontFamily
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }

                                        Rectangle {
                                            Layout.topMargin: 2
                                            Layout.preferredWidth: statusRow.implicitWidth + Theme.spacingSmall * 2
                                            Layout.preferredHeight: 20
                                            radius: height / 2
                                            color: root.statusMutedColor(model.status)

                                            RowLayout {
                                                id: statusRow
                                                anchors.centerIn: parent
                                                spacing: 5

                                                Rectangle {
                                                    width: 6
                                                    height: 6
                                                    radius: 3
                                                    color: root.statusColor(model.status)
                                                }

                                                Label {
                                                    text: root.statusLabel(model.status)
                                                    color: root.statusColor(model.status)
                                                    font.pixelSize: Theme.fontSizeCaption
                                                    font.family: Theme.fontFamily
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
