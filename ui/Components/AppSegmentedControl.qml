import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes

/*
 * AppSegmentedControl - choix exclusif entre 2 a 4 options visibles d'un
 * coup d'oeil (ex. Carte / Liste, Utilisateur / Administrateur).
 *
 * Rail en creux + segment actif en surface : le meme rendu partout dans
 * l'application. Chaque segment est un bouton accessible au clavier.
 *
 *   AppSegmentedControl {
 *       model: [ { label: qsTr("Carte"), glyph: "" }, { label: qsTr("Liste") } ]
 *       currentIndex: 0
 *       onActivated: function(index) { ... }
 *   }
 *
 * stretch : true = segments repartis sur toute la largeur (formulaires) ;
 *           false = largeur naturelle (barres d'outils).
 */
Rectangle {
    id: root

    property var model: []
    property int currentIndex: 0
    property bool stretch: true
    property bool small: false
    // Conservee pour compatibilite (police Font Awesome desormais globale).
    property string iconFontFamily: "FontAwesome"

    signal activated(int index)

    Layout.fillWidth: root.stretch
    implicitHeight: (root.small ? Theme.controlHeightSmall : Theme.controlHeight)
    implicitWidth: segmentsRow.implicitWidth + 6
    radius: Theme.radiusControl
    color: Theme.sunken
    Accessible.role: Accessible.PageTabList

    RowLayout {
        id: segmentsRow
        anchors.fill: parent
        anchors.margins: 3
        spacing: 2

        Repeater {
            model: root.model

            delegate: AbstractButton {
                id: segment

                required property var modelData
                required property int index

                readonly property bool isCurrent: segment.index === root.currentIndex

                Layout.fillWidth: root.stretch
                Layout.fillHeight: true
                implicitWidth: segmentContent.implicitWidth + 24
                hoverEnabled: true
                focusPolicy: Qt.TabFocus
                checkable: false
                Accessible.role: Accessible.PageTab
                Accessible.name: segment.modelData.label || ""
                Accessible.selected: segment.isCurrent

                onClicked: {
                    root.currentIndex = segment.index
                    root.activated(segment.index)
                }

                HoverHandler { cursorShape: Qt.PointingHandCursor }

                background: Rectangle {
                    radius: Theme.radiusControl - 2
                    color: segment.isCurrent ? Theme.surface0
                                             : (segment.hovered ? Theme.alpha(Theme.surface0, 0.5) : "transparent")
                    border.width: segment.isCurrent && Theme.darkMode ? 1 : 0
                    border.color: Theme.line

                    // Ombre discrete sous le segment actif.
                    Rectangle {
                        visible: segment.isCurrent && !Theme.darkMode
                        z: -1
                        anchors.fill: parent
                        anchors.topMargin: 1
                        anchors.bottomMargin: -1
                        radius: parent.radius
                        color: Theme.shadowColor
                    }

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: -2
                        radius: parent.radius + 2
                        color: "transparent"
                        border.width: 2
                        border.color: Theme.focusRing
                        visible: segment.visualFocus
                    }
                }

                contentItem: Item {
                    RowLayout {
                        id: segmentContent
                        anchors.centerIn: parent
                        spacing: 6

                        FaIcon {
                            visible: (segment.modelData.glyph || "").length > 0
                            glyph: segment.modelData.glyph || ""
                            color: segment.isCurrent ? Theme.ink : Theme.ink3
                            font.pixelSize: Theme.fs(12)
                        }

                        Text {
                            text: segment.modelData.label || ""
                            color: segment.isCurrent ? Theme.ink : Theme.ink2
                            font.pixelSize: Theme.fs(root.small ? 12 : 13)
                            font.weight: segment.isCurrent ? Theme.weightSemibold : Theme.weightMedium
                            font.family: Theme.fontFamily
                        }

                        // Compteur optionnel ({ label, count }).
                        Text {
                            visible: segment.modelData.count !== undefined
                            text: segment.modelData.count !== undefined ? segment.modelData.count : ""
                            color: Theme.ink3
                            font.pixelSize: Theme.fs(11)
                            font.weight: Theme.weightMedium
                            font.family: Theme.fontFamily
                            font.features: ({ "tnum": 1 })
                        }
                    }
                }
            }
        }
    }
}
