import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes

/*
 * TableHeader - en-tete de tableau du design system (Postes, Journal
 * d'audit, Administration).
 *
 * columns : [{ title, width (px) | fill: true, sortKey (optionnel),
 *              align: "left" | "right" | "center", visible (optionnel) }]
 * Les lignes du tableau reprennent les memes largeurs (voir
 * TableHeader.cellWidth) pour rester alignees.
 *
 * Tri : clic (ou Espace/Entree) sur un titre portant un sortKey ; un
 * second clic inverse l'ordre. L'hote trie ses donnees sur sortKey /
 * sortAscending.
 */
Rectangle {
    id: root

    property var columns: []
    property string sortKey: ""
    property bool sortAscending: true
    property int sidePadding: Theme.cardPadding

    signal sortRequested(string key)

    implicitHeight: Theme.compact ? 32 : 36
    color: Theme.surface1

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 1
        color: Theme.line
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: root.sidePadding
        anchors.rightMargin: root.sidePadding
        spacing: 12

        Repeater {
            model: root.columns

            delegate: AbstractButton {
                id: cell
                required property var modelData

                readonly property bool sortable: (cell.modelData.sortKey || "").length > 0
                readonly property bool sorted: cell.sortable && cell.modelData.sortKey === root.sortKey

                visible: cell.modelData.visible !== false
                Layout.fillWidth: cell.modelData.fill === true
                Layout.preferredWidth: cell.modelData.fill === true ? 100 : (cell.modelData.width || 100)
                Layout.minimumWidth: cell.modelData.fill === true ? 80 : (cell.modelData.width || 100)
                Layout.fillHeight: true
                enabled: cell.sortable
                hoverEnabled: cell.sortable
                focusPolicy: cell.sortable ? Qt.TabFocus : Qt.NoFocus
                Accessible.role: Accessible.ColumnHeader
                Accessible.name: cell.modelData.title
                onClicked: root.sortRequested(cell.modelData.sortKey)

                HoverHandler { cursorShape: cell.sortable ? Qt.PointingHandCursor : Qt.ArrowCursor }

                background: Rectangle {
                    color: "transparent"
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 4
                        radius: 4
                        color: "transparent"
                        border.width: 2
                        border.color: Theme.focusRing
                        visible: cell.visualFocus
                    }
                }

                contentItem: RowLayout {
                    spacing: 4
                    layoutDirection: cell.modelData.align === "right" ? Qt.RightToLeft : Qt.LeftToRight

                    Text {
                        text: cell.modelData.title
                        color: cell.sorted || cell.hovered ? Theme.ink : Theme.ink3
                        font.pixelSize: Theme.fs(12)
                        font.weight: Theme.weightSemibold
                        font.family: Theme.fontFamily
                        elide: Text.ElideRight
                    }

                    FaIcon {
                        visible: cell.sorted
                        glyph: root.sortAscending ? "" : ""
                        color: Theme.ink2
                        font.pixelSize: Theme.fs(11)
                    }

                    Item { Layout.fillWidth: true }
                }
            }
        }
    }
}
