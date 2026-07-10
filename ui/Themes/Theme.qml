pragma Singleton
import QtQuick

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

    // Etat courant du theme. false = Light (Themes/Light.qml), true = Dark (Themes/Dark.qml)
    property bool darkMode: false

    function toggle() {
        darkMode = !darkMode
    }

    // Couleurs de base
    readonly property color background: darkMode ? "#14161A" : "#F6F7FB"
    readonly property color surface: darkMode ? "#1E2126" : "#FFFFFF"
    readonly property color surfaceAlt: darkMode ? "#262A31" : "#EEF1F6"
    readonly property color secondaryBackground: darkMode ? "#1E2126" : "#EEF1F6"

    readonly property color primary: darkMode ? "#5B8DEF" : "#2D6CDF"
    readonly property color primaryHover: darkMode ? "#75A2FF" : "#1E58C4"
    readonly property color accent: darkMode ? "#5B8DEF" : "#2D6CDF"
    readonly property color accentDark: darkMode ? "#4A7AD9" : "#1E58C4"
    readonly property color primaryText: "#FFFFFF"

    readonly property color text: darkMode ? "#F2F3F5" : "#1A1D21"
    readonly property color textSecondary: darkMode ? "#9AA2AC" : "#5C6572"

    readonly property color border: darkMode ? "#33373D" : "#E2E5EB"
    readonly property color shadow: darkMode ? "#00000066" : "#1A1D2122"

    readonly property color error: darkMode ? "#FF7A7A" : "#D64545"
    readonly property color success: darkMode ? "#4ADE80" : "#2FAE60"

    // Metriques communes
    readonly property int spacingSmall: 8
    readonly property int spacingMedium: 16
    readonly property int spacingLarge: 24

    readonly property int radiusSmall: 6
    readonly property int radiusMedium: 10
    readonly property int radiusLarge: 16

    // Typographie
    readonly property string fontFamily: "Segoe UI"
    readonly property int fontSizeTitle: 26
    readonly property int fontSizeHeading: 18
    readonly property int fontSizeBody: 14
    readonly property int fontSizeSmall: 12
}
