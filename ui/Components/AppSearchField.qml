import QtQuick
import QtQuick.Controls
import Themes

/*
 * AppSearchField - champ de recherche compact avec icone loupe integree,
 * a la place du motif TextField + Text (icone) duplique dans les vues de
 * recherche (NewConversationView, ConversationsView, CreateGroupView,
 * ExplorerAddressBar, FileTransferView, SharedFolderView...).
 *
 * Contrairement a AppTextField (champ de formulaire avec label/helper),
 * AppSearchField n'a pas de label et reste un simple champ autonome -
 * pensé pour être place directement dans une barre d'outils ou en tete
 * de liste.
 *
 * Deux gabarits, selon `compact` :
 *   - compact: false (defaut) - hauteur 48, fond carte arrondi
 *     (Theme.surfaceAlt), comme les barres de recherche "pleine largeur"
 *     des vues Chat.
 *   - compact: true - hauteur 28, pilule a fond transparent, comme la
 *     barre d'adresse de l'explorateur ou les barres de recherche en
 *     ligne (FileTransferView, SharedFolderView).
 *
 * Usage :
 *   AppSearchField {
 *       placeholderText: qsTr("Rechercher un utilisateur...")
 *       Layout.fillWidth: true
 *       onTextChanged: usersListView.applyFilter(text)
 *   }
 *
 *   AppSearchField {
 *       compact: true
 *       Layout.preferredWidth: 220
 *   }
 */
Rectangle {
    id: root

    property bool compact: false
    property alias text: field.text
    property alias placeholderText: field.placeholderText
    property alias field: field
    property real rightInset: 0

    implicitHeight: compact ? 28 : 48
    radius: compact ? height / 2 : Theme.radiusMedium
    color: compact ? "transparent" : Theme.surfaceAlt
    border.width: compact ? 1 : (field.activeFocus ? 2 : 1)
    border.color: field.activeFocus ? Theme.primary : Theme.border

    Behavior on border.color { ColorAnimation { duration: 100 } }

    FaIcon {
        id: icon
        anchors.left: parent.left
        anchors.leftMargin: root.compact ? 10 : Theme.spacingMedium
        anchors.verticalCenter: parent.verticalCenter
        glyph: "\uf002"
        color: Theme.textTertiary
        font.pixelSize: root.compact ? 11 : 13
    }

    TextField {
        id: field
        anchors.left: icon.right
        anchors.leftMargin: root.compact ? 4 : Theme.spacingXs
        anchors.right: parent.right
        anchors.rightMargin: (root.compact ? 6 : Theme.spacingMedium) + root.rightInset
        anchors.verticalCenter: parent.verticalCenter
        height: parent.height
        color: Theme.text
        font.pixelSize: root.compact ? Theme.fontSizeSmall : Theme.fontSizeBody
        font.family: Theme.fontFamily
        placeholderTextColor: Theme.textTertiary
        selectionColor: Theme.primary
        selectedTextColor: Theme.primaryText
        selectByMouse: true
        leftPadding: 0
        rightPadding: 0
        background: Rectangle { color: "transparent" }
    }
}
