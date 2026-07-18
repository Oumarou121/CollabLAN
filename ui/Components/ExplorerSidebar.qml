import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes

/*
 * ExplorerSidebar - panneau lateral "ACCES RAPIDE" (168px) partage entre
 * FileTransferView et SharedFolderView (Option B - liste compacte).
 *
 * Le model attendu est un tableau d'objets :
 *   { key: "all", label: qsTr("Tout"), color: Theme.textTertiary, dim: true }
 * "dim" (optionnel) applique une opacite reduite a la pastille (utilise
 * pour l'entree "Tout", neutre par nature).
 */
Rectangle {
    id: root

    property var quickFilters: []
    property string activeFilter: "all"

    signal filterSelected(string key)

    implicitWidth: 168
    color: Theme.surfaceAlt
    border.width: 1
    border.color: Theme.border

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacingSmall
        spacing: 2

        Label {
            text: qsTr("ACCÈS RAPIDE")
            color: Theme.textTertiary
            font.pixelSize: Theme.fontSizeCaption
            font.bold: true
            Layout.topMargin: 4
            Layout.bottomMargin: 4
            Layout.leftMargin: 8
        }

        Repeater {
            model: root.quickFilters

            delegate: Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 34
                radius: Theme.radiusSmall
                color: root.activeFilter === modelData.key ? Theme.selectionBackground
                       : itemArea.containsMouse ? Theme.surfaceHover
                       : "transparent"

                // Lisere d'accent a gauche pour l'element actif (repere
                // visuel qui ne depend pas de la couleur de fond, donc
                // reste visible dans les deux themes).
                Rectangle {
                    visible: root.activeFilter === modelData.key
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: 3
                    radius: 1.5
                    color: Theme.primary
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 8
                    spacing: 8

                    Rectangle {
                        width: 16
                        height: 16
                        radius: 8
                        color: modelData.color || Theme.textTertiary
                        opacity: modelData.dim ? 0.55 : 1
                    }
                    Label {
                        Layout.fillWidth: true
                        text: modelData.label
                        color: root.activeFilter === modelData.key ? Theme.primary : Theme.text
                        font.pixelSize: Theme.fontSizeSmall
                        font.bold: root.activeFilter === modelData.key
                    }
                }

                MouseArea {
                    id: itemArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.filterSelected(modelData.key)
                }
            }
        }

        Item { Layout.fillHeight: true }
    }
}
