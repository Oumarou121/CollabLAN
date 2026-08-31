pragma Singleton
import QtQuick
import Qt.labs.settings

/*
 * Theme - singleton expose globalement (import "Themes").
 *
 * Consolide dynamiquement les palettes Light.qml / Dark.qml : toutes les
 * couleurs sont des expressions dependant de `darkMode`, donc changer
 * `Theme.darkMode` (ou appeler `Theme.toggle()`) met a jour instantanement
 * tous les ecrans qui utilisent `Theme.xxx` dans leurs bindings.
 */
QtObject {
    id: theme

    property var persistedSettings: Settings {
        category: "Appearance"
        property bool savedDarkMode: false
    }

    // Etat courant du theme. false = Light (Themes/Light.qml), true = Dark (Themes/Dark.qml)
    property bool darkMode: persistedSettings.savedDarkMode

    function toggle() {
        darkMode = !darkMode
        persistedSettings.savedDarkMode = darkMode
    }

    // ---- Couleurs de base ------------------------------------------------
    readonly property color background: darkMode ? "#15171C" : "#F5F6FA"
    readonly property color surface: darkMode ? "#1D2027" : "#FFFFFF"
    readonly property color surfaceAlt: darkMode ? "#262A32" : "#EEF0F6"
    readonly property color surfaceHover: darkMode ? "#2C313A" : "#E6E9F2"
    readonly property color secondaryBackground: darkMode ? "#1D2027" : "#EEF0F6"

    // Panneau lateral (sidebar) : legerement plus fonce/distinct de la
    // surface de contenu pour marquer la hierarchie de navigation.
    readonly property color sidebarBackground: darkMode ? "#12141A" : "#1B1E2A"
    readonly property color sidebarText: "#E7E9F5"
    readonly property color sidebarTextMuted: "#9AA0C0"
    readonly property color sidebarHover: darkMode ? "#1D2029" : "#262A3A"
    readonly property color sidebarActive: darkMode ? "#2A2FE0" : "#4C5BFF"
    readonly property color sidebarBorder: darkMode ? "#22252E" : "#262A3A"

    // Accent principal : indigo moderne, un peu plus distinctif que le
    // bleu "par defaut" tout en restant sobre et lisible.
    readonly property color primary: darkMode ? "#818CF8" : "#4F46E5"
    readonly property color primaryHover: darkMode ? "#9AA3FF" : "#4338CA"
    readonly property color primaryMuted: darkMode ? "#2A2A45" : "#EEF0FE"
    readonly property color primaryDeep: darkMode ? "#6366F1" : "#3730A3"
    readonly property color accent: primary
    readonly property color accentDark: primaryHover
    readonly property color primaryText: "#FFFFFF"

    readonly property color text: darkMode ? "#F2F3F7" : "#1A1D29"
    readonly property color textSecondary: darkMode ? "#9AA0B2" : "#616881"
    readonly property color textTertiary: darkMode ? "#6E7486" : "#8B92A6"

    readonly property color border: darkMode ? "#2E323C" : "#E4E7F0"
    readonly property color divider: border
    readonly property color shadow: darkMode ? "#00000080" : "#1A1D2118"
    readonly property color shadowSoft: darkMode ? "#00000055" : "#1A1D210F"
    readonly property color overlay: darkMode ? "#000000AA" : "#1A1D2166"

    // ---- Jetons "explorateur de fichiers" ---------------------------------
    // Selection façon Windows/Nautilus : léger voile teinté de la couleur
    // d'accent, plus marqué au survol, avec une bordure nette.
    readonly property color selectionBackground: Qt.rgba(primary.r, primary.g, primary.b, 0.14)
    readonly property color selectionBackgroundHover: Qt.rgba(primary.r, primary.g, primary.b, 0.22)
    readonly property color selectionBorder: primary

    // Barre d'adresse / fil d'Ariane et en-tête de liste (vue "Détails").
    readonly property color addressBarBackground: darkMode ? "#1A1C22" : "#FFFFFF"
    readonly property color breadcrumbChipHover: darkMode ? "#262A32" : "#EEF0F6"
    readonly property color listHeaderBackground: darkMode ? "#1A1C22" : "#F3F4F9"

    // Barre d'état inférieure (fine, collée en bas, comme un vrai explorateur).
    readonly property color statusBarBackground: darkMode ? "#12141A" : "#EEF0F6"

    // Ascenseur discret.
    readonly property color scrollbarThumb: darkMode ? "#3A3F4A" : "#C8CCDA"

    readonly property color error: darkMode ? "#FF7A7A" : "#D6455A"
    readonly property color errorMuted: darkMode ? "#3A2229" : "#FCEBEC"
    readonly property color success: darkMode ? "#4ADE80" : "#1FA971"
    readonly property color successMuted: darkMode ? "#1E332A" : "#E5F8EF"
    readonly property color warning: darkMode ? "#FBBF24" : "#D97706"
    readonly property color warningMuted: darkMode ? "#3A3120" : "#FEF3E2"

    // Palette utilisee pour generer une couleur d'avatar deterministe a
    // partir d'un nom (voir colorForName ci-dessous).
    readonly property var avatarPalette: [
        "#4C5BFF", "#E85C8A", "#1FA971", "#D97706",
        "#7C5CFF", "#0EA5B7", "#DB4F4F", "#3D8BCC"
    ]

    function colorForName(name) {
        if (!name || name.length === 0)
            return primary
        let hash = 0
        for (let i = 0; i < name.length; ++i) {
            hash = (hash * 31 + name.charCodeAt(i)) & 0xffffffff
        }
        const index = Math.abs(hash) % avatarPalette.length
        return avatarPalette[index]
    }

    // ---- Metriques communes ----------------------------------------------
    readonly property int spacingXs: 4
    readonly property int spacingSmall: 8
    readonly property int spacingMedium: 16
    readonly property int spacingLarge: 24
    readonly property int spacingXl: 32

    readonly property int radiusSmall: 8
    readonly property int radiusMedium: 12
    readonly property int radiusLarge: 20
    readonly property int radiusXl: 26
    readonly property int radiusPill: 999

    // ---- Typographie -------------------------------------------------------
    readonly property string fontFamily: "Inter"
    readonly property string fontFamilyFallback: "Segoe UI"
    readonly property int fontSizeTitle: 26
    readonly property int fontSizeHeading: 18
    readonly property int fontSizeSubheading: 15
    readonly property int fontSizeBody: 14
    readonly property int fontSizeSmall: 12
    readonly property int fontSizeCaption: 11
}
