import QtQuick
import QtQuick.Controls
import Themes

/*
 * AppComboBox - liste deroulante du design system.
 *
 * Accepte une liste de chaines, ou d'objets avec textRole / valueRole
 * (ex. [{ value: "access_denied", label: qsTr("Accès refusé") }] avec
 * textRole: "label", valueRole: "value") : aucune cle technique n'est
 * jamais montree a l'utilisateur.
 */
ComboBox {
    id: root

    implicitHeight: Theme.controlHeight
    implicitWidth: 200
    font.pixelSize: Theme.fs(13)
    font.family: Theme.fontFamily
    leftPadding: 12
    rightPadding: 32

    function labelFor(entry) {
        if (entry === undefined || entry === null)
            return ""
        if (typeof entry === "object" && root.textRole.length > 0)
            return entry[root.textRole]
        return entry
    }

    HoverHandler {
        cursorShape: Qt.PointingHandCursor
    }

    contentItem: Text {
        text: root.displayText
        color: root.enabled ? Theme.ink : Theme.inkDisabled
        font: root.font
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }

    indicator: FaIcon {
        x: root.width - width - 12
        y: (root.height - height) / 2
        glyph: ""
        color: Theme.ink3
        font.pixelSize: Theme.fs(13)
        rotation: root.popup.visible ? 180 : 0
        Behavior on rotation { NumberAnimation { duration: Theme.durationFast } }
    }

    background: Rectangle {
        radius: Theme.radiusControl
        color: root.enabled ? Theme.surface0 : Theme.sunken
        border.width: 1
        border.color: (root.activeFocus || root.popup.visible) ? Theme.accentColor
                    : (root.hovered ? Theme.ink3 : Theme.lineStrong)

        Behavior on border.color { ColorAnimation { duration: Theme.durationFast } }

        Rectangle {
            anchors.fill: parent
            anchors.margins: -3
            radius: parent.radius + 3
            color: "transparent"
            border.width: 3
            border.color: Theme.alpha(Theme.accentColor, 0.18)
            visible: root.visualFocus
        }
    }

    popup: Popup {
        y: root.height + 4
        width: Math.max(root.width, 180)
        implicitHeight: Math.min(contentItem.implicitHeight + 10, 300)
        padding: 5

        background: Rectangle {
            radius: Theme.radiusMedium
            color: Theme.surface0
            border.width: 1
            border.color: Theme.line

            Rectangle {
                z: -1
                anchors.fill: parent
                anchors.topMargin: 3
                anchors.bottomMargin: -6
                radius: parent.radius + 2
                color: Theme.shadowColor
            }
        }

        contentItem: ListView {
            clip: true
            implicitHeight: contentHeight
            model: root.popup.visible ? root.delegateModel : null
            currentIndex: root.highlightedIndex
            ScrollBar.vertical: ScrollBar {}
        }
    }

    delegate: ItemDelegate {
        id: delegateItem
        width: ListView.view ? ListView.view.width : root.width
        implicitHeight: Theme.compact ? 30 : 34

        required property var modelData
        required property int index

        highlighted: root.highlightedIndex === index
        HoverHandler { cursorShape: Qt.PointingHandCursor }

        contentItem: Text {
            text: root.labelFor(delegateItem.modelData)
            color: Theme.ink
            font.pixelSize: Theme.fs(13)
            font.family: Theme.fontFamily
            font.weight: delegateItem.index === root.currentIndex ? Theme.weightSemibold : Theme.weightRegular
            leftPadding: 4
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }

        background: Rectangle {
            radius: Theme.radiusSmall
            color: delegateItem.highlighted ? Theme.hover : "transparent"
        }
    }
}
