#include "AuthorizedMachineRepository.h"

#include <QSqlError>
#include <QSqlQuery>
#include <QVariant>
#include <QDateTime>
#include <QUuid>

namespace database {

namespace {
QString notNull(const QString &value)
{
    return value.isNull() ? QStringLiteral("") : value;
}
}

AuthorizedMachineRepository::AuthorizedMachineRepository(QSqlDatabase database)
    : m_db(std::move(database))
{
}

AuthorizedMachineRepository::~AuthorizedMachineRepository() = default;

models::AuthorizedMachine AuthorizedMachineRepository::machineFromQuery(const QSqlQuery &query) const
{
    models::AuthorizedMachine machine;
    machine.setId(query.value(QStringLiteral("id")).toInt());
    machine.setUuid(query.value(QStringLiteral("machine_uuid")).toString());
    machine.setCertificateFingerprint(query.value(QStringLiteral("certificate_fingerprint")).toString());
    machine.setIpAddress(query.value(QStringLiteral("ip_address")).toString());
    machine.setLastIpAddress(query.value(QStringLiteral("last_ip_address")).toString());
    machine.setHostname(query.value(QStringLiteral("hostname")).toString());
    machine.setAuthorized(query.value(QStringLiteral("authorized")).toInt() != 0);
    const QString status = query.value(QStringLiteral("status")).toString();
    machine.setStatus(status.isEmpty()
        ? (machine.isAuthorized() ? models::MachineStatus::Authorized : models::MachineStatus::Revoked)
        : status);
    
    const int addedBy = query.value(QStringLiteral("added_by")).toInt();
    if (!query.isNull(QStringLiteral("added_by"))) {
        machine.setAddedBy(addedBy);
    }
    
    machine.setAddedAt(QDateTime::fromString(query.value(QStringLiteral("added_at")).toString(), Qt::ISODate));
    machine.setReason(query.value(QStringLiteral("reason")).toString());
    return machine;
}

int AuthorizedMachineRepository::create(const models::AuthorizedMachine &machine)
{
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral(
        "INSERT INTO AuthorizedMachines (machine_uuid, certificate_fingerprint, ip_address, last_ip_address, hostname, authorized, status, added_by, added_at, reason) "
        "VALUES (:machine_uuid, :certificate_fingerprint, :ip_address, :last_ip_address, :hostname, :authorized, :status, :added_by, :added_at, :reason)"));
    query.bindValue(QStringLiteral(":machine_uuid"), machine.uuid().isEmpty() ? QUuid::createUuid().toString(QUuid::WithoutBraces) : machine.uuid());
    query.bindValue(QStringLiteral(":ip_address"), notNull(machine.ipAddress()));
    query.bindValue(QStringLiteral(":certificate_fingerprint"), notNull(machine.certificateFingerprint()));
    query.bindValue(QStringLiteral(":last_ip_address"), notNull(machine.lastIpAddress()));
    query.bindValue(QStringLiteral(":hostname"), notNull(machine.hostname()));
    query.bindValue(QStringLiteral(":authorized"), machine.isAuthorized() ? 1 : 0);
    query.bindValue(QStringLiteral(":status"), machine.status());
    
    if (machine.addedBy().has_value()) {
        query.bindValue(QStringLiteral(":added_by"), machine.addedBy().value());
    } else {
        query.bindValue(QStringLiteral(":added_by"), QVariant());
    }
    
    query.bindValue(QStringLiteral(":added_at"), machine.addedAt().toString(Qt::ISODate));
    query.bindValue(QStringLiteral(":reason"), notNull(machine.reason()));

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return -1;
    }
    return query.lastInsertId().toInt();
}

bool AuthorizedMachineRepository::update(const models::AuthorizedMachine &machine)
{
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral(
        "UPDATE AuthorizedMachines SET machine_uuid = :machine_uuid, certificate_fingerprint = :certificate_fingerprint, ip_address = :ip_address, last_ip_address = :last_ip_address, hostname = :hostname, "
        "authorized = :authorized, status = :status, added_by = :added_by, added_at = :added_at, reason = :reason "
        "WHERE id = :id"));
    query.bindValue(QStringLiteral(":machine_uuid"), machine.uuid());
    query.bindValue(QStringLiteral(":certificate_fingerprint"), machine.certificateFingerprint());
    query.bindValue(QStringLiteral(":ip_address"), notNull(machine.ipAddress()));
    query.bindValue(QStringLiteral(":last_ip_address"), notNull(machine.lastIpAddress()));
    query.bindValue(QStringLiteral(":hostname"), notNull(machine.hostname()));
    query.bindValue(QStringLiteral(":authorized"), machine.isAuthorized() ? 1 : 0);
    query.bindValue(QStringLiteral(":status"), machine.status());
    
    if (machine.addedBy().has_value()) {
        query.bindValue(QStringLiteral(":added_by"), machine.addedBy().value());
    } else {
        query.bindValue(QStringLiteral(":added_by"), QVariant());
    }
    
    query.bindValue(QStringLiteral(":added_at"), machine.addedAt().toString(Qt::ISODate));
    query.bindValue(QStringLiteral(":reason"), notNull(machine.reason()));
    query.bindValue(QStringLiteral(":id"), machine.id());

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return false;
    }
    return query.numRowsAffected() > 0;
}

