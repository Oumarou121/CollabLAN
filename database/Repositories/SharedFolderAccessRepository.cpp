#include "SharedFolderAccessRepository.h"

#include <QSqlError>
#include <QSqlQuery>
#include <QVariant>

namespace database {

SharedFolderAccessRepository::SharedFolderAccessRepository(QSqlDatabase database)
    : m_db(std::move(database))
{
}

SharedFolderAccessRepository::~SharedFolderAccessRepository() = default;

models::SharedFolderAccess SharedFolderAccessRepository::accessFromQuery(const QSqlQuery &query) const
{
    models::SharedFolderAccess access;
    access.setId(query.value(QStringLiteral("id")).toLongLong());
    access.setFolderId(query.value(QStringLiteral("folder_id")).toLongLong());
    access.setUserId(query.value(QStringLiteral("user_id")).toLongLong());
    access.setPermission(models::stringToSharedFolderPermission(query.value(QStringLiteral("permission")).toString())
                              .value_or(models::SharedFolderPermission::Read));
    const QVariant grantedBy = query.value(QStringLiteral("granted_by"));
    access.setGrantedBy(grantedBy.isNull() ? 0 : grantedBy.toLongLong());
    access.setCreatedAt(query.value(QStringLiteral("created_at")).toDateTime());
    return access;
}

std::optional<models::SharedFolderAccess> SharedFolderAccessRepository::grant(
    qint64 folderId, qint64 userId, models::SharedFolderPermission permission, qint64 grantedBy)
{
    QSqlQuery query(m_db);
    // ON CONFLICT (folder_id, user_id) UNIQUE, migration 020) : un second
    // grant() sur la meme paire met simplement a jour la permission au
    // lieu d'echouer (INSERT OR REPLACE reutiliserait l'id existant, ce
    // qui est le comportement souhaite ici -- un utilisateur n'a jamais
    // plus d'une ligne d'acces par dossier).
    if (!query.prepare(QStringLiteral(
        "INSERT INTO SharedFolderAccess (folder_id, user_id, permission, granted_by) "
        "VALUES (:folder_id, :user_id, :permission, :granted_by) "
        "ON CONFLICT(folder_id, user_id) DO UPDATE SET permission = :permission2, granted_by = :granted_by2"))) {
        m_lastError = query.lastError().text();
        return std::nullopt;
    }
    query.bindValue(QStringLiteral(":folder_id"), folderId);
    query.bindValue(QStringLiteral(":user_id"), userId);
    query.bindValue(QStringLiteral(":permission"), models::sharedFolderPermissionToString(permission));
    query.bindValue(QStringLiteral(":permission2"), models::sharedFolderPermissionToString(permission));
    query.bindValue(QStringLiteral(":granted_by"), grantedBy > 0 ? QVariant(grantedBy) : QVariant());
    query.bindValue(QStringLiteral(":granted_by2"), grantedBy > 0 ? QVariant(grantedBy) : QVariant());

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return std::nullopt;
    }

    QSqlQuery findQuery(m_db);
    findQuery.prepare(QStringLiteral(
        "SELECT * FROM SharedFolderAccess WHERE folder_id = :folder_id AND user_id = :user_id"));
    findQuery.bindValue(QStringLiteral(":folder_id"), folderId);
    findQuery.bindValue(QStringLiteral(":user_id"), userId);
    if (!findQuery.exec() || !findQuery.next()) {
        m_lastError = findQuery.lastError().text();
        return std::nullopt;
    }
    return accessFromQuery(findQuery);
}

bool SharedFolderAccessRepository::revoke(qint64 folderId, qint64 userId)
{
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral(
        "DELETE FROM SharedFolderAccess WHERE folder_id = :folder_id AND user_id = :user_id"));
    query.bindValue(QStringLiteral(":folder_id"), folderId);
    query.bindValue(QStringLiteral(":user_id"), userId);

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return false;
    }
    return true; // idempotent : absence de ligne n'est pas une erreur
}

models::SharedFolderPermission SharedFolderAccessRepository::permissionFor(qint64 folderId, qint64 userId) const
{
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral(
        "SELECT permission FROM SharedFolderAccess WHERE folder_id = :folder_id AND user_id = :user_id"));
    query.bindValue(QStringLiteral(":folder_id"), folderId);
    query.bindValue(QStringLiteral(":user_id"), userId);

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return models::SharedFolderPermission::None;
    }
    if (!query.next()) {
        return models::SharedFolderPermission::None;
    }
    return models::stringToSharedFolderPermission(query.value(0).toString())
        .value_or(models::SharedFolderPermission::None);
}

QVector<models::SharedFolderAccess> SharedFolderAccessRepository::listForFolder(qint64 folderId) const
{
    QVector<models::SharedFolderAccess> result;
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral(
        "SELECT * FROM SharedFolderAccess WHERE folder_id = :folder_id ORDER BY created_at ASC"));
    query.bindValue(QStringLiteral(":folder_id"), folderId);

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return result;
    }
    while (query.next()) {
        result.append(accessFromQuery(query));
    }
    return result;
}

QVector<models::SharedFolderAccess> SharedFolderAccessRepository::listForUser(qint64 userId) const
{
    QVector<models::SharedFolderAccess> result;
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral(
        "SELECT * FROM SharedFolderAccess WHERE user_id = :user_id ORDER BY created_at ASC"));
    query.bindValue(QStringLiteral(":user_id"), userId);

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return result;
    }
    while (query.next()) {
        result.append(accessFromQuery(query));
    }
    return result;
}

QVector<models::SharedFolderAccess> SharedFolderAccessRepository::getSinceId(qint64 sinceId, int limit) const
{
    QVector<models::SharedFolderAccess> result;
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral(
        "SELECT * FROM SharedFolderAccess WHERE id > :since_id ORDER BY id ASC LIMIT :limit"));
    query.bindValue(QStringLiteral(":since_id"), sinceId);
    query.bindValue(QStringLiteral(":limit"), limit);

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return result;
    }
    while (query.next()) {
        result.append(accessFromQuery(query));
    }
    return result;
}

qint64 SharedFolderAccessRepository::latestId() const
{
    QSqlQuery query(m_db);
    if (!query.exec(QStringLiteral("SELECT MAX(id) FROM SharedFolderAccess")) || !query.next()) {
        m_lastError = query.lastError().text();
        return 0;
    }
    return query.value(0).toLongLong();
}

QString SharedFolderAccessRepository::lastError() const
{
    return m_lastError;
}

} // namespace database
