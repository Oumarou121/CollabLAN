.pragma library

/*
 * hemicycleLayout.js - placement de l'hemicycle des postes (Ligne claire).
 *
 * Fonctions pures, reprises de la maquette validee
 * (design/dashboard-exploration-2026/concept-a-refine/app.js) :
 *
 *  - computeSeats() : sieges groupes par etat, en 1 a 4 rangees selon le
 *    nombre de postes ; taille des sieges deduite de l'espacement reel.
 *    Ne depend QUE de la liste {id, status} et de la taille : le modele du
 *    Repeater des sieges ne change donc pas a chaque tick de transfert.
 *  - computeLabels() : noms en marge, des deux cotes, a la hauteur de leur
 *    siege, ecartes sans chevauchement. Au-dela de MAX_ALL_LABELS postes,
 *    seuls la selection, l'activite et le serveur sont nommes.
 *
 * Disposition indicative (regroupement par etat), pas une topologie.
 */

var ORDER = ["calling", "transferring", "online", "busy", "away", "offline"]
var MAX_ALL_LABELS = 14

function clamp(v, a, b) { return Math.max(a, Math.min(b, v)) }

function statusRank(s) {
    var i = ORDER.indexOf(s)
    return i < 0 ? 2 : i
}

// Ordre d'affichage : par etat (activite d'abord), puis par nom.
function sortPeers(peers) {
    return peers.slice().sort(function(a, b) {
        return (statusRank(a.status) - statusRank(b.status))
               || String(a.name || "").localeCompare(String(b.name || ""))
    })
}

function seatPositions(n, cx, cy, rOut, rIn, rows, pad) {
    var radii = []
    var k
    for (k = 0; k < rows; k++)
        radii.push(rows === 1 ? rOut : rIn + (rOut - rIn) * k / (rows - 1))
    var sum = 0
    for (k = 0; k < rows; k++) sum += radii[k]
    var counts = []
    var total = 0
    for (k = 0; k < rows; k++) {
        counts.push(Math.max(1, Math.round(n * radii[k] / sum)))
        total += counts[k]
    }
    var diff = n - total
    k = rows - 1
    var guard = 0
    while (diff !== 0 && guard++ < 1000) {
        if (diff > 0) { counts[k]++; diff-- }
        else if (counts[k] > 1) { counts[k]--; diff++ }
        k = (k - 1 + rows) % rows
    }
    var pos = []
    for (k = 0; k < rows; k++) {
        var c = counts[k], r = radii[k]
        for (var j = 0; j < c; j++) {
            var a = c === 1 ? Math.PI / 2 : Math.PI - pad - j * (Math.PI - 2 * pad) / (c - 1)
            pos.push({ a: a, r: r, x: cx + r * Math.cos(a), y: cy - r * Math.sin(a) })
        }
    }
    pos.sort(function(p, q) { return (q.a - p.a) || (p.r - q.r) })
    return { pos: pos, counts: counts }
}

// peers : [{ id, status }] (deja tries par sortPeers). Renvoie la geometrie.
function computeSeats(peers, width, height) {
    var W = width, H = height
    var n = peers.length
    var floorY = H - 48
    var labelW = clamp(W * 0.17, 116, 196)
    var out = { cx: W / 2, cy: floorY, rOut: 0, rIn: 0, rows: 0, s: 10, rT: 26,
                labelW: labelW, floorY: floorY, seats: [], allLabels: n <= MAX_ALL_LABELS }
    if (n === 0 || W <= 0 || H <= 0)
        return out
    var rows = n <= 7 ? 1 : n <= 16 ? 2 : n <= 32 ? 3 : 4
    var margin = labelW + 44
    var pad = rows === 1 ? (n <= 2 ? 0.78 : n <= 4 ? 0.44 : 0.24) : 0.17
    var rOut = Math.max(90, Math.min(W / 2 - margin, floorY - 22))
    var inRatio = rows === 1 ? 1 : rows === 2 ? 0.66 : rows === 3 ? 0.52 : 0.46
    var est = seatPositions(n, 0, 0, rOut, rOut * inRatio, rows, pad)
    var outerCount = est.counts[est.counts.length - 1]
    var spacing = rOut * (Math.PI - 2 * pad) / Math.max(1, outerCount - 1)
    var s = clamp(spacing * 0.33, 8, 17)
    if (rows > 1)
        s = Math.min(s, (rOut - rOut * inRatio) / (rows - 1) * 0.36)
    rOut -= s + 4
    var rIn = rOut * inRatio
    var cx = W / 2, cy = floorY
    var placed = seatPositions(n, cx, cy, rOut, rIn, rows, pad).pos
    for (var i = 0; i < n; i++) {
        var q = placed[i]
        out.seats.push({ id: peers[i].id, index: i, x: q.x, y: q.y, a: q.a, r: q.r })
    }
    out.cx = cx
    out.rOut = rOut
    out.rIn = rIn
    out.rows = rows
    out.s = s
    out.rT = Math.max(20, Math.min(30, rIn - s - 22))
    return out
}

