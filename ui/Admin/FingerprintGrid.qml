import QtQuick
import QtQuick.Layouts
import Themes

/*
 * FingerprintGrid - empreinte SHA-256 d'un certificat, lisible a voix haute :
 * 64 caracteres en 16 groupes de 4, sur quatre colonnes. `large` pour les
 * fenetres ou l'on compare l'empreinte avec celle affichee sur le poste.
 */
Rectangle {
    id: root

    property string fingerprint: ""
    property bool large: false

    readonly property var groups: {
        const clean = String(root.fingerprint || "").replace(/[^0-9a-fA-F]/g, "").toUpperCase()
        return clean.length ? clean.match(/.{1,4}/g) : []
    }

    implicitHeight: Math.max(grid.implicitHeight + (root.large ? 28 : 20), 40)
    radius: Theme.radiusSheet
    color: Theme.surface0
    border.width: 1
    border.color: root.large ? Theme.ruleInk : Theme.line
    Accessible.role: Accessible.StaticText
    Accessible.name: qsTr("Empreinte %1").arg(root.groups.join(" "))

    GridLayout {
        id: grid
        x: root.large ? 16 : 12
        y: root.large ? 14 : 10
        width: parent.width - 2 * x
        columns: 4
        columnSpacing: root.large ? 14 : 10
        rowSpacing: root.large ? 6 : 4
        Repeater {
            model: root.groups
            delegate: Text {
                required property string modelData
                required property int index
                Layout.fillWidth: true
                horizontalAlignment: index % 4 === 0 ? Text.AlignLeft : index % 4 === 3 ? Text.AlignRight : Text.AlignHCenter
                text: modelData
                color: Theme.ink
                font.family: "Cascadia Mono"
                font.pixelSize: root.large ? Theme.fs(15) : Theme.fs(12.5)
                font.letterSpacing: 0.6
            }
        }
    }
    Text {
        visible: root.groups.length === 0
        anchors.centerIn: parent
        text: qsTr("Aucune empreinte enregistrée")
        color: Theme.ink3
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fs(12.5)
    }
}
