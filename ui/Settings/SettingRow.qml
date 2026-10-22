import QtQuick
import QtQuick.Layouts
import Themes
import "../Components"

/*
 * SettingRow - une ligne de reglage : libelle et explication a gauche,
 * reglage a droite ; empilee en fenetre etroite. Filet au-dessus, sauf
 * pour la premiere ligne visible du groupe. `edited` marque une saisie en
 * cours (filet d'encre a gauche, fond feuille) en attendant Enregistrer.
 */
Item {
    id: root

    property string label: ""
    property string labelIcon: ""
    property string help: ""
    property bool dimmed: false         // reglage sans effet (ex. sons coupes)
    property bool edited: false
    default property alias content: controlColumn.data

    readonly property bool stacked: width < 560
    readonly property real labelWidth: Math.max(180, Math.min(300, width * 0.3))
    readonly property bool isFirst: {
        const p = root.parent
        if (!p) return true
        for (let i = 0; i < p.children.length; i++)
            if (p.children[i].visible) return p.children[i] === root
        return true
    }

    Layout.fillWidth: true
    implicitHeight: grid.implicitHeight + 32

    Rectangle {
        visible: root.edited
        x: -14
        width: parent.width + 14
        height: parent.height
        color: Theme.surface0
        Rectangle { width: 3; height: parent.height; color: Theme.ruleInk }
    }
    Rectangle { visible: !root.isFirst; width: parent.width; height: 1; color: Theme.line }

    GridLayout {
        id: grid
        y: 16
        width: parent.width
        columns: root.stacked ? 1 : 2
        columnSpacing: root.width > 900 ? 32 : 24
        rowSpacing: 10

        ColumnLayout {
            Layout.alignment: Qt.AlignTop
            Layout.preferredWidth: root.stacked ? -1 : root.labelWidth
            Layout.maximumWidth: root.stacked ? Number.POSITIVE_INFINITY : root.labelWidth
            Layout.fillWidth: root.stacked
            spacing: 3
            opacity: root.dimmed ? 0.45 : 1
            Row {
                spacing: 10
                LineIcon { visible: root.labelIcon.length > 0; anchors.verticalCenter: parent.verticalCenter; path: root.labelIcon; size: 16; strokeWidth: 1.7; color: Theme.ink3 }
                Text { text: root.label; color: Theme.ink; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13.5); font.weight: Theme.weightSemibold }
            }
            Text {
                visible: root.help.length > 0
                Layout.fillWidth: true
                text: root.help
                wrapMode: Text.WordWrap
                lineHeight: 1.1
                color: Theme.ink3
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(12.5)
            }
        }

        ColumnLayout {
            id: controlColumn
            Layout.alignment: Qt.AlignTop
            Layout.fillWidth: true
            // Sans enfant extensible, une ColumnLayout ne depasse pas sa largeur
            // naturelle et la grille la centrerait : on leve ce plafond.
            Layout.maximumWidth: Number.POSITIVE_INFINITY
            spacing: 8
        }
    }
}
