#include "AuthorizedMachineRepository.h"

#include <QSqlError>
#include <QSqlQuery>
#include <QSqlRecord>
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
    // Enregistrement lu une fois par ligne : value(nom) le reconstruisait a chaque colonne.
    const QSqlRecord rec = query.record();
    models::AuthorizedMachine machine;
    machine.setId(query.value(rec.indexOf(QLatin1String("id"))).toInt());
    machine.setUuid(query.value(rec.indexOf(QLatin1String("machine_uuid"))).toString());
    machine.setCertificateFingerprint(query.value(rec.indexOf(QLatin1String("certificate_fingerprint"))).toString());
    machine.setIpAddress(query.value(rec.indexOf(QLatin1String("ip_address"))).toString());
    machine.setLastIpAddress(query.value(rec.indexOf(QLatin1String("last_ip_address"))).toString());
    machine.setHostname(query.value(rec.indexOf(QLatin1String("hostname"))).toString());
    machine.setAuthorized(query.value(rec.indexOf(QLatin1String("authorized"))).toInt() != 0);
    const QString status = query.value(rec.indexOf(QLatin1String("status"))).toString();
    machine.setStatus(status.isEmpty()
        ? (machine.isAuthorized() ? models::MachineStatus::Authorized : models::MachineStatus::Revoked)
        : status);
    
    const int addedBy = query.value(rec.indexOf(QLatin1String("added_by"))).toInt();
    if (!query.isNull(QStringLiteral("added_by"))) {
        machine.setAddedBy(addedBy);
    }
    
    machine.setAddedAt(QDateTime::fromString(query.value(rec.indexOf(QLatin1String("added_at"))).toString(), Qt::ISODate));
    machine.setReason(query.value(rec.indexOf(QLatin1String("reason"))).toString());
    return machine;
}

int AuthorizedMachineRepository::create(const models::AuthorizedMachine &machine)
{
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral(
        "INSERT INTO AuthorizedClients (machine_uuid, certificate_fingerprint, ip_address, last_ip_address, hostname, authorized, status, added_by, added_at, reason) "
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
        "UPDATE AuthorizedClients SET machine_uuid = :machine_uuid, certificate_fingerprint = :certificate_fingerprint, ip_address = :ip_address, last_ip_address = :last_ip_address, hostname = :hostname, "
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
    query.prepare(QStringLiteral("DELETE FROM AuthorizedClients WHERE id = :id"));
    query.bindValue(QStringLiteral(":id"), id);

    if (!query.exec()) {
        m_lastError = query.lastError().text();
        return false;
    }
    return query.numRowsAffected() > 0;
}

std::optional<models::AuthorizedMachine> AuthorizedMachineRepository::findByIpAddress(const QString &ipAddress) const
{
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral("SELECT * FROM AuthorizedClients WHERE ip_address = :ip_address"));
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

std::optional<models::AuthorizedMachine> AuthorizedMachineRepository::findByCertificateFingerprint(const QString &fingerprint) const
{
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral("SELECT * FROM AuthorizedClients WHERE certificate_fingerprint = :fingerprint"));
    query.bindValue(QStringLiteral(":fingerprint"), fingerprint.toLower());
    if (!query.exec()) { m_lastError = query.lastError().text(); return std::nullopt; }
    if (!query.next()) return std::nullopt;
    return machineFromQuery(query);
}

bool AuthorizedMachineRepository::updateLastSeen(const QString &fingerprint, const QString &ipAddress)
{
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral("UPDATE AuthorizedClients SET last_ip_address = :ip, ip_address = :ip WHERE certificate_fingerprint = :fingerprint"));
    query.bindValue(QStringLiteral(":ip"), ipAddress);
    query.bindValue(QStringLiteral(":fingerprint"), fingerprint.toLower());
    if (!query.exec()) { m_lastError = query.lastError().text(); return false; }
    return query.numRowsAffected() > 0;
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
            "SELECT 1 FROM AuthorizedClients WHERE status = 'authorized' LIMIT 1"))) {
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
    if (!query.exec(QStringLiteral("SELECT * FROM AuthorizedClients ORDER BY added_at DESC"))) {
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
    if (!query.exec(QStringLiteral("SELECT * FROM AuthorizedClients WHERE status = 'authorized' ORDER BY added_at DESC"))) {
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
    if (!query.exec(QStringLiteral("SELECT * FROM AuthorizedClients WHERE status = 'revoked' ORDER BY added_at DESC"))) {
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
