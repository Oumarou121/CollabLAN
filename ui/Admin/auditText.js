.pragma library

/*
 * auditText.js - lecture en clair d'une entree du journal d'audit.
 *
 * AuditManager enregistre des textes bruts sans accents (« Appel avec
 * 192.168.1.21 : Manque (Entrant) », « Transfert 'x.zip' (641728512 octets) :
 * Termine »...). L'ecran les reformule pour un humain : adresse -> poste ->
 * personne, octets -> Mo, statut accentue, n° de conversation -> nom. Rien
 * n'est invente : un texte non reconnu est rendu tel quel (accents remis), et
 * le texte brut reste affiche dans la fiche.
 *
 * Usage : import "auditText.js" as AuditText
 *         AuditText.read(entry, ctx)  ctx = { who(ip), conv(id) }
 */

var STATUS = {
    "En cours": "en cours", "in_progress": "en cours",
    "En attente": "en attente", "pending": "en attente",
    "Termine": "terminé", "completed": "terminé",
    "Manque": "manqué", "missed": "manqué",
    "Refuse": "refusé", "rejected": "refusé",
    "Annule": "annulé", "cancelled": "annulé",
    "Echoue": "échoué", "failed": "échoué"
}
var BAD = { "échoué": true, "manqué": true, "refusé": true }

// Mots enregistres sans accents (AuditManager, Application).
var ACCENTS = [
    ["refusee", "refusée"], ["Refusee", "Refusée"], ["refuse)", "refusé)"], ["envoye", "envoyé"], ["recu", "reçu"],
    ["etablie", "établie"], ["emetteur", "émetteur"], ["deconnecte", "déconnecté"], ["delai", "délai"],
    ["depasse", "dépassé"], ["authentifie", "authentifié"], ["Echec", "Échec"], ["Termine", "Terminé"],
    ["Echoue", "Échoué"], ["Manque", "Manqué"], ["Annule", "Annulé"], ["Refuse ", "Refusé "]
]

function esc(t) {
    return String(t === undefined || t === null ? "" : t).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
}

function accent(t) {
    var s = String(t || "")
    for (var i = 0; i < ACCENTS.length; i++)
        s = s.split(ACCENTS[i][0]).join(ACCENTS[i][1])
    return s
}

function capital(t) { return t.length ? t.charAt(0).toUpperCase() + t.slice(1) : t }

function isAddress(t) { return /^\d{1,3}(\.\d{1,3}){3}$/.test(t || "") || /^[0-9a-fA-F:]+:[0-9a-fA-F:]*$/.test(t || "") }

// 641728512 -> « 612 Mo »
function size(bytes) {
    var b = Number(bytes)
    if (!(b > 0)) return ""
    var units = ["o", "Ko", "Mo", "Go", "To"]
    var v = b, i = 0
    while (v >= 1024 && i < units.length - 1) { v /= 1024; i++ }
    var txt = i === 0 ? v.toFixed(0) : (v < 10 ? v.toFixed(1) : v.toFixed(0))
    return txt.replace(".", ",") + " " + units[i]
}

function statusOf(word) {
    var w = (word || "").trim()
    return STATUS[w] !== undefined ? STATUS[w] : w.toLowerCase()
}

// Mot de statut colore (StyledText) : rouge si negatif, vert si termine.
function statusHtml(st, label, danger, ok) {
    if (BAD[st]) return "<font color=\"" + danger + "\"><b>" + esc(label) + "</b></font>"
    if (st === "terminé") return "<font color=\"" + ok + "\"><b>" + esc(label) + "</b></font>"
    return esc(label)
}

/*
 * read(entry, ctx) -> { line, sub, bad, ip, conv, file }
 *   entry : { eventType, description, actorLabel, userId }
 *   ctx   : { who(ip) -> libelle, conv(id) -> nom, danger, ok (couleurs) }
 * line et sub sont du texte riche (StyledText) deja echappe.
 */
