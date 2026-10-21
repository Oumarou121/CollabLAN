import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import "../Components"
import "../Components/icons.js" as Icons
import "transferFormat.js" as Fmt

/*
 * TransferPeerCard - carte compacte d'un correspondant : identite, resume
 * d'activite et dernier fichier echange avec son statut.
 * Etats : repos (surface + bordure 1) | survol (bordure plus visible) |
 * selection (dashboardPrimarySoft + bordure dashboardPrimary 2 px).
 * Aucun deplacement ni changement de taille au survol.
 */
Rectangle {
    id: root

    property string peerLabel: ""
    property bool isUser: false
    property string metaText: ""
    property int activeCount: 0
    property string lastFileName: ""
    property string lastState: ""
    property string lastStatusText: ""
    property bool selected: false
    // false (<= 720 px) : seule la ligne identite est affichee (maquette .peer .pl).
    property bool showLastTransfer: true
    // "online" | "away" | "busy" | "" (correspondant non present sur le reseau
    // actuellement, ou pair sans compte utilisateur type PC-COMPTA-01).
    property string presenceStatus: ""

    signal clicked()

    readonly property bool hovered: mouse.containsMouse

    // Modernisation (priorité 16 du brief) : plus de "border + radius +
    // avatar + texte" générique. Le repos et le survol se distinguent par
    // surface uniquement (pas de contour) ; la sélection est signalée par
    // un liseré d'accent à gauche plutôt qu'une bordure pleine 2px.
    implicitHeight: 100
    radius: Theme.radiusMedium
    color: root.selected ? Theme.dashboardPrimarySoft
                         : (root.hovered ? Theme.surfaceLevel3 : Theme.surfaceLevel2)
    border.width: 0

    Behavior on color { ColorAnimation { duration: 100 } }

    Rectangle {
        visible: root.selected
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 3
        radius: 1.5
        color: Theme.dashboardPrimary
    }

    Accessible.role: Accessible.Button
    Accessible.name: root.peerLabel
    Accessible.description: root.metaText

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Rectangle {
                Layout.preferredWidth: 36
                Layout.preferredHeight: 36
                Layout.alignment: Qt.AlignVCenter
                radius: 18
                color: root.selected ? Theme.dashboardSurface : Theme.dashboardPrimarySoft

                Label {
                    visible: root.isUser
                    anchors.centerIn: parent
                    text: Fmt.initialOf(root.peerLabel)
                    color: Theme.dashboardPrimary
                    font.pixelSize: Theme.fs(15)
                    font.weight: Font.Bold
                    font.family: Theme.fontFamily
                }

                LineIcon {
                    visible: !root.isUser
                    anchors.centerIn: parent
                    size: 18
                    strokeWidth: 1.9
                    color: Theme.dashboardPrimary
                    path: Icons.monitor
                }

                // Pastille de presence (maquette .peer .dot) : verte/ambre/grise,
                // uniquement quand le statut reseau du pair est connu.
                Rectangle {
                    visible: root.presenceStatus.length > 0
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.rightMargin: -1
                    anchors.bottomMargin: -1
                    width: 10
                    height: 10
                    radius: 5
                    color: root.presenceStatus === "away" ? Theme.dashboardWarning
                           : (root.presenceStatus === "busy" ? Theme.dashboardInkTertiary
                           : Theme.dashboardSuccessText)
                    border.width: 2
                    border.color: root.selected ? Theme.dashboardPrimarySoft : Theme.dashboardSurface
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 1

                Label {
                    Layout.fillWidth: true
                    text: root.peerLabel
                    color: Theme.dashboardInk
                    font.pixelSize: Theme.fs(14)
                    font.weight: Font.Bold
                    font.family: Theme.fontFamily
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }

                Label {
                    Layout.fillWidth: true
                    text: root.metaText
                    color: Theme.dashboardInkTertiary
                    font.pixelSize: Theme.fs(12)
                    font.family: Theme.fontFamily
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
            }

            Rectangle {
                visible: root.activeCount > 0
                Layout.alignment: Qt.AlignTop
                implicitWidth: activeLabel.implicitWidth + 16
                implicitHeight: 20
                radius: Theme.radiusPill
                color: root.selected ? Theme.dashboardSurface : Theme.dashboardPrimarySoft

                Label {
                    id: activeLabel
                    anchors.centerIn: parent
                    text: qsTr("%1 en cours").arg(root.activeCount)
                    color: Theme.dashboardPrimary
                    font.pixelSize: Theme.fs(11)
                    font.weight: Font.DemiBold
                    font.family: Theme.fontFamily
                }
            }
        }

        Rectangle {
            visible: root.showLastTransfer
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: root.selected ? Theme.dashboardPrimaryMuted : Theme.hairline
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            visible: root.showLastTransfer && root.lastFileName.length > 0

            FileTypeIcon {
                fileName: root.lastFileName
                size: 22
            }

            Label {
                Layout.fillWidth: true
                text: root.lastFileName
                color: Theme.dashboardInkSecondary
                font.pixelSize: Theme.fs(12)
                font.family: Theme.fontFamily
                elide: Text.ElideMiddle
                maximumLineCount: 1
            }

            TransferStatusBadge {
                transferState: root.lastState
                text: root.lastStatusText
            }
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
