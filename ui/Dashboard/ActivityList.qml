import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import "../Components"

/*
 * ActivityList - Container minimal pour activité
 * Pas de carte blanche, juste header + lignes à plat
 */
ColumnLayout {
    id: root
    spacing: 0

    property var activities: []
    property bool loading: false

    // Header - height 30px
    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: 30

        RowLayout {
            anchors.fill: parent
            spacing: 8

            Label {
                text: qsTr("Activité récente")
                color: Theme.dashboardInk
                font.pixelSize: 15
                font.bold: true
                font.family: Theme.fontFamily
            }

            // Résumé contextuel (priorité 11 du brief), même logique que
            // TransferList : donner du contexte sans ajouter de carte.
            Label {
                text: root.activities.length > 0
                      ? qsTr("Aujourd'hui \u00B7 %1 événement%2").arg(root.activities.length).arg(root.activities.length > 1 ? "s" : "")
                      : ""
                color: Theme.dashboardInkTertiary
                font.pixelSize: 12
                font.family: Theme.fontFamily
            }

            Item { Layout.fillWidth: true }

            Button {
                visible: !root.loading && root.activities.length > 0
                text: qsTr("Voir le journal")
                flat: true
                font.pixelSize: 12
                font.family: Theme.fontFamily
                background: Rectangle { color: "transparent" }
                contentItem: Label {
                    text: parent.text
                    color: Theme.dashboardPrimary
                    font.pixelSize: 12
                    font.family: Theme.fontFamily
                }
            }
        }
    }

    SkeletonRows {
        visible: root.loading
        variant: "activity"
        Layout.fillWidth: true
    }

    EmptyState {
        visible: !root.loading && root.activities.length === 0
        Layout.fillWidth: true
        Layout.fillHeight: true
        iconName: "log"
        title: qsTr("Aucune activité pour le moment")
        description: qsTr("Les connexions, messages, transferts et appels apparaîtront ici.")
    }

    // Lignes à plat
    ScrollView {
        visible: !root.loading && root.activities.length > 0
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true

        ColumnLayout {
            width: parent.width
            spacing: 0

            Repeater {
                model: root.activities
                delegate: ActivityRow {
                    Layout.fillWidth: true
                    event: modelData.event || ""
                    actor: modelData.actor || ""
                    message: modelData.message || ""
                    result: modelData.result || ""
                    resultBadge: modelData.resultBadge || ""
                    timestamp: modelData.timestamp || new Date()
                    isFirst: index === 0
                    isLast: index === root.activities.length - 1
                }
            }
        }
    }
}
