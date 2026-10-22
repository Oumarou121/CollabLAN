#ifndef CORE_PERMISSIONMANAGER_H
#define CORE_PERMISSIONMANAGER_H

#include <QObject>
#include <QSet>
#include <QString>
#include <QStringList>
#include <optional>
#include <memory>
#include <vector>
#include "models/AuthorizedMachine.h"

namespace database {
class DatabaseManager;
class AuthorizedMachineRepository;
class TrustedServerRepository;
}

namespace models {
class AuthorizedMachine;
}

namespace core {

/**
 * @brief Rôles utilisateurs dans l'application (issue #67).
 */
enum class UserRole {
    User,   ///< Utilisateur standard (accès limité)
    Admin   ///< Administrateur (accès complet, y compris administration)
};

/**
 * @brief Convertit un rôle en chaîne de caractères pour stockage en base.
 */
QString userRoleToString(UserRole role);

/**
 * @brief Convertit une chaîne de caractères en rôle.
 */
std::optional<UserRole> stringToUserRole(const QString &str);

/**
 * @brief Gestion des permissions et des rôles (admin, utilisateur...).
 *
 * Vérifie les droits avant les actions sensibles (accès à l'administration,
 * gestion des utilisateurs, etc.) et gère la liste blanche/noire des machines
 * autorisées (issue #68).
 */
class PermissionManager : public QObject
{
    Q_OBJECT

public:
    explicit PermissionManager(database::DatabaseManager *dbManager, QObject *parent = nullptr);
    ~PermissionManager() override;

    /// Vérifie si un rôle a le droit d'effectuer une action d'administration.
    static bool canPerformAdminAction(UserRole role);

    /// Vérifie si un rôle a le droit d'accéder à l'écran d'administration.
    static bool canAccessAdminView(UserRole role);

    /// Vérifie si un rôle a le droit de gérer les utilisateurs.
    static bool canManageUsers(UserRole role);

    /// Vérifie si un rôle a le droit de gérer les machines autorisées.
    static bool canManageAuthorizedMachines(UserRole role);

    /// Vérifie si une adresse IP est autorisée à rejoindre le réseau (issue #68).
    /// Q_INVOKABLE requis : MessagingServer/MessagingService l'appellent via
    /// QMetaObject::invokeMethod("isMachineAuthorized", ...) plutot que par un
    /// pointeur direct (voir issue #70). Sans ce marqueur, invokeMethod
    /// echoue silencieusement ("No such method...") et le controle d'acces
    /// se retrouve fail-open (authorized reste a sa valeur par defaut true).
    Q_INVOKABLE bool isMachineAuthorized(const QString &ipAddress) const;
    Q_INVOKABLE bool isMachineAuthorizedByCertificate(const QString &fingerprint) const;
    /// Accepte aussi un certificat de serveur deja epingle localement (retour
    /// du serveur officiel vers un pair devenu TEMP_SERVER) et une machine
    /// que le serveur actif declare autorisee (appels et transferts directs
    /// entre clients, cf. setServerAuthorizedFingerprints).
    Q_INVOKABLE bool isMachineAuthorizedOrTrustedServer(const QString &fingerprint) const;

