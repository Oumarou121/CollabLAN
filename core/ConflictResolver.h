#ifndef CORE_CONFLICTRESOLVER_H
#define CORE_CONFLICTRESOLVER_H

#include <QString>

#include "models/SharedFile.h"

namespace core {

/**
 * @brief Detecte et resout les conflits de synchronisation (Phase 9 de
 * "Shared Folder") : deux postes ont modifie le meme fichier
 * independamment, avant d'avoir pu se synchroniser entre eux.
 *
 * Heuristique retenue pour cette premiere version (volontairement
 * simple ; le hash de contenu, plus couteux a calculer par bloc, est
 * laisse pour une optimisation ulterieure -- cf. spec, "plus tard") :
 * il y a conflit lorsque la version locale et la version distante ont
 * toutes deux progresse depuis la derniere fois qu'elles etaient
 * identiques (donc ni l'une ni l'autre n'est un simple "retard" a
 * rattraper) ET que leur contenu differe (hash different). Dans ce cas
 * la copie locale est renommee pour ne pas ecraser silencieusement le
 * travail de l'autre poste, puis la version distante est appliquee sous
 * le nom d'origine.
 */
namespace ConflictResolver {

enum class Resolution {
    NoConflict,      // Pas de conflit : la version distante peut etre appliquee directement.
    RemoteIsOlder,   // La version distante est perimee (deja rattrapee) : rien a faire.
    Conflict         // Conflit reel : la copie locale doit etre renommee avant application du remote.
};

Resolution resolve(const models::SharedFile &local, int remoteVersion, const QString &remoteHash);

// Construit le nouveau nom pour la copie locale en conflit, sur le
// modele "rapport (Bob).docx" donne par la specification, a partir du
// nom du poste distant (label lisible, pas l'identifiant machine).
QString conflictFileName(const QString &relativePath, const QString &remoteMachineLabel);

} // namespace ConflictResolver

} // namespace core

#endif // CORE_CONFLICTRESOLVER_H
