import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Shapes
import Themes
import "../Components"
import "../Components/icons.js" as Icons

/*
 * FolderComposer - volet « Partager un dossier » (Ligne claire), meme
 * facture que « Nouveau transfert » : trois etapes visibles d'un coup
 * (1 le dossier, 2 les membres et leur droit, 3 les exclusions), une phrase
 * qui resume, puis la confirmation. createFolder() ne fixe qu'un droit pour
 * tous les membres ; il se regle ensuite personne par personne.
 */
Rectangle {
    id: root

    property var users: []                 // [{ userId, username }]
    property string localPath: ""
    property bool done: false
    property string errorText: ""

    property string name: ""
    property bool nameEdited: false
    property var picked: []                // userIds
    property bool allowWrite: true
    property var patterns: []
    property string createdName: ""

    signal closeRequested()
    signal browseRequested()
    signal pathDropped(string path)
    signal errorDismissed()
    signal createRequested(string name, string path, var userIds, bool allowWrite, string excludes)

    readonly property bool canCreate: root.localPath.length > 0 && root.name.trim().length > 0

    function reset() {
        root.name = ""
        root.nameEdited = false
        root.picked = []
        root.allowWrite = true
        root.patterns = []
        root.createdName = ""
        nameField.text = ""
        patternField.text = ""
    }
    function baseName(path) {
        const s = String(path || "").replace(/[\\/]+$/, "")
        return s.substring(Math.max(s.lastIndexOf("/"), s.lastIndexOf("\\")) + 1)
    }
    function cleanUrl(url) {
        let path = decodeURIComponent(url.toString()).replace(/^file:\/\//, "")
        if (/^\/[A-Za-z]:/.test(path)) path = path.substring(1)
        return path
    }
    // Le nom affiche reprend celui du dossier tant qu'on ne l'a pas change.
    onLocalPathChanged: if (!root.nameEdited) { root.name = root.baseName(root.localPath); nameField.text = root.name }

    function isPicked(id) { return root.picked.indexOf(id) !== -1 }
    function toggle(id) {
        root.picked = root.isPicked(id) ? root.picked.filter(function(x) { return x !== id }) : root.picked.concat([id])
    }
    function addPattern(raw) {
        const v = (raw || "").trim()
        if (v.length > 0 && root.patterns.indexOf(v) === -1) root.patterns = root.patterns.concat([v])
    }
    function pickedNames() {
        return root.users.filter(function(u) { return root.isPicked(u.userId) }).map(function(u) { return u.username })
    }
    function esc(t) { return String(t).replace(/&/g, "&amp;").replace(/</g, "&lt;") }

    color: Theme.bg

    Rectangle { width: 1; height: parent.height; color: Theme.ruleInk; z: 2 }
    Rectangle {
        x: -28
        width: 28
        height: parent.height
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 1.0; color: Theme.shadowStrong }
        }
    }
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

    component StepHeader: RowLayout {
        id: sh
        property string number: "1"
        property string title: ""
        property string note: ""
        property bool done: false
        spacing: 12
        Text {
            Layout.preferredWidth: 18
            text: sh.done ? "✓" : sh.number
            color: sh.done ? Theme.successInk : Theme.ink3
            font.family: Theme.fontFamilySerif
            font.pixelSize: Theme.fs(22)
            font.weight: Theme.weightBold
        }
        Text {
            text: sh.title
            color: Theme.ink
            font.family: Theme.fontFamilySerif
            font.pixelSize: Theme.fs(16)
            font.weight: Theme.weightBold
        }
        Text {
            Layout.fillWidth: true
            visible: sh.note.length > 0
            text: sh.note
            color: Theme.ink3
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fs(12.5)
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 1
        spacing: 0

        // ---- En-tete ------------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 24
            Layout.rightMargin: 14
            Layout.topMargin: 18
            Layout.bottomMargin: 14
            spacing: 8
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3
                CapsLabel { text: qsTr("Nouveau dossier partagé") }
                Text {
                    text: root.done ? qsTr("Dossier partagé") : qsTr("Partager un dossier")
                    color: Theme.ink
                    font.family: Theme.fontFamilySerif
                    font.pixelSize: Theme.fs(24)
                    font.weight: Theme.weightBold
                }
                Text {
                    Layout.fillWidth: true
                    text: qsTr("Les fichiers restent sur ce poste ; les membres en reçoivent une copie tenue à jour.")
                    color: Theme.ink3
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(12.5)
                    wrapMode: Text.WordWrap
                }
            }
            AbstractButton {
                id: closeBtn
                Layout.alignment: Qt.AlignTop
                Layout.preferredWidth: 34
                Layout.preferredHeight: 34
                hoverEnabled: true
                Accessible.name: qsTr("Fermer")
                onClicked: root.closeRequested()
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                background: Rectangle { radius: 17; color: closeBtn.hovered ? Theme.selectWash : "transparent"; border.width: closeBtn.visualFocus ? 2 : 0; border.color: Theme.focusRing }
                contentItem: Item { LineIcon { anchors.centerIn: parent; path: Icons.close; size: 17; strokeWidth: 1.8; color: Theme.ink2 } }
            }
        }
        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.line }

        // ---- Erreur ---------------------------------------------------------
        Rectangle {
            visible: root.errorText.length > 0
            Layout.fillWidth: true
            Layout.leftMargin: 24
            Layout.rightMargin: 24
            Layout.topMargin: 12
            implicitHeight: errRow.implicitHeight + 16
            color: Theme.dangerSoft
            Rectangle { width: 2; height: parent.height; color: Theme.dangerColor }
            RowLayout {
                id: errRow
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 6
                Text { Layout.fillWidth: true; text: root.errorText; color: Theme.ink; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12.5); wrapMode: Text.WordWrap }
                TextLink { text: qsTr("OK"); arrow: false; onClicked: root.errorDismissed() }
            }
        }

        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: width
            contentHeight: body.implicitHeight + 20
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            ColumnLayout {
                id: body
                x: 24
                width: parent.width - 48
                spacing: 0

                // ================= CONFIRMATION =================
                ColumnLayout {
                    visible: root.done
                    Layout.fillWidth: true
                    Layout.topMargin: 18
                    spacing: 8
                    RowLayout {
                        spacing: 12
                        StateGlyph { kind: "ok"; size: 18 }
                        Text {
                            Layout.fillWidth: true
                            text: qsTr("« %1 » est partagé.").arg(root.createdName)
                            color: Theme.ink
                            font.family: Theme.fontFamilySerif
                            font.pixelSize: Theme.fs(16)
                            font.weight: Theme.weightBold
                            wrapMode: Text.WordWrap
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        Layout.leftMargin: 30
                        text: qsTr("Ses fichiers sont indexés sur ce poste, en arrière-plan : vous pouvez fermer ce volet. L'avancement reste visible dans la liste (« indexation… ») et les membres reçoivent le dossier ensuite.")
                        color: Theme.ink2
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(13)
                        wrapMode: Text.WordWrap
                    }
                }

                // ================= 1 Le dossier =================
                ColumnLayout {
                    visible: !root.done
                    Layout.fillWidth: true
                    Layout.topMargin: 16
                    spacing: 8
                    StepHeader { Layout.fillWidth: true; number: "1"; title: qsTr("Le dossier"); done: root.canCreate }
                    Item {
                        id: drop
                        Layout.fillWidth: true
                        Layout.leftMargin: 30
                        implicitHeight: dropRow.implicitHeight + 30
                        readonly property bool filled: root.localPath.length > 0
                        Rectangle { anchors.fill: parent; visible: drop.filled; radius: Theme.radiusSheet; color: Theme.surface0; border.width: 1; border.color: Theme.ruleInk }
                        Shape {
                            visible: !drop.filled
                            anchors.fill: parent
                            preferredRendererType: Shape.CurveRenderer
                            ShapePath {
                                fillColor: dropHover.hovered || dropArea.containsDrag ? Theme.selectWash : "transparent"
                                strokeColor: dropHover.hovered || dropArea.containsDrag ? Theme.ink3 : Theme.lineStrong
                                strokeWidth: 1.5
                                strokeStyle: ShapePath.DashLine
                                dashPattern: [3, 2.5]
                                startX: 1; startY: 1
                                PathLine { x: drop.width - 1; y: 1 }
                                PathLine { x: drop.width - 1; y: drop.height - 1 }
                                PathLine { x: 1; y: drop.height - 1 }
                                PathLine { x: 1; y: 1 }
                            }
                        }
                        HoverHandler { id: dropHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.browseRequested() }
                        DropArea {
                            id: dropArea
                            anchors.fill: parent
                            onDropped: function(d) { if (d.hasUrls && d.urls.length > 0) root.pathDropped(root.cleanUrl(d.urls[0])) }
                        }
                        RowLayout {
                            id: dropRow
                            anchors.verticalCenter: parent.verticalCenter
                            x: 16
                            width: parent.width - 32
                            spacing: 12
                            LineIcon { path: drop.filled ? Icons.folder : Icons.folderPlus; size: 24; strokeWidth: 1.4; color: Theme.ink2 }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                Text {
                                    Layout.fillWidth: true
                                    text: drop.filled ? root.localPath : qsTr("Déposez un dossier ici")
                                    color: Theme.ink
                                    font.family: drop.filled ? "Cascadia Mono" : Theme.fontFamilySerif
                                    font.pixelSize: drop.filled ? Theme.fs(12.5) : Theme.fs(15)
                                    font.weight: drop.filled ? Theme.weightMedium : Theme.weightBold
                                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: drop.filled ? qsTr("Son contenu sera indexé à la création.") : qsTr("ou cliquez pour le choisir")
                                    color: Theme.ink3
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(12)
                                }
                            }
                            AppButton { variant: drop.filled ? "line" : "ink"; size: "small"; text: drop.filled ? qsTr("Changer…") : qsTr("Choisir…"); onClicked: root.browseRequested() }
                        }
                    }
                    Text {
                        Layout.leftMargin: 30
                        Layout.topMargin: 6
                        text: qsTr("Nom affiché aux membres")
                        color: Theme.ink2
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(12)
                        font.weight: Theme.weightSemibold
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.leftMargin: 30
                        implicitHeight: 36
                        radius: Theme.radiusSheet
                        color: Theme.surface0
                        border.width: nameField.activeFocus ? 1.5 : 1
                        border.color: nameField.activeFocus ? Theme.ink : Theme.lineStrong
                        TextField {
                            id: nameField
                            anchors.fill: parent
                            leftPadding: 12
                            rightPadding: 12
                            placeholderText: qsTr("repris du nom du dossier")
                            placeholderTextColor: Theme.ink3
                            color: Theme.ink
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(13.5)
                            background: Item {}
                            selectByMouse: true
                            Accessible.name: qsTr("Nom affiché aux membres")
                            onTextEdited: { root.nameEdited = true; root.name = text }
                        }
                    }
                    Rectangle { Layout.fillWidth: true; Layout.topMargin: 10; Layout.preferredHeight: 1; color: Theme.line }
                }

                // ================= 2 Les membres =================
                ColumnLayout {
                    visible: !root.done
                    Layout.fillWidth: true
                    Layout.topMargin: 16
                    spacing: 6
                    StepHeader {
                        Layout.fillWidth: true
                        number: "2"
                        title: qsTr("Les membres")
                        done: root.picked.length > 0
                        note: root.picked.length === 0 ? qsTr("facultatif") : ""
                    }
                    Text {
                        visible: root.users.length === 0
                        Layout.fillWidth: true
                        Layout.leftMargin: 30
                        text: qsTr("Aucun autre utilisateur pour l'instant : le dossier sera indexé et vous pourrez ajouter des membres plus tard.")
                        color: Theme.ink3
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(12.5)
                        wrapMode: Text.WordWrap
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 30
                        spacing: 0
                        Repeater {
                            model: root.users
                            delegate: AbstractButton {
                                id: ub
                                required property var modelData
                                required property int index
                                readonly property bool on: root.isPicked(ub.modelData.userId)
                                Layout.fillWidth: true
                                implicitHeight: 38
                                hoverEnabled: true
                                focusPolicy: Qt.TabFocus
                                Accessible.role: Accessible.CheckBox
                                Accessible.checked: ub.on
                                Accessible.name: ub.modelData.username
                                onClicked: root.toggle(ub.modelData.userId)
                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                                background: Rectangle {
                                    color: ub.hovered ? Theme.selectWash : "transparent"
                                    border.width: ub.visualFocus ? 2 : 0
                                    border.color: Theme.focusRing
                                    Rectangle { visible: ub.index > 0; width: parent.width; height: 1; color: Theme.line }
                                }
                                contentItem: RowLayout {
                                    spacing: 12
                                    Rectangle {
                                        Layout.leftMargin: 6
                                        Layout.preferredWidth: 16
                                        Layout.preferredHeight: 16
                                        radius: 2
                                        color: ub.on ? Theme.ink : "transparent"
                                        border.width: ub.on ? 0 : 1.5
                                        border.color: Theme.lineStrong
                                        LineIcon { visible: ub.on; anchors.centerIn: parent; path: Icons.check; size: 12; strokeWidth: 2.6; color: Theme.inkOnInk }
                                    }
                                    Text { Layout.fillWidth: true; text: ub.modelData.username; color: Theme.ink; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13); font.weight: Theme.weightSemibold; elide: Text.ElideRight }
                                }
                            }
                        }
                    }
                    Text {
                        visible: root.users.length > 0
                        Layout.leftMargin: 30
                        Layout.topMargin: 10
                        text: qsTr("Ils pourront")
                        color: Theme.ink2
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(12)
                        font.weight: Theme.weightSemibold
                    }
                    Repeater {
                        model: root.users.length > 0 ? [
                            { w: true, t: qsTr("Modifier"), d: qsTr("leurs changements reviennent chez tous les membres") },
                            { w: false, t: qsTr("Consulter seulement"), d: qsTr("lecture seule ; vous restez seul à modifier") }
                        ] : []
                        delegate: AbstractButton {
                            id: rb
                            required property var modelData
                            readonly property bool on: rb.modelData.w === root.allowWrite
                            Layout.fillWidth: true
                            Layout.leftMargin: 30
                            implicitHeight: rbRow.implicitHeight + 14
                            hoverEnabled: true
                            focusPolicy: Qt.TabFocus
                            Accessible.role: Accessible.RadioButton
                            Accessible.checked: rb.on
                            Accessible.name: rb.modelData.t
                            onClicked: root.allowWrite = rb.modelData.w
                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                            background: Rectangle { radius: Theme.radiusSheet; color: rb.hovered ? Theme.selectWash : "transparent"; border.width: rb.visualFocus ? 2 : 0; border.color: Theme.focusRing }
                            contentItem: RowLayout {
                                id: rbRow
                                spacing: 10
                                Rectangle {
                                    Layout.leftMargin: 6
                                    Layout.alignment: Qt.AlignTop
                                    Layout.topMargin: 1
                                    Layout.preferredWidth: 16
                                    Layout.preferredHeight: 16
                                    radius: 8
                                    color: "transparent"
                                    border.width: rb.on ? 5 : 1.5
                                    border.color: rb.on ? Theme.ink : Theme.lineStrong
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1
                                    Text { text: rb.modelData.t; color: Theme.ink; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13); font.weight: Theme.weightSemibold }
                                    Text { Layout.fillWidth: true; text: rb.modelData.d; color: Theme.ink3; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12); wrapMode: Text.WordWrap }
                                }
                            }
                        }
                    }
                    Text {
                        visible: root.users.length > 0
                        Layout.fillWidth: true
                        Layout.leftMargin: 30
                        Layout.topMargin: 4
                        text: qsTr("Le droit pourra être réglé personne par personne ensuite, dans « Gérer les accès ».")
                        color: Theme.ink3
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(12)
                        wrapMode: Text.WordWrap
                    }
                    Rectangle { Layout.fillWidth: true; Layout.topMargin: 10; Layout.preferredHeight: 1; color: Theme.line }
                }

                // ================= 3 Exclusions =================
                ColumnLayout {
                    visible: !root.done
                    Layout.fillWidth: true
                    Layout.topMargin: 16
                    spacing: 8
                    StepHeader { Layout.fillWidth: true; number: "3"; title: qsTr("Exclusions"); note: qsTr("facultatif") }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.leftMargin: 30
                        implicitHeight: 36
                        radius: Theme.radiusSheet
                        color: Theme.surface0
                        border.width: patternField.activeFocus ? 1.5 : 1
                        border.color: patternField.activeFocus ? Theme.ink : Theme.lineStrong
                        TextField {
                            id: patternField
                            anchors.fill: parent
                            leftPadding: 12
                            rightPadding: 12
                            placeholderText: qsTr("*.log, node_modules, Brouillons/*")
                            placeholderTextColor: Theme.ink3
                            color: Theme.ink
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(13.5)
                            background: Item {}
                            selectByMouse: true
                            Accessible.name: qsTr("Motif d'exclusion")
                            onAccepted: { root.addPattern(text); text = "" }
                            onTextChanged: {
                                if (text.indexOf(",") === -1) return
                                const parts = text.split(",")
                                for (let i = 0; i < parts.length - 1; i++) root.addPattern(parts[i])
                                text = parts[parts.length - 1]
                            }
                        }
                    }
                    Flow {
                        visible: root.patterns.length > 0
                        Layout.fillWidth: true
                        Layout.leftMargin: 30
                        spacing: 6
                        Repeater {
                            model: root.patterns
                            delegate: Rectangle {
                                id: chip
                                required property var modelData
                                implicitWidth: chipRow.implicitWidth + 14
                                implicitHeight: 26
                                radius: 13
                                color: "transparent"
                                border.width: 1
                                border.color: Theme.lineStrong
                                Row {
                                    id: chipRow
                                    x: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 4
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: chip.modelData; color: Theme.ink; font.family: "Cascadia Mono"; font.pixelSize: Theme.fs(12) }
                                    AbstractButton {
                                        id: rmChip
                                        width: 18; height: 18
                                        hoverEnabled: true
                                        Accessible.name: qsTr("Retirer %1").arg(chip.modelData)
                                        onClicked: root.patterns = root.patterns.filter(function(p) { return p !== chip.modelData })
                                        background: Rectangle { radius: 9; color: rmChip.hovered ? Theme.selectWash : "transparent" }
                                        contentItem: Item { LineIcon { anchors.centerIn: parent; path: Icons.close; size: 11; strokeWidth: 2.2; color: Theme.ink3 } }
                                    }
                                }
                            }
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        Layout.leftMargin: 30
                        text: qsTr("S'ajoutent aux exclusions par défaut (dossiers système, fichiers temporaires). Local à ce poste.")
                        color: Theme.ink3
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(12)
                        wrapMode: Text.WordWrap
                    }
                }

                // Resume
                Text {
                    visible: !root.done && root.canCreate
                    Layout.fillWidth: true
                    Layout.topMargin: 16
                    textFormat: Text.StyledText
                    wrapMode: Text.WordWrap
                    color: Theme.ink2
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(14)
                    text: {
                        const names = root.pickedNames()
                        if (names.length === 0)
                            return qsTr("Partager <b>%1</b>, sans membre pour l'instant.").arg(root.esc(root.name.trim()))
                        const who = names.length === 1 ? "<b>" + root.esc(names[0]) + "</b>"
                                  : names.length === 2 ? "<b>" + root.esc(names[0]) + "</b> " + qsTr("et") + " <b>" + root.esc(names[1]) + "</b>"
                                  : qsTr("<b>%1 personnes</b>").arg(names.length)
                        return qsTr("Partager <b>%1</b> avec %2, qui pourront le <b>%3</b>.")
                               .arg(root.esc(root.name.trim())).arg(who).arg(root.allowWrite ? qsTr("modifier") : qsTr("consulter"))
                    }
                }
            }
        }

        // ---- Pied ---------------------------------------------------------
        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.ruleInk }
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 62
            Layout.leftMargin: 24
            Layout.rightMargin: 24
            spacing: 8
            Text {
                Layout.fillWidth: true
                visible: !root.done
                text: root.canCreate ? qsTr("Indexation à la création") : qsTr("Choisissez un dossier pour continuer")
                color: Theme.ink3
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(12)
                wrapMode: Text.WordWrap
            }
            Item { Layout.fillWidth: true; visible: root.done }
            AppButton { visible: !root.done; variant: "ghost"; text: qsTr("Annuler"); onClicked: root.closeRequested() }
            AppButton {
                visible: !root.done
                variant: "ink"
                iconPath: Icons.share
                text: qsTr("Partager le dossier")
                enabled: root.canCreate
                onClicked: {
                    if (patternField.text.trim().length > 0) { root.addPattern(patternField.text); patternField.text = "" }
                    root.createdName = root.name.trim()
                    root.createRequested(root.name.trim(), root.localPath, root.picked, root.allowWrite, root.patterns.join(","))
                }
            }
            AppButton { visible: root.done; variant: "line"; text: qsTr("Fermer"); onClicked: root.closeRequested() }
        }
    }
}
