.pragma library

/*
 * callPeople.js - qui est au bout du fil : relie une adresse du reseau local
 * a son poste (peersModel) puis a la personne (compte, via userUuid). Partage
 * par l'ecran Appels et l'appel en cours.
 *
 * Usage : import "callPeople.js" as People
 */

// Postes connus du reseau local : [{ id, machine, userUuid, status, address, signalingPort }]
function readPeers(peersModel) {
    var list = []
    if (!peersModel)
        return list
    var n = peersModel.rowCount ? peersModel.rowCount() : (peersModel.count || 0)
    for (var i = 0; i < n; i++) {
        var idx = peersModel.index(i, 0)
        list.push({ id: peersModel.data(idx, 257) || "", machine: peersModel.data(idx, 258) || "",
                    userUuid: peersModel.data(idx, 259) || "", status: peersModel.data(idx, 260) || "",
                    address: peersModel.data(idx, 261) || "", signalingPort: peersModel.data(idx, 264) || 0 })
    }
    return list
}

// Nom de compte par userUuid : { uuid: username }
function readUsers(messagingContext) {
    var map = {}
    if (!messagingContext || !messagingContext.availableUsers)
        return map
    var users = messagingContext.availableUsers() || []
    for (var i = 0; i < users.length; i++)
        if (users[i].userUuid)
            map[users[i].userUuid] = users[i].username
    return map
}

function peerAt(peers, address) {
    for (var i = 0; i < peers.length; i++)
        if (peers[i].address === address)
            return peers[i]
    return null
}

// Libelle d'une adresse : la personne, a defaut le poste, a defaut le nom
// enregistre dans l'historique, a defaut l'adresse.
function labelFor(peers, users, address, fallbackName) {
    var p = peerAt(peers, address)
    if (p && p.userUuid && users[p.userUuid])
        return users[p.userUuid]
    if (p && p.machine)
        return p.machine
    return fallbackName && fallbackName.length > 0 ? fallbackName : address
}

function personOf(peer, users) {
    return peer && peer.userUuid && users[peer.userUuid] ? users[peer.userUuid] : ""
}

function presenceKind(s) {
    s = (s || "").toLowerCase()
    return s === "away" || s === "busy" || s === "offline" ? s : (s.length ? "online" : "offline")
}

function presenceWord(s) {
    switch (presenceKind(s)) {
    case "away": return qsTr("Absent")
    case "busy": return qsTr("Occupé")
    case "offline": return qsTr("Hors ligne")
    }
    return qsTr("En ligne")
}

function initials(label) {
    var w = (label || "?").split(/[\s-]+/).filter(function(x) { return x.length > 0 })
    return ((w[0] || "?").charAt(0) + (w.length > 1 ? w[1].charAt(0) : "")).toUpperCase()
}

// « 4 min 12 », « 45 s »
function duration(seconds) {
    if (!seconds || seconds <= 0)
        return ""
    if (seconds < 60)
        return seconds + " s"
    var s = seconds % 60
    return Math.floor(seconds / 60) + " min " + (s < 10 ? "0" + s : s)
}

// « 04:12 »
function clock(seconds) {
    var m = Math.floor(seconds / 60), s = seconds % 60
    return (m < 10 ? "0" + m : m) + ":" + (s < 10 ? "0" + s : s)
}
