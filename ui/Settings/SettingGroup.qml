import QtQuick
import QtQuick.Layouts
import Themes
import "../Components"

/*
 * SettingGroup - groupe de reglages en Ligne claire : titre serif pose sur
 * un filet d'encre, portee du groupe ecrite a droite (« Vous, sur ce
 * poste · immédiat »...), puis les lignes (SettingRow).
 */
ColumnLayout {
    id: root

    property string title: ""
    property string scopeIcon: ""
    property string scopeText: ""       // texte riche : <b> marque a qui s'applique le groupe
    property bool first: false
    default property alias rows: rowsColumn.data

    Layout.fillWidth: true
    Layout.topMargin: root.first ? 4 : 22
    spacing: 0

    Rectangle { visible: !root.first; Layout.fillWidth: true; Layout.preferredHeight: 2; color: Theme.ruleInk }

    GridLayout {
        Layout.fillWidth: true
        Layout.topMargin: root.first ? 6 : 10
        columns: root.width < 560 ? 1 : 2
        columnSpacing: 16
        rowSpacing: 4
        Text {
            Layout.fillWidth: true
            text: root.title
            color: Theme.ink
            font.family: Theme.fontFamilySerif
            font.pixelSize: Theme.fs(18)
            font.weight: Theme.weightBold
            Accessible.role: Accessible.Heading
        }
        Row {
            visible: root.scopeText.length > 0
            spacing: 6
            LineIcon { anchors.verticalCenter: parent.verticalCenter; path: root.scopeIcon; size: 13; strokeWidth: 1.7; color: Theme.ink3 }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.StyledText
                text: root.scopeText
                color: Theme.ink3
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(11.5)
            }
        }
    }

    ColumnLayout {
        id: rowsColumn
        Layout.fillWidth: true
        spacing: 0
    }
}
