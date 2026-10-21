.pragma library

/*
 * transferFormat.js - utilitaires d'affichage partages par les composants
 * de l'ecran Transferts. Aucune logique metier.
 * Usage : import "transferFormat.js" as Fmt
 */

function fileNameFromPath(path) {
    if (!path)
        return ""
    var s = String(path)
    var cut = Math.max(s.lastIndexOf("/"), s.lastIndexOf("\\"))
    s = s.substring(cut + 1)
    try {
        s = decodeURIComponent(s)
    } catch (e) {
        // nom deja decode : on garde tel quel
    }
    return s
}

function formatBytes(bytes) {
    if (!bytes || bytes <= 0)
        return "0 o"
    var units = ["o", "Ko", "Mo", "Go", "To"]
    var value = bytes
    var unit = 0
    while (value >= 1024 && unit < units.length - 1) {
        value /= 1024
        unit++
    }
    if (unit === 0)
        return Math.round(value) + " o"
    var digits = value < 10 ? 1 : 0
    return value.toLocaleString(Qt.locale(), "f", digits) + " " + units[unit]
}

// Variante plus precise pour les progressions ("32,8 Mo sur 48,2 Mo") :
// une decimale jusqu'a 100.
function formatBytesPrecise(bytes) {
    if (!bytes || bytes <= 0)
        return "0 o"
    var units = ["o", "Ko", "Mo", "Go", "To"]
    var value = bytes
    var unit = 0
    while (value >= 1024 && unit < units.length - 1) {
        value /= 1024
        unit++
    }
    if (unit === 0)
        return Math.round(value) + " o"
    return value.toLocaleString(Qt.locale(), "f", value < 100 ? 1 : 0) + " " + units[unit]
}

// "doc" | "sheet" | "slides" | "image" | "archive" | "media" | "file"
function fileKind(fileName) {
    var parts = String(fileName || "").split(".")
    var ext = parts.length > 1 ? parts[parts.length - 1].toLowerCase() : ""
    switch (ext) {
    case "pdf": case "doc": case "docx": case "odt": case "rtf": case "txt": case "md":
        return "doc"
    case "xls": case "xlsx": case "ods": case "csv":
        return "sheet"
    case "ppt": case "pptx": case "odp":
        return "slides"
    case "jpg": case "jpeg": case "png": case "gif": case "bmp": case "webp": case "svg":
        return "image"
    case "zip": case "rar": case "7z": case "tar": case "gz":
        return "archive"
    case "mp4": case "mov": case "avi": case "mkv": case "webm":
    case "mp3": case "wav": case "flac": case "ogg": case "m4a":
        return "media"
    default:
        return "file"
    }
}

function initialOf(label) {
    var s = String(label || "").trim()
    return s.length > 0 ? s.charAt(0).toUpperCase() : "?"
}
