#ifndef DATABASE_OUTBOXREPOSITORY_H
#define DATABASE_OUTBOXREPOSITORY_H

#include <QJsonObject>
#include <QSqlDatabase>
#include <QString>
#include <QVector>

namespace database {

/// Changement en attente d'accuse du serveur (table Outbox).
struct OutboxChange {
    QString changeId;
    QString userUuid;
    QJsonObject payload;
    bool requiresOfficial = false;
};

/**
 * @brief File d'attente persistante des changements a transmettre au serveur
 *        (migration 035) : modification/suppression de message, groupes.
 *        Chaque changement reste jusqu'a l'accuse du serveur ("change_ack").
 */
class OutboxRepository
{
public:
    explicit OutboxRepository(QSqlDatabase database);

    /// Ajoute un changement ; son payload recoit "changeId".
    /// @return l'identifiant du changement (vide en cas d'echec).
    QString enqueue(const QString &userUuid, QJsonObject payload, bool requiresOfficial);
    /// Changements en attente, dans l'ordre ou ils ont ete faits ; userUuid
    /// vide : tous les utilisateurs.
    QVector<OutboxChange> pending(const QString &userUuid = QString()) const;
    bool remove(const QString &changeId);
    int count() const;

private:
    QSqlDatabase m_db;
};

} // namespace database

#endif // DATABASE_OUTBOXREPOSITORY_H