    /// Liste des machines autorisees envoyee par le serveur actif (message
    /// "authorized_peers", recu uniquement sur la connexion TLS vers ce
    /// serveur deja approuve). Gardee en memoire seulement : elle remplace la
    /// precedente a chaque envoi et n'est jamais ecrite dans la politique
    /// d'admission locale (AuthorizedClients).
    void setServerAuthorizedFingerprints(const QStringList &fingerprints);
    void clearServerAuthorizedFingerprints();
    bool isAuthorizedByServer(const QString &fingerprint) const;
    /// Empreintes a envoyer aux clients : machines autorisees localement,
    /// plus la liste recue (un serveur de secours relaie celle du serveur
    /// officiel).
    QStringList authorizedFingerprintsForPeers() const;
    /// Serveurs approuves localement (liste TrustedServers). Un serveur de
    /// secours les transmet a ses clients pour qu'un poste arrive pendant la
    /// panne reconnaisse le serveur officiel a son retour.
    QStringList trustedServerFingerprints() const;
    /// Serveurs designes par le serveur actif (champ "servers" de
    /// "authorized_peers", en memoire). Au premier contact, un tel serveur est
    /// epingle dans TrustedServers sans approbation manuelle, sauf s'il a ete
    /// revoque localement.
    void setVouchedServerFingerprints(const QStringList &fingerprints);
    bool isVouchedServer(const QString &fingerprint) const;
    /// Reprise par le serveur officiel d'une autorisation donnee sur un
    /// serveur de secours pendant une panne. Sans effet (faux) si la machine
    /// est deja autorisee ou revoquee ici : seule une machine inconnue ou en
    /// attente est reprise.
    bool adoptTempServerAuthorization(const QString &fingerprint, const QString &machineUuid,
                                      const QString &hostname, const QString &ipAddress,
                                      std::optional<int> authorizedBy, const QString &reason);
    /// Vrai si ce certificat a ete approuve comme SERVEUR (liste TrustedServers) : seul un tel
    /// pair recoit le journal de synchronisation complet (cf. SyncService).
    Q_INVOKABLE bool isTrustedServer(const QString &fingerprint) const;
    /// Vrai si ce poste a deja approuve au moins un serveur (il a deja fait
    /// partie d'un reseau) ; faux pour un poste neuf.
    bool hasTrustedServer() const;
    Q_INVOKABLE void recordMachineSeen(const QString &fingerprint, const QString &ipAddress);
    /// Verifie la confiance LOCALE envers le certificat du serveur. Cette
    /// decision ne quitte jamais ce poste.
    Q_INVOKABLE bool trustRemoteServerCertificate(const QString &fingerprint,
                                                  const QString &ipAddress);
    Q_INVOKABLE bool approveServerCertificate(const QString &fingerprint,
                                              const QString &ipAddress,
                                              const QString &hostname = QString());
    Q_INVOKABLE bool revokeServerCertificate(const QString &fingerprint,
                                             const QString &reason = QString());

    /// Enregistre un CLIENT inconnu cote serveur. Cette liste ne represente
    /// jamais les certificats de serveurs approuves par le poste local.
    Q_INVOKABLE bool registerPendingMachineByCertificate(const QString &fingerprint,
                                                         const QString &ipAddress,
                                                         const QString &hostname = QString());

    std::optional<models::AuthorizedMachine> findMachineByCertificateFingerprint(const QString &fingerprint) const;

    bool removeMachine(int id);

    /// Révoque une machine par son adresse IP (issue #68).
    bool revokeMachine(const QString &ipAddress, int revokedBy, const QString &reason = QString());

    /// Autorise une machine par son adresse IP (issue #68).
    bool authorizeMachine(const QString &ipAddress, int authorizedBy, const QString &reason = QString());
    bool authorizeMachineByCertificate(const QString &fingerprint, const QString &machineUuid,
                                       const QString &hostname, const QString &ipAddress,
                                       std::optional<int> authorizedBy, const QString &reason = QString());
    bool revokeMachineByCertificate(const QString &fingerprint, int revokedBy,
                                const QString &reason = QString());
    bool authorizeExistingMachineByCertificate(const QString &fingerprint, int authorizedBy,
                                const QString &reason = QString());

    /// Retourne toutes les machines (pour AuthorizedMachineModel)
    std::vector<models::AuthorizedMachine> getAllMachines() const;
    Q_INVOKABLE int pendingClientCount() const;

    /// Retourne le DatabaseManager (pour AuthorizedMachineModel)
    database::DatabaseManager* databaseManager() const;

signals:
    void machineChanged(const models::AuthorizedMachine &machine);
    /// Une machine a ete retiree de la liste (les autres changements passent
    /// par machineChanged).
    void machineRemoved(int id);


private:
    database::DatabaseManager *m_dbManager = nullptr;
    /// Politique d'admission appliquee par le serveur aux clients entrants.
    std::unique_ptr<database::AuthorizedMachineRepository> m_repository;
    /// Magasin de pinning TLS du client, strictement local et non replique.
    std::unique_ptr<database::TrustedServerRepository> m_trustedServers;
    /// Machines declarees autorisees par le serveur actif (en memoire).
    QSet<QString> m_serverAuthorized;
    /// Serveurs designes par le serveur actif (en memoire).
    QSet<QString> m_vouchedServers;
};

} // namespace core

#endif // CORE_PERMISSIONMANAGER_H
