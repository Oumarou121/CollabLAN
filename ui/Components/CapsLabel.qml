import QtQuick
import Themes

/*
 * CapsLabel - rubrique en petites capitales espacees (Ligne claire) :
 * surtitres, en-tetes de colonnes, groupes de navigation.
 */
Text {
    color: Theme.ink3
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontSizeCaps
    font.weight: Theme.weightSemibold
    font.letterSpacing: Theme.capsLetterSpacing
    font.capitalization: Font.AllUppercase
    elide: Text.ElideRight
}
