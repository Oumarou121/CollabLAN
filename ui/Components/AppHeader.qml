import QtQuick
import QtQuick.Layouts
import Themes

/*
 * AppHeader - en-tete de page standard (refonte 2026).
 *
 * Depuis que la navigation est fournie par AppShell, l'en-tete de page
 * n'est plus un bandeau avec bouton retour : c'est un titre de page
 * (+ sous-titre) aligne sur la grille, avec les actions de la page a
 * droite. Le bouton retour reste disponible pour les SOUS-pages
 * (showBackButton: true).
 *
 *   AppHeader {
 *       title: qsTr("Postes")
 *       subtitle: qsTr("12 postes détectés sur le réseau")
 *       AppButton { text: qsTr("Actualiser"); onClicked: ... }   // actions
 *   }
 */
Item {
    id: root

    Layout.fillWidth: true
    implicitHeight: headerRow.implicitHeight + topPadding + bottomPadding

    property string title: ""
    property string subtitle: ""
    property bool showBackButton: false
    // Icone de contexte optionnelle (glyphe Font Awesome) devant le titre.
    property string leadingIcon: ""
    property string leadingIconFontFamily: ""
    property bool showDivider: false
    property int topPadding: Theme.compact ? 16 : 24
    property int bottomPadding: Theme.compact ? 12 : 18
    property int sidePadding: Theme.pagePadding

    signal backRequested()

    // Actions de droite : tout enfant declare dans AppHeader { ... }.
    default property alias trailingContent: trailingRow.data

    Rectangle {
        visible: root.showDivider
        anchors.bottom: parent.bottom
        width: parent.width
        height: 1
        color: Theme.line
    }

    RowLayout {
        id: headerRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: root.sidePadding
        anchors.rightMargin: root.sidePadding
        anchors.topMargin: root.topPadding
        spacing: 12

        IconButton {
            visible: root.showBackButton
            Layout.alignment: Qt.AlignTop
            glyph: ""
            variant: "secondary"
            size: Theme.controlHeight
            tooltip: qsTr("Retour")
            onClicked: root.backRequested()
        }

        Rectangle {
            visible: root.leadingIcon.length > 0
            Layout.alignment: Qt.AlignTop
            Layout.preferredWidth: 40
            Layout.preferredHeight: 40
            radius: Theme.radiusMedium
            color: Theme.accentSoft

            FaIcon {
                anchors.centerIn: parent
                glyph: root.leadingIcon
                color: Theme.darkMode ? Theme.accentHover : Theme.accentColor
                font.pixelSize: Theme.fs(16)
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 3

            Text {
                text: root.title
                color: Theme.ink
                font.pixelSize: Theme.fontSizeTitle
                font.weight: Theme.weightBold
                font.letterSpacing: -0.4
                font.family: Theme.fontFamily
                elide: Text.ElideRight
                Layout.fillWidth: true
                Accessible.role: Accessible.Heading
            }

            Text {
                visible: root.subtitle.length > 0
                text: root.subtitle
                color: Theme.ink2
                font.pixelSize: Theme.fs(13)
                font.family: Theme.fontFamily
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
        }

        RowLayout {
            id: trailingRow
            Layout.alignment: Qt.AlignVCenter
            spacing: Theme.spacingSmall
        }
    }
}
