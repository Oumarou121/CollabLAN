import QtQuick
import QtQuick.Layouts
import Themes

/*
 * AppSegmentedControl - rangee de boutons exclusifs, a la place d'un
 * ComboBox quand il n'y a que 2-4 choix qu'on veut voir d'un coup
 * d'oeil (ex: role Utilisateur/Administrateur dans la modale "Ajouter
 * un utilisateur").
 *
 * `model` attend une liste d'objets { label, glyph } (glyph optionnel,
 * glyphe Font Awesome). `currentIndex` est bindable dans les deux sens.
 *
 * Usage :
 *   AppSegmentedControl {
 *       Layout.fillWidth: true
 *       model: [
 *           { label: qsTr("Utilisateur"), glyph: "\uf007" },
 *           { label: qsTr("Administrateur"), glyph: "\uf132" }
 *       ]
 *       currentIndex: 0
 *       onCurrentIndexChanged: ...
 *   }
 */
RowLayout {
    id: root

    property var model: []
    property int currentIndex: 0
    property string iconFontFamily: iconFont.name

    signal activated(int index)

    spacing: Theme.spacingXs
    Layout.fillWidth: true

    FontLoader {
        id: iconFont
        source: "../Assets/fonts/fontawesome-webfont.ttf"
    }

    Repeater {
        model: root.model

        delegate: Rectangle {
            id: segment

            required property var modelData
            required property int index

            readonly property bool isCurrent: index === root.currentIndex

            Layout.fillWidth: true
            Layout.preferredHeight: 38
            radius: Theme.radiusMedium
            color: isCurrent ? Theme.primaryMuted : "transparent"
            border.width: 1
            border.color: isCurrent ? Theme.primary : Theme.border

            Behavior on color { ColorAnimation { duration: 100 } }

            HoverHandler {
                cursorShape: Qt.PointingHandCursor
            }

            Row {
                anchors.centerIn: parent
                spacing: Theme.spacingXs

                Text {
                    visible: (segment.modelData.glyph || "").length > 0
                    text: segment.modelData.glyph || ""
                    font.family: iconFont.name
                    font.pixelSize: Theme.fontSizeSmall
                    color: segment.isCurrent ? Theme.primary : Theme.textSecondary
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    text: segment.modelData.label || ""
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    font.bold: segment.isCurrent
                    color: segment.isCurrent ? Theme.primary : Theme.textSecondary
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    root.currentIndex = segment.index
                    root.activated(segment.index)
                }
            }
        }
    }
}
