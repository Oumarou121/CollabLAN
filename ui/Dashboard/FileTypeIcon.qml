import QtQuick
import Themes
import "../Components"
import "../Components/icons.js" as Icons
import "transferFormat.js" as Fmt

/*
 * FileTypeIcon - vignette d'icone de fichier (tuile douce + glyphe filaire
 * teinte selon la categorie). isFolder : icone de dossier.
 */
Rectangle {
    id: root

    property string fileName: ""
    property bool isFolder: false
    property int size: 32

    readonly property string kind: root.isFolder ? "folder" : Fmt.fileKind(root.fileName)

    readonly property color tint: {
        switch (root.kind) {
        case "doc":     return Theme.dashboardPrimary
        case "sheet":   return Theme.dashboardSuccess
        case "slides":  return Theme.dashboardWarning
        case "image":   return Theme.dashboardInfo
        case "media":   return Theme.dashboardCall
        case "folder":  return Theme.dashboardPrimary
        default:        return Theme.dashboardInkSecondary
        }
    }

    readonly property color soft: {
        switch (root.kind) {
        case "doc":     return Theme.dashboardPrimarySoft
        case "sheet":   return Theme.dashboardSuccessSoft
        case "slides":  return Theme.dashboardWarningSoft
        case "image":   return Theme.dashboardInfoSoft
        case "media":   return Theme.dashboardCallSoft
        case "folder":  return Theme.dashboardPrimarySoft
        default:        return Theme.dashboardSurfaceAlt
        }
    }

    readonly property string glyph: {
        switch (root.kind) {
        case "doc":
        case "sheet":
        case "slides":  return Icons.fileText
        case "image":   return Icons.image
        case "archive": return Icons.archive
        case "media":   return Icons.media
        case "folder":  return Icons.folder
        default:        return Icons.file
        }
    }

    implicitWidth: size
    implicitHeight: size
    width: size
    height: size
    radius: size >= 32 ? 10 : Theme.radiusSmall
    color: root.soft

    LineIcon {
        anchors.centerIn: parent
        size: Math.round(root.size * 0.52)
        strokeWidth: 1.9
        color: root.tint
        path: root.glyph
    }
}