bool AuthorizedMachineRepository::remove(int id)
{
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral("DELETE FROM AuthorizedMachines WHERE id = :id"));
    query.bindValue(QStringLiteral(":id"), id);

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return false;
    }
    return query.numRowsAffected() > 0;
}

bool AuthorizedMachineRepository::removeByUuidOrCertificate(const QString &uuid, const QString &fingerprint)
{
    const QString normalizedUuid = uuid.trimmed();
    const QString normalizedFingerprint = fingerprint.trimmed().toLower();
    if (normalizedUuid.isEmpty() && normalizedFingerprint.isEmpty()) {
        m_lastError = QStringLiteral("Suppression impossible : UUID et empreinte absents");
        return false;
    }

    QSqlQuery query(m_db);
    query.prepare(QStringLiteral(
        "DELETE FROM AuthorizedMachines "
        "WHERE (:uuid <> '' AND machine_uuid = :uuid) "
        "   OR (:fingerprint <> '' AND certificate_fingerprint = :fingerprint)"));
    query.bindValue(QStringLiteral(":uuid"), normalizedUuid);
    query.bindValue(QStringLiteral(":fingerprint"), normalizedFingerprint);

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return false;
    }
    return query.numRowsAffected() > 0;
}

std::optional<models::AuthorizedMachine> AuthorizedMachineRepository::findByIpAddress(const QString &ipAddress) const
{
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral("SELECT * FROM AuthorizedMachines WHERE ip_address = :ip_address"));
    query.bindValue(QStringLiteral(":ip_address"), ipAddress);

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return std::nullopt;
    }
    if (!query.next()) {
        return std::nullopt;
    }
    return machineFromQuery(query);
}

std::optional<models::AuthorizedMachine> AuthorizedMachineRepository::findByUuid(const QString &uuid) const
{
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral("SELECT * FROM AuthorizedMachines WHERE machine_uuid = :uuid"));
    query.bindValue(QStringLiteral(":uuid"), uuid);
    if (!query.exec()) { m_lastError = query.lastError().text(); return std::nullopt; }
    if (!query.next()) return std::nullopt;
    return machineFromQuery(query);
}

std::optional<models::AuthorizedMachine> AuthorizedMachineRepository::findByCertificateFingerprint(const QString &fingerprint) const
{
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral("SELECT * FROM AuthorizedMachines WHERE certificate_fingerprint = :fingerprint"));
    query.bindValue(QStringLiteral(":fingerprint"), fingerprint.toLower());
    if (!query.exec()) { m_lastError = query.lastError().text(); return std::nullopt; }
    if (!query.next()) return std::nullopt;
    return machineFromQuery(query);
}

bool AuthorizedMachineRepository::updateLastSeen(const QString &fingerprint, const QString &ipAddress)
{
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral("UPDATE AuthorizedMachines SET last_ip_address = :ip, ip_address = :ip WHERE certificate_fingerprint = :fingerprint"));
    query.bindValue(QStringLiteral(":ip"), ipAddress);
    query.bindValue(QStringLiteral(":fingerprint"), fingerprint.toLower());
    if (!query.exec()) { m_lastError = query.lastError().text(); return false; }
    return query.numRowsAffected() > 0;
}

bool AuthorizedMachineRepository::upsertRemote(const models::AuthorizedMachine &machine)
{
    const QString uuid = machine.uuid().trimmed();
    const QString fingerprint = machine.certificateFingerprint().trimmed().toLower();
    if (uuid.isEmpty() && fingerprint.isEmpty()) return false;

    std::optional<models::AuthorizedMachine> existing;
    if (!uuid.isEmpty()) existing = findByUuid(uuid);
    if (!existing.has_value() && !fingerprint.isEmpty())
        existing = findByCertificateFingerprint(fingerprint);

    if (existing.has_value()) {
        models::AuthorizedMachine updated = machine;
        updated.setId(existing->id());
        if (updated.uuid().trimmed().isEmpty()) updated.setUuid(existing->uuid());
        if (updated.certificateFingerprint().trimmed().isEmpty())
            updated.setCertificateFingerprint(existing->certificateFingerprint());
        return update(updated);
    }

    return create(machine) >= 0;
}

bool AuthorizedMachineRepository::setAuthorizationByCertificate(const QString &fingerprint,
                                                               bool authorized,
                                                               int changedBy,
                                                               const QString &reason)
{
    auto machine = findByCertificateFingerprint(fingerprint);
    if (!machine.has_value()) {
        m_lastError = QStringLiteral("Machine introuvable pour cette empreinte de certificat");
        return false;
    }

    machine->setStatus(authorized ? models::MachineStatus::Authorized : models::MachineStatus::Revoked);
    machine->setAddedBy(changedBy);
    machine->setReason(reason);
    return update(*machine);
}

