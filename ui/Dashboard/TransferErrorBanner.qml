import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import "../Components"
import "../Components/icons.js" as Icons

/*
 * TransferErrorBanner - bloc "Echec du transfert" de la maquette (.err) :
 * fond errorSoft, bordure error, icone d'alerte, titre + message et action
 * "Reessayer". Affiche dans la page (sous le titre), contrairement a
 * InlineAlert qui sert aux erreurs ponctuelles flottantes.
 */
Rectangle {
    id: root

    property string title: ""
    property string message: ""
    property string actionText: qsTr("Réessayer")

    signal retryRequested()

    implicitHeight: content.implicitHeight + 24
    radius: Theme.radiusSmall
    color: Theme.dashboardErrorSoft
    border.width: 1
    border.color: Theme.dashboardError

    Accessible.role: Accessible.AlertMessage
    Accessible.name: root.title + ". " + root.message

    RowLayout {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 12
        spacing: 12

        LineIcon {
            Layout.alignment: Qt.AlignTop
            size: 18
            strokeWidth: 1.9
            color: Theme.dashboardError
            path: Icons.alertCircle
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            spacing: 0

            Label {
                Layout.fillWidth: true
                text: root.title
                color: Theme.dashboardErrorText
                font.pixelSize: Theme.fs(14)
                font.weight: Font.Bold
                font.family: Theme.fontFamily
                elide: Text.ElideRight
            }
            Label {
                Layout.fillWidth: true
                text: root.message
                color: Theme.dashboardErrorText
                font.pixelSize: Theme.fs(13)
                font.family: Theme.fontFamily
                wrapMode: Text.WordWrap
            }
        }

        DashboardButton {
            Layout.alignment: Qt.AlignTop
            variant: "soft"
            controlHeight: 28
            text: root.actionText
            onClicked: root.retryRequested()
        }
    }
}
