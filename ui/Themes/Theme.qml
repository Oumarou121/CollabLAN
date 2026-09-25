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
    readonly property color background: darkMode ? "#15171C" : "#F2F5F8"
    readonly property color surface: darkMode ? "#1D2027" : "#FFFFFF"
    readonly property color surfaceAlt: darkMode ? "#262A32" : "#E7EDF3"
    readonly property color surfaceHover: darkMode ? "#2C313A" : "#DCE5EE"
    readonly property color secondaryBackground: darkMode ? "#1D2027" : "#E7EDF3"
    readonly property color colorTextField: darkMode ? "#262A32" : "#F2F5F8"

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
    readonly property color primary: darkMode ? "#818CF8" : "#2457A6"
    readonly property color primaryHover: darkMode ? "#9AA3FF" : "#1D4689"
    readonly property color primaryMuted: darkMode ? "#2A2A45" : "#E5ECF7"
    readonly property color primaryDeep: darkMode ? "#6366F1" : "#163B73"
    readonly property color accent: primary
    readonly property color accentDark: primaryHover
    readonly property color primaryText: "#FFFFFF"

    readonly property color text: darkMode ? "#F2F3F7" : "#17212B"
    readonly property color textSecondary: darkMode ? "#9AA0B2" : "#536273"
    readonly property color textTertiary: darkMode ? "#6E7486" : "#6B7785"

    readonly property color border: darkMode ? "#2E323C" : "#C7D1DC"
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
    readonly property color breadcrumbChipHover: darkMode ? "#262A32" : "#E7EDF3"
    readonly property color listHeaderBackground: darkMode ? "#1A1C22" : "#E7EDF3"

    // Barre d'état inférieure (fine, collée en bas, comme un vrai explorateur).
    readonly property color statusBarBackground: darkMode ? "#12141A" : "#E7EDF3"

    // Ascenseur discret.
    readonly property color scrollbarThumb: darkMode ? "#3A3F4A" : "#AEBBC8"

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
    readonly property string fontFamily: "Inter"   // laisser tel quel
    readonly property string fontFamilyFallback: "Segoe UI"
    readonly property int fontSizeTitle: 26
    readonly property int fontSizeHeading: 18
    readonly property int fontSizeSubheading: 15
    readonly property int fontSizeBody: 14
    readonly property int fontSizeSmall: 12
    readonly property int fontSizeCaption: 11

    // ---- Dashboard V2.1 Tokens ---------------------------------------------
    // Couleurs spécifiques au dashboard selon la maquette
    readonly property color dashboardBackground: darkMode ? "#0E1517" : "#EEF2F1"
    readonly property color dashboardSurface: darkMode ? "#1D2027" : "#FFFFFF"
    readonly property color dashboardSurfaceAlt: darkMode ? "#262A32" : "#F7F9F8"
    readonly property color dashboardLine: darkMode ? "#2E323C" : "#DDE4E2"
    readonly property color dashboardLineStrong: darkMode ? "#3A3F4A" : "#C7D1DC"
    readonly property color dashboardInk: darkMode ? "#EAF1F2" : "#15222B"
    readonly property color dashboardInkSecondary: darkMode ? "#B3C2C6" : "#4A5961"
    readonly property color dashboardInkTertiary: darkMode ? "#93A5AB" : "#62717A"
    readonly property color dashboardPrimary: darkMode ? "#7FC4D6" : "#0B5C70"
    readonly property color dashboardPrimaryHover: darkMode ? "#9AD5E5" : "#0A4A5C"
    readonly property color dashboardPrimarySoft: darkMode ? "#173139" : "#E0EEF2"
    readonly property color dashboardPrimaryMuted: darkMode ? "#1A2D35" : "#D1E8ED"
    readonly property color dashboardPrimaryText: "#FFFFFF"
    readonly property color dashboardSuccess: darkMode ? "#55C88A" : "#258A68"
    readonly property color dashboardSuccessText: darkMode ? "#86E5A8" : "#1A6B4E"
    readonly property color dashboardSuccessSoft: darkMode ? "#18362D" : "#E3F3EC"
    readonly property color dashboardWarning: darkMode ? "#F5BE55" : "#B87513"
    readonly property color dashboardWarningText: darkMode ? "#FFD699" : "#8B560E"
    readonly property color dashboardWarningSoft: darkMode ? "#3A301C" : "#FFF2D9"
    readonly property color dashboardError: darkMode ? "#F58D91" : "#C34F55"
    readonly property color dashboardErrorText: darkMode ? "#FFB3B6" : "#9E3F44"
    readonly property color dashboardErrorSoft: darkMode ? "#3A2024" : "#FBE7E8"
    readonly property color dashboardInfo: darkMode ? "#86B8F4" : "#477DB8"
    readonly property color dashboardInfoText: darkMode ? "#B8D4FF" : "#366090"
    readonly property color dashboardInfoSoft: darkMode ? "#1C3046" : "#E9F1FB"
    readonly property color dashboardCall: darkMode ? "#C792EA" : "#8A63B6"
    readonly property color dashboardCallText: darkMode ? "#E0B8FF" : "#6B4A8C"
    readonly property color dashboardCallSoft: darkMode ? "#2A2235" : "#F0E6F7"

    // Dimensions spécifiques au dashboard
    readonly property int dashboardSidebarWidth: 216
    readonly property int dashboardSidebarWidthCompact: 76
    readonly property int dashboardHeaderHeight: 52
    readonly property int dashboardNetworkWidth: 840
    readonly property int dashboardNetworkHeight: 480

    // États du dashboard
    readonly property color dashboardHover: darkMode ? "#2C313A" : "#DCE5EE"
    readonly property color dashboardSelected: darkMode ? "#2A2FE0" : "#4C5BFF"
    readonly property color dashboardDisabled: darkMode ? "#1A1C22" : "#E7EDF3"
    readonly property color dashboardDisabledText: darkMode ? "#4A4E5A" : "#9AA0B2"

    // Ombres dashboard (limitées selon la maquette)
    readonly property color dashboardShadow: darkMode ? "#00000040" : "#1A1D2112"
    readonly property color dashboardShadowSoft: darkMode ? "#00000020" : "#1A1D2108"

    // ---- Hiérarchie de surfaces (modernisation Dashboard/Transferts) ------
    // 4 niveaux de profondeur obtenus par contraste + spacing plutôt que par
    // bordures systématiques. À utiliser à la place de card générique
    // "rectangle blanc + border + radius" partout où c'est possible.
    readonly property color surfaceLevel1: dashboardBackground                 // fond général de l'app
    readonly property color surfaceLevel2: darkMode ? "#181D20" : "#F5F8F7"    // surfaces principales, très peu différenciées du fond
    readonly property color surfaceLevel3: darkMode ? "#232830" : "#FFFFFF"    // éléments interactifs / flottants (lignes hover, chips actifs)
    readonly property color surfaceLevel4: darkMode ? "#262C35" : "#FFFFFF"    // panels contextuels, drawer, tooltip, peer panel

    // Séparateurs très discrets (au lieu de border pleine autour de tout)
    readonly property color hairline: darkMode ? "#FFFFFF12" : "#15222B0F"
    readonly property color hairlineStrong: darkMode ? "#FFFFFF1E" : "#15222B1C"

    // Ombres réservées aux surfaces réellement flottantes (drawer, popup,
    // tooltip, panneau peer) - jamais utilisées pour une simple card de liste.
    readonly property color elevationShadow: darkMode ? "#00000055" : "#15222B1A"

    // Échelle de spacing "respiration" un cran au-dessus de spacingXl,
    // utile pour les zones d'introduction (Bonjour) et le drawer.
    readonly property int spacingXxl: 40

    // Poids de police pour renforcer la hiérarchie (dominant / secondaire / discret)
    readonly property int weightRegular: Font.Normal
    readonly property int weightMedium: Font.Medium
    readonly property int weightSemibold: Font.DemiBold
    readonly property int weightBold: Font.Bold
}
