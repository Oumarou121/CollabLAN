import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import "../Components"

/*
 * TransferList - Container minimal pour transferts
 * Pas de carte blanche, juste header + lignes à plat
 */
ColumnLayout {
    id: root
    spacing: 0

    property var transfers: []

    signal detailsRequested(var transfer)
    signal openLocationRequested(var transfer)
    signal retryRequested(var transfer)

    // Header - height 30px
    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: 30

        RowLayout {
            anchors.fill: parent
            spacing: 8

            Label {
                text: qsTr("Transferts")
                color: Theme.dashboardInk
                font.pixelSize: 15
                font.bold: true
                font.family: Theme.fontFamily
            }

            Label {
                text: root.transfers.length > 0 ? (root.transfers.length + " en cours") : ""
                color: Theme.dashboardInkTertiary
                font.pixelSize: 12
                font.family: Theme.fontFamily
            }

            Item { Layout.fillWidth: true }

            Button {
                text: qsTr("Tous les transferts")
                flat: true
                font.pixelSize: 12
                font.family: Theme.fontFamily
                background: Rectangle { color: "transparent" }
                contentItem: Label {
                    text: parent.text
                    color: Theme.dashboardPrimary
                    font.pixelSize: 12
                    font.family: Theme.fontFamily
                }
            }
        }
    }

    // Lignes à plat
    ScrollView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true

        ColumnLayout {
            width: parent.width
            spacing: 0

            Repeater {
                model: root.transfers
                delegate: TransferRow {
                    Layout.fillWidth: true
                    fileName: modelData.fileName || ""
                    peerName: modelData.peerName || ""
                    address: modelData.address || ""
                    progress: modelData.progress || 0
                    transferred: modelData.transferred || 0
                    total: modelData.total || 0
                    status: modelData.status || "En cours"
                    isIncoming: modelData.isIncoming || false

                    onDetailsRequested: root.detailsRequested(modelData)
                    onOpenLocationRequested: root.openLocationRequested(modelData)
                    onRetryRequested: root.retryRequested(modelData)
                }
            }
        }
    }
}
