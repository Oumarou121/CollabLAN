import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes

/*
 * StartupLoadingView - ecran affiche pendant la preparation de la session
 * (tentative de reconnexion automatique) avant Login ou l'accueil.
 */
Item {
    id: root
    objectName: "startupLoadingView"

    Rectangle { anchors.fill: parent; color: Theme.bg }

    ColumnLayout {
        anchors.centerIn: parent
        spacing: Theme.spacingLarge

        BrandMark {
            Layout.alignment: Qt.AlignHCenter
            size: 56
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: "LocaLink"
            color: Theme.ink
            font.pixelSize: Theme.fs(22)
            font.weight: Theme.weightBold
            font.family: Theme.fontFamily
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 10

            Spinner {
                Layout.preferredWidth: 18
                Layout.preferredHeight: 18
                running: root.visible
            }
            Text {
                text: qsTr("Préparation de votre session…")
                color: Theme.ink2
                font.pixelSize: Theme.fs(14)
                font.family: Theme.fontFamily
                Accessible.role: Accessible.StaticText
            }
        }
    }
}
