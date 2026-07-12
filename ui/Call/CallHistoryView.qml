import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes

/*
 * CallHistoryView - historique des appels vocaux emis/recus par
 * l'utilisateur local, persiste en base (migration 013, voir
 * core::CallHistoryManager / database::CallHistoryRepository).
 *
 * Vue reactive, comme UsersView/AuditLogModel : s'appuie sur le modele
 * QML global "callHistoryModel" (core::CallHistoryModel, expose depuis
 * app/main.cpp), qui se rafraichit automatiquement a chaque appel
 * enregistre/finalise (core::CallHistoryManager::callRecorded/
 * callFinalized).
 */
Item {
    id: root

    property var model: (typeof callHistoryModel !== "undefined") ? callHistoryModel : null

    signal backRequested()

    function statusLabel(status) {
        switch (status) {
        case "completed": return qsTr("Termine")
        case "missed": return qsTr("Manque")
        case "rejected": return qsTr("Refuse")
        case "cancelled": return qsTr("Annule")
        case "failed": return qsTr("Echoue")
        default: return qsTr("En cours")
        }
    }

    function statusColor(status) {
        switch (status) {
        case "completed": return Theme.success
        case "missed": return Theme.error
        case "rejected": return Theme.error
        case "cancelled": return Theme.textSecondary
        case "failed": return Theme.error
        default: return Theme.primary
        }
    }

    function directionIcon(direction) {
        return direction === "outgoing" ? "\u2197" : "\u2199"
    }

    function formatDuration(seconds) {
        if (seconds === undefined || seconds === null || seconds < 0)
            return ""
        const m = Math.floor(seconds / 60)
        const s = seconds % 60
        return (m > 0 ? (m + " min ") : "") + s + " s"
    }

    function formatDate(isoString) {
        if (!isoString)
            return ""
        const d = new Date(isoString)
        return d.toLocaleString(Qt.locale(), "dd/MM/yyyy HH:mm")
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.background
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacingLarge
        spacing: Theme.spacingMedium

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSmall

            Button {
                text: qsTr("< Retour")
                Layout.preferredHeight: 32

                background: Rectangle {
                    radius: Theme.radiusSmall
                    color: parent.hovered ? Theme.surfaceAlt : "transparent"
                    border.width: 1
                    border.color: Theme.border
                }

                contentItem: Text {
                    text: qsTr("< Retour")
                    color: Theme.text
                    font.pixelSize: Theme.fontSizeSmall
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                onClicked: root.backRequested()
            }

            Label {
                text: qsTr("Historique des appels")
                font.pixelSize: Theme.fontSizeHeading
                font.bold: true
                font.family: Theme.fontFamily
                color: Theme.text
            }

            Item { Layout.fillWidth: true }

            Rectangle {
                Layout.preferredWidth: countLabel.implicitWidth + Theme.spacingMedium
                Layout.preferredHeight: 28
                radius: height / 2
                color: Theme.surfaceAlt
                border.color: Theme.border
                border.width: 1

                Label {
                    id: countLabel
                    anchors.centerIn: parent
                    text: root.model ? qsTr("%n appel(s)", "", root.model.count) : qsTr("0 appel")
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeSmall
                }
            }

            Button {
                text: qsTr("Actualiser")
                Layout.preferredHeight: 28
                onClicked: if (root.model) root.model.refresh()
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Theme.radiusLarge
            color: Theme.surface
            border.color: Theme.border
            border.width: 1
            clip: true

            ColumnLayout {
                anchors.centerIn: parent
                spacing: Theme.spacingSmall
                visible: listView.count === 0
                width: parent.width * 0.7

                Label {
                    Layout.alignment: Qt.AlignHCenter
                    text: qsTr("Aucun appel dans l'historique")
                    font.pixelSize: Theme.fontSizeBody
                    font.bold: true
                    color: Theme.text
                    horizontalAlignment: Text.AlignHCenter
                }

                Label {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.fillWidth: true
                    text: qsTr("Vos appels emis et recus apparaitront ici automatiquement.")
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeSmall
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }
            }

            ListView {
                id: listView
                anchors.fill: parent
                anchors.margins: Theme.spacingSmall
                spacing: Theme.spacingSmall
                clip: true
                model: root.model

                delegate: Rectangle {
                    width: listView.width
                    height: 60
                    radius: Theme.radiusMedium
                    color: Theme.surfaceAlt

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.spacingMedium
                        anchors.rightMargin: Theme.spacingMedium
                        spacing: Theme.spacingMedium

                        Rectangle {
                            width: 36
                            height: 36
                            radius: 18
                            color: Theme.primary

                            Text {
                                anchors.centerIn: parent
                                text: root.directionIcon(direction)
                                color: Theme.primaryText
                                font.pixelSize: 16
                                font.bold: true
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Label {
                                text: (peerName && peerName.length > 0) ? peerName : peerAddress
                                color: Theme.text
                                font.pixelSize: Theme.fontSizeBody
                                font.bold: true
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }

                            Label {
                                text: root.formatDate(startedAt)
                                       + (durationSeconds >= 0 ? (" \u2022 " + root.formatDuration(durationSeconds)) : "")
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontSizeSmall
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }

                        RowLayout {
                            spacing: Theme.spacingSmall / 2

                            Rectangle {
                                width: 8
                                height: 8
                                radius: 4
                                color: root.statusColor(status)
                            }

                            Label {
                                text: root.statusLabel(status)
                                color: Theme.textSecondary
                                font.pixelSize: Theme.fontSizeSmall
                            }
                        }
                    }
                }
            }
        }
    }
}
