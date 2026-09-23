import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import "../Components"

/*
 * ActivityRow - Ligne d'activité à plat selon la maquette HTML exacte
 * Height: 41px
 * Grid: 40px | minmax(0,1fr) | auto
 * Gap: 10px
 * Border-top: 1px solid line
 */
Rectangle {
    id: root
    height: 41
    color: "transparent"

    property string event: ""
    property string actor: ""
    property string message: ""
    property string result: ""
    property string resultBadge: ""
    property var timestamp: new Date()

    // Border top (sauf premier)
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 1
        color: Theme.dashboardLine
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 0
        anchors.rightMargin: 0
        spacing: 10

        // Timestamp - 40px
        Label {
            Layout.preferredWidth: 40
            text: Qt.formatTime(root.timestamp, "hh:mm")
            color: Theme.dashboardInkTertiary
            font.pixelSize: 11
            font.weight: 500
            font.family: Theme.fontFamily
        }

        // Contenu - minmax(0,1fr)
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Row {
                spacing: 6

                Rectangle {
                    width: 6
                    height: 6
                    radius: 3
                    color: eventColor
                    anchors.verticalCenter: parent.verticalCenter

                    readonly property color eventColor: {
                        switch(root.event) {
                            case "connection": return Theme.dashboardSuccess
                            case "message": return Theme.dashboardInfo
                            case "transfer": return Theme.dashboardPrimary
                            case "call": return Theme.dashboardCall
                            case "access_denied": return Theme.dashboardError
                            default: return Theme.dashboardInkTertiary
                        }
                    }
                }

                Label {
                    text: root.actor || eventLabel
                    color: Theme.dashboardInk
                    font.pixelSize: 14
                    font.bold: true
                    font.family: Theme.fontFamily
                    elide: Text.ElideRight

                    readonly property string eventLabel: {
                        switch(root.event) {
                            case "connection": return qsTr("Connexion")
                            case "message": return qsTr("Message")
                            case "transfer": return qsTr("Transfert")
                            case "call": return qsTr("Appel")
                            case "access_denied": return qsTr("Accès refusé")
                            default: return qsTr("Activité")
                        }
                    }
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

        // Badge résultat - auto
        Rectangle {
            Layout.preferredWidth: resultBadgeText.width + 12
            Layout.preferredHeight: 22
            radius: 999
            color: resultBadgeColor
            visible: root.resultBadge.length > 0

            Label {
                id: resultBadgeText
                anchors.centerIn: parent
                text: resultBadgeLabel
                color: "#FFFFFF"
                font.pixelSize: 12
                font.bold: true
                font.family: Theme.fontFamily
            }

            readonly property color resultBadgeColor: {
                switch(root.resultBadge) {
                    case "ok": return Theme.dashboardSuccess
                    case "err": return Theme.dashboardError
                    case "xf": return Theme.dashboardPrimary
                    case "call": return Theme.dashboardCall
                    default: return Theme.dashboardInkTertiary
                }
            }

            readonly property string resultBadgeLabel: {
                switch(root.resultBadge) {
                    case "ok": return qsTr("Terminé")
                    case "err": return qsTr("Refusé")
                    case "xf": return qsTr("En cours")
                    case "call": return qsTr("En cours")
                    default: return ""
                }
            }
        }
    }
}
