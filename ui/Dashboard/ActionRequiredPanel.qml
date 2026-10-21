import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import "../Components"
import "../Components/icons.js" as Icons

/*
 * ActionRequiredPanel - Zone "À traiter" du Dashboard, refonte 2026.
 *
 * Chaque demande est une carte : filet gauche de 3 px a la couleur de
 * l'urgence, pastille d'icone voilee, titre + description, badge
 * d'urgence, puis une action pleine largeur ("Examiner"). Le fond vient
 * du parent (carte du dashboard).
 *
 * Aucun bouton decoratif : "Examiner" est la seule action reellement
 * cablee (voir HomeView.adminSectionRequested).
 */
ColumnLayout {
    id: root
    spacing: 0

    property var actions: []
    // false quand le panneau est place dans une Card qui porte deja le titre.
    property bool showHeader: true

    signal actionRequested(var action, string actionType)

    // Header - height 32px
    RowLayout {
        visible: root.showHeader
        Layout.fillWidth: true
        Layout.preferredHeight: 32
        spacing: 8

        Label {
            text: qsTr("À traiter")
            color: Theme.dashboardInk
            font.pixelSize: Theme.fontSizeCardTitle
            font.bold: true
            font.letterSpacing: -0.15
            font.family: Theme.fontFamily
        }

        // Badge compteur - voile plutot qu'aplat (la couleur signale, elle
        // ne crie pas).
        Rectangle {
            Layout.preferredWidth: Math.max(20, countLabel.implicitWidth + 12)
            Layout.preferredHeight: 20
            radius: Theme.radiusPill
            color: Theme.dashboardWarningSoft
            visible: root.actions.length > 0

            Label {
                id: countLabel
                anchors.centerIn: parent
                text: root.actions.length > 99 ? "99+" : root.actions.length
                color: Theme.dashboardWarningText
                font.pixelSize: Theme.fs(11)
                font.bold: true
                font.family: Theme.fontFamily
            }
        }

        Item {
            Layout.fillWidth: true
        }
    }

    // Liste des items
    ScrollView {
        id: itemsScroll
        Layout.fillWidth: true
        Layout.fillHeight: true
        // Sans cette condition, ce ScrollView vide restait visible en
        // parallèle de l'état vide ci-dessous : les deux Layout.fillHeight
        // se partageaient alors la hauteur disponible (place réservée à un
        // ScrollView sans contenu), ce qui poussait l'état vide dans la
        // moitié basse du panneau au lieu de le centrer.
        visible: root.actions.length > 0
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: ScrollBar.AsNeeded

        ColumnLayout {
            // availableWidth (et non parent.width) : le parent est le
            // contentItem du Flickable, dont la largeur vaut la largeur
            // implicite du contenu - d'où des cartes plus étroites que la
            // colonne. availableWidth = largeur réelle du viewport.
            width: itemsScroll.availableWidth
            spacing: 8

            Repeater {
                model: root.actions

                delegate: Rectangle {
                    id: card
                    required property var modelData

                    Layout.fillWidth: true
                    implicitHeight: cardColumn.implicitHeight + 24
                    radius: Theme.radiusRow
                    color: Theme.dashboardSurfaceAlt
                    border.width: 1
                    border.color: Theme.dashboardLine

                    readonly property color actionColor: {
                        switch (card.modelData.urgency) {
                        case "high": return Theme.dashboardError
                        case "medium": return Theme.dashboardWarning
                        default: return Theme.dashboardInfo
                        }
                    }

                    readonly property color actionColorSoft: {
                        switch (card.modelData.urgency) {
                        case "high": return Theme.dashboardErrorSoft
                        case "medium": return Theme.dashboardWarningSoft
                        default: return Theme.dashboardInfoSoft
                        }
                    }

                    readonly property color actionColorText: {
                        switch (card.modelData.urgency) {
                        case "high": return Theme.dashboardErrorText
                        case "medium": return Theme.dashboardWarningText
                        default: return Theme.dashboardInfoText
                        }
                    }

                    readonly property string urgencyIcon: {
                        switch (card.modelData.urgency) {
                        case "high": return Icons.ban
                        case "medium": return Icons.alertTriangle
                        default: return Icons.messageCircle
                        }
                    }

                    readonly property string urgencyLabel: {
                        switch (card.modelData.urgency) {
                        case "high": return qsTr("Alerte")
                        case "medium": return qsTr("Action requise")
                        default: return qsTr("Information")
                        }
                    }

                    ColumnLayout {
                        id: cardColumn
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        anchors.topMargin: 12
                        spacing: 9

                        RowLayout {
                            id: cardRow
                            Layout.fillWidth: true
                            spacing: 9
                            // Panneau etroit (petite fenetre, texte agrandi) : le badge passe
                            // sous la description pour laisser toute la largeur au titre.
                            readonly property bool stackBadge: width < 300

                            Rectangle {
                                Layout.preferredWidth: 26
                                Layout.preferredHeight: 26
                                Layout.alignment: Qt.AlignTop
                                radius: 8
                                color: card.actionColorSoft

                                LineIcon {
                                    anchors.centerIn: parent
                                    path: card.urgencyIcon
                                    color: card.actionColorText
                                    size: 14
                                    strokeWidth: 1.9
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                Label {
                                    text: card.modelData.title || ""
                                    color: Theme.dashboardInk
                                    font.pixelSize: Theme.fs(13)
                                    font.weight: Theme.weightSemibold
                                    font.family: Theme.fontFamily
                                    wrapMode: Text.WordWrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }

                                Label {
                                    visible: text.length > 0
                                    text: card.modelData.description || ""
                                    color: Theme.dashboardInkSecondary
                                    font.pixelSize: Theme.fs(12)
                                    font.family: Theme.fontFamily
                                    wrapMode: Text.WordWrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }

                                UrgencyBadge {
                                    visible: cardRow.stackBadge
                                    Layout.topMargin: 4
                                    label: card.urgencyLabel
                                    soft: card.actionColorSoft
                                    ink: card.actionColorText
                                }
                            }

                            // Badge d'urgence - voile + texte, jamais un aplat.
                            UrgencyBadge {
                                visible: !cardRow.stackBadge
                                Layout.alignment: Qt.AlignTop
                                label: card.urgencyLabel
                                soft: card.actionColorSoft
                                ink: card.actionColorText
                            }
                        }

                        // Action unique, secondaire : plusieurs demandes ne doivent
                        // pas aligner plusieurs boutons pleins concurrents.
                        AppButton {
                            Layout.alignment: Qt.AlignRight
                            text: card.modelData.type === "authorization" ? qsTr("Examiner la demande")
                                                                           : qsTr("Voir le journal")
                            iconGlyph: ""
                            variant: "soft"
                            size: "small"
                            onClicked: root.actionRequested(card.modelData, "examine")
                        }
                    }
                }
            }
        }
    }

    // État vide
    Item {
        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: root.actions.length === 0

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 10

            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 48
                Layout.preferredHeight: 48
                radius: 24
                color: Theme.dashboardSuccessSoft

                LineIcon {
                    anchors.centerIn: parent
                    path: Icons.checkCircle
                    color: Theme.dashboardSuccessText
                    size: 24
                    strokeWidth: 1.8
                }
            }

            Label {
                text: qsTr("Tout est en ordre")
                color: Theme.dashboardInk
                font.pixelSize: Theme.fs(14)
                font.weight: Theme.weightSemibold
                font.family: Theme.fontFamily
                Layout.alignment: Qt.AlignHCenter
            }

            Label {
                text: qsTr("Aucune autorisation en attente,\naucune connexion refusée récente.")
                color: Theme.dashboardInkTertiary
                font.pixelSize: Theme.fs(12)
                font.family: Theme.fontFamily
                horizontalAlignment: Text.AlignHCenter
                Layout.alignment: Qt.AlignHCenter
            }
        }
    }

    // Badge d'urgence - voile + texte, jamais un aplat.
    component UrgencyBadge: Rectangle {
        property string label: ""
        property color soft: "transparent"
        property color ink: Theme.ink

        implicitWidth: badgeText.implicitWidth + 16
        implicitHeight: 20
        radius: Theme.radiusPill
        color: soft

        Label {
            id: badgeText
            anchors.centerIn: parent
            text: parent.label
            color: parent.ink
            font.pixelSize: Theme.fs(11)
            font.weight: Theme.weightSemibold
            font.family: Theme.fontFamily
        }
    }
}