function read(entry, ctx) {
    var d = String(entry.description || "")
    var who = ctx && ctx.who ? ctx.who : function(ip) { return ip }
    var conv = ctx && ctx.conv ? ctx.conv : function() { return "" }
    var danger = ctx && ctx.danger ? ctx.danger : "#B42318"
    var ok = ctx && ctx.ok ? ctx.ok : "#1F7A45"
    var m

    if ((m = d.match(/^Connexion (etablie|perdue) avec (\S+?)(?: \((.*)\))?$/))) {
        var joined = m[1] === "etablie"
        return { line: qsTr("<b>%1</b> %2").arg(esc(who(m[2]))).arg(joined ? qsTr("a rejoint le réseau") : qsTr("a quitté le réseau")),
                 sub: esc(m[2] + (m[3] ? " · " + accent(m[3]) : "")), bad: !joined, ip: m[2] }
    }
    if ((m = d.match(/^Utilisateur authentifie : (.*)$/)))
        return { line: qsTr("<b>%1</b> s'est connecté à son compte").arg(esc(m[1])), sub: qsTr("Ouverture de session sur ce poste") }

    if ((m = d.match(/^Message (envoye|recu) dans la conversation #(\d+)$/))) {
        var name = conv(Number(m[2]))
        return { line: (m[1] === "envoye" ? qsTr("Message envoyé") : qsTr("Message reçu")) + " · "
                       + (name ? qsTr("discussion <b>%1</b>").arg(esc(name)) : qsTr("conversation <b>#%1</b>").arg(m[2])),
                 sub: qsTr("Le contenu des messages n'est pas journalisé"), conv: Number(m[2]) }
    }
    if ((m = d.match(/^Transfert '(.*)' \((\d+) octets\) : ([^(]+?)(?: \((.*)\))?$/))) {
        var st = statusOf(m[3])
        var parts = [size(m[2]), statusHtml(st, st, danger, ok)]
        if (m[4]) parts.push(esc(accent(m[4])))
        return { line: "<b>" + esc(m[1]) + "</b>", sub: parts.filter(function(p) { return p.length > 0 }).join(" · "), bad: !!BAD[st], file: m[1] }
    }
    if ((m = d.match(/^Appel avec (\S+) : (.*)$/))) {
        var rest = m[2]
        var incoming = /Entrant|incoming/.test(rest)
        var outgoing = /Sortant|outgoing/.test(rest)
        var cst = ""
        for (var k in STATUS) if (rest.indexOf(k) !== -1) { cst = STATUS[k]; break }
        var who1 = esc(who(m[1]))
        var line = incoming ? qsTr("Appel reçu de <b>%1</b>").arg(who1)
                 : outgoing ? qsTr("Appel passé à <b>%1</b>").arg(who1)
                 : qsTr("Appel avec <b>%1</b>").arg(who1)
        return { line: line, sub: (cst ? statusHtml(cst, capital(cst), danger, ok) + " · " : "") + esc(m[1]),
                 bad: !!BAD[cst], ip: m[1] }
    }
    if ((m = d.match(/^Tentative refusee : (.*?)(?: \(depuis (\S+)\))?$/))) {
        var why = accent(m[1]).replace(/^Machine \S+ non autorisée : /, "").replace(/ \(refusée?\)$/, "")
        if (m[2])
            return { line: qsTr("Connexion refusée depuis <b>%1</b>").arg(esc(who(m[2]))), sub: esc(capital(why)), bad: true, ip: m[2] }
        return { line: qsTr("Action refusée : <b>%1</b>").arg(esc(why)),
                 sub: entry.actorLabel && isAddress(entry.actorLabel) ? qsTr("depuis %1").arg(esc(who(entry.actorLabel))) : qsTr("Bloquée sur ce poste"),
                 bad: true, ip: entry.actorLabel && isAddress(entry.actorLabel) ? entry.actorLabel : "" }
    }
    if ((m = d.match(/^Echec d'authentification : (.*)$/)))
        return { line: qsTr("Échec de connexion à un compte"), sub: esc(capital(accent(m[1]))), bad: true }

    return { line: esc(accent(d)), sub: "", bad: entry.eventType === "access_denied",
             ip: isAddress(entry.actorLabel) ? entry.actorLabel : "" }
}
