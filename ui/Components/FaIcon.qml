import QtQuick

/*
 * FaIcon - simple glyphe Font Awesome 4.7.0 (icone seule, sans etat de
 * survol/clic - pour ca voir Components/IconButton.qml). Charge sa propre
 * police, comme le reste des ecrans de l'application (DashboardCard,
 * ConversationsView, IconButton...), pour un rendu monochrome/teinte
 * fiable a la place des glyphes Unicode "systeme".
 */
Text {
    id: root

    property string glyph: ""

    // Charge la police pour qu'elle soit enregistree dans l'application (le
    // FontLoader la rend disponible globalement des qu'un premier composant
    // la reference), mais on ne lie plus font.family a iconFont.name : ce
    // nom reste vide tant que le chargement asynchrone n'est pas termine,
    // ce qui pouvait laisser le Text sans police valide au premier rendu
    // (glyphe invisible - carre de couleur vide, voir section Transferts du
    // Dashboard). Nom de police en dur, identique a celui deja utilise sans
    // FontLoader ailleurs dans l'app (voir Dashboard/NetworkPeer.qml) et
    // confirme comme le nom reel integre dans fontawesome-webfont.ttf.
    FontLoader {
        source: "../Assets/fonts/fontawesome-webfont.ttf"
    }

    text: root.glyph
    font.family: "FontAwesome"
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
}
