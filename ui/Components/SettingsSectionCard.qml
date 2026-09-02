import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes

/*
 * SettingsSectionCard - carte de section utilisee par l'ecran "Parametres"
 * (SettingsView.qml), alignee sur AdminView.qml.
 *
 * Reprend le pattern deja utilise ailleurs dans l'app (icone dans un
 * badge colore + titre, cf. DashboardCard sur HomeView) pour une hierarchie
 * visuelle coherente entre l'ecran d'accueil, l'administration et les
 * parametres. Utilise la meme police d'icones Font Awesome 4.7.0 que
 * DashboardCard (glyphes fa fa-*) plutot qu'un caractere Unicode brut, pour
 * un rendu identique sur tous les postes (refonte design juillet 2026,
 * alignement complet des ecrans Parametres sur Login/Home).
 *
 * Le contenu de la section (champs, cases a cocher...) se place comme
 * enfants normaux du composant, empiles verticalement sous l'en-tete.
 */
ColumnLayout {
    id: root

    default property alias content: contentColumn.children
    property string icon: ""
    property string title: ""
    property string subtitle: ""

    spacing: 0

    FontLoader {
        id: iconFont
        source: "../Assets/fonts/fontawesome-webfont.ttf"
    }
    readonly property string iconFontFamily: iconFont.name

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: cardColumn.implicitHeight + Theme.spacingLarge * 2
        radius: Theme.radiusSmall
        color: Theme.surface
        border.width: 1
        border.color: Theme.border
        antialiasing: true

        ColumnLayout {
            id: cardColumn
            anchors.fill: parent
            anchors.margins: Theme.spacingLarge
            spacing: Theme.spacingMedium

            RowLayout {
                spacing: Theme.spacingMedium
                Layout.bottomMargin: Theme.spacingXs

                Rectangle {
                    Layout.preferredWidth: 36
                    Layout.preferredHeight: 36
                    radius: Theme.radiusMedium
                    color: Theme.primaryMuted
                    visible: root.icon.length > 0

                    Text {
                        anchors.centerIn: parent
                        text: root.icon
                        font.family: root.iconFontFamily
                        font.pixelSize: 15
                        color: Theme.primary
                    }
                }

                ColumnLayout {
                    spacing: 1
                    Label {
                        text: root.title
                        font.pixelSize: Theme.fontSizeSubheading
                        font.bold: true
                        font.family: Theme.fontFamily
                        color: Theme.text
                    }
                    Label {
                        text: root.subtitle
                        visible: root.subtitle.length > 0
                        font.pixelSize: Theme.fontSizeSmall
                        font.family: Theme.fontFamily
                        color: Theme.textTertiary
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                }
            }

            ColumnLayout {
                id: contentColumn
                Layout.fillWidth: true
                spacing: Theme.spacingMedium
            }
        }
    }
}
