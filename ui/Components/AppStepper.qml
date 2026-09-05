import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes

/*
 * AppStepper - indicateur d'etape pour les modales en plusieurs temps
 * (ex : creation d'un dossier partage), a la place du RowLayout +
 * Repeater sur-mesure duplique a chaque assistant multi-etapes.
 *
 * Contrairement a la version precedente (codee pour exactement 2
 * etapes, connecteur de largeur fixe visible seulement entre l'etape 1
 * et 2), ce composant :
 *  - accepte n'importe quel nombre d'etapes (steps: liste de libelles) ;
 *  - etire les connecteurs pour occuper l'espace disponible entre les
 *    badges, au lieu d'un trait de largeur fixe ;
 *  - met un leger anneau autour du badge de l'etape courante pour la
 *    distinguer plus nettement des etapes a venir.
 *
 * Usage :
 *   AppStepper {
 *       Layout.fillWidth: true
 *       steps: [qsTr("Dossier"), qsTr("Partage")]
 *       currentStep: createDialog.step   // 1-indexe
 *   }
 */
RowLayout {
    id: root

    property var steps: []
    property int currentStep: 1

    spacing: Theme.spacingSmall

    Repeater {
        model: root.steps

        delegate: RowLayout {
            id: stepDelegate
            required property string modelData
            required property int index

            readonly property int stepNumber: index + 1
            readonly property bool isCurrent: root.currentStep === stepNumber
            readonly property bool isDone: root.currentStep > stepNumber
            readonly property bool hasConnector: index < root.steps.length - 1

            Layout.fillWidth: hasConnector
            spacing: Theme.spacingSmall

            Rectangle {
                id: badge
                Layout.preferredWidth: 24
                Layout.preferredHeight: 24
                radius: Theme.radiusPill
                color: stepDelegate.isCurrent || stepDelegate.isDone ? Theme.primary : Theme.surfaceAlt
                border.width: stepDelegate.isCurrent ? 0 : 1
                border.color: stepDelegate.isDone ? Theme.primary : Theme.border

                Behavior on color { ColorAnimation { duration: 150 } }

                // Anneau discret autour du badge de l'etape courante.
                Rectangle {
                    visible: stepDelegate.isCurrent
                    anchors.centerIn: parent
                    width: parent.width + 6
                    height: parent.height + 6
                    radius: width / 2
                    color: "transparent"
                    border.width: 1.5
                    border.color: Theme.primaryMuted
                }

                Text {
                    anchors.centerIn: parent
                    text: stepDelegate.isDone ? "\u2713" : String(stepDelegate.stepNumber)
                    color: stepDelegate.isCurrent || stepDelegate.isDone ? Theme.primaryText : Theme.textTertiary
                    font.pixelSize: 11
                    font.bold: true
                }
            }

            Label {
                text: stepDelegate.modelData
                color: stepDelegate.isCurrent ? Theme.text : Theme.textTertiary
                font.pixelSize: Theme.fontSizeSmall
                font.bold: stepDelegate.isCurrent
            }

            Rectangle {
                visible: stepDelegate.hasConnector
                Layout.fillWidth: true
                Layout.minimumWidth: 16
                Layout.preferredHeight: 2
                radius: 1
                color: stepDelegate.isDone ? Theme.primary : Theme.border
                Behavior on color { ColorAnimation { duration: 150 } }
            }
        }
    }
}
