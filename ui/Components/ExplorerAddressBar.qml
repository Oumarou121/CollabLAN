import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes

/*
 * ExplorerAddressBar - barre du haut (48px) partagee entre FileTransferView
 * et SharedFolderView (Option B - liste compacte) :
 *   - bouton retour + actualiser
 *   - fil d'Ariane pilule : racine cliquable + segment courant en gras
 *   - champ recherche (optionnel)
 *   - bascule grille/liste (optionnelle)
 *   - zone d'actions additionnelles a droite, propre a chaque ecran
 *     (ex: Historique/Réindexer/⋯ dans SharedFolderView), via le default
 *     property "extraActions" : tout enfant declare directement dans le
 *     composant est ajoute apres la zone recherche/bascule.
 */
Rectangle {
    id: root

    default property alias extraActions: extraRow.data

    property string rootLabel: ""
    // Vide = on est a la racine (segment courant = rootLabel en gras).
    property string currentLabel: ""

    property bool showSearch: true
    property string searchText: ""
    property string searchPlaceholder: qsTr("Rechercher...")

    property bool showViewToggle: false
    property string viewMode: "grid"   // "grid" | "list"

    signal backClicked()
    signal refreshClicked()
    signal rootClicked()
    signal searchQueryChanged(string text)
    signal viewModeSelected(string mode)

    implicitHeight: 48
    color: Theme.addressBarBackground
    border.width: 1
    border.color: Theme.border
    z: 2

    component ToolbarIconButton: Button {
        property string glyph: ""
        implicitWidth: 32
        implicitHeight: 32
        background: Rectangle {
            radius: Theme.radiusSmall
            color: parent.down ? Theme.surfaceHover : (parent.hovered ? Theme.breadcrumbChipHover : "transparent")
        }
        contentItem: Text {
            text: parent.glyph
            color: parent.enabled ? Theme.text : Theme.textTertiary
            font.pixelSize: Theme.fontSizeBody
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.spacingMedium
        anchors.rightMargin: Theme.spacingMedium
        spacing: Theme.spacingSmall

        ToolbarIconButton {
            glyph: "\u2190"
            onClicked: root.backClicked()
        }
        ToolbarIconButton {
            glyph: "\u21bb"
            onClicked: root.refreshClicked()
        }

        // ---- Fil d'Ariane, style barre d'adresse ----
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 32
            radius: Theme.radiusPill
            color: Theme.surfaceAlt
            border.width: 1
            border.color: Theme.border

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.spacingSmall
                anchors.rightMargin: Theme.spacingSmall
                spacing: 2

                Rectangle {
                    id: crumbRootChip
                    radius: Theme.radiusPill
                    color: root.currentLabel.length > 0 && crumbRootArea.containsMouse ? Theme.breadcrumbChipHover : "transparent"
                    implicitHeight: 24
                    implicitWidth: crumbRootLabel.implicitWidth + 20

                    Label {
                        id: crumbRootLabel
                        anchors.centerIn: parent
                        text: root.rootLabel
                        font.pixelSize: Theme.fontSizeSmall
                        font.bold: root.currentLabel.length === 0
                        color: root.currentLabel.length === 0 ? Theme.text : Theme.textSecondary
                    }
                    Rectangle {
                        visible: root.currentLabel.length > 0 && crumbRootArea.containsMouse
                        anchors.left: crumbRootLabel.left
                        anchors.right: crumbRootLabel.right
                        anchors.bottom: crumbRootLabel.bottom
                        anchors.bottomMargin: -1
                        height: 1
                        color: Theme.textSecondary
                    }
                    MouseArea {
                        id: crumbRootArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: root.currentLabel.length > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                        enabled: root.currentLabel.length > 0
                        onClicked: root.rootClicked()
                    }
                }

                Label {
                    visible: root.currentLabel.length > 0
                    text: "\u203A"
                    color: Theme.textTertiary
                    font.pixelSize: Theme.fontSizeSmall
                }

                Rectangle {
                    visible: root.currentLabel.length > 0
                    radius: Theme.radiusPill
                    color: "transparent"
                    implicitHeight: 24
                    implicitWidth: crumbCurrentLabel.implicitWidth + 12
                    Layout.maximumWidth: 220

                    Label {
                        id: crumbCurrentLabel
                        anchors.centerIn: parent
                        width: parent.implicitWidth - 12
                        text: root.currentLabel
                        font.pixelSize: Theme.fontSizeSmall
                        font.bold: true
                        color: Theme.text
                        elide: Text.ElideRight
                    }
                }

                Item { Layout.fillWidth: true }
            }
        }

        // ---- Recherche ----
        Item {
            visible: root.showSearch
            Layout.preferredWidth: 220
            Layout.preferredHeight: 32

            AppSearchField {
                id: searchField
                compact: true
                anchors.fill: parent
                placeholderText: root.searchPlaceholder
                text: root.searchText
                rightInset: clearButton.visible ? clearButton.width + 4 : 0
                onTextChanged: root.searchQueryChanged(text)
            }

            ToolbarIconButton {
                id: clearButton
                glyph: "\u2715"
                visible: root.searchText.length > 0
                implicitWidth: 22
                implicitHeight: 22
                anchors.right: parent.right
                anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                onClicked: { searchField.text = ""; root.searchQueryChanged("") }
            }
        }

        // ---- Bascule vue grille / liste ----
        Rectangle {
            visible: root.showViewToggle
            Layout.preferredHeight: 32
            Layout.preferredWidth: 64
            radius: Theme.radiusSmall
            color: Theme.surfaceAlt
            border.width: 1
            border.color: Theme.border

            RowLayout {
                anchors.fill: parent
                anchors.margins: 2
                spacing: 2
                ToolbarIconButton {
                    implicitWidth: 28
                    implicitHeight: 28
                    background: Rectangle {
                        radius: Theme.radiusSmall
                        color: root.viewMode === "grid" ? Theme.primary : "transparent"
                    }
                    contentItem: Item {
                        readonly property color dotColor: root.viewMode === "grid" ? Theme.primaryText : Theme.text
                        Grid {
                            anchors.centerIn: parent
                            columns: 2
                            rows: 2
                            spacing: 3
                            Repeater {
                                model: 4
                                Rectangle {
                                    width: 6
                                    height: 6
                                    radius: 1
                                    color: parent.parent.dotColor
                                }
                            }
                        }
                    }
                    onClicked: root.viewModeSelected("grid")
                }
                ToolbarIconButton {
                    implicitWidth: 28
                    implicitHeight: 28
                    background: Rectangle {
                        radius: Theme.radiusSmall
                        color: root.viewMode === "list" ? Theme.primary : "transparent"
                    }
                    contentItem: Item {
                        readonly property color barColor: root.viewMode === "list" ? Theme.primaryText : Theme.text
                        Column {
                            anchors.centerIn: parent
                            spacing: 3
                            Repeater {
                                model: 3
                                Rectangle {
                                    width: 16
                                    height: 3
                                    radius: 1
                                    color: parent.parent.barColor
                                }
                            }
                        }
                    }
                    onClicked: root.viewModeSelected("list")
                }
            }
        }

        // ---- Actions additionnelles propres a l'ecran appelant ----
        Row {
            id: extraRow
            spacing: Theme.spacingSmall
        }
    }
}
