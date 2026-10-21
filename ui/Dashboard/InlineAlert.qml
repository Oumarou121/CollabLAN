import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import "../Components"
import "../Components/icons.js" as Icons

/*
 * InlineAlert - message d'erreur / d'information dans le langage du
 * Dashboard : fond "soft", bordure fine teintee, texte teinte, icone
 * d'alerte (remplace l'ancien bandeau rouge sature pleine largeur).
 * tone : "error" (defaut) | "success" | "info"
 */
Rectangle {
    id: root

    property string text: ""
    property string tone: "error"
    property bool closable: true

    signal closeRequested()

    readonly property color soft: tone === "success" ? Theme.dashboardSuccessSoft
                                : tone === "info" ? Theme.dashboardInfoSoft
                                : Theme.dashboardErrorSoft
    readonly property color accent: tone === "success" ? Theme.dashboardSuccess
                                  : tone === "info" ? Theme.dashboardInfo
                                  : Theme.dashboardError
    readonly property color ink: tone === "success" ? Theme.dashboardSuccessText
                               : tone === "info" ? Theme.dashboardInfoText
                               : Theme.dashboardErrorText

    implicitHeight: Math.max(40, message.implicitHeight + 24)
    radius: Theme.radiusSmall
    color: root.soft
    border.width: 1
    border.color: root.accent

    Accessible.role: Accessible.AlertMessage
    Accessible.name: root.text

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 8
        spacing: 10

        LineIcon {
            Layout.alignment: Qt.AlignVCenter
            size: 18
            strokeWidth: 2
            color: root.accent
            path: root.tone === "success" ? Icons.check : Icons.alertCircle
        }

        Label {
            id: message
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            text: root.text
            color: root.ink
            font.pixelSize: Theme.fs(13)
            font.family: Theme.fontFamily
            wrapMode: Text.WordWrap
        }

        DashboardButton {
            visible: root.closable
            Layout.alignment: Qt.AlignVCenter
            variant: "ghost"
            iconOnly: true
            controlHeight: 28
            iconPath: Icons.close
            tooltip: qsTr("Fermer")
            onClicked: root.closeRequested()
        }
    }
}
