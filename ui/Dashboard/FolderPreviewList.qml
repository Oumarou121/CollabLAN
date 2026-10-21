import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import "../Components"

/*
 * FolderPreviewList - apercu des dossiers partages (tableau de bord, role
 * utilisateur). Modele : SharedFolderContext.folderModel (roles name,
 * fileCount, isLocalOrigin, hasConflict, isActive).
 */
ColumnLayout {
    id: root
    spacing: 0

    property var folderModel: null
    property int maxItems: 5

    signal folderActivated()

    readonly property int total: root.folderModel ? listView.count : 0

    EmptyState {
        visible: root.total === 0
        Layout.fillWidth: true
        Layout.fillHeight: true
        iconName: "folder"
        title: qsTr("Aucun dossier partagé")
        description: qsTr("Les dossiers partagés avec vous et par vous apparaîtront ici.")
        actionText: qsTr("Ouvrir les dossiers")
        onActionClicked: root.folderActivated()
    }

    ListView {
        id: listView
        visible: root.total > 0
        Layout.fillWidth: true
        Layout.fillHeight: true
        interactive: false
        clip: true
        model: root.folderModel

        delegate: ItemDelegate {
            id: row
            required property int index
            required property string name
            required property int fileCount
            required property bool hasConflict
            required property bool isLocalOrigin

            visible: row.index < root.maxItems
            width: ListView.view.width
            height: row.index < root.maxItems ? (Theme.compact ? 44 : 52) : 0
            padding: 0
            leftPadding: 6
            rightPadding: 6
            hoverEnabled: true
            onClicked: root.folderActivated()
            Accessible.name: row.name

            HoverHandler { cursorShape: Qt.PointingHandCursor }

            background: Rectangle {
                radius: Theme.radiusRow
                color: row.hovered ? Theme.hover : "transparent"
            }

            contentItem: RowLayout {
                spacing: 10

                Rectangle {
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32
                    radius: 8
                    color: Theme.accentSoft

                    FaIcon {
                        anchors.centerIn: parent
                        glyph: ""
                        color: Theme.darkMode ? Theme.accentHover : Theme.accentColor
                        font.pixelSize: Theme.fs(14)
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    Text {
                        text: row.name
                        color: Theme.ink
                        font.pixelSize: Theme.fs(13)
                        font.weight: Theme.weightMedium
                        font.family: Theme.fontFamily
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    Text {
                        text: (row.fileCount === 1 ? qsTr("1 fichier") : qsTr("%1 fichiers").arg(row.fileCount))
                              + " · " + (row.isLocalOrigin ? qsTr("partagé par vous") : qsTr("partagé avec vous"))
                        color: Theme.ink3
                        font.pixelSize: Theme.fs(12)
                        font.family: Theme.fontFamily
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }

                StatusBadge {
                    visible: row.hasConflict
                    text: qsTr("Conflit")
                    tone: "warning"
                    compact: true
                }
            }
        }
    }
}
