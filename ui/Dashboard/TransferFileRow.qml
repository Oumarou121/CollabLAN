import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import "../Components"
import "../Components/icons.js" as Icons

/*
 * TransferFileRow - ligne plate d'un transfert : separateur fin en haut,
 * hauteur compacte, survol discret.
 *
 *   [icone]  Nom du fichier              Taille   Statut   Date   actions
 *            Envoye a PC-COMPTA-01
 *
 * Transfert en cours : la seconde ligne devient une barre de progression +
 * pourcentage + "158 Mo sur 204 Mo" (donnees reelles uniquement : ni debit
 * ni temps restant). Les largeurs de colonnes viennent de la vue pour que
 * l'en-tete du tableau reste aligne.
 */
Item {
    id: root

    property string fileName: ""
    property string peerLabel: ""
    property bool incoming: false
    property string transferState: "in_progress"
    property string statusText: ""
    property string errorString: ""
    property int percent: 0
    property string sizeText: ""
    property string progressText: ""
    property string dateText: ""
    property bool showSizeColumn: true
    property bool showDateColumn: true
    property bool showTopLine: true
    property bool canRetry: false
    property bool canOpen: false

    property int sizeColumnWidth: 84
    property int statusColumnWidth: 124
    property int dateColumnWidth: 116
    property int actionsColumnWidth: 96

    signal retryRequested()
    signal openRequested()
    signal detailsRequested()

    readonly property bool isActive: root.transferState === "in_progress"
    readonly property bool hovered: hover.hovered

    implicitHeight: root.isActive ? 68 : 56

    Behavior on implicitHeight { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

    Rectangle {
        anchors.fill: parent
        color: root.hovered ? Theme.surfaceLevel3 : "transparent"
        Behavior on color { ColorAnimation { duration: 100 } }
    }

    Rectangle {
        visible: root.showTopLine
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: Theme.hairline
    }

    HoverHandler { id: hover }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        spacing: 12

        FileTypeIcon {
            Layout.alignment: Qt.AlignVCenter
            fileName: root.fileName
            size: 32
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 3

            Label {
                Layout.fillWidth: true
                text: root.fileName
                color: Theme.dashboardInk
                font.pixelSize: Theme.fs(14)
                font.weight: Theme.weightSemibold
                font.family: Theme.fontFamily
                elide: Text.ElideMiddle
                maximumLineCount: 1

                ToolTip.visible: truncated && root.hovered
                ToolTip.text: root.fileName
                ToolTip.delay: 600
            }

            // Direction + correspondant.
            RowLayout {
                visible: !root.isActive
                Layout.fillWidth: true
                spacing: 5

                LineIcon {
                    size: 12
                    strokeWidth: 2.2
                    color: root.incoming ? Theme.dashboardSuccess : Theme.dashboardPrimary
                    path: root.incoming ? Icons.arrowDownLeft : Icons.arrowUpRight
                }

                Label {
                    Layout.fillWidth: true
                    text: (root.incoming ? qsTr("Reçu de %1") : qsTr("Envoyé à %1")).arg(root.peerLabel)
                          + (root.showSizeColumn ? "" : (root.sizeText.length > 0 ? "  ·  " + root.sizeText : ""))
                    color: Theme.dashboardInkSecondary
                    font.pixelSize: Theme.fs(12)
                    font.family: Theme.fontFamily
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
            }

            // Progression (transfert en cours). La barre a une largeur
            // preferee fixe ; seul le texte de fin absorbe l'espace restant
            // (deux fillWidth voisins se partageaient l'espace et
            // ecrasaient la barre).
            RowLayout {
                visible: root.isActive
                Layout.fillWidth: true
                spacing: 10

                Rectangle {
                    Layout.preferredWidth: 240
                    Layout.minimumWidth: 80
                    Layout.preferredHeight: 6
                    radius: 3
                    color: Theme.dashboardLine

                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: parent.width * Math.max(0, Math.min(100, root.percent)) / 100
                        radius: 3
                        color: Theme.dashboardPrimary
                        Behavior on width { NumberAnimation { duration: 180 } }
                    }
                }

                Label {
                    text: root.percent + " %"
                    color: Theme.dashboardPrimary
                    font.pixelSize: Theme.fs(12)
                    font.weight: Font.Bold
                    font.family: Theme.fontFamily
                }

                Label {
                    Layout.fillWidth: true
                    text: root.progressText
                    color: Theme.dashboardInkTertiary
                    font.pixelSize: Theme.fs(11)
                    font.family: Theme.fontFamily
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
            }
        }

        Label {
            visible: root.showSizeColumn
            Layout.preferredWidth: root.sizeColumnWidth
            Layout.alignment: Qt.AlignVCenter
            text: root.sizeText
            color: Theme.dashboardInkSecondary
            font.pixelSize: Theme.fs(12)
            font.family: Theme.fontFamily
        }

        Item {
            Layout.preferredWidth: root.statusColumnWidth
            Layout.preferredHeight: 22
            Layout.alignment: Qt.AlignVCenter

            TransferStatusBadge {
                anchors.verticalCenter: parent.verticalCenter
                transferState: root.transferState
                text: root.statusText

                ToolTip.visible: root.errorString.length > 0 && badgeHover.hovered
                ToolTip.text: root.errorString
                ToolTip.delay: 300
                HoverHandler { id: badgeHover }
            }
        }

        Label {
            visible: root.showDateColumn
            Layout.preferredWidth: root.dateColumnWidth
            Layout.alignment: Qt.AlignVCenter
            text: root.dateText
            color: Theme.dashboardInkTertiary
            font.pixelSize: Theme.fs(12)
            font.family: Theme.fontFamily
            elide: Text.ElideRight
        }

        Item {
            Layout.preferredWidth: root.actionsColumnWidth
            Layout.preferredHeight: 28
            Layout.alignment: Qt.AlignVCenter

            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4

                DashboardButton {
                    visible: root.canRetry
                    variant: "soft"
                    controlHeight: 28
                    text: qsTr("Réessayer")
                    onClicked: root.retryRequested()
                }

                DashboardButton {
                    visible: root.canOpen
                    variant: "ghost"
                    iconOnly: true
                    controlHeight: 28
                    iconPath: Icons.folderOpen
                    tooltip: qsTr("Ouvrir l'emplacement")
                    // Action secondaire discrete : visible au survol / focus (maquette .h).
                    opacity: (root.hovered || activeFocus) ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                    onClicked: root.openRequested()
                }

                // "Détails" (maquette .acts : bouton ghost toujours present,
                // revele au survol/focus comme les autres actions .h).
                DashboardButton {
                    variant: "ghost"
                    controlHeight: 28
                    text: qsTr("Détails")
                    opacity: (root.hovered || activeFocus) ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                    onClicked: root.detailsRequested()
                }
            }
        }
    }
}
