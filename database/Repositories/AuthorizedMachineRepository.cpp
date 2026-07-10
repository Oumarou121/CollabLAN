#include "AuthorizedMachineRepository.h"

#include <QSqlError>
#include <QSqlQuery>
#include <QVariant>
#include <QDateTime>

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
    machine.setIpAddress(query.value(QStringLiteral("ip_address")).toString());
    machine.setHostname(query.value(QStringLiteral("hostname")).toString());
    machine.setAuthorized(query.value(QStringLiteral("authorized")).toInt() != 0);
    
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
        "INSERT INTO AuthorizedMachines (ip_address, hostname, authorized, added_by, added_at, reason) "
        "VALUES (:ip_address, :hostname, :authorized, :added_by, :added_at, :reason)"));
    query.bindValue(QStringLiteral(":ip_address"), notNull(machine.ipAddress()));
    query.bindValue(QStringLiteral(":hostname"), notNull(machine.hostname()));
    query.bindValue(QStringLiteral(":authorized"), machine.isAuthorized() ? 1 : 0);
    
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
        "UPDATE AuthorizedMachines SET ip_address = :ip_address, hostname = :hostname, "
        "authorized = :authorized, added_by = :added_by, added_at = :added_at, reason = :reason "
        "WHERE id = :id"));
    query.bindValue(QStringLiteral(":ip_address"), notNull(machine.ipAddress()));
    query.bindValue(QStringLiteral(":hostname"), notNull(machine.hostname()));
    query.bindValue(QStringLiteral(":authorized"), machine.isAuthorized() ? 1 : 0);
    
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
    if (!query.exec(QStringLiteral("SELECT * FROM AuthorizedMachines WHERE authorized = 1 ORDER BY added_at DESC"))) {
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
    if (!query.exec(QStringLiteral("SELECT * FROM AuthorizedMachines WHERE authorized = 0 ORDER BY added_at DESC"))) {
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
        newMachine.setAuthorized(false);
        newMachine.setAddedBy(revokedBy);
        newMachine.setReason(reason);
        return create(newMachine) >= 0;
    }
    
    // Mettre à jour l'entrée existante
    machine->setAuthorized(false);
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
        newMachine.setAuthorized(true);
        newMachine.setAddedBy(authorizedBy);
        newMachine.setReason(reason);
        return create(newMachine) >= 0;
    }
    
    // Mettre à jour l'entrée existante
    machine->setAuthorized(true);
    machine->setAddedBy(authorizedBy);
    machine->setReason(reason);
    return update(*machine);
}

QString AuthorizedMachineRepository::lastError() const
{
    return m_lastError;
}

} // namespace database
