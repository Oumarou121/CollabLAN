import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import "../Components"

/*
 * TransferRow - Ligne de transfert à plat selon la maquette HTML exacte
 * Height: 46px
 * Grid: 32px | minmax(0,1fr) | 128px | 38px | 96px
 * Gap: 12px
 * Border-top: 1px solid line
 */
Rectangle {
    id: root
    height: 46
    color: "transparent"

    property string fileName: ""
    property string peerName: ""
    property string address: ""
    property double progress: 0
    property var transferred: 0
    property var total: 0
    property string status: "En cours"
    property bool isIncoming: false

    signal detailsRequested()
    signal openLocationRequested()
    signal retryRequested()

    readonly property color progressColor: root.status === "Échoué" ? "#C8453B" : "#0B5C70"

    // Border top
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 1
        color: Theme.dashboardLine
    }

    // Hover background
    Rectangle {
        anchors.fill: parent
        anchors.topMargin: 1
        color: Qt.rgba(11, 92, 112, 0.06)
        visible: hoverArea.containsMouse
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        spacing: 12

        // Icône fichier - 32px
        Rectangle {
            Layout.preferredWidth: 32
            Layout.preferredHeight: 32
            radius: 8
            color: root.status === "Échoué" ? "#FBE9E7" : "#E0EEF2"

            FaIcon {
                anchors.centerIn: parent
                glyph: fileIcon
                color: root.status === "Échoué" ? "#C8453B" : "#0B5C70"
                font.pixelSize: 16
            }

            readonly property string fileIcon: {
                if (root.fileName.endsWith(".zip")) return "\uf1c9"
                if (root.fileName.endsWith(".pdf")) return "\uf1c1"
                if (root.fileName.endsWith(".pptx") || root.fileName.endsWith(".ppt")) return "\uf1c4"
                if (root.fileName.endsWith(".xlsx") || root.fileName.endsWith(".xls")) return "\uf1c3"
                if (root.fileName.endsWith(".docx") || root.fileName.endsWith(".doc")) return "\uf1c2"
                return "\uf15b"
            }
        }

        // Nom fichier + route - minmax(0,1fr)
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            Label {
                text: root.fileName
                color: Theme.dashboardInk
                font.pixelSize: 14
                font.bold: true
                font.family: Theme.fontFamily
                elide: Text.ElideRight
                Layout.fillWidth: true
            }

            // Route: direction + peer
            Row {
                spacing: 5

                Label {
                    text: root.isIncoming ? qsTr("Réception") : qsTr("Envoi")
                    color: "#4A5961"
                    font.pixelSize: 12
                    font.family: Theme.fontFamily
                }

                FaIcon {
                    glyph: root.isIncoming ? "\uf063" : "\uf062"
                    color: "#0B5C70"
                    font.pixelSize: 10
                    anchors.verticalCenter: parent.verticalCenter
                    transform: Rotation { origin.x: 5; origin.y: 5; angle: root.isIncoming ? 180 : 0 }
                }

                Label {
                    text: root.peerName
                    color: "#15222B"
                    font.pixelSize: 12
                    font.bold: true
                    font.family: Theme.fontFamily
                }
            }
        }

        // Progression + meta - 128px
        ColumnLayout {
            Layout.preferredWidth: 128
            spacing: 4

            Rectangle {
                Layout.fillWidth: true
                height: 6
                radius: 99
                color: "#DDE4E2"

                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: parent.width * root.progress
                    radius: 99
                    color: progressColor
                }
            }

            Label {
                text: formatBytes(root.transferred) + " sur " + formatBytes(root.total)
                color: "#62717A"
                font.pixelSize: 11
                font.family: Theme.fontFamily
                Layout.fillWidth: true
            }
        }

        // Pourcentage - 38px
        Label {
            Layout.preferredWidth: 38
            text: Math.round(root.progress * 100) + " %"
            color: root.status === "Échoué" ? "#C8453B" : "#4A5961"
            font.pixelSize: 12
            font.bold: true
            font.family: Theme.fontFamily
            horizontalAlignment: Text.AlignRight
        }

        // Actions - 96px
        Row {
            Layout.preferredWidth: 96
            spacing: 2
            layoutDirection: Qt.RightToLeft

            Button {
                text: qsTr("Détails")
                flat: true
                font.pixelSize: 12
                font.family: Theme.fontFamily
                visible: root.status !== "Échoué"
                onClicked: root.detailsRequested()
            }

            IconButton {
                glyph: "\uf115"
                size: 28
                visible: root.status === "Terminé"
                onClicked: root.openLocationRequested()
            }

            Button {
                text: qsTr("Réessayer")
                flat: true
                font.pixelSize: 12
                font.family: Theme.fontFamily
                visible: root.status === "Échoué"
                onClicked: root.retryRequested()
            }

            IconButton {
                glyph: "\uf141"
                size: 28
                visible: root.status !== "Échoué"
            }
        }
    }

    MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.detailsRequested()
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
