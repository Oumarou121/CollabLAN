import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import "../Components"
import "../Components/icons.js" as Icons
import "transferFormat.js" as Fmt

/*
 * TransferDetailsDialog - fiche "Détails" d'un transfert (bouton .acts
 * "Détails" de la maquette, present sur chaque ligne/tuile mais sans
 * comportement dans la demo HTML - voir S.err/T dans localink-transfer-ui-v1.html).
 *
 * Ne fait qu'afficher les champs deja connus du transfert (aucun appel
 * reseau, aucune donnee inventee) : nom, sens, correspondant, taille,
 * statut, date, chemin local et message d'erreur le cas echeant.
 * Les actions (Reessayer / Ouvrir l'emplacement) restent les memes que
 * sur la ligne, transmises via signaux pour utiliser les vraies API.
 */
Popup {
    id: root

    property var item: null    // objet fileRow() de FileTransferView, ou null
    property bool canRetry: false
    property bool canOpen: false

    signal retryRequested()
    signal openRequested()

    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    width: 380
    x: (parent ? parent.width - width : 0) / 2
    y: (parent ? parent.height - implicitHeight : 0) / 2

    background: Rectangle {
        radius: Theme.radiusMedium
        color: Theme.dashboardSurface
        border.width: 1
        border.color: Theme.dashboardLine
    }

    Overlay.modal: Rectangle { color: "#00000066" }

    contentItem: ColumnLayout {
        spacing: 14

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            FileTypeIcon {
                fileName: root.item ? root.item.fileName : ""
                size: 36
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Label {
                    Layout.fillWidth: true
                    text: root.item ? root.item.fileName : ""
                    color: Theme.dashboardInk
                    font.pixelSize: 14
                    font.weight: Font.Bold
                    font.family: Theme.fontFamily
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
                Label {
                    Layout.fillWidth: true
                    text: root.item
                          ? (root.item.incoming ? qsTr("Reçu de %1").arg(root.item.peerLabel)
                                                 : qsTr("Envoyé à %1").arg(root.item.peerLabel))
                          : ""
                    color: Theme.dashboardInkTertiary
                    font.pixelSize: 12
                    font.family: Theme.fontFamily
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
            }
            DashboardButton {
                variant: "ghost"
                iconOnly: true
                controlHeight: 26
                iconPath: Icons.close
                tooltip: qsTr("Fermer")
                onClicked: root.close()
            }
        }

        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.dashboardLine }

        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: 16
            rowSpacing: 8

            Label {
                text: qsTr("Statut")
                color: Theme.dashboardInkTertiary
                font.pixelSize: 12
                font.family: Theme.fontFamily
            }
            TransferStatusBadge {
                Layout.alignment: Qt.AlignRight
                transferState: root.item ? root.item.state : ""
                text: root.item ? root.item.statusText : ""
            }

            Label {
                text: qsTr("Taille")
                color: Theme.dashboardInkTertiary
                font.pixelSize: 12
                font.family: Theme.fontFamily
            }
            Label {
                Layout.alignment: Qt.AlignRight
                text: root.item ? Fmt.formatBytes(root.item.totalBytes) : ""
                color: Theme.dashboardInk
                font.pixelSize: 12
                font.weight: Font.DemiBold
                font.family: Theme.fontFamily
            }

            Label {
                visible: root.item && root.item.state === "in_progress"
                text: qsTr("Transféré")
                color: Theme.dashboardInkTertiary
                font.pixelSize: 12
                font.family: Theme.fontFamily
            }
            Label {
                visible: root.item && root.item.state === "in_progress"
                Layout.alignment: Qt.AlignRight
                text: root.item
                      ? qsTr("%1 sur %2 (%3 %)").arg(Fmt.formatBytes(root.item.bytesTransferred))
                            .arg(Fmt.formatBytes(root.item.totalBytes)).arg(root.item.percent)
                      : ""
                color: Theme.dashboardInk
                font.pixelSize: 12
                font.family: Theme.fontFamily
            }

            Label {
                text: qsTr("Date")
                color: Theme.dashboardInkTertiary
                font.pixelSize: 12
                font.family: Theme.fontFamily
            }
            Label {
                Layout.alignment: Qt.AlignRight
                text: root.item ? root.item.timestamp : ""
                color: Theme.dashboardInk
                font.pixelSize: 12
                font.family: Theme.fontFamily
            }

            Label {
                visible: root.item && root.item.filePath.length > 0
                text: qsTr("Emplacement")
                color: Theme.dashboardInkTertiary
                font.pixelSize: 12
                font.family: Theme.fontFamily
            }
            Label {
                visible: root.item && root.item.filePath.length > 0
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignRight
                horizontalAlignment: Text.AlignRight
                text: root.item ? root.item.filePath : ""
                color: Theme.dashboardInk
                font.pixelSize: 11
                font.family: Theme.fontFamily
                elide: Text.ElideLeft
                maximumLineCount: 1
            }
        }

        Label {
            visible: root.item && root.item.errorString.length > 0
            Layout.fillWidth: true
            text: root.item ? root.item.errorString : ""
            color: Theme.dashboardErrorText
            font.pixelSize: 12
            font.family: Theme.fontFamily
            wrapMode: Text.WordWrap
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 4
            spacing: 8

            Item { Layout.fillWidth: true }

            DashboardButton {
                visible: root.canOpen
                variant: "ghost"
                controlHeight: 30
                iconPath: Icons.folderOpen
                text: qsTr("Ouvrir l'emplacement")
                onClicked: { root.openRequested(); root.close() }
            }
            DashboardButton {
                visible: root.canRetry
                variant: "soft"
                controlHeight: 30
                text: qsTr("Réessayer")
                onClicked: { root.retryRequested(); root.close() }
            }
        }
    }

}
