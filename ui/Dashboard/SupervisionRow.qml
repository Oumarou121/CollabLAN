import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import "../Components"

/*
 * SupervisionRow - ligne compacte des panneaux du tableau de bord
 * (interventions, echanges en cours, evenements, appels) :
 *
 *   [pastille] Titre                        [badge]
 *              meta (icone optionnelle)     heure | [action]
 *              [progression optionnelle]
 *
 * showDivider : filet superieur (toutes les lignes sauf la premiere).
 */
Item {
    id: root

    property string glyph: ""
    property string tone: "neutral"
    property string title: ""
    property string meta: ""
    property string metaGlyph: ""
    property real progress: -1          // 0..1, ou -1 : pas de barre
    property string badgeText: ""
    property string badgeTone: "neutral"
    property string timeText: ""
    property string actionText: ""
    property string actionTooltip: ""
    property bool showDivider: true
    // Nombre de lignes de la description avant elision (1 ou 2).
    property int maxMetaLines: 2

    signal actionTriggered()

    implicitHeight: layout.implicitHeight + 18
    Accessible.role: Accessible.ListItem
    Accessible.name: root.title + (root.meta.length > 0 ? ", " + root.meta : "")

    Rectangle {
        visible: root.showDivider
        anchors.top: parent.top
        width: parent.width
        height: 1
        color: Theme.line
    }

    RowLayout {
        id: layout
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 12

        Rectangle {
            Layout.preferredWidth: 28
            Layout.preferredHeight: 28
            Layout.alignment: Qt.AlignVCenter
            radius: 8
            color: Theme.toneSoft(root.tone)

            FaIcon {
                anchors.centerIn: parent
                glyph: root.glyph
                color: Theme.toneInk(root.tone)
                font.pixelSize: Theme.fs(12)
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Text {
                id: titleText
                Layout.fillWidth: true
                text: root.title
                color: Theme.ink
                font.pixelSize: Theme.fs(13)
                font.weight: Theme.weightSemibold
                font.family: Theme.fontFamily
                elide: Text.ElideRight

                // Texte complet en infobulle des qu'il est tronque.
                HoverHandler { id: titleHover }
                ToolTip.visible: titleHover.hovered && titleText.truncated
                ToolTip.text: titleText.text
            }
            RowLayout {
                Layout.fillWidth: true
                visible: root.meta.length > 0
                spacing: 4
                FaIcon {
                    Layout.alignment: Qt.AlignTop
                    Layout.topMargin: 2
                    visible: root.metaGlyph.length > 0
                    glyph: root.metaGlyph
                    color: Theme.ink3
                    font.pixelSize: Theme.fs(10)
                }
                Text {
                    id: metaText
                    Layout.fillWidth: true
                    text: root.meta
                    color: Theme.ink3
                    font.pixelSize: Theme.fs(12)
                    font.family: Theme.fontFamily
                    // Jusqu'a deux lignes : une description complete reste lisible
                    // meme quand la ligne porte un bouton d'action.
                    wrapMode: Text.Wrap
                    maximumLineCount: root.maxMetaLines
                    elide: Text.ElideRight

                    HoverHandler { id: metaHover }
                    ToolTip.visible: metaHover.hovered && metaText.truncated
                    ToolTip.text: metaText.text
                }
            }
            Rectangle {
                visible: root.progress >= 0
                Layout.fillWidth: true
                Layout.topMargin: 3
                Layout.preferredHeight: 5
                radius: 3
                color: Theme.sunken

                Rectangle {
                    width: parent.width * Math.max(0, Math.min(1, root.progress))
                    height: parent.height
                    radius: 3
                    color: Theme.accentColor
                    Behavior on width { NumberAnimation { duration: Theme.durationNormal } }
                }
            }
        }

        ColumnLayout {
            visible: root.actionText.length === 0 && (root.badgeText.length > 0 || root.timeText.length > 0)
            Layout.alignment: Qt.AlignVCenter
            spacing: 4

            StatusBadge {
                visible: root.badgeText.length > 0
                Layout.alignment: Qt.AlignRight
                text: root.badgeText
                tone: root.badgeTone
                showDot: false
                compact: true
            }
            Text {
                visible: root.timeText.length > 0
                Layout.alignment: Qt.AlignRight
                text: root.timeText
                color: Theme.ink3
                font.pixelSize: Theme.fs(11.5)
                font.family: Theme.fontFamily
            }
        }

        AppButton {
            visible: root.actionText.length > 0
            Layout.alignment: Qt.AlignVCenter
            text: root.actionText
            tooltip: root.actionTooltip
            size: "small"
            variant: "secondary"
            onClicked: root.actionTriggered()
        }
    }
}
