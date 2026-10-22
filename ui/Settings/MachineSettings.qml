import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import QtCore
import Themes
import "../Components"
import "../Components/icons.js" as Icons

/*
 * MachineSettings - Parametres > Ce poste (Ligne claire).
 *
 *   - Nom du poste (settingsModel.machineName, vide = nom Windows) : saisi
 *     puis Enregistrer / Annuler sur la ligne. Le setter est branche sur la
 *     decouverte (main.cpp) : on ne l'appelle qu'a l'enregistrement, pour
 *     qu'aucune annonce ne diffuse un nom a moitie tape.
 *   - Fichiers recus (defaultDownloadPath, vide = Documents/LocaLink
 *     Transfers) et dossier partage propose (defaultSharedFolderPath) :
 *     choisis par le selecteur de dossier, enregistres aussitot.
 */
ColumnLayout {
    id: root
    spacing: 0

    readonly property var settings: (typeof settingsModel !== "undefined") ? settingsModel : null
    readonly property string savedName: root.settings ? root.settings.machineName : ""
    property string draftName: root.savedName
    readonly property bool editingName: root.draftName.trim() !== root.savedName
    property string savedKey: ""            // name | dl | share : ligne qui affiche « Enregistré »
    onSavedNameChanged: if (!nameField.field.activeFocus) { root.draftName = root.savedName; nameField.text = root.savedName }

    // Dossier de reception par defaut de TransferService::receiveDirectory().
    readonly property string defaultDownload: root.localPath(StandardPaths.writableLocation(StandardPaths.DocumentsLocation)) + "/LocaLink Transfers"
    readonly property string downloadPath: root.settings ? root.settings.defaultDownloadPath : ""
    readonly property string sharePath: root.settings ? root.settings.defaultSharedFolderPath : ""

    function localPath(url) {
        let p = decodeURIComponent(String(url)).replace(/^file:\/\//, "")
        if (/^\/[A-Za-z]:/.test(p)) p = p.substring(1)
        return p
    }
    function nativePath(p) { return Qt.platform.os === "windows" ? String(p).replace(/\//g, "\\") : p }
    function persist(key) {
        if (root.settings) root.settings.save()
        root.savedKey = key
        savedTimer.restart()
    }
    Timer { id: savedTimer; interval: 6000; onTriggered: root.savedKey = "" }

    function saveName() {
        if (!root.settings) return
        root.settings.machineName = root.draftName.trim()
        root.draftName = root.settings.machineName
        nameField.text = root.draftName
        root.persist("name")
        nameField.field.focus = false
    }
    function cancelName() { root.draftName = root.savedName; nameField.text = root.savedName; nameField.field.focus = false }

    component PathBox: Rectangle {
        id: pb
        property string path: ""
        property bool isDefault: false
        Layout.fillWidth: true
        Layout.maximumWidth: 560
        implicitHeight: 38
        radius: Theme.radiusSheet
        color: Theme.surface0
        border.width: 1
        border.color: Theme.line
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 10
            LineIcon { path: Icons.folder; size: 16; strokeWidth: 1.7; color: Theme.ink3 }
            Text {
                Layout.fillWidth: true
                text: root.nativePath(pb.path)
                elide: Text.ElideMiddle
                color: Theme.ink
                font.family: "Cascadia Mono"
                font.pixelSize: Theme.fs(12.5)
            }
            CapsLabel { visible: pb.isDefault; text: qsTr("par défaut"); font.pixelSize: Theme.fs(10) }
        }
    }

    // ---- Identite sur le reseau ------------------------------------------------
    SettingGroup {
        first: true
        title: qsTr("Identité sur le réseau")
        scopeIcon: Icons.share
        scopeText: qsTr("Vu par <b>tout le réseau</b>")

        SettingRow {
            label: qsTr("Nom du poste")
            help: qsTr("Le nom sous lequel les autres vous voient dans Postes, Appels, Transferts et Dossiers partagés.")
            edited: root.editingName
            FieldBox {
                id: nameField
                text: root.draftName
                placeholderText: qsTr("Nom Windows de la machine")
                accessibleName: qsTr("Nom du poste")
                onEdited: { root.draftName = nameField.text; root.savedKey = "" }
                onAccepted: if (root.editingName) root.saveName()
                onEscaped: root.cancelName()
            }
            Flow {
                visible: root.editingName
                Layout.fillWidth: true
                spacing: 8
                AppButton { variant: "ink"; size: "small"; iconPath: Icons.check; text: qsTr("Enregistrer"); onClicked: root.saveName() }
                AppButton { variant: "ghost"; size: "small"; text: qsTr("Annuler"); onClicked: root.cancelName() }
                Text {
                    width: Math.min(implicitWidth, parent.width)
                    height: 30
                    verticalAlignment: Text.AlignVCenter
                    wrapMode: Text.WordWrap
                    text: qsTr("Les autres postes verront ce nom à la prochaine annonce, en quelques secondes.")
                    color: Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12)
                }
            }
            SavedNote {
                visible: !root.editingName && root.savedKey === "name"
                text: root.savedName.length ? qsTr("Enregistré · les autres postes voient maintenant « %1 »").arg(root.savedName)
                                            : qsTr("Enregistré · les autres postes voient le nom Windows de la machine")
            }
            Text {
                visible: !root.editingName && root.savedKey !== "name"
                Layout.fillWidth: true
                text: qsTr("Laissé vide, le nom Windows de la machine est utilisé.")
                wrapMode: Text.WordWrap
                color: Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12)
            }
        }
    }

    // ---- Dossiers ------------------------------------------------------------------
    SettingGroup {
        title: qsTr("Dossiers")
        scopeIcon: Icons.monitor
        scopeText: qsTr("<b>Ce poste</b> · immédiat")

        SettingRow {
            label: qsTr("Fichiers reçus")
            help: qsTr("Les fichiers qu'on vous envoie arrivent ici, rangés dans un sous-dossier par correspondant. Appliqué aux prochains transferts.")
            PathBox { path: root.downloadPath.length ? root.downloadPath : root.defaultDownload; isDefault: root.downloadPath.length === 0 }
            Flow {
                Layout.fillWidth: true
                spacing: 8
                AppButton { variant: "line"; size: "small"; iconPath: Icons.folderOpen; text: qsTr("Changer…"); onClicked: downloadDialog.open() }
                AppButton {
                    variant: "ghost"; size: "small"; iconPath: Icons.external; text: qsTr("Ouvrir")
                    onClicked: Qt.openUrlExternally("file:///" + (root.downloadPath.length ? root.downloadPath : root.defaultDownload))
                }
                AppButton {
                    visible: root.downloadPath.length > 0
                    variant: "ghost"; size: "small"; text: qsTr("Revenir au dossier par défaut")
                    onClicked: { root.settings.defaultDownloadPath = ""; root.persist("dl") }
                }
                SavedNote { visible: root.savedKey === "dl"; height: 30 }
            }
        }
        SettingRow {
            label: qsTr("Dossiers partagés")
            help: qsTr("Emplacement proposé quand vous créez un dossier partagé. Vous pourrez en choisir un autre à chaque fois.")
            PathBox { visible: root.sharePath.length > 0; path: root.sharePath }
            Text {
                visible: root.sharePath.length === 0
                Layout.fillWidth: true
                text: qsTr("Aucun : vous choisissez l'emplacement à chaque création.")
                wrapMode: Text.WordWrap
                color: Theme.ink2; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13)
            }
            Flow {
                Layout.fillWidth: true
                spacing: 8
                AppButton { variant: "line"; size: "small"; iconPath: Icons.folderOpen; text: root.sharePath.length ? qsTr("Changer…") : qsTr("Choisir…"); onClicked: shareDialog.open() }
                SavedNote { visible: root.savedKey === "share"; height: 30 }
            }
        }
    }

    FolderDialog {
        id: downloadDialog
        title: qsTr("Dossier des fichiers reçus")
        currentFolder: "file:///" + (root.downloadPath.length ? root.downloadPath : root.defaultDownload)
        onAccepted: { root.settings.defaultDownloadPath = root.localPath(selectedFolder); root.persist("dl") }
    }
    FolderDialog {
        id: shareDialog
        title: qsTr("Emplacement proposé pour les dossiers partagés")
        currentFolder: root.sharePath.length ? "file:///" + root.sharePath : StandardPaths.writableLocation(StandardPaths.DocumentsLocation)
        onAccepted: { root.settings.defaultSharedFolderPath = root.localPath(selectedFolder); root.persist("share") }
    }
}
