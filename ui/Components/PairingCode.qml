import QtQuick
import QtQuick.Layouts
import Themes

/*
 * PairingCode - code d'appairage a 6 chiffres (« 482 913 »), en serif, pose
 * dans un cadre a filet d'encre. Le meme code s'affiche sur le serveur
 * (Administration) et sur le poste qui demande a rejoindre le reseau : les
 * deux personnes verifient qu'il est identique avant de confirmer.
 */
Rectangle {
    id: root

    property string code: ""
    property bool large: true
    readonly property string spaced: root.code.length === 6 ? root.code.slice(0, 3) + " " + root.code.slice(3) : root.code

    Layout.fillWidth: true
    implicitHeight: label.implicitHeight + (root.large ? 26 : 16)
    radius: Theme.radiusSheet
    color: Theme.surface0
    border.width: root.large ? 1.5 : 1
    border.color: root.large ? Theme.ruleInk : Theme.line
    Accessible.role: Accessible.StaticText
    Accessible.name: root.code.length ? qsTr("Code d'appairage %1").arg(root.code.split("").join(" ")) : qsTr("Code d'appairage en cours de calcul")

    Text {
        id: label
        anchors.centerIn: parent
        text: root.code.length ? root.spaced : qsTr("Calcul du code…")
        color: root.code.length ? Theme.ink : Theme.ink3
        font.family: root.code.length ? Theme.fontFamilySerif : Theme.fontFamily
        font.pixelSize: root.code.length ? Theme.fs(root.large ? 36 : 24) : Theme.fs(13)
        font.weight: Theme.weightBold
        font.letterSpacing: root.code.length ? (root.large ? 6 : 3) : 0
        font.features: ({ "tnum": 1, "lnum": 1 })
    }
}
