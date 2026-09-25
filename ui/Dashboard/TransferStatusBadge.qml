import QtQuick
import QtQuick.Controls
import Themes
import "../Components"
import "../Components/icons.js" as Icons

/*
 * TransferStatusBadge - pastille de statut d'un transfert, meme langage
 * "soft / text" que TransferRow et ActivityRow : fond doux + texte teinte
 * + glyphe filaire. Le statut n'est jamais porte par la couleur seule.
 *
 * transferState : "in_progress" | "completed" | "failed" | "cancelled" | "interrupted"
 * text : libelle (statusText) ; a defaut, libelle par defaut de l'etat.
 */
Rectangle {
    id: root

    property string transferState: "in_progress"
    property string text: ""
    property bool showIcon: true

    readonly property string label: {
        if (root.text.length > 0)
            return root.text
        switch (root.transferState) {
        case "completed":   return qsTr("Terminé")
        case "failed":      return qsTr("Échoué")
        case "cancelled":   return qsTr("Annulé")
        case "interrupted": return qsTr("Interrompu")
        default:            return qsTr("En cours")
        }
    }

    readonly property color soft: {
        switch (root.transferState) {
        case "completed":   return Theme.dashboardSuccessSoft
        case "failed":      return Theme.dashboardErrorSoft
        case "interrupted": return Theme.dashboardWarningSoft
        case "cancelled":   return Theme.dashboardSurfaceAlt
        default:            return Theme.dashboardPrimarySoft
        }
    }

    readonly property color tint: {
        switch (root.transferState) {
        case "completed":   return Theme.dashboardSuccessText
        case "failed":      return Theme.dashboardErrorText
        case "interrupted": return Theme.dashboardWarningText
        case "cancelled":   return Theme.dashboardInkTertiary
        default:            return Theme.dashboardPrimary
        }
    }

    readonly property string glyph: {
        switch (root.transferState) {
        case "completed":   return Icons.check
        case "failed":      return Icons.alertCircle
        case "interrupted": return Icons.alertTriangle
        case "cancelled":   return Icons.ban
        default:            return Icons.clock
        }
    }

    implicitWidth: content.implicitWidth + 18
    implicitHeight: 22
    radius: Theme.radiusPill
    color: root.soft

    Accessible.name: root.label

    Row {
        id: content
        anchors.centerIn: parent
        spacing: 5

        LineIcon {
            visible: root.showIcon
            anchors.verticalCenter: parent.verticalCenter
            size: 12
            strokeWidth: 2.2
            color: root.tint
            path: root.glyph
        }

        Label {
            anchors.verticalCenter: parent.verticalCenter
            text: root.label
            color: root.tint
            font.pixelSize: 11
            font.weight: Font.DemiBold
            font.family: Theme.fontFamily
        }
    }
}
