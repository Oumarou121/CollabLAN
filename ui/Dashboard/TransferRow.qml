import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import "../Components"

/*
 * TransferRow - Carte de transfert (section "Transferts" du dashboard).
 *
 * Refonte (issue design "revoir les items de la section Transferts") :
 * l'ancienne version etait une ligne plate a bordure unique, en couleurs
 * figees (incompatibles avec le mode sombre) et sans distinction visuelle
 * claire entre un transfert actif et un transfert termine/echoue de
 * l'historique. Desormais :
 *  - carte independante (fond + bordure + coin arrondis), plus une simple
 *    ligne separee par un filet ;
 *  - toutes les couleurs viennent de Theme.dashboardXxx (compatible clair/
 *    sombre) au lieu de hex codes en dur ;
 *  - badge de statut colore (pastille + texte), coherent avec le meme
 *    systeme de couleurs "soft/text" que le reste du dashboard ;
 *  - barre de progression uniquement pour un transfert reellement actif
 *    (state === "in_progress") - les entrees d'historique (termine/
 *    echoue/annule/interrompu) affichent a la place la taille totale et
 *    la date/heure du transfert ;
 *  - icone de fichier teintee selon le statut (memes couleurs que le
 *    badge) plutot que toujours "primary".
 */
Rectangle {
    id: root

    property string fileName: ""
    property string peerName: ""
    property string address: ""
    property double progress: 0
    property var transferred: 0
    property var total: 0
    property string status: "En cours"
    // state technique (in_progress/completed/failed/cancelled/interrupted) -
    // pilote l'affichage barre de progression vs meta historique. Replie sur
    // une deduction depuis `status` si non fourni (compatibilite ascendante).
    property string state: ""
    property bool isIncoming: false
    // Date ISO du transfert (entry.timestamp) - affichee pour les entrees
    // d'historique (pas de barre de progression a montrer a la place).
    property string timestamp: ""

    signal detailsRequested()
    signal openLocationRequested()
    signal retryRequested()

    readonly property string effectiveState: root.state.length > 0 ? root.state : {
        "En cours": "in_progress",
        "Terminé": "completed",
        "Échoué": "failed",
        "Annulé": "cancelled",
        "Interrompu": "interrupted"
    }[root.status] || "in_progress"

    readonly property bool isActive: effectiveState === "in_progress"

    // ---- Palette par statut : pastille (fond att.), texte, icone ---------
    readonly property color statusSoft: {
        switch (root.effectiveState) {
        case "in_progress": return Theme.dashboardPrimarySoft
        case "completed":   return Theme.dashboardSuccessSoft
        case "failed":      return Theme.dashboardErrorSoft
        case "interrupted": return Theme.dashboardWarningSoft
        default:            return Theme.dashboardSurfaceAlt
        }
    }
    readonly property color statusText: {
        switch (root.effectiveState) {
        case "in_progress": return Theme.dashboardPrimary
        case "completed":   return Theme.dashboardSuccessText
        case "failed":      return Theme.dashboardErrorText
        case "interrupted": return Theme.dashboardWarningText
        default:            return Theme.dashboardInkTertiary
        }
    }

    implicitHeight: cardColumn.implicitHeight + Theme.spacingMedium * 2
    radius: Theme.radiusMedium
    color: hoverArea.containsMouse ? Theme.dashboardHover : Theme.dashboardSurface
    border.width: 1
    border.color: Theme.dashboardLine

    Behavior on color { ColorAnimation { duration: 100 } }

    ColumnLayout {
        id: cardColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Theme.spacingMedium
        spacing: Theme.spacingSmall

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            // Icône fichier, teintée selon le statut du transfert.
            Rectangle {
                Layout.preferredWidth: 36
                Layout.preferredHeight: 36
                radius: 10
                color: root.statusSoft

                FaIcon {
                    anchors.centerIn: parent
                    glyph: fileIcon
                    color: root.statusText
                    font.pixelSize: 18
                }

                readonly property string fileIcon: {
                    if (root.fileName.endsWith(".zip") || root.fileName.endsWith(".rar")
                            || root.fileName.endsWith(".7z")) return "\uf1c6"
                    if (root.fileName.endsWith(".pdf")) return "\uf1c1"
                    if (root.fileName.endsWith(".pptx") || root.fileName.endsWith(".ppt")) return "\uf1c4"
                    if (root.fileName.endsWith(".xlsx") || root.fileName.endsWith(".xls")) return "\uf1c3"
                    if (root.fileName.endsWith(".docx") || root.fileName.endsWith(".doc")) return "\uf1c2"
                    if (root.fileName.endsWith(".html") || root.fileName.endsWith(".htm")
                            || root.fileName.endsWith(".css") || root.fileName.endsWith(".js")
                            || root.fileName.endsWith(".json") || root.fileName.endsWith(".xml")) return "\uf1c9"
                    if (root.fileName.endsWith(".jpg") || root.fileName.endsWith(".jpeg")
                            || root.fileName.endsWith(".png") || root.fileName.endsWith(".gif")
                            || root.fileName.endsWith(".webp") || root.fileName.endsWith(".bmp")) return "\uf1c5"
                    if (root.fileName.endsWith(".mp4") || root.fileName.endsWith(".mov")
                            || root.fileName.endsWith(".avi") || root.fileName.endsWith(".mkv")) return "\uf1c8"
                    if (root.fileName.endsWith(".mp3") || root.fileName.endsWith(".wav")
                            || root.fileName.endsWith(".flac")) return "\uf1c7"
                    if (root.fileName.endsWith(".txt") || root.fileName.endsWith(".md")) return "\uf0f6"
                    return "\uf0f6"
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Label {
                    text: root.fileName
                    color: Theme.dashboardInk
                    font.pixelSize: 14
                    font.bold: true
                    font.family: Theme.fontFamily
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                Row {
                    spacing: 5

                    Label {
                        text: root.isIncoming ? qsTr("Réception") : qsTr("Envoi")
                        color: Theme.dashboardInkSecondary
                        font.pixelSize: 12
                        font.family: Theme.fontFamily
                    }

                    FaIcon {
                        glyph: root.isIncoming ? "\uf063" : "\uf062"
                        color: Theme.dashboardPrimary
                        font.pixelSize: 10
                        anchors.verticalCenter: parent.verticalCenter
                        transform: Rotation { origin.x: 5; origin.y: 5; angle: root.isIncoming ? 180 : 0 }
                    }

                    Label {
                        text: root.peerName
                        color: Theme.dashboardInk
                        font.pixelSize: 12
                        font.bold: true
                        font.family: Theme.fontFamily
                    }
                }
            }

            // Badge de statut - pastille + libelle, coherent avec le
            // systeme de couleurs soft/text du reste du dashboard.
            Rectangle {
                Layout.alignment: Qt.AlignTop
                implicitWidth: statusRow.implicitWidth + 18
                implicitHeight: 22
                radius: Theme.radiusPill
                color: root.statusSoft

                Row {
                    id: statusRow
                    anchors.centerIn: parent
                    spacing: 5

                    Rectangle {
                        width: 6; height: 6; radius: 3
                        anchors.verticalCenter: parent.verticalCenter
                        color: root.statusText
                    }

                    Label {
                        text: root.status
                        color: root.statusText
                        font.pixelSize: 11
                        font.bold: true
                        font.family: Theme.fontFamily
                    }
                }
            }
        }

        // ---- Ligne meta : barre de progression (actif) OU taille+date
        // (historique) - jamais les deux, pour ne pas afficher "0 %"
        // fige sur un transfert termine/echoue de longue date. ----------
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 2
            spacing: 10
            visible: root.isActive

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 6
                radius: 99
                color: Theme.dashboardLine

                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: parent.width * root.progress
                    radius: 99
                    color: Theme.dashboardPrimary
                }
            }

            Label {
                text: formatBytes(root.transferred) + " / " + formatBytes(root.total)
                color: Theme.dashboardInkTertiary
                font.pixelSize: 11
                font.family: Theme.fontFamily
            }

            Label {
                text: Math.round(root.progress * 100) + " %"
                color: Theme.dashboardPrimary
                font.pixelSize: 12
                font.bold: true
                font.family: Theme.fontFamily
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 2
            spacing: 10
            visible: !root.isActive

            Label {
                text: formatBytes(root.total) + (root.formattedDate.length > 0 ? " \u00B7 " + root.formattedDate : "")
                color: Theme.dashboardInkTertiary
                font.pixelSize: 11
                font.family: Theme.fontFamily
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            Row {
                spacing: 6

                DashboardButton {
                    variant: "ghost"
                    controlHeight: 26
                    text: qsTr("Détails")
                    visible: root.effectiveState !== "failed"
                    onClicked: root.detailsRequested()
                }

                IconButton {
                    glyph: "\uf115"
                    size: 26
                    visible: root.effectiveState === "completed"
                    onClicked: root.openLocationRequested()
                }

                DashboardButton {
                    variant: "ghost"
                    controlHeight: 26
                    text: qsTr("Réessayer")
                    visible: root.effectiveState === "failed"
                    onClicked: root.retryRequested()
                }
            }
        }
    }

    readonly property string formattedDate: {
        if (!root.timestamp)
            return ""
        const d = new Date(root.timestamp)
        if (isNaN(d.getTime()))
            return ""
        const now = new Date()
        const sameDay = d.toDateString() === now.toDateString()
        return sameDay ? d.toLocaleString(Qt.locale(), "HH:mm")
                       : d.toLocaleString(Qt.locale(), "dd/MM/yyyy HH:mm")
    }

    MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.detailsRequested()
        // Laisse les boutons internes (Details/Reessayer/dossier) recevoir
        // leurs propres clics : declaree en dernier ici, elle ne couvre en
        // pratique que les zones non deja occupees par cardColumn au sein
        // du meme parent grace au z par defaut (voir NetworkListView pour
        // le cas inverse, corrige separement).
        z: -1
    }

    function formatBytes(bytes) {
        if (!bytes || bytes <= 0) return "0 o"
        const units = ["o", "Ko", "Mo", "Go"]
        let value = bytes
        let unitIndex = 0
        while (value >= 1024 && unitIndex < units.length - 1) {
            value /= 1024
            unitIndex++
        }
        return (unitIndex === 0 ? value.toFixed(0) : value.toFixed(1)) + " " + units[unitIndex]
    }
}