// geo : resultat de computeSeats ; info : { id -> { visible, notable, selected, ring } }
// gap : ecart vertical minimal entre deux etiquettes (deux lignes de texte).
function computeLabels(geo, info, gap) {
    var labels = []
    if (!geo.seats.length)
        return labels
    var cand = []
    var i
    for (i = 0; i < geo.seats.length; i++) {
        var st = geo.seats[i]
        var inf = info[st.id] || {}
        if (!inf.visible) continue
        if (!geo.allLabels && !inf.notable && !inf.selected) continue
        cand.push({ seat: st, selected: !!inf.selected, ring: !!inf.ring })
    }
    if (!geo.allLabels) {
        cand.sort(function(a, b) { return (b.selected ? 1 : 0) - (a.selected ? 1 : 0) })
        cand = cand.slice(0, 10)
    }
    var sides = { L: [], R: [] }
    for (i = 0; i < cand.length; i++) {
        var c = Math.cos(cand[i].seat.a)
        if (c < -1e-6 || (Math.abs(c) <= 1e-6 && sides.L.length <= sides.R.length))
            sides.L.push(cand[i])
        else
            sides.R.push(cand[i])
    }
    var yMin = 14, yMax = geo.floorY - 18
    var cx = geo.cx, rOut = geo.rOut, s = geo.s
    ;["L", "R"].forEach(function(side) {
        var list = sides[side]
        // Capacite du cote : au-dela, on garde la selection puis les premiers
        // postes nommes (les autres restent accessibles par survol/registre).
        var cap = Math.max(1, Math.floor((yMax - yMin) / (gap * 0.82)) + 1)
        if (list.length > cap) {
            list.sort(function(a, b) { return (b.selected ? 1 : 0) - (a.selected ? 1 : 0) })
            list = list.slice(0, cap)
        }
        list.sort(function(a, b) { return a.seat.y - b.seat.y })
        if (!list.length) return
        var G = gap
        if (list.length * G > yMax - yMin)
            G = Math.max(gap * 0.82, (yMax - yMin) / list.length)
        var ys = list.map(function(e) { return e.seat.y + 4 })
        var k
        for (k = 1; k < ys.length; k++) ys[k] = Math.max(ys[k], ys[k - 1] + G)
        if (ys[ys.length - 1] > yMax) {
            ys[ys.length - 1] = yMax
            for (k = ys.length - 2; k >= 0; k--) ys[k] = Math.min(ys[k], ys[k + 1] - G)
        }
        if (ys[0] < yMin) {
            var step = (yMax - yMin) / Math.max(1, ys.length - 1)
            for (k = 0; k < ys.length; k++) ys[k] = yMin + k * Math.min(G, step)
        }
        var left = side === "L"
        var xText = left ? cx - rOut - s - 30 : cx + rOut + s + 30
        for (k = 0; k < list.length; k++) {
            var seat = list[k].seat, yl = ys[k]
            // Trait de rappel droit, du bord du siege au debut du nom.
            var xe = left ? xText + 6 : xText - 6, ye = yl - 4
            var len = Math.sqrt((xe - seat.x) * (xe - seat.x) + (ye - seat.y) * (ye - seat.y)) || 1
            var r0 = list[k].ring ? s + 6 : s + 2
            labels.push({
                id: seat.id,
                side: side,
                x: xText,
                y: yl,
                selected: list[k].selected,
                x0: seat.x + (xe - seat.x) / len * r0,
                y0: seat.y + (ye - seat.y) / len * r0,
                x1: xe,
                y1: ye
            })
        }
    })
    return labels
}
