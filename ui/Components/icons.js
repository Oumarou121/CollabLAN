.pragma library

/*
 * icons.js - chemins SVG (grille 24 x 24, style Lucide, trait) des icones
 * filaires utilisees avec Components/LineIcon.qml, comme dans la maquette
 * V2.x. Un seul endroit pour les definir : les vues declarent
 * `LineIcon { path: Icons.send }`.
 *
 * Usage : import "../Components/icons.js" as Icons
 */

var search = "M11 19a8 8 0 1 0 0-16 8 8 0 0 0 0 16z M21 21l-4.35-4.35"
var close = "M18 6L6 18 M6 6l12 12"
var plus = "M12 5v14 M5 12h14"
var check = "M20 6L9 17l-5-5"
var chevronRight = "M9 18l6-6-6-6"
var chevronLeft = "M15 18l-6-6 6-6"
var arrowUpRight = "M7 17L17 7 M7 7h10v10"
var arrowDownLeft = "M17 7L7 17 M17 17H7V7"
var upload = "M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4 M17 8l-5-5-5 5 M12 3v12"
var send = "M22 2L11 13 M22 2l-7 20-4-9-9-4 20-7z"
var refresh = "M21 12a9 9 0 1 1-9-9c2.52 0 4.93 1 6.74 2.74L21 8 M21 3v5h-5"
var grid = "M3 3h7v7H3z M14 3h7v7h-7z M14 14h7v7h-7z M3 14h7v7H3z"
var list = "M8 6h13 M8 12h13 M8 18h13 M3 6h0.01 M3 12h0.01 M3 18h0.01"
var folder = "M4 20h16a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.93a2 2 0 0 1-1.66-.9l-.82-1.2A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2z"
var folderOpen = "M6 14l1.5-2.9A2 2 0 0 1 9.24 10H20a2 2 0 0 1 1.94 2.5l-1.54 6a2 2 0 0 1-1.95 1.5H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h3.9a2 2 0 0 1 1.69.9l.81 1.2a2 2 0 0 0 1.67.9H18a2 2 0 0 1 2 2v2"
var file = "M14.5 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7.5L14.5 2z M14 2v4a2 2 0 0 0 2 2h4"
var fileText = "M14.5 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7.5L14.5 2z M14 2v4a2 2 0 0 0 2 2h4 M10 9H8 M16 13H8 M16 17H8"
var image = "M5 3h14a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2z M11 9a2 2 0 1 1-4 0 2 2 0 0 1 4 0z M21 15l-3.086-3.086a2 2 0 0 0-2.828 0L6 21"
var archive = "M3 3h18a1 1 0 0 1 1 1v3a1 1 0 0 1-1 1H3a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1z M4 8v11a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8 M10 12h4"
var media = "M12 22a10 10 0 1 0 0-20 10 10 0 0 0 0 20z M10 8l6 4-6 4V8z"
var clock = "M12 22a10 10 0 1 0 0-20 10 10 0 0 0 0 20z M12 6v6l4 2"
var alertCircle = "M12 22a10 10 0 1 0 0-20 10 10 0 0 0 0 20z M12 8v4 M12 16h0.01"
var alertTriangle = "M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z M12 9v4 M12 17h0.01"
var ban = "M12 22a10 10 0 1 0 0-20 10 10 0 0 0 0 20z M4.93 4.93l14.14 14.14"
var monitor = "M4 3h16a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2z M8 21h8 M12 17v4"

// Ajoutes pour unifier ActionRequiredPanel / TransferRow / ActivityRow
// (Dashboard) sur le meme systeme d'icones filaires que le reste de
// l'app, a la place des glyphes Font Awesome utilises auparavant.
var checkCircle = "M22 11.08V12a10 10 0 1 1-5.93-9.14 M22 4L12 14.01l-3-3"
var bell = "M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9 M10.3 21a1.94 1.94 0 0 0 3.4 0"
var messageCircle = "M21 11.5a8.38 8.38 0 0 1-.9 3.8 8.5 8.5 0 0 1-7.6 4.7 8.38 8.38 0 0 1-3.8-.9L3 21l1.9-5.7a8.38 8.38 0 0 1-.9-3.8 8.5 8.5 0 0 1 4.7-7.6 8.38 8.38 0 0 1 3.8-.9h.5a8.48 8.48 0 0 1 8 8v.5z"
var link = "M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71 M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"
var phone = "M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6 19.79 19.79 0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72c.127.96.361 1.903.7 2.81a2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45c.907.339 1.85.573 2.81.7A2 2 0 0 1 22 16.92z"
// Meme trace que l'icone "transfer" deja utilisee dans EmptyState.qml
// (etat vide validee sur la maquette V2.2) : deux fleches opposees.
var exchange = "M7 4 3 8l4 4 M3 8h14 M17 20l4-4-4-4 M21 16H7"

// ---- Ligne claire (navigation et accueil) ----------------------------------
var overview = "M5 3.5h4a1.5 1.5 0 0 1 1.5 1.5v5A1.5 1.5 0 0 1 9 11.5H5A1.5 1.5 0 0 1 3.5 10V5A1.5 1.5 0 0 1 5 3.5z M15 3.5h4a1.5 1.5 0 0 1 1.5 1.5v2A1.5 1.5 0 0 1 19 8.5h-4A1.5 1.5 0 0 1 13.5 7V5A1.5 1.5 0 0 1 15 3.5z M15 11.5h4a1.5 1.5 0 0 1 1.5 1.5v6a1.5 1.5 0 0 1-1.5 1.5h-4a1.5 1.5 0 0 1-1.5-1.5v-6a1.5 1.5 0 0 1 1.5-1.5z M5 14.5h4a1.5 1.5 0 0 1 1.5 1.5v3A1.5 1.5 0 0 1 9 20.5H5A1.5 1.5 0 0 1 3.5 19v-3A1.5 1.5 0 0 1 5 14.5z"
var shield = "M12 3.2L4.5 6v5.6c0 4.6 3.1 8 7.5 9.2 4.4-1.2 7.5-4.6 7.5-9.2V6z M9 12l2.2 2.2L15.5 10"
var sliders = "M4 6.5h9 M17 6.5h3 M4 12h3 M11 12h9 M4 17.5h11 M19 17.5h1 M17 6.5a2 2 0 1 1-4 0 2 2 0 0 1 4 0z M11 12a2 2 0 1 1-4 0 2 2 0 0 1 4 0z M19 17.5a2 2 0 1 1-4 0 2 2 0 0 1 4 0z"
var info = "M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0z M12 16.5v-5 M12 8h0.01"
var logout = "M9.5 20.5h-4a2 2 0 0 1-2-2v-13a2 2 0 0 1 2-2h4 M15.5 16.5L20 12l-4.5-4.5 M20 12H9"
var menu = "M4 6.5h16 M4 12h16 M4 17.5h16"
var chevronDown = "M6 9.5l6 6 6-6"
var arrowRight = "M4.5 12h15 M13.5 6l6 6-6 6"
var server = "M5.5 3.5h13a2 2 0 0 1 2 2v3a2 2 0 0 1-2 2h-13a2 2 0 0 1-2-2v-3a2 2 0 0 1 2-2z M5.5 13.5h13a2 2 0 0 1 2 2v3a2 2 0 0 1-2 2h-13a2 2 0 0 1-2-2v-3a2 2 0 0 1 2-2z M7.5 7h0.01 M7.5 17h0.01"
var journal = "M8.5 6.5h12 M8.5 12h12 M8.5 17.5h12 M4 6.5h0.01 M4 12h0.01 M4 17.5h0.01"
