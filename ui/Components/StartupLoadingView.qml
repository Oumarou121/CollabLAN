import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes

Item {
    id: root
    objectName: "startupLoadingView"

    Rectangle { anchors.fill: parent; color: Theme.background }

    ColumnLayout {
        anchors.centerIn: parent
        spacing: Theme.spacingMedium

        Label {
            Layout.alignment: Qt.AlignHCenter
            text: qsTr("CollabLAN")
            color: Theme.primary
            font.pixelSize: 30
            font.bold: true
        }
        BusyIndicator {
            Layout.alignment: Qt.AlignHCenter
            running: true
        }
        Label {
            Layout.alignment: Qt.AlignHCenter
            text: qsTr("Préparation de votre session…")
            color: Theme.textSecondary
        }
    }
}
