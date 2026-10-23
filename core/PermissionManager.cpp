#include "PermissionManager.h"
#include "NetworkAddress.h"
#include "DatabaseManager.h"
#include "database/Repositories/AuthorizedMachineRepository.h"
#include "database/Repositories/TrustedServerRepository.h"
#include "models/AuthorizedMachine.h"

namespace core {

QString userRoleToString(UserRole role)
{
    switch (role) {
    case UserRole::Admin:
        return QStringLiteral("admin");
    case UserRole::User:
        return QStringLiteral("user");
    }
    return QStringLiteral("user");
}

std::optional<UserRole> stringToUserRole(const QString &str)
{
    if (str == QStringLiteral("admin"))
        return UserRole::Admin;
    if (str == QStringLiteral("user"))
        return UserRole::User;
    return std::nullopt;
}

PermissionManager::PermissionManager(database::DatabaseManager *dbManager, QObject *parent)
    : QObject(parent)
    , m_dbManager(dbManager)
{
    if (m_dbManager) {
        m_repository = std::make_unique<database::AuthorizedMachineRepository>(m_dbManager->database());
        m_trustedServers = std::make_unique<database::TrustedServerRepository>(m_dbManager->database());
    }
}

PermissionManager::~PermissionManager()
{
}

bool PermissionManager::canPerformAdminAction(UserRole role)
{
    return role == UserRole::Admin;
}

bool PermissionManager::canAccessAdminView(UserRole role)
{
    return role == UserRole::Admin;
}

bool PermissionManager::canManageUsers(UserRole role)
{
    return role == UserRole::Admin;
}

bool PermissionManager::canManageAuthorizedMachines(UserRole role)
{
    return role == UserRole::Admin;
}

bool PermissionManager::isMachineAuthorized(const QString &rawIpAddress) const
{
    const QString ipAddress = network::displayAddress(rawIpAddress);
    if (!m_repository)
        return false; // Fail-closed : refuse par défaut si le repository n'est pas initialisé
    Q_UNUSED(ipAddress)
    return false;
}

bool PermissionManager::isMachineAuthorizedByCertificate(const QString &fingerprint) const
{
    if (!m_repository || fingerprint.trimmed().isEmpty()) return false;
    const auto machine = m_repository->findByCertificateFingerprint(fingerprint);
    // Seul le statut 'authorized' donne acces ; 'pending' et 'revoked'
    // restent refuses meme si l'ancien champ authorized trainait a true.
    return machine.has_value() && machine->status() == models::MachineStatus::Authorized;
}

bool PermissionManager::isMachineAuthorizedOrTrustedServer(const QString &fingerprint) const
{
    if (fingerprint.trimmed().isEmpty()) return false;
    // Ce certificat a deja ete accepte lors d'une connexion sortante vers
    // ce serveur. Il ne devient donc pas un client inconnu lorsque le poste
    // local est promu temporairement et que le serveur officiel revient.
    return isMachineAuthorizedByCertificate(fingerprint)
        || (m_trustedServers && m_trustedServers->isTrusted(fingerprint))
        || isAuthorizedByServer(fingerprint);
}

void PermissionManager::setServerAuthorizedFingerprints(const QStringList &fingerprints)
{
    QSet<QString> next;
    for (const QString &fingerprint : fingerprints) {
        const QString normalized = fingerprint.trimmed().toLower();
        if (!normalized.isEmpty())
            next.insert(normalized);
    }
    m_serverAuthorized = next;
}

void PermissionManager::clearServerAuthorizedFingerprints()
{
    m_serverAuthorized.clear();
}

bool PermissionManager::isAuthorizedByServer(const QString &fingerprint) const
{
    const QString normalized = fingerprint.trimmed().toLower();
    return !normalized.isEmpty() && m_serverAuthorized.contains(normalized);
}

QStringList PermissionManager::authorizedFingerprintsForPeers() const
{
    QSet<QString> all = m_serverAuthorized;
    if (m_repository) {
        for (const models::AuthorizedMachine &machine : m_repository->findAuthorized()) {
            const QString fingerprint = machine.certificateFingerprint().trimmed().toLower();
            if (!fingerprint.isEmpty() && machine.status() == models::MachineStatus::Authorized)
                all.insert(fingerprint);
        }
    }
    QStringList out = all.values();
    out.sort();
    return out;
}

QStringList PermissionManager::trustedServerFingerprints() const
{
    return m_trustedServers ? m_trustedServers->trustedFingerprints() : QStringList();
}

void PermissionManager::setVouchedServerFingerprints(const QStringList &fingerprints)
{
    QSet<QString> next;
    for (const QString &fingerprint : fingerprints) {
        const QString normalized = fingerprint.trimmed().toLower();
        if (!normalized.isEmpty())
            next.insert(normalized);
    }
    m_vouchedServers = next;
}

bool PermissionManager::isVouchedServer(const QString &fingerprint) const
{
    const QString normalized = fingerprint.trimmed().toLower();
    return !normalized.isEmpty() && m_vouchedServers.contains(normalized);
}

bool PermissionManager::adoptTempServerAuthorization(const QString &fingerprint, const QString &machineUuid,
                                                     const QString &hostname, const QString &rawIpAddress,
                                                     std::optional<int> authorizedBy, const QString &reason)
{
    const QString ipAddress = network::displayAddress(rawIpAddress);
    if (!m_repository || fingerprint.trimmed().isEmpty()) return false;
    const auto existing = m_repository->findByCertificateFingerprint(fingerprint);
    // Une decision deja prise ici (autorisation ou revocation) fait foi.
    if (existing.has_value() && !existing->isPending())
        return false;
    return authorizeMachineByCertificate(fingerprint, machineUuid, hostname, ipAddress,
                                         authorizedBy, reason);
}

bool PermissionManager::hasTrustedServer() const
{
    return m_trustedServers && m_trustedServers->hasAnyTrusted();
}

bool PermissionManager::isTrustedServer(const QString &fingerprint) const
{
    return !fingerprint.trimmed().isEmpty() && m_trustedServers && m_trustedServers->isTrusted(fingerprint);
}

void PermissionManager::recordMachineSeen(const QString &fingerprint, const QString &rawIpAddress)
{
    const QString ipAddress = network::displayAddress(rawIpAddress);
    if (!m_repository || fingerprint.trimmed().isEmpty()) return;
    m_repository->updateLastSeen(fingerprint, ipAddress);
}

void PermissionManager::recordMachineIdentity(const QString &fingerprint, const QString &hostname,
                                              const QString &userUuid)
{
    if (!m_repository || fingerprint.trimmed().isEmpty()) return;
    if (m_repository->updateIdentity(fingerprint, hostname, userUuid))
        emit machineIdentityChanged();
}

bool PermissionManager::trustRemoteServerCertificate(const QString &fingerprint,
                                                      const QString &rawIpAddress)
{
    const QString ipAddress = network::displayAddress(rawIpAddress);
    if (!m_trustedServers || fingerprint.trimmed().isEmpty()) return false;
    if (m_trustedServers->isTrusted(fingerprint)) {
        // setTrusted rafraichit l'adresse et la date sans changer la decision.
        m_trustedServers->setTrusted(fingerprint, ipAddress, QString());
        return true;
    }

    // CORRECTIF (reconciliation TEMP_SERVER bloquee indefiniment sans
    // action humaine) : TrustedServerRepository (liste "je fais confiance
    // a ce serveur en tant que client") est une liste INDEPENDANTE de
    // AuthorizedMachineRepository (liste "cette machine est autorisee sur
    // le reseau", geree par l'admin). Un poste qui joue habituellement le
    // role de Server officiel n'agit jamais comme client sortant, donc sa
    // TrustedServerRepository locale reste vide -- jusqu'au jour ou il doit
    // reconcilier avec un pair devenu TEMP_SERVER, ce qui exige alors une
    // approbation manuelle que personne n'anticipe (l'echec initial se
    // produit typiquement sans utilisateur present pour cliquer "approuver").
    // Si la machine distante a deja franchi la porte de securite
    // principale (autorisee par un admin dans AuthorizedMachineRepository),
    // exiger une SECONDE approbation manuelle pour le meme role de
    // confiance n'ajoute rien cote securite -- on l'approuve donc
    // automatiquement ici, sans intervention humaine. Une machine non
    // autorisee (inconnue du reseau) reste, elle, bloquee comme avant.
    if (isMachineAuthorizedByCertificate(fingerprint)) {
        return m_trustedServers->setTrusted(fingerprint, ipAddress, QStringLiteral("Machine deja autorisee"));
    }

    // Meme raisonnement pour une machine que le serveur officiel declare
    // autorisee (liste "authorized_peers") : c'est typiquement le client elu
    // serveur de secours pendant une panne. Sans cela, les autres clients
    // rejetaient son annonce, relancaient une election et se promouvaient a
    // leur tour : plusieurs serveurs de secours qui se refusaient entre eux.
    // Pas d'epinglage dans TrustedServers : la confiance dure tant que la
    // liste du serveur contient cette machine (une revocation reste effective).
    if (isAuthorizedByServer(fingerprint))
        return true;

    // Serveur designe par le serveur actif (champ "servers" de
    // "authorized_peers") : c'est le serveur officiel transmis par un serveur
    // de secours a un poste arrive pendant la panne. Sans cela, ce poste
    // refusait le serveur officiel a son retour et se promouvait lui-meme.
    // Epingle (il redevient le serveur habituel), sauf revocation locale.
    if (isVouchedServer(fingerprint)
        && m_trustedServers->statusForFingerprint(fingerprint).value_or(QString()) != QStringLiteral("revoked")) {
        return m_trustedServers->setTrusted(fingerprint, ipAddress, QString());
    }

    // Le serveur inconnu est visible localement dans TrustedServers, sans
    // declencher machineChanged : ce signal concerne exclusivement la
    // politique d'admission du serveur et ne doit jamais etre diffuse.
    m_trustedServers->registerPending(fingerprint, ipAddress, QStringLiteral("Serveur distant"));
    return false;
}

bool PermissionManager::approveServerCertificate(const QString &fingerprint,
                                                  const QString &rawIpAddress,
                                                  const QString &hostname)
{
    const QString ipAddress = network::displayAddress(rawIpAddress);
    return m_trustedServers
        && m_trustedServers->setTrusted(fingerprint, ipAddress, hostname);
}

bool PermissionManager::revokeServerCertificate(const QString &fingerprint,
                                                 const QString &reason)
{
    return m_trustedServers && m_trustedServers->revoke(fingerprint, reason);
}

bool PermissionManager::registerPendingMachineByCertificate(const QString &fingerprint,
                                                             const QString &rawIpAddress,
                                                             const QString &hostname)
{
    const QString ipAddress = network::displayAddress(rawIpAddress);
    if (!m_repository || fingerprint.trimmed().isEmpty()) return false;

    const bool alreadyKnown = m_repository->findByCertificateFingerprint(fingerprint).has_value();
    const bool ok = m_repository->registerPendingByCertificate(
        fingerprint, ipAddress, hostname,
        QStringLiteral("Machine détectée — autorisation requise"));
    if (ok && !alreadyKnown) {
        const auto saved = m_repository->findByCertificateFingerprint(fingerprint);
        if (saved) emit machineChanged(*saved);
    }
    return ok;
}

std::optional<models::AuthorizedMachine> PermissionManager::findMachineByCertificateFingerprint(const QString &fingerprint) const
{
    if (!m_repository) return std::nullopt;
    return m_repository->findByCertificateFingerprint(fingerprint);
}

bool PermissionManager::revokeMachine(const QString &rawIpAddress, int revokedBy, const QString &reason)
{
    const QString ipAddress = network::displayAddress(rawIpAddress);
    if (!m_repository)
        return false;
    const bool ok = m_repository->revokeByIpAddress(ipAddress, revokedBy, reason);
    if (ok) { auto machine = m_repository->findByIpAddress(ipAddress); if (machine) emit machineChanged(*machine); }
    return ok;
}

bool PermissionManager::revokeMachineByCertificate(const QString &fingerprint,
                                                   int revokedBy,
                                                   const QString &reason)
{
    if (!m_repository || fingerprint.trimmed().isEmpty())
        return false;

    const bool ok = m_repository->setAuthorizationByCertificate(
        fingerprint,
        false,
        revokedBy,
        reason
    );

    if (ok) {
        auto machine = m_repository->findByCertificateFingerprint(fingerprint);
        if (machine) {
            emit machineChanged(*machine);
        }
    }

    return ok;
}

bool PermissionManager::authorizeExistingMachineByCertificate(const QString &fingerprint,
                                                              int authorizedBy,
                                                              const QString &reason)
{
    if (!m_repository || fingerprint.trimmed().isEmpty())
        return false;

    const bool ok = m_repository->setAuthorizationByCertificate(
        fingerprint,
        true,
        authorizedBy,
        reason
    );

    if (ok) {
        auto machine = m_repository->findByCertificateFingerprint(fingerprint);
        if (machine) {
            emit machineChanged(*machine);
        }
    }

    return ok;
}

bool PermissionManager::authorizeMachine(const QString &rawIpAddress, int authorizedBy, const QString &reason)
{
    const QString ipAddress = network::displayAddress(rawIpAddress);
    if (!m_repository)
        return false;
    const bool ok = m_repository->authorizeByIpAddress(ipAddress, authorizedBy, reason);
    if (ok) { auto machine = m_repository->findByIpAddress(ipAddress); if (machine) emit machineChanged(*machine); }
    return ok;
}

bool PermissionManager::removeMachine(int id)
{
    if (!m_repository)
        return false;

    const bool ok = m_repository->remove(id);
    if (ok) emit machineRemoved(id);
    return ok;
}

bool PermissionManager::authorizeMachineByCertificate(const QString &fingerprint, const QString &machineUuid,
                                                      const QString &hostname, const QString &rawIpAddress,
                                                      std::optional<int> authorizedBy, const QString &reason)
{
    const QString ipAddress = network::displayAddress(rawIpAddress);
    if (!m_repository || fingerprint.trimmed().isEmpty()) return false;
    models::AuthorizedMachine machine;
    machine.setUuid(machineUuid);
    machine.setCertificateFingerprint(fingerprint.toLower());
    machine.setHostname(hostname);
    machine.setIpAddress(ipAddress);
    machine.setLastIpAddress(ipAddress);
    machine.setStatus(models::MachineStatus::Authorized);
    machine.setAddedBy(authorizedBy);
    machine.setReason(reason);
    const auto existing = m_repository->findByCertificateFingerprint(fingerprint);
    bool ok = false;
    if (existing.has_value()) {
        machine.setId(existing->id());
        ok = m_repository->update(machine);
    } else {
        ok = m_repository->create(machine) >= 0;
    }
    if (ok) {
        const auto saved = m_repository->findByCertificateFingerprint(fingerprint);
        if (saved) emit machineChanged(*saved);
    }
    return ok;
}

std::vector<models::AuthorizedMachine> PermissionManager::getAllMachines() const
{
    if (!m_repository)
        return {};
    return m_repository->findAll();
}

int PermissionManager::pendingClientCount() const
{
    if (!m_repository) return 0;
    int count = 0;
    for (const auto &client : m_repository->findAll()) {
        if (client.isPending()) ++count;
    }
    return count;
}

database::DatabaseManager* PermissionManager::databaseManager() const
{
    return m_dbManager;
}

} // namespace core
