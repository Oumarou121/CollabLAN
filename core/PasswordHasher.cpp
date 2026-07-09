#include "PasswordHasher.h"

#include <QCryptographicHash>
#include <QRandomGenerator>

namespace core {

namespace {
constexpr int kSaltBytes = 16;
const QChar kSeparator = QLatin1Char(':');
}

QString PasswordHasher::generateSaltHex()
{
    QByteArray salt;
    salt.resize(kSaltBytes);
    for (int i = 0; i < kSaltBytes; ++i) {
        salt[i] = static_cast<char>(QRandomGenerator::global()->bounded(256));
    }
    return QString::fromLatin1(salt.toHex());
}

QString PasswordHasher::computeHash(const QString &password, const QString &saltHex)
{
    const QByteArray payload = (saltHex + password).toUtf8();
    return QString::fromLatin1(QCryptographicHash::hash(payload, QCryptographicHash::Sha256).toHex());
}

QString PasswordHasher::hash(const QString &password)
{
    const QString saltHex = generateSaltHex();
    return saltHex + kSeparator + computeHash(password, saltHex);
}

bool PasswordHasher::verify(const QString &password, const QString &storedHash)
{
    const int separatorIndex = storedHash.indexOf(kSeparator);
    if (separatorIndex <= 0 || separatorIndex == storedHash.length() - 1) {
        return false;
    }

    const QString saltHex = storedHash.left(separatorIndex);
    const QString expectedHash = storedHash.mid(separatorIndex + 1);

    return computeHash(password, saltHex) == expectedHash;
}

} // namespace core
