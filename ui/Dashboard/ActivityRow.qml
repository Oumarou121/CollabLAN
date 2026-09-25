import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import "../Components"
import "../Components/icons.js" as Icons

/*
 * ActivityRow - Carte d'activité récente (section "Activité récente" du
 * dashboard).
 *
 * Refonte (meme demarche que TransferRow) : carte independante (fond +
 * bordure + coins arrondis + survol) au lieu d'une ligne a plat separee
 * par un simple filet, icone d'evenement teintee (coherente avec le badge)
 * au lieu du seul point colore, et badge de resultat en pastille douce
 * (fond teinte + texte colore) au lieu de texte blanc sur aplat, pour
 * rester coherent avec le systeme de couleurs "soft/text" desormais
 * utilise dans TransferRow.
 */
Rectangle {
    id: root

    property string event: ""
    property string actor: ""
    property string message: ""
    property string result: ""
    property string resultBadge: ""
    property var timestamp: new Date()

    signal clicked()

    implicitHeight: contentRow.implicitHeight + Theme.spacingSmall * 2
    radius: Theme.radiusMedium
    color: hoverArea.containsMouse ? Theme.dashboardHover : Theme.dashboardSurface
    border.width: 1
    border.color: Theme.dashboardLine

    Behavior on color { ColorAnimation { duration: 100 } }

    // ---- Palette par type d'evenement (icone + badge par defaut) --------
    readonly property color eventSoft: {
        switch (root.event) {
        case "connection":     return Theme.dashboardSuccessSoft
        case "message":        return Theme.dashboardInfoSoft
        case "transfer":       return Theme.dashboardPrimarySoft
        case "call":           return Theme.dashboardCallSoft
        case "access_denied":  return Theme.dashboardErrorSoft
        default:               return Theme.dashboardSurfaceAlt
        }
    }
    readonly property color eventText: {
        switch (root.event) {
        case "connection":     return Theme.dashboardSuccessText
        case "message":        return Theme.dashboardInfoText
        case "transfer":       return Theme.dashboardPrimary
        case "call":           return Theme.dashboardCallText
        case "access_denied":  return Theme.dashboardErrorText
        default:               return Theme.dashboardInkTertiary
        }
    }
    readonly property string eventGlyph: {
        switch (root.event) {
        case "connection":    return Icons.link
        case "message":       return Icons.messageCircle
        case "transfer":      return Icons.exchange
        case "call":          return Icons.phone
        case "access_denied": return Icons.ban
        default:              return Icons.bell
        }
    }
    readonly property string eventLabel: {
        switch (root.event) {
        case "connection":    return qsTr("Connexion")
        case "message":       return qsTr("Message")
        case "transfer":      return qsTr("Transfert")
        case "call":          return qsTr("Appel")
        case "access_denied": return qsTr("Accès refusé")
        default:              return qsTr("Activité")
        }
    }

    // ---- Palette du badge de resultat, independante du type d'evenement -
    readonly property color badgeSoft: {
        switch (root.resultBadge) {
        case "ok":   return Theme.dashboardSuccessSoft
        case "err":  return Theme.dashboardErrorSoft
        case "xf":   return Theme.dashboardPrimarySoft
        case "call": return Theme.dashboardCallSoft
        default:     return Theme.dashboardSurfaceAlt
        }
    }
    readonly property color badgeText: {
        switch (root.resultBadge) {
        case "ok":   return Theme.dashboardSuccessText
        case "err":  return Theme.dashboardErrorText
        case "xf":   return Theme.dashboardPrimary
        case "call": return Theme.dashboardCallText
        default:     return Theme.dashboardInkTertiary
        }
    }
    readonly property string badgeLabel: {
        switch (root.resultBadge) {
        case "ok":   return qsTr("Terminé")
        case "err":  return qsTr("Refusé")
        case "xf":   return qsTr("En cours")
        case "call": return qsTr("En cours")
        default:     return ""
        }
    }

    RowLayout {
        id: contentRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: Theme.spacingSmall
        spacing: 12

        // Icône d'événement, teintée selon le type (coherent avec l'icone
        // de fichier de TransferRow).
        Rectangle {
            Layout.preferredWidth: 32
            Layout.preferredHeight: 32
            radius: 9
            color: root.eventSoft

            LineIcon {
                anchors.centerIn: parent
                path: root.eventGlyph
                color: root.eventText
                size: 14
                strokeWidth: 1.9
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Label {
                    text: root.actor || root.eventLabel
                    color: Theme.dashboardInk
                    font.pixelSize: 14
                    font.bold: true
                    font.family: Theme.fontFamily
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                Label {
                    text: Qt.formatTime(root.timestamp, "hh:mm")
                    color: Theme.dashboardInkTertiary
                    font.pixelSize: 11
                    font.weight: Font.Medium
                    font.family: Theme.fontFamily
                }
            }

            Label {
                text: root.message
                color: Theme.dashboardInkSecondary
                font.pixelSize: 12
                font.family: Theme.fontFamily
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
        }

        // Badge résultat - pastille douce (fond teinte + texte colore)
        // au lieu de l'ancien aplat blanc-sur-couleur.
        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: badgeLabelText.implicitWidth + 18
            implicitHeight: 22
            radius: Theme.radiusPill
            color: root.badgeSoft
            visible: root.resultBadge.length > 0

            Label {
                id: badgeLabelText
                anchors.centerIn: parent
                text: root.badgeLabel
                color: root.badgeText
                font.pixelSize: 11
                font.bold: true
                font.family: Theme.fontFamily
            }
        }
    }

    MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
        z: -1
    }
}