bool AuthorizedMachineRepository::hasAnyAuthorizedMachine() const
{
    QSqlQuery query(m_db);
    if (!query.exec(QStringLiteral(
            "SELECT 1 FROM AuthorizedMachines WHERE status = 'authorized' LIMIT 1"))) {
        m_lastError = query.lastError().text();
        return false;
    }
    return query.next();
}

bool AuthorizedMachineRepository::registerPendingByCertificate(const QString &fingerprint,
                                                                const QString &ipAddress,
                                                                const QString &hostname,
                                                                const QString &reason)
{
    const QString normalizedFingerprint = fingerprint.trimmed().toLower();
    if (normalizedFingerprint.isEmpty()) {
        m_lastError = QStringLiteral("Empreinte de certificat absente");
        return false;
    }

    auto existing = findByCertificateFingerprint(normalizedFingerprint);
    if (existing.has_value()) {
        // Une machine deja connue (authorized/revoked/pending) n'est jamais
        // re-degradee en pending automatiquement : seule sa derniere IP vue
        // est rafraichie.
        return updateLastSeen(normalizedFingerprint, ipAddress);
    }

    models::AuthorizedMachine machine;
    machine.setCertificateFingerprint(normalizedFingerprint);
    machine.setIpAddress(ipAddress);
    machine.setLastIpAddress(ipAddress);
    machine.setHostname(hostname);
    machine.setStatus(models::MachineStatus::Pending);
    machine.setReason(reason.isEmpty()
        ? QStringLiteral("Machine détectée — autorisation requise")
        : reason);
    return create(machine) >= 0;
}

std::vector<models::AuthorizedMachine> AuthorizedMachineRepository::findAll() const
{
    std::vector<models::AuthorizedMachine> machines;

    QSqlQuery query(m_db);
    if (!query.exec(QStringLiteral("SELECT * FROM AuthorizedMachines ORDER BY added_at DESC"))) {
        m_lastError = query.lastError().text();
        return machines;
    }
    while (query.next()) {
        machines.push_back(machineFromQuery(query));
    }
    return machines;
}

std::vector<models::AuthorizedMachine> AuthorizedMachineRepository::findAuthorized() const
{
    std::vector<models::AuthorizedMachine> machines;

    QSqlQuery query(m_db);
    if (!query.exec(QStringLiteral("SELECT * FROM AuthorizedMachines WHERE status = 'authorized' ORDER BY added_at DESC"))) {
        m_lastError = query.lastError().text();
        return machines;
    }
    while (query.next()) {
        machines.push_back(machineFromQuery(query));
    }
    return machines;
}

std::vector<models::AuthorizedMachine> AuthorizedMachineRepository::findRevoked() const
{
    std::vector<models::AuthorizedMachine> machines;

    QSqlQuery query(m_db);
    if (!query.exec(QStringLiteral("SELECT * FROM AuthorizedMachines WHERE status = 'revoked' ORDER BY added_at DESC"))) {
        m_lastError = query.lastError().text();
        return machines;
    }
    while (query.next()) {
        machines.push_back(machineFromQuery(query));
    }
    return machines;
}

bool AuthorizedMachineRepository::isAuthorized(const QString &ipAddress) const
{
    const auto machine = findByIpAddress(ipAddress);
    // Si aucune restriction n'existe pour cette IP, elle est autorisée par défaut
    if (!machine.has_value()) {
        return true;
    }
    return machine->isAuthorized();
}

bool AuthorizedMachineRepository::revokeByIpAddress(const QString &ipAddress, int revokedBy, const QString &reason)
{
    auto machine = findByIpAddress(ipAddress);
    if (!machine.has_value()) {
        // Créer une nouvelle entrée révoquée
        models::AuthorizedMachine newMachine;
        newMachine.setIpAddress(ipAddress);
        newMachine.setStatus(models::MachineStatus::Revoked);
        newMachine.setAddedBy(revokedBy);
        newMachine.setReason(reason);
        return create(newMachine) >= 0;
    }
    
    // Mettre à jour l'entrée existante
    machine->setStatus(models::MachineStatus::Revoked);
    machine->setAddedBy(revokedBy);
    machine->setReason(reason);
    return update(*machine);
}

bool AuthorizedMachineRepository::authorizeByIpAddress(const QString &ipAddress, int authorizedBy, const QString &reason)
{
    auto machine = findByIpAddress(ipAddress);
    if (!machine.has_value()) {
        // Créer une nouvelle entrée autorisée
        models::AuthorizedMachine newMachine;
        newMachine.setIpAddress(ipAddress);
        newMachine.setStatus(models::MachineStatus::Authorized);
        newMachine.setAddedBy(authorizedBy);
        newMachine.setReason(reason);
        return create(newMachine) >= 0;
    }
    
    // Mettre à jour l'entrée existante
    machine->setStatus(models::MachineStatus::Authorized);
    machine->setAddedBy(authorizedBy);
    machine->setReason(reason);
    return update(*machine);
}

QString AuthorizedMachineRepository::lastError() const
{
    return m_lastError;
}

} // namespace database
