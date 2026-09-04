#ifndef DATABASE_AUTHORIZEDMACHINEREPOSITORY_H
#define DATABASE_AUTHORIZEDMACHINEREPOSITORY_H

#include <QSqlDatabase>
#include <QString>
#include <optional>
#include <vector>

#include "models/AuthorizedMachine.h"

class QSqlQuery;

namespace database {

/**
 * @brief Accès aux données de la table AuthorizedMachines (issue #68).
 *
 * Gère la liste blanche/noire des machines pouvant rejoindre le réseau LocaLink.
 */
class AuthorizedMachineRepository
{
public:
    explicit AuthorizedMachineRepository(QSqlDatabase database);
    ~AuthorizedMachineRepository();

    /**
     * @brief Insère une nouvelle machine autorisée/révoquée.
     * @return l'id généré, ou -1 en cas d'échec.
     */
    int create(const models::AuthorizedMachine &machine);

    /**
     * @brief Met à jour une machine existante.
     */
    bool update(const models::AuthorizedMachine &machine);

    /**
     * @brief Supprime une machine par son id.
     */
    bool remove(int id);
    bool removeByUuidOrCertificate(const QString &uuid, const QString &fingerprint);

    /**
     * @brief Recherche une machine par son adresse IP.
     */
    std::optional<models::AuthorizedMachine> findByIpAddress(const QString &ipAddress) const;
    std::optional<models::AuthorizedMachine> findByUuid(const QString &uuid) const;
    std::optional<models::AuthorizedMachine> findByCertificateFingerprint(const QString &fingerprint) const;
    bool upsertRemote(const models::AuthorizedMachine &machine);
    bool updateLastSeen(const QString &fingerprint, const QString &ipAddress);

    /**
     * @brief Récupère toutes les machines.
     */
    std::vector<models::AuthorizedMachine> findAll() const;

    /**
     * @brief Récupère uniquement les machines autorisées.
     */
    std::vector<models::AuthorizedMachine> findAuthorized() const;

    /**
     * @brief Récupère uniquement les machines révoquées.
     */
    std::vector<models::AuthorizedMachine> findRevoked() const;

    /**
     * @brief Vérifie si une adresse IP est autorisée.
     * @return true si autorisée ou si aucune restriction n'existe pour cette IP.
     */
    bool isAuthorized(const QString &ipAddress) const;

    /**
     * @brief Révoque une machine par son adresse IP.
     */
    bool revokeByIpAddress(const QString &ipAddress, int revokedBy, const QString &reason = QString());

    /**
     * @brief Autorise une machine par son adresse IP.
     */
    bool authorizeByIpAddress(const QString &ipAddress, int authorizedBy, const QString &reason = QString());
    bool setAuthorizationByCertificate(const QString &fingerprint, bool authorized,
                                   int changedBy, const QString &reason = QString());

    /**
     * @brief true si au moins une machine a le statut 'authorized' (bootstrap admin).
     */
    bool hasAnyAuthorizedMachine() const;

    /**
     * @brief Enregistre (ou met a jour) une machine inconnue en statut 'pending'.
     * N'autorise jamais automatiquement : la machine reste refusee tant
     * qu'un admin ne l'a pas explicitement autorisee.
     */
    bool registerPendingByCertificate(const QString &fingerprint, const QString &ipAddress,
                                      const QString &hostname, const QString &reason);

    QString lastError() const;

private:
    models::AuthorizedMachine machineFromQuery(const QSqlQuery &query) const;

    QSqlDatabase m_db;
    mutable QString m_lastError;
};

} // namespace database

#endif // DATABASE_AUTHORIZEDMACHINEREPOSITORY_H
