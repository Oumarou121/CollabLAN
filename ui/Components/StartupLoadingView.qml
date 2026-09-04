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

        BusyIndicator {
            Layout.alignment: Qt.AlignHCenter
            palette.highlight: Theme.primary
            running: true
        }
        Label {
            Layout.alignment: Qt.AlignHCenter
            text: qsTr("Préparation de votre session…")
            color: Theme.textSecondary
        }
    }
}
