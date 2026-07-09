import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes

/*
 * UsersView - liste des postes decouverts en temps reel sur le reseau
 * local (issue #17).
 *
 * La vue est purement reactive : elle se contente d'afficher le contenu
 * du modele QML "peersModel" (network::PeersModel, expose depuis
 * app/main.cpp), lequel est mis a jour ligne par ligne par
 * DiscoveryService a chaque decouverte / mise a jour / perte de poste.
 * Aucune action manuelle (bouton "rafraichir"...) n'est necessaire : la
 * ListView se met a jour automatiquement via les signaux du modele.
 */
Item {
    id: root

    // Modele optionnel : permet de charger cette vue dans un contexte de
    // preview/design (Qt Design Studio, tests QML) sans que "peersModel"
    // soit defini dans le contexte racine.
    property var model: (typeof peersModel !== "undefined") ? peersModel : null

    signal backRequested()

    Rectangle {
        anchors.fill: parent
        color: Theme.background
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacingLarge
        spacing: Theme.spacingMedium

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSmall

            Button {
                text: qsTr("< Retour")
                Layout.preferredHeight: 32

                background: Rectangle {
                    radius: Theme.radiusSmall
                    color: parent.hovered ? Theme.surfaceAlt : "transparent"
                    border.width: 1
                    border.color: Theme.border
                }

                contentItem: Text {
                    text: qsTr("< Retour")
                    color: Theme.text
                    font.pixelSize: Theme.fontSizeSmall
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                onClicked: root.backRequested()
            }

            Label {
                text: qsTr("Postes connectes")
                font.pixelSize: Theme.fontSizeHeading
                font.bold: true
                font.family: Theme.fontFamily
                color: Theme.text
            }

            Item { Layout.fillWidth: true }

            Rectangle {
                Layout.preferredWidth: countLabel.implicitWidth + Theme.spacingMedium
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
                }
            }
        }

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
                visible: listView.count === 0
                width: parent.width * 0.7

                Label {
                    Layout.alignment: Qt.AlignHCenter
                    text: qsTr("Aucun poste detecte pour le moment")
                    font.pixelSize: Theme.fontSizeBody
                    font.bold: true
                    color: Theme.text
                    horizontalAlignment: Text.AlignHCenter
                }

                Label {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.fillWidth: true
                    text: qsTr("Les postes du reseau local apparaissent ici automatiquement des qu'ils sont detectes.")
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeSmall
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }
            }

            ListView {
                id: listView
                anchors.fill: parent
                anchors.margins: Theme.spacingSmall
                spacing: Theme.spacingSmall
                clip: true
                model: root.model

                // Anime discretement les postes qui apparaissent/disparaissent,
                // pour que la mise a jour "temps reel" soit lisible a l'oeil.
                add: Transition {
                    NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 150 }
                }
                remove: Transition {
                    NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 150 }
                }
                displaced: Transition {
                    NumberAnimation { properties: "y"; duration: 150 }
                }

                delegate: Rectangle {
                    width: listView.width
                    height: 60
                    radius: Theme.radiusMedium
                    color: Theme.surfaceAlt

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.spacingMedium
                        anchors.rightMargin: Theme.spacingMedium
                        spacing: Theme.spacingMedium

                        Rectangle {
                            width: 36
                            height: 36
                            radius: 18
                            color: Theme.primary

                            Text {
                                anchors.centerIn: parent
                                text: name && name.length > 0 ? name.charAt(0).toUpperCase() : "?"
                                color: Theme.primaryText
                                font.pixelSize: 14
                                font.bold: true
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Label {
                                text: name
                                color: Theme.text
                                font.pixelSize: Theme.fontSizeBody
                                font.bold: true
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }

                            Label {
                                text: address + (port ? (":" + port) : "")
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontSizeSmall
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }

                        // Pastille de statut ("online"/"away"/"busy"...) mise a
                        // jour automatiquement en cas de peerUpdated (ex.
                        // changement de statut cote poste distant).
                        RowLayout {
                            spacing: Theme.spacingSmall / 2

                            Rectangle {
                                width: 8
                                height: 8
                                radius: 4
                                color: status === "online" ? Theme.success
                                       : status === "busy" ? Theme.error
                                       : Theme.textSecondary
                            }

                            Label {
                                text: status
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontSizeSmall
                                font.capitalization: Font.Capitalize
                            }
                        }
                    }
                }
            }
        }
    }
}
