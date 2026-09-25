import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import "../Components"
import "../Components/icons.js" as Icons

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
            color: Theme.dashboardInk
            font.pixelSize: 15
            font.weight: Theme.weightSemibold
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
            color: Theme.dashboardWarning
            visible: root.actions.length > 0

            Label {
                anchors.centerIn: parent
                text: root.actions.length > 99 ? "99+" : root.actions.length
                color: Theme.dashboardSurface
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
        // Sans cette condition, ce ScrollView vide restait visible en
        // parallèle de l'état vide ci-dessous : les deux Layout.fillHeight
        // se partageaient alors la hauteur disponible (place réservée à un
        // ScrollView sans contenu), ce qui poussait l'état vide dans la
        // moitié basse du panneau au lieu de le centrer.
        visible: root.actions.length > 0
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
                            case "high": return Theme.dashboardError
                            case "medium": return Theme.dashboardWarning
                            default: return Theme.dashboardInfo
                        }
                    }

                    readonly property color actionColorSoft: {
                        switch(modelData.urgency) {
                            case "high": return Theme.dashboardErrorSoft
                            case "medium": return Theme.dashboardWarningSoft
                            default: return Theme.dashboardInfoSoft
                        }
                    }

                    readonly property string urgencyIcon: {
                        switch(modelData.urgency) {
                            case "high": return Icons.alertTriangle
                            case "medium": return Icons.bell
                            default: return Icons.messageCircle
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

                                LineIcon {
                                    anchors.centerIn: parent
                                    path: urgencyIcon
                                    color: Theme.dashboardSurface
                                    size: 14
                                    strokeWidth: 1.9
                                }
                            }

                            // Contenu
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4

                                Label {
                                    text: modelData.title || ""
                                    color: Theme.dashboardInk
                                    font.pixelSize: 13
                                    font.weight: Theme.weightSemibold
                                    font.family: Theme.fontFamily
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }

                                Label {
                                    text: modelData.description || ""
                                    color: Theme.dashboardInkSecondary
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
                                color: parent.hovered ? Theme.surfaceLevel3 : "transparent"
                                radius: 6
                            }
                            contentItem: Label {
                                text: parent.text
                                color: Theme.dashboardPrimary
                                font.pixelSize: 12
                                font.family: Theme.fontFamily
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            onClicked: root.actionRequested(modelData, "examine")
                        }

                        // Badge urgence - soft/texte plutôt qu'aplat coloré
                        // (priorité 18 du brief : la couleur signale, elle
                        // ne décore pas).
                        Rectangle {
                            implicitWidth: urgencyLabelText.implicitWidth + 18
                            Layout.preferredHeight: 22
                            radius: Theme.radiusPill
                            color: actionColorSoft

                            Label {
                                id: urgencyLabelText
                                anchors.centerIn: parent
                                text: urgencyLabel
                                color: actionColor
                                font.pixelSize: 11
                                font.weight: Theme.weightSemibold
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

            LineIcon {
                path: Icons.checkCircle
                color: Theme.dashboardInkTertiary
                size: 28
                strokeWidth: 1.6
                Layout.alignment: Qt.AlignHCenter
            }

            Label {
                text: qsTr("Rien à traiter")
                color: Theme.dashboardInkTertiary
                font.pixelSize: 14
                font.weight: Theme.weightSemibold
                font.family: Theme.fontFamily
                Layout.alignment: Qt.AlignHCenter
            }

            Label {
                text: qsTr("Tout est en ordre")
                color: Theme.dashboardInkSecondary
                font.pixelSize: 12
                font.family: Theme.fontFamily
                Layout.alignment: Qt.AlignHCenter
            }
        }
    }
}
