#ifndef MODELS_SHAREDFOLDERPERMISSION_H
#define MODELS_SHAREDFOLDERPERMISSION_H

#include <QString>
#include <optional>

namespace models {

/**
 * @brief Niveau d'acces d'un utilisateur a un SharedFolder dont il n'est
 * pas proprietaire (voir SharedFolderAccess / SharedFolderAccessRepository).
 *
 * None n'est jamais persiste explicitement : c'est la valeur retournee
 * quand aucune ligne SharedFolderAccess n'existe pour (folder, user) et
 * que l'utilisateur n'est ni proprietaire ni administrateur.
 */
enum class SharedFolderPermission {
    None,
    Read,
    Write
};

QString sharedFolderPermissionToString(SharedFolderPermission permission);
std::optional<SharedFolderPermission> stringToSharedFolderPermission(const QString &value);

/// true si permission permet au moins la lecture (Read ou Write).
inline bool canRead(SharedFolderPermission permission)
{
    return permission == SharedFolderPermission::Read || permission == SharedFolderPermission::Write;
}

/// true uniquement pour Write.
inline bool canWrite(SharedFolderPermission permission)
{
    return permission == SharedFolderPermission::Write;
}

} // namespace models

#endif // MODELS_SHAREDFOLDERPERMISSION_H
