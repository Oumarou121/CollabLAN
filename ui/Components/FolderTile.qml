import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes

/*
 * FolderTile - tuile "dossier" utilisee pour presenter une categorie (ici :
 * un correspondant de transfert de fichiers) sous forme de dossier, a la
 * maniere d'un explorateur de fichiers moderne (Windows 11 / Nautilus) :
 *   - icone de dossier "plat" avec onglet et leger degrade
 *   - pastille de comptage superposee au coin
 *   - libelle + sous-libelle centres sous l'icone
 *   - etat survole (legere elevation) et etat selectionne (voile + bordure
 *     de la couleur d'accent, comme la selection d'un explorateur)
 */
Item {
    id: root

    property string label: ""
    property string sublabel: ""
    property int count: 0
    property color accentColor: Theme.primary
    property bool highlighted: false
    property bool hasConflict: false

    signal opened()

    implicitWidth: 136
    implicitHeight: 132

    readonly property bool hovered: mouseArea.containsMouse

    // ---- Fond de la tuile (survol / selection) ----
    Rectangle {
        id: tileBg
        anchors.fill: parent
        radius: Theme.radiusMedium
        color: root.highlighted ? Theme.selectionBackground
               : root.hovered ? Theme.surfaceHover
               : "transparent"
        border.width: root.highlighted ? 1 : 0
        border.color: Theme.selectionBorder

        Behavior on color { ColorAnimation { duration: 120 } }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacingSmall
        spacing: 6

        // ---- Icone de dossier ----
        Item {
            id: iconArea
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 64
            Layout.preferredHeight: 52
            Layout.topMargin: 6

            // Legere "elevation" au survol : ombre discrete sous le dossier.
            Rectangle {
                anchors.fill: folderShape
                anchors.topMargin: 3
                radius: folderShape.radius
                color: Theme.shadow
                opacity: root.hovered ? 0.55 : 0
                Behavior on opacity { NumberAnimation { duration: 120 } }
            }

            // Corps du dossier (forme "plate" a onglet, style Explorer moderne).
            Item {
                id: folderShape
                anchors.fill: parent
                property real radius: 6
                scale: root.hovered ? 1.04 : 1.0
                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                // Onglet arriere-plan (partie visible derriere le rabat).
                Rectangle {
                    x: 2
                    y: 4
                    width: parent.width * 0.42
                    height: 10
                    radius: 3
                    color: root.accentColor
                    opacity: 0.75
                }

                // Corps principal du dossier.
                Rectangle {
                    y: 10
                    width: parent.width
                    height: parent.height - 10
                    radius: folderShape.radius
                    color: root.accentColor

                    // Degrade subtil pour un rendu moins plat (facade "vitree").
                    Rectangle {
                        anchors.fill: parent
                        radius: parent.radius
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.16) }
                            GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.0) }
                        }
                    }

                    // Ligne de pli du rabat avant.
                    Rectangle {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: parent.height * 0.38
                        radius: folderShape.radius
                        color: Qt.rgba(1, 1, 1, 0.10)
                    }
                }
            }

            // Pastille conflit (warning badge sur le coin superieur gauche)
            Rectangle {
                visible: root.hasConflict
                width: 21
                height: 21
                radius: 11
                color: "#C07000" // Ambre
                border.width: 2
                border.color: Theme.surface
                anchors.left: folderShape.left
                anchors.top: folderShape.top
                anchors.leftMargin: -7
                anchors.topMargin: -4

                Text {
                    anchors.centerIn: parent
                    text: "⚠"
                    font.pixelSize: 11
                    font.bold: true
                    font.family: Theme.fontFamily
                    color: "#FFFFFF"
                }
            }

            // Pastille de comptage (nombre d'elements dans ce dossier).
            Rectangle {
                visible: root.count > 0
                width: 21
                height: 21
                radius: 11
                color: Theme.primary
                border.width: 2
                border.color: Theme.surface
                anchors.right: folderShape.right
                anchors.top: folderShape.top
                anchors.rightMargin: -7
                anchors.topMargin: -4

                Text {
                    anchors.centerIn: parent
                    text: root.count > 99 ? "99+" : root.count
                    font.pixelSize: 10
                    font.bold: true
                    font.family: Theme.fontFamily
                    color: Theme.primaryText
                }
            }
        }

        Label {
            Layout.fillWidth: true
            text: root.label
            color: Theme.text
            font.pixelSize: Theme.fontSizeSmall
            font.bold: true
            font.family: Theme.fontFamily
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            maximumLineCount: 1
        }

        Label {
            Layout.fillWidth: true
            visible: root.sublabel.length > 0
            text: root.sublabel
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSizeCaption
            font.family: Theme.fontFamily
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            maximumLineCount: 1
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.opened()
    }
}
