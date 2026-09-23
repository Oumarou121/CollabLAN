import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import "../Components"

/*
 * ActionRequiredPanel - Zone "À traiter" selon la maquette HTML exacte
 * Background: transparent (le fond vient du parent)
 * Header: "À traiter" + badge compteur
 * Items: Design avec border-left couleur + icône + texte + boutons
 */
ColumnLayout {
    id: root
    spacing: 0

    property var actions: []

    signal actionRequested(var action, string actionType)

    // Header - height 32px
    RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: 32
        spacing: 8

        Label {
            text: qsTr("À traiter")
            color: "#15222B"
            font.pixelSize: 15
            font.bold: true
            font.family: Theme.fontFamily
        }

        Item {
            Layout.fillWidth: true
        }

        // Badge compteur
        Rectangle {
            Layout.preferredWidth: 20
            Layout.preferredHeight: 20
            radius: 10
            color: "#C27A0E"
            visible: root.actions.length > 0

            Label {
                anchors.centerIn: parent
                text: root.actions.length > 99 ? "99+" : root.actions.length
                color: "#FFFFFF"
                font.pixelSize: 11
                font.bold: true
                font.family: Theme.fontFamily
            }
        }
    }

    // Liste des items
    ScrollView {
        id: itemsScroll
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: ScrollBar.AsNeeded

        ColumnLayout {
            // availableWidth (et non parent.width) : le parent est le
            // contentItem du Flickable, dont la largeur vaut la largeur
            // implicite du contenu - d'où des cartes plus étroites que la
            // colonne. availableWidth = largeur réelle du viewport.
            width: itemsScroll.availableWidth
            spacing: 14

            Repeater {
                model: root.actions
                delegate: ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    readonly property color actionColor: {
                        switch(modelData.urgency) {
                            case "high": return "#C8453B"
                            case "medium": return "#C27A0E"
                            default: return "#3A78B8"
                        }
                    }

                    readonly property color actionColorSoft: {
                        switch(modelData.urgency) {
                            case "high": return "#FBE9E7"
                            case "medium": return "#FCF1DC"
                            default: return "#E5EEF8"
                        }
                    }

                    readonly property string urgencyIcon: {
                        switch(modelData.urgency) {
                            case "high": return "\uf071"
                            case "medium": return "\uf132"
                            default: return "\uf0e5"
                        }
                    }

                    readonly property string urgencyLabel: {
                        switch(modelData.urgency) {
                            case "high": return "Alerte"
                            case "medium": return "Action requise"
                            default: return "Information"
                        }
                    }

                    // Item avec border-left couleur
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 60
                        color: actionColorSoft
                        radius: 8

                        Rectangle {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: 3
                            color: actionColor
                            radius: 2
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 10

                            // Icône
                            Rectangle {
                                Layout.preferredWidth: 28
                                Layout.preferredHeight: 28
                                radius: 7
                                color: actionColor

                                FaIcon {
                                    anchors.centerIn: parent
                                    glyph: urgencyIcon
                                    color: "#FFFFFF"
                                    font.pixelSize: 14
                                }
                            }

                            // Contenu
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4

                                Label {
                                    text: modelData.title || ""
                                    color: "#15222B"
                                    font.pixelSize: 13
                                    font.bold: true
                                    font.family: Theme.fontFamily
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }

                                Label {
                                    text: modelData.description || ""
                                    color: "#4A5961"
                                    font.pixelSize: 12
                                    font.family: Theme.fontFamily
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                    maximumLineCount: 2
                                }
                            }
                        }
                    }

                    // Boutons d'action
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Item {
                            Layout.fillWidth: true
                        }

                        Button {
                            text: qsTr("Examiner")
                            flat: true
                            font.pixelSize: 12
                            font.family: Theme.fontFamily
                            background: Rectangle {
                                color: parent.hovered ? "#F5F9F9" : "transparent"
                                radius: 6
                            }
                            contentItem: Label {
                                text: parent.text
                                color: "#0B5C70"
                                font.pixelSize: 12
                                font.family: Theme.fontFamily
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            onClicked: root.actionRequested(modelData, "examine")
                        }

                        // Badge urgence
                        Rectangle {
                            Layout.preferredWidth: 90
                            Layout.preferredHeight: 24
                            radius: 12
                            color: actionColor

                            Label {
                                anchors.centerIn: parent
                                text: urgencyLabel
                                color: "#FFFFFF"
                                font.pixelSize: 11
                                font.bold: true
                                font.family: Theme.fontFamily
                            }
                        }
                    }
                }
            }
        }
    }

    // État vide
    Item {
        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: root.actions.length === 0

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 12

            FaIcon {
                glyph: "\uf1de"
                color: "#62717A"
                font.pixelSize: 28
                Layout.alignment: Qt.AlignHCenter
            }

            Label {
                text: qsTr("Rien à traiter")
                color: "#62717A"
                font.pixelSize: 14
                font.bold: true
                font.family: Theme.fontFamily
                Layout.alignment: Qt.AlignHCenter
            }

            Label {
                text: qsTr("Tout est en ordre")
                color: "#4A5961"
                font.pixelSize: 12
                font.family: Theme.fontFamily
                Layout.alignment: Qt.AlignHCenter
            }
        }
    }
}
