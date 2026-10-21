pragma Singleton
import QtQuick
import QtCore

/*
 * Theme - design system de LocaLink (refonte 2026), singleton expose
 * globalement (import Themes).
 *
 * UN SEUL jeu de couleurs canonique (bg, surface, ink, accent, etats...).
 * Les deux anciennes familles de noms - "heritee" (text, primary,
 * border...) et "dashboard*" (dashboardInk, dashboardLine...) - sont
 * conservees comme ALIAS de ce jeu canonique : tous les ecrans partagent
 * donc la meme palette, quelle que soit la generation de code qui les a
 * ecrits. Nouveau code : utiliser les noms canoniques.
 *
 * Preferences d'apparence (persistees, appliquees a chaud, sans
 * redemarrage) : mode clair/sombre/systeme, couleur d'accent, taille du
 * texte, densite, barre laterale reduite. Voir Parametres > Apparence.
 */
QtObject {
    id: theme

    // ======================================================================
    // Preferences persistees (QSettings, categorie "Appearance")
    // ======================================================================
    property Settings prefs: Settings {
        category: "Appearance"
        // Ancienne cle (bascule clair/sombre) : lue une seule fois pour
        // migrer vers `mode`.
        property bool savedDarkMode: false
        property string mode: ""
        property string accent: "blue"
        property real fontScale: 1.0
        property string density: "comfortable"
        property bool sidebarCollapsed: false
    }

    // "light" | "dark" | "system"
    readonly property string mode: prefs.mode.length > 0 ? prefs.mode
                                                          : (prefs.savedDarkMode ? "dark" : "light")
    // "blue" | "indigo" | "teal" | "graphite"
    readonly property string accentName: accentPalettes[prefs.accent] !== undefined ? prefs.accent : "blue"
    // 0.9 | 1.0 | 1.1 | 1.2
    readonly property real fontScale: Math.max(0.85, Math.min(1.3, prefs.fontScale))
    // "comfortable" | "compact"
    readonly property string density: prefs.density === "compact" ? "compact" : "comfortable"
    readonly property bool compact: density === "compact"
    readonly property bool sidebarCollapsed: prefs.sidebarCollapsed

    readonly property bool systemDark: Qt.styleHints.colorScheme === Qt.ColorScheme.Dark
    readonly property bool darkMode: mode === "dark" || (mode === "system" && systemDark)

    function setMode(value) { prefs.mode = value }
    function setAccent(value) { if (accentPalettes[value] !== undefined) prefs.accent = value }
    function setFontScale(value) { prefs.fontScale = value }
    function setDensity(value) { prefs.density = value }
    function setSidebarCollapsed(value) { prefs.sidebarCollapsed = value }
    // Bascule rapide (en-tete) : passe en clair/sombre explicite.
    function toggle() { prefs.mode = darkMode ? "light" : "dark" }

    // Taille de police mise a l'echelle de la preference d'accessibilite.
    // Tous les `font.pixelSize` de l'application passent par fs().
    function fs(px) { return Math.max(9, Math.round(px * fontScale)) }
    function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

    // Voile et encre d'une "tonalite" (pastilles d'icone, badges) :
    // "success" | "warning" | "danger" | "call" | "accent" | "transfer" | "neutral".
    function toneSoft(tone) {
        switch (tone) {
        case "success": return successSoft
        case "warning": return warningSoft
        case "danger": return dangerSoft
        case "call": return callSoft
        case "accent":
        case "transfer": return accentSoft
        default: return sunken
        }
    }
    function toneInk(tone) {
        switch (tone) {
        case "success": return successInk
        case "warning": return warningInk
        case "danger": return dangerInk
        case "call": return callInk
        case "accent": return navActiveInk
        case "transfer": return markTransfer
        default: return ink2
        }
    }

    // ======================================================================
    // Accents selectionnables : [accent, survol, voile, attenue]
    // Tous verifies >= 4,5:1 contre leur fond (texte blanc en clair, texte
    // encre en sombre).
    // ======================================================================
    readonly property var accentPalettes: ({
        "blue":     { label: qsTr("Bleu"),
                      light: ["#2563EB", "#1D4ED8", "#EEF3FE", "#C7D7FD"],
                      dark:  ["#5B8DEF", "#7DA5F3", "#16223A", "#28407A"] },
        "indigo":   { label: qsTr("Indigo"),
                      light: ["#4F46E5", "#4338CA", "#EFEEFD", "#CFCCF8"],
                      dark:  ["#8B85F2", "#A6A1F6", "#1F1D3D", "#36326E"] },
        "teal":     { label: qsTr("Sarcelle"),
                      light: ["#0E7490", "#0B5F76", "#E6F3F6", "#B5DCE5"],
                      dark:  ["#2BA7C6", "#4CBBD6", "#0F2E37", "#1C4E5C"] },
        "graphite": { label: qsTr("Graphite"),
                      light: ["#334155", "#1E293B", "#EEF1F5", "#CBD3DF"],
                      dark:  ["#A5B4C8", "#C3CEDC", "#1E2736", "#3A475C"] }
    })
    readonly property var accentKeys: ["blue", "indigo", "teal", "graphite"]
    readonly property var _accent: accentPalettes[accentName][darkMode ? "dark" : "light"]

    // ======================================================================
    // Jeu canonique
    // ======================================================================
    // Neutres "ardoise" legerement bleutes.
    readonly property color bg:            darkMode ? "#0B1018" : "#F4F6FA"
    readonly property color surface0:      darkMode ? "#121925" : "#FFFFFF"
    readonly property color surface1:      darkMode ? "#172030" : "#F8FAFC"
    readonly property color sunken:        darkMode ? "#1C2636" : "#EEF2F7"
    readonly property color hover:         darkMode ? "#1E293B" : "#F1F4F9"
    readonly property color line:          darkMode ? "#243045" : "#E3E8EF"
    readonly property color lineStrong:    darkMode ? "#33415A" : "#CBD3DF"
    readonly property color ink:           darkMode ? "#E6EBF2" : "#0F172A"
    readonly property color ink2:          darkMode ? "#A4B0C2" : "#475569"
    readonly property color ink3:          darkMode ? "#8391A7" : "#64748B"
    readonly property color inkDisabled:   darkMode ? "#5A6880" : "#94A3B8"

    readonly property color accentColor:   _accent[0]
    readonly property color accentHover:   _accent[1]
    readonly property color accentSoft:    _accent[2]
    readonly property color accentMuted:   _accent[3]
    readonly property color accentInk:     darkMode ? "#0B1018" : "#FFFFFF"
    // Encre sur fonds pleins (accent, rouge, vert). Jamais "onXxx" : en QML
    // un identifiant on+Majuscule est lu comme un gestionnaire de signal.
    readonly property color inkOnAccent:   accentInk
    readonly property color inkOnDanger:   darkMode ? "#1A0B0D" : "#FFFFFF"
    readonly property color inkOnSuccess:  darkMode ? "#06200F" : "#FFFFFF"
    readonly property color focusRing:     _accent[0]

    readonly property color successColor:  darkMode ? "#4ADE80" : "#15803D"
    readonly property color successSoft:   darkMode ? "#10291C" : "#E8F6EE"
    readonly property color successInk:    darkMode ? "#86EFAC" : "#166534"
    readonly property color warningColor:  darkMode ? "#F0B25A" : "#B45309"
    readonly property color warningSoft:   darkMode ? "#2E2412" : "#FEF4E6"
    readonly property color warningInk:    darkMode ? "#FCD38D" : "#92400E"
    readonly property color dangerColor:   darkMode ? "#F87171" : "#DC2626"
    readonly property color dangerHover:   darkMode ? "#FCA5A5" : "#B91C1C"
    readonly property color dangerSoft:    darkMode ? "#331619" : "#FDECEC"
    readonly property color dangerInk:     darkMode ? "#FCA5A5" : "#B91C1C"
    readonly property color infoColor:     darkMode ? "#7FB4E8" : "#1D6FA5"
    readonly property color infoSoft:      darkMode ? "#132637" : "#E8F1F8"
    readonly property color infoInk:       darkMode ? "#A8CCF0" : "#15567F"
    readonly property color callColor:     darkMode ? "#9C6BE0" : "#6D4AA8"
    readonly property color callSoft:      darkMode ? "#241B38" : "#F2EDFB"
    readonly property color callInk:       darkMode ? "#C4B5FD" : "#5B3A96"

    // Navigation laterale : surface claire, plus legere que le contenu en
    // sombre, separee par un filet - jamais un bloc massif.
    readonly property color navBg:         darkMode ? "#0E141F" : "#FFFFFF"
    readonly property color navInk:        darkMode ? "#C9D2DF" : "#334155"
    readonly property color navInkMuted:   darkMode ? "#7D8BA1" : "#64748B"
    readonly property color navHover:      darkMode ? "#18212F" : "#F1F4F9"
    readonly property color navActive:     accentSoft
    readonly property color navActiveInk:  darkMode ? _accent[1] : _accent[0]
    readonly property color navLine:       line

    readonly property color scrim:         darkMode ? "#000000A6" : "#0F172A66"
    readonly property color shadowColor:   darkMode ? "#00000066" : "#0F172A14"
    readonly property color shadowStrong:  darkMode ? "#00000099" : "#0F172A29"

    // ---- Marques de la carte reseau ---------------------------------------
    // Jeu de 3 teintes valide pour le daltonisme : la couleur n'encode que
    // l'ACTIVITE, toujours doublee d'un badge et d'un libelle.
    readonly property color markTransfer:  darkMode ? "#2B96B5" : "#0B7E9E"
    readonly property color markCall:      callColor
    readonly property color markAway:      darkMode ? "#C9821F" : "#B45309"
    readonly property color markOnline:    successColor
    readonly property color markOffline:   lineStrong
    readonly property color orbitInner:    darkMode ? "#33415A" : "#C2CCDA"
    readonly property color orbitOuter:    darkMode ? "#273347" : "#D7DEE8"
    readonly property color nodeOffline:   darkMode ? "#172030" : "#F1F4F8"
    readonly property color nodeOfflineLine: darkMode ? "#4A5870" : "#B4BFCE"
    readonly property color nodeOfflineInk:  darkMode ? "#7D8BA1" : "#8794A8"
    // Dossiers : la convention "dossier jaune" reste reconnue instantanement,
    // desaturee pour s integrer a la palette ardoise.
    readonly property color folderColor:   darkMode ? "#D9A441" : "#F2B84B"
    readonly property color folderTab:     darkMode ? "#B88730" : "#DE9F2C"

    // ======================================================================
    // Metriques (densite)
    // ======================================================================
    readonly property int spacingXs: 4
    readonly property int spacingSmall: compact ? 6 : 8
    readonly property int spacingMedium: compact ? 12 : 16
    readonly property int spacingLarge: compact ? 18 : 24
    readonly property int spacingXl: compact ? 24 : 32
    readonly property int spacingXxl: compact ? 32 : 40
    readonly property int spacingGutter: compact ? 12 : 16
    readonly property int pagePadding: compact ? 18 : 28
    readonly property int cardPadding: compact ? 12 : 18

    readonly property int controlHeight: compact ? 32 : 38
    readonly property int controlHeightSmall: compact ? 28 : 32
    readonly property int rowHeight: compact ? 40 : 52
    readonly property int navItemHeight: compact ? 32 : 36
    readonly property int iconSize: 16

    readonly property int radiusSmall: 6
    readonly property int radiusControl: 8
    readonly property int radiusMedium: 10
    readonly property int radiusLarge: 14
    readonly property int radiusXl: 20
    readonly property int radiusPill: 999
    readonly property int radiusCard: 12
    readonly property int radiusRow: 8

    // ---- Typographie (Inter embarquee, repli Segoe UI) ---------------------
    readonly property string fontFamily: "Inter"
    readonly property string fontFamilyFallback: "Segoe UI"
    readonly property int fontSizeDisplay: fs(28)
    readonly property int fontSizeTitle: fs(22)
    readonly property int fontSizeHeading: fs(17)
    readonly property int fontSizeSubheading: fs(15)
    readonly property int fontSizeBody: fs(14)
    readonly property int fontSizeSmall: fs(12)
    readonly property int fontSizeCaption: fs(11)
    readonly property int fontSizeCardTitle: fs(15)
    readonly property int fontSizeMetric: fs(26)
    readonly property int fontSizeOverline: fs(11)

    readonly property int weightRegular: Font.Normal
    readonly property int weightMedium: Font.Medium
    readonly property int weightSemibold: Font.DemiBold
    readonly property int weightBold: Font.Bold

    // ---- Mouvement ---------------------------------------------------------
    readonly property int durationFast: 110
    readonly property int durationNormal: 180

    // ======================================================================
    // Structure de l'application
    // ======================================================================
    readonly property int sidebarWidth: compact ? 216 : 232
    readonly property int sidebarWidthCollapsed: 64
    readonly property int topbarHeight: compact ? 48 : 56

    // Paliers de resolution (voir planche "Resolutions").
    readonly property int bpMetricsWrap: 1180
    readonly property int bpPanelsWrap: 1080
    readonly property int bpListFallback: 900
    readonly property int pairMinWidth: 640

    // Avatars : teintes deterministes par nom, harmonisees avec la palette.
    readonly property var avatarPalette: [
        "#2563EB", "#0E7490", "#7C3AED", "#B45309",
        "#15803D", "#BE185D", "#4F46E5", "#0F766E"
    ]

    function colorForName(name) {
        if (!name || name.length === 0)
            return accentColor
        let hash = 0
        for (let i = 0; i < name.length; ++i)
            hash = (hash * 31 + name.charCodeAt(i)) & 0xffffffff
        return avatarPalette[Math.abs(hash) % avatarPalette.length]
    }

    // ======================================================================
    // ALIAS - noms herites (ne pas utiliser dans le nouveau code)
    // ======================================================================
    readonly property color background: bg
    readonly property color surface: surface0
    readonly property color surfaceAlt: surface1
    readonly property color surfaceHover: hover
    readonly property color secondaryBackground: surface1
    readonly property color colorTextField: surface0
    readonly property color sidebarBackground: navBg
    readonly property color sidebarText: navInk
    readonly property color sidebarTextMuted: navInkMuted
    readonly property color sidebarHover: navHover
    readonly property color sidebarActive: navActive
    readonly property color sidebarBorder: navLine
    readonly property color primary: accentColor
    readonly property color primaryHover: accentHover
    readonly property color primaryMuted: accentSoft
    readonly property color primaryDeep: accentHover
    readonly property color accent: accentColor
    readonly property color accentDark: accentHover
    readonly property color primaryText: accentInk
    readonly property color text: ink
    readonly property color textSecondary: ink2
    readonly property color textTertiary: ink3
    readonly property color border: lineStrong
    readonly property color divider: line
    readonly property color shadow: shadowStrong
    readonly property color shadowSoft: shadowColor
    readonly property color overlay: scrim
    readonly property color selectionBackground: alpha(accentColor, 0.12)
    readonly property color selectionBackgroundHover: alpha(accentColor, 0.2)
    readonly property color selectionBorder: accentColor
    readonly property color addressBarBackground: surface0
    readonly property color breadcrumbChipHover: hover
    readonly property color listHeaderBackground: surface1
    readonly property color statusBarBackground: surface1
    readonly property color scrollbarThumb: lineStrong
    readonly property color error: dangerColor
    readonly property color errorMuted: dangerSoft
    readonly property color success: successColor
    readonly property color successMuted: successSoft
    readonly property color warning: warningColor
    readonly property color warningMuted: warningSoft
    readonly property color hairline: line
    readonly property color hairlineStrong: lineStrong
    readonly property color elevationShadow: shadowStrong
    readonly property color surfaceLevel1: bg
    readonly property color surfaceLevel2: surface1
    readonly property color surfaceLevel3: surface0
    readonly property color surfaceLevel4: surface0

    readonly property color dashboardBackground: bg
    readonly property color dashboardSurface: surface0
    readonly property color dashboardSurfaceAlt: surface1
    readonly property color dashboardSurfaceSunken: sunken
    readonly property color dashboardLine: line
    readonly property color dashboardLineStrong: lineStrong
    readonly property color dashboardInk: ink
    readonly property color dashboardInkSecondary: ink2
    readonly property color dashboardInkTertiary: ink3
    readonly property color dashboardPrimary: accentColor
    readonly property color dashboardPrimaryHover: accentHover
    readonly property color dashboardPrimarySoft: accentSoft
    readonly property color dashboardPrimaryMuted: accentMuted
    readonly property color dashboardPrimaryText: accentInk
    readonly property color dashboardSuccess: successColor
    readonly property color dashboardSuccessText: successInk
    readonly property color dashboardSuccessSoft: successSoft
    readonly property color dashboardWarning: warningColor
    readonly property color dashboardWarningText: warningInk
    readonly property color dashboardWarningSoft: warningSoft
    readonly property color dashboardError: dangerColor
    readonly property color dashboardErrorText: dangerInk
    readonly property color dashboardErrorSoft: dangerSoft
    readonly property color dashboardInfo: infoColor
    readonly property color dashboardInfoText: infoInk
    readonly property color dashboardInfoSoft: infoSoft
    readonly property color dashboardCall: callColor
    readonly property color dashboardCallText: callInk
    readonly property color dashboardCallSoft: callSoft
    readonly property color dashboardMarkTransfer: markTransfer
    readonly property color dashboardMarkCall: markCall
    readonly property color dashboardMarkAway: markAway
    readonly property color dashboardMarkOffline: markOffline
    readonly property color dashboardOrbitInner: orbitInner
    readonly property color dashboardOrbitOuter: orbitOuter
    readonly property color dashboardNodeOffline: nodeOffline
    readonly property color dashboardNodeOfflineLine: nodeOfflineLine
    readonly property color dashboardNodeOfflineInk: nodeOfflineInk
    readonly property color dashboardHubGradient: accentHover
    readonly property color dashboardHover: hover
    readonly property color dashboardSelected: accentColor
    readonly property color dashboardDisabled: sunken
    readonly property color dashboardDisabledText: inkDisabled
    readonly property color dashboardShadow: shadowColor
    readonly property color dashboardShadowSoft: shadowColor

    readonly property int dashboardSidebarWidth: sidebarWidth
    readonly property int dashboardSidebarWidthCompact: sidebarWidthCollapsed
    readonly property int dashboardHeaderHeight: topbarHeight
    readonly property int dashboardNetworkWidth: 760
    readonly property int dashboardNetworkHeight: 420
    readonly property int dashboardBpMetricsWrap: bpMetricsWrap
    readonly property int dashboardBpPanelsWrap: bpPanelsWrap
    readonly property int dashboardBpListFallback: bpListFallback
    readonly property int dashboardPairMinWidth: pairMinWidth
}
