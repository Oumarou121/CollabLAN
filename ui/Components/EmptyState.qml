import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes

/*
 * EmptyState - etat vide reutilisable pour les listes du dashboard
 * (Transferts, Activite recente), selon la maquette V2.2.
 *
 * Disposition a plat, alignee a gauche sous l'en-tete de la section :
 * pastille d'icone a gauche, titre + description a droite, bouton
 * d'action optionnel sous le texte (actionText vide = pas de bouton).
 */
ColumnLayout {
    id: root

    // Nom de l'icone filaire de la maquette : "transfer" | "log"
    property string iconName: ""
    property string title: ""
    property string description: ""
    property string actionText: ""

    signal actionClicked()

    spacing: 0

    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 10
        spacing: 12

        Rectangle {
            Layout.alignment: Qt.AlignTop
            Layout.preferredWidth: 38
            Layout.preferredHeight: 38
            radius: 11
            color: Theme.dashboardPrimarySoft

            LineIcon {
                anchors.centerIn: parent
                size: 20
                strokeWidth: 1.75
                color: Theme.dashboardPrimary
                path: root.iconName === "transfer"
                      ? "M7 4 3 8l4 4 M3 8h14 M17 20l4-4-4-4 M21 16H7"
                      : root.iconName === "log"
                        ? "M8 6h13 M8 12h13 M8 18h13 M3 6h0.01 M3 12h0.01 M3 18h0.01"
                        : ""
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            spacing: 2

            Label {
                Layout.fillWidth: true
                Layout.topMargin: 2
                text: root.title
                color: Theme.dashboardInk
                font.pixelSize: 14
                font.bold: true
                font.family: Theme.fontFamily
                elide: Text.ElideRight
            }

            Label {
                Layout.fillWidth: true
                text: root.description
                color: Theme.dashboardInkTertiary
                font.pixelSize: 12
                font.family: Theme.fontFamily
                wrapMode: Text.WordWrap
            }

            Button {
                id: actionBtn
                visible: root.actionText.length > 0
                Layout.topMargin: 8
                implicitHeight: 30
                implicitWidth: actionLabel.implicitWidth + 24
                hoverEnabled: true
                text: root.actionText
                onClicked: root.actionClicked()

                HoverHandler { cursorShape: Qt.PointingHandCursor }

                background: Rectangle {
                    radius: Theme.radiusSmall
                    color: actionBtn.hovered ? Theme.dashboardPrimaryMuted : Theme.dashboardPrimarySoft
                    Behavior on color { ColorAnimation { duration: 100 } }
                }
                contentItem: Label {
                    id: actionLabel
                    text: actionBtn.text
                    color: Theme.dashboardPrimary
                    font.pixelSize: 12
                    font.bold: true
                    font.family: Theme.fontFamily
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }
    }

    Item { Layout.fillHeight: true }
}
