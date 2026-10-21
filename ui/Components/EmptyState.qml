import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes

/*
 * EmptyState - etat vide / erreur / resultat de recherche vide.
 *
 * Explique toujours POURQUOI c'est vide et propose, quand il y en a une, la
 * prochaine action utile (actionText). Centre dans l'espace disponible.
 *
 * iconName : "transfer" | "log" | "chat" | "folder" | "peers" | "call"
 *            | "search" | "error" | "offline" | "lock" | "check" | "users"
 * tone     : "neutral" (defaut) | "danger" (erreur) | "success"
 * compact  : version reduite (petits panneaux).
 */
ColumnLayout {
    id: root

    property string iconName: ""
    property string glyph: ""
    property string title: ""
    property string description: ""
    property string actionText: ""
    property string secondaryActionText: ""
    property string tone: "neutral"
    property bool compact: false

    signal actionClicked()
    signal secondaryActionClicked()

    readonly property string resolvedGlyph: {
        if (root.glyph.length > 0) return root.glyph
        switch (root.iconName) {
        case "transfer": return ""
        case "log": return ""
        case "chat": return ""
        case "folder": return ""
        case "peers": return ""
        case "users": return ""
        case "call": return ""
        case "search": return ""
        case "error": return ""
        case "offline": return ""
        case "lock": return ""
        case "check": return ""
        default: return ""
        }
    }

    spacing: 0

    Item { Layout.fillHeight: true }

    Rectangle {
        Layout.alignment: Qt.AlignHCenter
        Layout.preferredWidth: root.compact ? 40 : 52
        Layout.preferredHeight: root.compact ? 40 : 52
        radius: width / 2
        color: root.tone === "danger" ? Theme.dangerSoft
             : root.tone === "success" ? Theme.successSoft
             : Theme.sunken

        FaIcon {
            anchors.centerIn: parent
            glyph: root.resolvedGlyph
            color: root.tone === "danger" ? Theme.dangerInk
                 : root.tone === "success" ? Theme.successInk
                 : Theme.ink3
            font.pixelSize: Theme.fs(root.compact ? 16 : 20)
        }
    }

    Text {
        Layout.fillWidth: true
        Layout.topMargin: root.compact ? 10 : 14
        horizontalAlignment: Text.AlignHCenter
        text: root.title
        color: Theme.ink
        font.pixelSize: Theme.fs(root.compact ? 13 : 14)
        font.weight: Theme.weightSemibold
        font.family: Theme.fontFamily
        wrapMode: Text.WordWrap
    }

    Text {
        visible: root.description.length > 0
        Layout.fillWidth: true
        Layout.maximumWidth: 360
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: 4
        horizontalAlignment: Text.AlignHCenter
        text: root.description
        color: Theme.ink3
        font.pixelSize: Theme.fs(12)
        font.family: Theme.fontFamily
        wrapMode: Text.WordWrap
    }

    RowLayout {
        visible: root.actionText.length > 0 || root.secondaryActionText.length > 0
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: root.compact ? 10 : 14
        spacing: 8

        AppButton {
            visible: root.secondaryActionText.length > 0
            text: root.secondaryActionText
            variant: "secondary"
            size: "small"
            onClicked: root.secondaryActionClicked()
        }
        AppButton {
            visible: root.actionText.length > 0
            text: root.actionText
            variant: "soft"
            size: "small"
            onClicked: root.actionClicked()
        }
    }

    Item { Layout.fillHeight: true }
}
