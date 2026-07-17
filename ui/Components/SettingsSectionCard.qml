import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes

/*
 * SettingsSectionCard - carte de section utilisee dans l'onglet
 * "Paramètres" de AdminView.qml (Organisation / Préférences / Ports
 * réseau...).
 *
 * Reprend le pattern deja utilise ailleurs dans l'app (icone dans un
 * badge colore + titre, cf. DashboardCard) pour une hierarchie visuelle
 * coherente entre l'ecran d'accueil et les ecrans d'administration.
 * Le contenu de la section (champs, cases a cocher...) se place comme
 * enfants normaux du composant, empiles verticalement sous l'en-tete.
 */
ColumnLayout {
    id: root

    default property alias content: contentColumn.children
    property string icon: ""
    property string title: ""

    spacing: 0

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: cardColumn.implicitHeight + Theme.spacingMedium * 2
        radius: Theme.radiusLarge
        color: Theme.surface
        border.width: 1
        border.color: Theme.border

        ColumnLayout {
            id: cardColumn
            anchors.fill: parent
            anchors.margins: Theme.spacingMedium
            spacing: Theme.spacingSmall

            RowLayout {
                spacing: Theme.spacingSmall
                Layout.bottomMargin: Theme.spacingXs

                Rectangle {
                    Layout.preferredWidth: 28
                    Layout.preferredHeight: 28
                    radius: Theme.radiusMedium
                    color: Theme.primaryMuted
                    visible: root.icon.length > 0

                    Text {
                        anchors.centerIn: parent
                        text: root.icon
                        font.pixelSize: 14
                        color: Theme.primary
                    }
                }

                Label {
                    text: root.title
                    font.pixelSize: Theme.fontSizeSubheading
                    font.bold: true
                    font.family: Theme.fontFamily
                    color: Theme.text
                }
            }

            ColumnLayout {
                id: contentColumn
                Layout.fillWidth: true
                spacing: Theme.spacingSmall
            }
        }
    }
}
