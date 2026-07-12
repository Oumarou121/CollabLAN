import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes

/*
 * SharedFolderDetailView - historique de synchronisation d'un dossier
 * partage (Phase 10 de la fonctionnalite "Shared Folder").
 *
 * Interroge syncHistoryService.recentOperations(folderId) : simple vue
 * de lecture, sans mise a jour automatique (l'historique est reconsulte
 * a chaque ouverture de l'ecran ou clic sur "Actualiser").
 */
Item {
    id: root

    property int folderId: -1
    property string folderName: ""
    property var historyService: (typeof syncHistoryService !== "undefined") ? syncHistoryService : null

    signal backRequested()

    Rectangle {
        anchors.fill: parent
        color: Theme.background
    }

    function refresh() {
        historyModel.clear()
        if (!root.historyService || root.folderId < 0) {
            return
        }
        const entries = root.historyService.recentOperations(root.folderId, 100)
        for (let i = 0; i < entries.length; ++i) {
            historyModel.append(entries[i])
        }
    }

    onFolderIdChanged: refresh()

    ListModel { id: historyModel }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacingLarge
        spacing: Theme.spacingMedium

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSmall

            Button {
                text: qsTr("< Retour")
                Layout.preferredHeight: 32

                background: Rectangle {
                    radius: Theme.radiusSmall
                    color: parent.hovered ? Theme.surfaceAlt : "transparent"
                    border.width: 1
                    border.color: Theme.border
                }

                contentItem: Text {
                    text: qsTr("< Retour")
                    color: Theme.text
                    font.pixelSize: Theme.fontSizeSmall
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                onClicked: root.backRequested()
            }

            Label {
                text: root.folderName
                font.pixelSize: Theme.fontSizeHeading
                font.bold: true
                font.family: Theme.fontFamily
                color: Theme.text
            }

            Item { Layout.fillWidth: true }

            Button {
                text: qsTr("Actualiser")
                onClicked: root.refresh()
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Theme.radiusLarge
            color: Theme.surface
            border.color: Theme.border
            border.width: 1
            clip: true

            ColumnLayout {
                anchors.centerIn: parent
                spacing: Theme.spacingSmall
                visible: historyList.count === 0
                width: parent.width * 0.7

                Label {
                    Layout.alignment: Qt.AlignHCenter
                    text: qsTr("Aucune activite de synchronisation pour le moment")
                    font.pixelSize: Theme.fontSizeBody
                    font.bold: true
                    color: Theme.text
                    horizontalAlignment: Text.AlignHCenter
                }
            }

            ListView {
                id: historyList
                anchors.fill: parent
                anchors.margins: Theme.spacingSmall
                spacing: Theme.spacingSmall
                clip: true
                model: historyModel

                delegate: Rectangle {
                    width: historyList.width
                    height: 48
                    radius: Theme.radiusMedium
                    color: Theme.surfaceAlt

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.spacingMedium
                        anchors.rightMargin: Theme.spacingMedium
                        spacing: Theme.spacingMedium

                        Label {
                            text: action
                            color: Theme.primary
                            font.bold: true
                            font.pixelSize: Theme.fontSizeSmall
                            font.capitalization: Font.AllUppercase
                        }

                        Label {
                            text: path
                            color: Theme.text
                            font.pixelSize: Theme.fontSizeSmall
                            elide: Text.ElideMiddle
                            Layout.fillWidth: true
                        }

                        Label {
                            text: qsTr("v%1").arg(version)
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeSmall
                        }

                        Label {
                            text: date
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontSizeSmall
                        }
                    }
                }
            }
        }
    }
}
