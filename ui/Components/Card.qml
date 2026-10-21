import QtQuick
import QtQuick.Layouts
import Themes

/*
 * Card - conteneur de section du design system.
 *
 * Surface blanche (ou ardoise en sombre), filet fin, rayon 12, sans ombre :
 * la hierarchie vient du contraste avec le fond de page, pas d'effets.
 *
 * En-tete optionnel : titre, sous-titre, compteur, actions (headerActions).
 * Contenu : enfants declares dans Card { ... } (ColumnLayout interne).
 *
 *   Card {
 *       title: qsTr("Transferts récents")
 *       count: 3
 *       headerActions: [ AppButton { text: qsTr("Tout voir"); variant: "ghost"; size: "small" } ]
 *       TransferList { Layout.fillWidth: true; Layout.fillHeight: true }
 *   }
 */
Rectangle {
    id: root

    property string title: ""
    property string subtitle: ""
    property int count: -1
    property string countTone: "neutral"
    property string glyph: ""
    // Marges interieures du contenu (0 pour une liste bord a bord).
    property int contentPadding: Theme.cardPadding
    property int contentTopPadding: root.hasHeader ? 4 : contentPadding
    property alias headerActions: actionsRow.data
    default property alias content: body.data

    readonly property bool hasHeader: root.title.length > 0

    radius: Theme.radiusCard
    color: Theme.surface0
    border.width: 1
    border.color: Theme.line
    implicitHeight: column.implicitHeight
    implicitWidth: 320

    ColumnLayout {
        id: column
        anchors.fill: parent
        spacing: 0

        RowLayout {
            visible: root.hasHeader
            Layout.fillWidth: true
            Layout.leftMargin: Theme.cardPadding
            Layout.rightMargin: Theme.cardPadding - 4
            Layout.topMargin: Theme.compact ? 10 : 14
            Layout.bottomMargin: Theme.compact ? 6 : 10
            spacing: 8

            FaIcon {
                visible: root.glyph.length > 0
                glyph: root.glyph
                color: Theme.ink2
                font.pixelSize: Theme.fs(14)
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                // fillWidth + espaceur : sans enfant extensible, une mise en
                // page Qt plafonne sa largeur a sa largeur implicite, et les
                // actions se colleraient au titre au lieu d'aller a droite.
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: root.title
                        color: Theme.ink
                        font.pixelSize: Theme.fontSizeCardTitle
                        font.weight: Theme.weightSemibold
                        font.family: Theme.fontFamily
                        elide: Text.ElideRight
                        Accessible.role: Accessible.Heading
                    }

                    StatusBadge {
                        visible: root.count >= 0
                        text: root.count > 99 ? "99+" : root.count
                        tone: root.countTone
                        showDot: false
                        compact: true
                    }

                    Item { Layout.fillWidth: true }
                }

                Text {
                    visible: root.subtitle.length > 0
                    text: root.subtitle
                    color: Theme.ink3
                    font.pixelSize: Theme.fs(12)
                    font.family: Theme.fontFamily
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }

            RowLayout {
                id: actionsRow
                spacing: 4
            }
        }

        ColumnLayout {
            id: body
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: root.contentPadding
            Layout.rightMargin: root.contentPadding
            Layout.topMargin: root.contentTopPadding
            Layout.bottomMargin: root.contentPadding
            spacing: Theme.spacingSmall
        }
    }
}
