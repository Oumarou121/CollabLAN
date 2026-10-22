#ifndef SAFEPATH_H
#define SAFEPATH_H

#include <QString>

namespace core::sync {

/// Chemin absolu de `relativePath` a l'interieur du dossier `root`, ou chaine
/// vide si ce chemin n'est pas acceptable.
///
/// Les chemins relatifs des dossiers partages arrivent du reseau (folder_op,
/// catchup, folder_file_request) : ils ne doivent JAMAIS permettre de lire,
/// d'ecrire, de renommer ou de supprimer un fichier hors du dossier partage.
/// Sont refuses : chemin vide, chemin absolu, lettre de lecteur ou flux NTFS
/// (":"), chemin UNC, segment "..", et tout chemin dont la cible reelle (liens
/// symboliques resolus) sort du dossier.
QString resolveInsideFolder(const QString &root, const QString &relativePath);

/// Vrai si `relativePath` designe, dans `root`, un element qui existe deja
/// sur le disque sous un nom different par la casse seulement ("Rapport.txt"
/// demande, "rapport.txt" present). Sur un systeme de fichiers insensible a la
/// casse (Windows), ce sont alors deux fichiers distincts d'un poste Linux qui
/// tomberaient sur le meme fichier ici. Toujours faux ailleurs.
bool caseDiffersOnDisk(const QString &root, const QString &relativePath);

} // namespace core::sync

#endif // SAFEPATH_H
