import QtQuick
import QtQuick.Layouts
import Themes

/*
 * SectionHeader - en-tete de rubrique de Ligne claire : filet d'encre de
 * 2 px, titre en PT Serif, compteur en chiffres serif (ambre si une
 * decision est attendue) et lien d'action optionnel a droite.
 */
ColumnLayout {
    id: root

    property string title: ""
    // -1 : pas de compteur.
    property int count: -1
    property bool attention: false
    property string linkText: ""
    property bool rule: true

    signal linkActivated()

    spacing: 10

    Rectangle {
        visible: root.rule
        Layout.fillWidth: true
        Layout.preferredHeight: 2
        color: Theme.ruleInk
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 10

        Text {
            text: root.title
            color: Theme.ink
            font.family: Theme.fontFamilySerif
            font.pixelSize: Theme.fontSizeRubric
            font.weight: Theme.weightBold
            elide: Text.ElideRight
            Layout.fillWidth: root.linkText.length === 0 && root.count < 0
            Accessible.role: Accessible.Heading
        }
        Item { Layout.fillWidth: true; visible: root.linkText.length > 0 || root.count >= 0 }
        Text {
            visible: root.count > 0
            text: root.count
            color: root.attention ? Theme.warningInk : Theme.ink3
            font.family: Theme.fontFamilySerif
            font.pixelSize: Theme.fontSizeRubric
            font.weight: Theme.weightBold
            font.features: ({ "tnum": 1 })
        }
        TextLink {
            visible: root.linkText.length > 0
            text: root.linkText
            onClicked: root.linkActivated()
        }
    }
}
