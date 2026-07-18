import QtQuick
import QtQuick.Controls
import Themes

/*
 * StatusBadge - pastille arrondie affichant un statut court (ex: "Terminé",
 * "En cours", "Échec", "Conflit", "Synchronisé"), utilisee dans la vue
 * "Détails" de FileTransferView et SharedFolderView pour garder un style
 * de badge identique entre les deux ecrans (Option B - liste compacte).
 *
 * Le tone determine la paire (fond clair / texte fonce) issue de Theme,
 * pour rester coherent en light et dark mode.
 */
Rectangle {
    id: root

    // "success" | "warning" | "error" | "info" | "neutral"
    property string tone: "neutral"
    property string text: ""

    readonly property color bgColor: {
        switch (root.tone) {
        case "success": return Theme.successMuted
        case "warning": return Theme.warningMuted
        case "error": return Theme.errorMuted
        case "info": return Theme.primaryMuted
        default: return Theme.surfaceAlt
        }
    }

    readonly property color fgColor: {
        switch (root.tone) {
        case "success": return Theme.success
        case "warning": return Theme.warning
        case "error": return Theme.error
        case "info": return Theme.primary
        default: return Theme.textSecondary
        }
    }

    implicitWidth: label.implicitWidth + 20
    implicitHeight: 20
    radius: Theme.radiusPill
    color: root.bgColor

    Label {
        id: label
        anchors.centerIn: parent
        text: root.text
        color: root.fgColor
        font.pixelSize: Theme.fontSizeCaption
        font.bold: true
        font.family: Theme.fontFamily
    }
}
