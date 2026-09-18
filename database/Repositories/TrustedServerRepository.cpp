#include "TrustedServerRepository.h"

#include <QSqlError>
#include <QSqlQuery>

namespace database {

TrustedServerRepository::TrustedServerRepository(QSqlDatabase database)
    : m_db(std::move(database))
{
}

std::optional<QString> TrustedServerRepository::statusForFingerprint(const QString &fingerprint) const
{
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral("SELECT status FROM TrustedServers WHERE certificate_fingerprint = :fingerprint"));
    query.bindValue(QStringLiteral(":fingerprint"), fingerprint.trimmed().toLower());
    if (!query.exec()) { m_lastError = query.lastError().text(); return std::nullopt; }
    if (!query.next()) return std::nullopt;
    return query.value(0).toString();
}

bool TrustedServerRepository::registerPending(const QString &fingerprint, const QString &ipAddress,
                                              const QString &hostname)
{
    const QString normalized = fingerprint.trimmed().toLower();
    if (normalized.isEmpty()) return false;
    if (statusForFingerprint(normalized).has_value()) {
        QSqlQuery update(m_db);
        update.prepare(QStringLiteral("UPDATE TrustedServers SET ip_address=:ip, last_ip_address=:ip, last_seen_at=datetime('now') WHERE certificate_fingerprint=:fingerprint"));
        update.bindValue(QStringLiteral(":ip"), ipAddress);
        update.bindValue(QStringLiteral(":fingerprint"), normalized);
        if (!update.exec()) { m_lastError = update.lastError().text(); return false; }
        return true;
    }
    QSqlQuery insert(m_db);
    insert.prepare(QStringLiteral("INSERT INTO TrustedServers (certificate_fingerprint, ip_address, last_ip_address, hostname, status, reason) VALUES (:fingerprint,:ip,:ip,:hostname,'pending','Certificat serveur inconnu : approbation locale requise')"));
    insert.bindValue(QStringLiteral(":fingerprint"), normalized);
    insert.bindValue(QStringLiteral(":ip"), ipAddress);
    insert.bindValue(QStringLiteral(":hostname"), hostname);
    if (!insert.exec()) { m_lastError = insert.lastError().text(); return false; }
    return true;
}

bool TrustedServerRepository::setTrusted(const QString &fingerprint, const QString &ipAddress,
                                         const QString &hostname)
{
    const QString normalized = fingerprint.trimmed().toLower();
    if (normalized.isEmpty()) return false;
    if (!registerPending(normalized, ipAddress, hostname))
        return false;
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral("UPDATE TrustedServers SET status='authorized', ip_address=:ip, last_ip_address=:ip, hostname=COALESCE(NULLIF(:hostname,''), hostname), last_seen_at=datetime('now'), reason='Serveur approuve localement' WHERE certificate_fingerprint=:fingerprint"));
    query.bindValue(QStringLiteral(":ip"), ipAddress);
    query.bindValue(QStringLiteral(":hostname"), hostname);
    query.bindValue(QStringLiteral(":fingerprint"), normalized);
    if (!query.exec()) { m_lastError = query.lastError().text(); return false; }
    return query.numRowsAffected() > 0;
}

bool TrustedServerRepository::revoke(const QString &fingerprint, const QString &reason)
{
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral("UPDATE TrustedServers SET status='revoked', reason=:reason, last_seen_at=datetime('now') WHERE certificate_fingerprint=:fingerprint"));
    query.bindValue(QStringLiteral(":reason"), reason);
    query.bindValue(QStringLiteral(":fingerprint"), fingerprint.trimmed().toLower());
    if (!query.exec()) { m_lastError = query.lastError().text(); return false; }
    return query.numRowsAffected() > 0;
}

bool TrustedServerRepository::isTrusted(const QString &fingerprint) const
{
    const auto status = statusForFingerprint(fingerprint);
    return status.has_value() && *status == QStringLiteral("authorized");
}

QString TrustedServerRepository::lastError() const { return m_lastError; }

} // namespace database
