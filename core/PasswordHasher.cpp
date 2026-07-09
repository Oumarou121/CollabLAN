#include "PasswordHasher.h"

#include <QCryptographicHash>
#include <QRandomGenerator>

namespace core {

namespace {
constexpr int kSaltByteLength = 16;
} // namespace

QString PasswordHasher::generateSalt()
{
    QByteArray salt(kSaltByteLength, Qt::Uninitialized);
    for (int i = 0; i < kSaltByteLength; ++i) {
        salt[i] = static_cast<char>(QRandomGenerator::global()->bounded(256));
    }
    return QString::fromLatin1(salt.toHex());
}

QString PasswordHasher::hash(const QString &password, const QString &salt)
{
    const QByteArray data = (salt + password).toUtf8();
    return QString::fromLatin1(QCryptographicHash::hash(data, QCryptographicHash::Sha256).toHex());
}

bool PasswordHasher::verify(const QString &password, const QString &salt, const QString &expectedHash)
{
    return hash(password, salt) == expectedHash;
}

} // namespace core