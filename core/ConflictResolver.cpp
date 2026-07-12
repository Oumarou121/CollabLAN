#include "ConflictResolver.h"

#include <QFileInfo>

namespace core {
namespace ConflictResolver {

Resolution resolve(const models::SharedFile &local, int remoteVersion, const QString &remoteHash)
{
    if (remoteVersion <= local.version()) {
        // Le distant n'a pas progresse depuis notre derniere version
        // connue : soit il est identique, soit il est en retard.
        return Resolution::RemoteIsOlder;
    }

    // Le distant a une version plus recente. S'il decrit exactement le
    // meme contenu que le notre, pas de conflit (l'un des deux poste a
    // simplement enregistre l'operation avant l'autre).
    if (!local.hash().isEmpty() && local.hash() == remoteHash) {
        return Resolution::NoConflict;
    }

    // Le distant est plus recent ET le contenu differe : si notre copie
    // locale n'a elle-meme pas ete modifiee depuis la derniere
    // synchronisation connue (meme version que celle deja synchronisee),
    // on peut appliquer le distant sans risque. On ne peut distinguer ce
    // cas ici sans connaitre la "derniere version synchronisee" ; par
    // prudence on considere donc que toute divergence de hash avec une
    // version distante plus recente est un conflit potentiel.
    return Resolution::Conflict;
}

QString conflictFileName(const QString &relativePath, const QString &remoteMachineLabel)
{
    const QFileInfo info(relativePath);
    const QString baseName = info.completeBaseName();
    const QString suffix = info.suffix();
    const QString dir = info.path();

    const QString newName = suffix.isEmpty()
        ? QStringLiteral("%1 (%2)").arg(baseName, remoteMachineLabel)
        : QStringLiteral("%1 (%2).%3").arg(baseName, remoteMachineLabel, suffix);

    if (dir.isEmpty() || dir == QStringLiteral(".")) {
        return newName;
    }
    return dir + QStringLiteral("/") + newName;
}

} // namespace ConflictResolver
} // namespace core
