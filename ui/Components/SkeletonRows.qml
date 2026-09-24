import QtQuick
import QtQuick.Layouts
import Themes

/*
 * SkeletonRows - lignes squelettes pour les listes du dashboard pendant le
 * chargement (maquette V2.2, mode "Chargement").
 *
 * variant: "transfer" (2 lignes : vignette, 2 lignes de texte, progression)
 *          "activity" (4 lignes : heure, 2 lignes de texte)
 */
ColumnLayout {
    id: root

    property string variant: "transfer"
    property int count: variant === "transfer" ? 2 : 4

    spacing: 0

    Repeater {
        model: root.count

        delegate: Item {
            Layout.fillWidth: true
            Layout.preferredHeight: root.variant === "transfer" ? 46 : 41

            Rectangle {
                visible: root.variant === "transfer" || index > 0
                anchors.top: parent.top
                width: parent.width
                height: 1
                color: Theme.dashboardLine
            }

            Loader {
                anchors.fill: parent
                sourceComponent: root.variant === "transfer" ? transferRow : activityRow
            }
        }
    }

    Component {
        id: transferRow

        RowLayout {
            spacing: 12

            SkeletonLine {
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                radius: 8
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 30

                SkeletonLine { y: 0;  width: parent.width * 0.6 }
                SkeletonLine { y: 18; width: parent.width * 0.4 }
            }

            SkeletonLine { Layout.preferredWidth: 128 }
        }
    }

    Component {
        id: activityRow

        RowLayout {
            spacing: 10

            Item {
                Layout.preferredWidth: 40
                Layout.preferredHeight: 12

                SkeletonLine { width: 32 }
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 30

                SkeletonLine { y: 0;  width: parent.width * 0.45 }
                SkeletonLine { y: 18; width: parent.width * 0.75 }
            }
        }
    }
}
