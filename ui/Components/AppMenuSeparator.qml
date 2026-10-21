import QtQuick
import QtQuick.Controls
import Themes

// Separateur d'AppMenu : filet fin, marges verticales reduites.
MenuSeparator {
    topPadding: 4
    bottomPadding: 4
    leftPadding: 6
    rightPadding: 6

    contentItem: Rectangle {
        implicitHeight: 1
        color: Theme.line
    }
}
