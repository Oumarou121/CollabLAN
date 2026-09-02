import QtQuick
import QtQuick.Controls
import Themes

/*
 * AppComboBox - liste deroulante stylisee, a la place du ComboBox "brut"
 * utilise jusqu'ici dans AdminView, FileTransferView et SharedFolderView.
 *
 * Usage :
 *   AppComboBox {
 *       model: [qsTr("Membre"), qsTr("Administrateur")]
 *       currentIndex: someIndex
 *       onActivated: someIndex = index
 *   }
 */
ComboBox {
    id: root

    implicitHeight: 40
    font.pixelSize: Theme.fontSizeBody
    font.family: Theme.fontFamily

    HoverHandler {
        cursorShape: Qt.PointingHandCursor
    }

    contentItem: Text {
        text: root.displayText
        color: Theme.text
        font: root.font
        leftPadding: Theme.spacingMedium
        rightPadding: root.indicator.width + Theme.spacingSmall
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }

    indicator: Text {
        x: root.width - width - Theme.spacingMedium
        y: (root.height - height) / 2
        text: "\u25BE"
        color: Theme.textSecondary
        font.pixelSize: Theme.fontSizeSmall
        rotation: root.popup.visible ? 180 : 0

        Behavior on rotation { NumberAnimation { duration: 100 } }
    }

    background: Rectangle {
        radius: Theme.radiusMedium
        color: Theme.background
        border.width: root.activeFocus || root.popup.visible ? 2 : 1
        border.color: (root.activeFocus || root.popup.visible) ? Theme.primary : Theme.border

        Behavior on border.color { ColorAnimation { duration: 100 } }
    }

    popup: Popup {
        y: root.height + Theme.spacingXs
        width: root.width
        implicitHeight: Math.min(contentItem.implicitHeight, 260)
        padding: Theme.spacingXs

        background: Rectangle {
            radius: Theme.radiusMedium
            color: Theme.surface
            border.width: 1
            border.color: Theme.border

            layer.enabled: true
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
        width: root.width
        implicitHeight: 36

        required property var modelData
        required property int index

        contentItem: Text {
            text: delegateItem.modelData
            color: Theme.text
            font.pixelSize: Theme.fontSizeBody
            font.family: Theme.fontFamily
            leftPadding: Theme.spacingSmall
            verticalAlignment: Text.AlignVCenter
        }

        background: Rectangle {
            radius: Theme.radiusSmall
            color: delegateItem.highlighted ? Theme.surfaceHover : "transparent"
        }

        highlighted: root.highlightedIndex === index
    }
}
