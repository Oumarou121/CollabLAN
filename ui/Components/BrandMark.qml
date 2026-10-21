import QtQuick
import Themes

/*
 * BrandMark - logo LocaLink (deux silhouettes bleues), sans cadre : le
 * dessin est lisible aussi bien sur fond clair que sombre. Utilise par la
 * navigation, la connexion et "A propos".
 */
Item {
    id: root

    property int size: 40

    implicitWidth: size
    implicitHeight: size
    width: size
    height: size

    Image {
        anchors.fill: parent
        source: "../Assets/logo.png"
        sourceSize.width: root.size * 2
        sourceSize.height: root.size * 2
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
        Accessible.role: Accessible.Graphic
        Accessible.name: "LocaLink"
    }
}
