import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Themes
import "../Components"

/*
 * InkSegmented - choix exclusif en cases jointives a filet ; la case
 * choisie est pleine d'encre. options : [{ label, value, icon? }].
 */
Rectangle {
    id: root

    property var options: []
    property var current
    signal picked(var value)
    Layout.alignment: Qt.AlignLeft

    implicitWidth: segRow.implicitWidth + 2
    implicitHeight: 34
    radius: Theme.radiusSheet
    color: "transparent"
    border.width: 1
    border.color: Theme.lineStrong
    Accessible.role: Accessible.Grouping

    Row {
        id: segRow
        x: 1; y: 1
        height: parent.height - 2
        Repeater {
            model: root.options
            delegate: AbstractButton {
                id: seg
                required property var modelData
                required property int index
                readonly property bool selected: String(root.current) === String(seg.modelData.value)
                height: segRow.height
                implicitWidth: segLabel.implicitWidth + (seg.modelData.icon ? 21 : 0) + 28
                hoverEnabled: true
                focusPolicy: Qt.StrongFocus
                Accessible.role: Accessible.RadioButton
                Accessible.checked: seg.selected
                Accessible.name: seg.modelData.label
                onClicked: root.picked(seg.modelData.value)
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                background: Rectangle {
                    color: seg.selected ? Theme.ink : seg.hovered ? Theme.hover : "transparent"
                    Rectangle { visible: seg.index > 0; width: 1; height: parent.height; color: Theme.lineStrong }
                    Rectangle { anchors.fill: parent; anchors.margins: 2; color: "transparent"; border.width: seg.visualFocus ? 2 : 0; border.color: Theme.focusRing }
                }
                contentItem: Item {
                    Row {
                        anchors.centerIn: parent
                        spacing: 7
                        LineIcon { visible: !!seg.modelData.icon; anchors.verticalCenter: parent.verticalCenter; path: seg.modelData.icon || ""; size: 14; strokeWidth: 1.8; color: seg.selected ? Theme.inkOnInk : Theme.ink2 }
                        Text {
                            id: segLabel
                            anchors.verticalCenter: parent.verticalCenter
                            text: seg.modelData.label
                            color: seg.selected ? Theme.inkOnInk : seg.hovered ? Theme.ink : Theme.ink2
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(13)
                            font.weight: seg.selected ? Theme.weightSemibold : Theme.weightMedium
                        }
                    }
                }
            }
        }
    }
}
