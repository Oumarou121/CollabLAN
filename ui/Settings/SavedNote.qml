import QtQuick
import QtQuick.Layouts
import Themes
import "../Components"
import "../Components/icons.js" as Icons

/*
 * SavedNote - « ✓ Enregistré » vert, affiche apres un enregistrement
 * sur la ligne concernee.
 */
Row {
    id: root
    property string text: qsTr("Enregistré")
    spacing: 6
    Layout.alignment: Qt.AlignLeft
    LineIcon { anchors.verticalCenter: parent.verticalCenter; path: Icons.check; size: 13; strokeWidth: 2.2; color: Theme.successInk }
    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.text
        color: Theme.successInk
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fs(12)
        font.weight: Theme.weightSemibold
    }
}
