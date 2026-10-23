import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Themes
import "../Components"

/*
 * InterventionList - « A traiter » (administrateur) / « A surveiller »
 * (utilisateur) de Ligne claire, en trois groupes :
 *   Decisions     autorisation demandee (◆ ambre), connexion refusee (× rouge)
 *   Incidents     transfert en echec (×), conflit de dossier partage (◆)
 *   A surveiller  postes autorises hors ligne, regroupes en une ligne (○)
 * La premiere autorisation, seule decision vraiment urgente, porte un
 * bandeau « A decider ». Aucune ligne n'est inventee : etat vide explicite.
 *
 * items : HomeView.interventions ({ kind, title, meta, action, tip, peerId... })
 */
ColumnLayout {
    id: root

    property var items: []
    property bool isAdmin: false

    signal activated(var item)

    readonly property var groups: {
        const decisions = root.items.filter(function(i) { return i.kind === "authorization" || i.kind === "denied" })
        const incidents = root.items.filter(function(i) { return i.kind === "transfer" || i.kind === "conflict" })
        const offline = root.items.filter(function(i) { return i.kind === "offline" })
        const out = []
        let urgentDone = false
        if (decisions.length)
            out.push({ title: qsTr("Décisions"), rows: decisions.map(function(i) {
                const urgent = !urgentDone && i.kind === "authorization"
                if (urgent) urgentDone = true
                return { item: i, glyph: i.kind === "authorization" ? "decision" : "error", title: i.title,
                         meta: i.meta, action: i.action, urgent: urgent }
            }) })
        if (incidents.length)
            out.push({ title: qsTr("Incidents"), rows: incidents.map(function(i) {
                return { item: i, glyph: i.kind === "conflict" ? "decision" : "error", title: i.title,
                         meta: i.meta, action: i.action, urgent: false }
            }) })
        if (offline.length)
            out.push({ title: qsTr("À surveiller"), rows: [{
                item: offline[0], glyph: "watch",
                title: offline.length > 1 ? qsTr("%1 postes autorisés hors ligne").arg(offline.length)
                                          : qsTr("%1 hors ligne").arg(offline[0].title),
                meta: offline.map(function(o) { return o.title }).join(", "),
                action: qsTr("Voir"), urgent: false }] })
        return out
    }
    readonly property int rowCount: root.groups.reduce(function(a, g) { return a + g.rows.length }, 0)
    readonly property bool hasDecision: root.items.some(function(i) { return i.kind === "authorization" || i.kind === "conflict" })

    spacing: 0

    SectionHeader {
        Layout.fillWidth: true
        title: root.isAdmin ? qsTr("À traiter") : qsTr("À surveiller")
        count: root.rowCount > 0 ? root.rowCount : -1
        attention: root.hasDecision
    }

    // ---- Etat vide -----------------------------------------------------------
    Text {
        visible: root.rowCount === 0
        Layout.fillWidth: true
        Layout.topMargin: 12
        text: qsTr("Rien à signaler.")
        color: Theme.ink
        font.family: Theme.fontFamilySerif
        font.pixelSize: Theme.fs(18)
    }
    Text {
        visible: root.rowCount === 0
        Layout.fillWidth: true
        Layout.topMargin: 3
        text: root.isAdmin
              ? qsTr("Demandes d'autorisation, refus de connexion et échecs de transfert apparaîtront ici dès qu'ils se produisent.")
              : qsTr("Les transferts en échec et les conflits de dossiers partagés apparaîtront ici.")
        color: Theme.ink3
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fs(12.5)
        wrapMode: Text.WordWrap
    }
    // Sans element extensible, la colonne (etiree a la hauteur du reseau sur
    // l'accueil) repartissait la place libre entre le titre et les deux
    // textes : « Rien à signaler. » flottait au milieu, la consigne en bas.
    Item {
        visible: root.rowCount === 0
        Layout.fillHeight: true
    }

    // ---- Groupes -------------------------------------------------------------
    Flickable {
        id: flick
        visible: root.rowCount > 0
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: 0
        Layout.preferredHeight: groupsColumn.implicitHeight
        contentWidth: width
        contentHeight: groupsColumn.implicitHeight
        clip: true
        interactive: contentHeight > height
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        ColumnLayout {
            id: groupsColumn
            width: flick.width
            spacing: 0

            Repeater {
                model: root.groups

                delegate: ColumnLayout {
                    id: grp
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    spacing: 0

                    Rectangle {
                        visible: grp.index > 0
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        Layout.preferredHeight: 1
                        color: Theme.line
                    }
                    CapsLabel {
                        Layout.fillWidth: true
                        Layout.topMargin: 10
                        Layout.bottomMargin: 2
                        text: grp.modelData.title
                    }

                    Repeater {
                        model: grp.modelData.rows

                        delegate: Rectangle {
                            id: line
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.topMargin: modelData.urgent ? 4 : 0
                            Layout.bottomMargin: modelData.urgent ? 4 : 0
                            implicitHeight: lineRow.implicitHeight + (modelData.urgent ? 18 : 14)
                            color: modelData.urgent ? Theme.warningSoft : "transparent"
                            radius: modelData.urgent ? Theme.radiusSheet : 0

                            Rectangle {
                                visible: line.modelData.urgent
                                width: 2
                                height: parent.height
                                color: Theme.warningColor
                            }

                            RowLayout {
                                id: lineRow
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: line.modelData.urgent ? 10 : 0
                                anchors.rightMargin: line.modelData.urgent ? 8 : 0
                                spacing: 10

                                StateGlyph {
                                    Layout.alignment: Qt.AlignTop
                                    Layout.topMargin: 3
                                    kind: line.modelData.glyph
                                    size: 12
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8
                                        Text {
                                            Layout.fillWidth: !line.modelData.urgent
                                            Layout.maximumWidth: lineRow.width - 120
                                            text: line.modelData.title
                                            color: Theme.ink
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fs(13.5)
                                            font.weight: Theme.weightSemibold
                                            elide: Text.ElideRight
                                        }
                                        CapsLabel {
                                            visible: line.modelData.urgent
                                            Layout.fillWidth: true
                                            text: qsTr("À décider")
                                            color: Theme.warningInk
                                            font.pixelSize: Theme.fs(9.5)
                                            font.weight: Theme.weightBold
                                        }
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: line.modelData.meta
                                        color: Theme.ink3
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fs(12)
                                        elide: Text.ElideRight
                                    }
                                }
                                TextLink {
                                    text: line.modelData.action
                                    tooltip: line.modelData.item.tip || ""
                                    onClicked: root.activated(line.modelData.item)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
