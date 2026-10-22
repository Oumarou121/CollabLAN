#ifndef DATABASE_TRUSTEDSERVERREPOSITORY_H
#define DATABASE_TRUSTEDSERVERREPOSITORY_H

#include <QSqlDatabase>
#include <QString>
#include <QStringList>
#include <optional>

namespace database {

/** Stockage strictement local des certificats de serveurs approuves. */
class TrustedServerRepository
{
public:
    explicit TrustedServerRepository(QSqlDatabase database);

    std::optional<QString> statusForFingerprint(const QString &fingerprint) const;
    bool registerPending(const QString &fingerprint, const QString &ipAddress,
                         const QString &hostname);
    bool setTrusted(const QString &fingerprint, const QString &ipAddress,
                    const QString &hostname);
    bool revoke(const QString &fingerprint, const QString &reason = QString());
    bool isTrusted(const QString &fingerprint) const;
    /// Vrai si au moins un serveur est approuve sur ce poste.
    bool hasAnyTrusted() const;
    /// Empreintes des serveurs approuves (statut 'authorized').
    QStringList trustedFingerprints() const;
    QString lastError() const;

private:
    QSqlDatabase m_db;
    mutable QString m_lastError;
};

} // namespace database

#endif // DATABASE_TRUSTEDSERVERREPOSITORY_H
