#ifndef MODELS_SHAREDFOLDERACCESS_H
#define MODELS_SHAREDFOLDERACCESS_H

#include <QString>
#include <QDateTime>

#include "SharedFolderPermission.h"

namespace models {

/**
 * @brief Une ligne d'acces accorde a un utilisateur sur un SharedFolder
 * dont il n'est pas proprietaire (table SharedFolderAccess, migration 020).
 */
class SharedFolderAccess {
public:
    SharedFolderAccess() = default;
    SharedFolderAccess(qint64 folderId, qint64 userId, SharedFolderPermission permission)
        : m_folderId(folderId), m_userId(userId), m_permission(permission)
    {
    }

    qint64 id() const { return m_id; }
    void setId(qint64 id) { m_id = id; }

    qint64 folderId() const { return m_folderId; }
    void setFolderId(qint64 folderId) { m_folderId = folderId; }

    qint64 userId() const { return m_userId; }
    void setUserId(qint64 userId) { m_userId = userId; }

    SharedFolderPermission permission() const { return m_permission; }
    void setPermission(SharedFolderPermission permission) { m_permission = permission; }

    qint64 grantedBy() const { return m_grantedBy; }
    void setGrantedBy(qint64 grantedBy) { m_grantedBy = grantedBy; }

    QDateTime createdAt() const { return m_createdAt; }
    void setCreatedAt(const QDateTime &createdAt) { m_createdAt = createdAt; }

private:
    qint64 m_id = 0;
    qint64 m_folderId = 0;
    qint64 m_userId = 0;
    SharedFolderPermission m_permission = SharedFolderPermission::Read;
    qint64 m_grantedBy = 0;
    QDateTime m_createdAt;
};

} // namespace models

#endif // MODELS_SHAREDFOLDERACCESS_H
