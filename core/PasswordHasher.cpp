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
    // Comparaison en temps constant pour eviter une fuite d'information via
    // le temps de reponse (attaque par canal auxiliaire) : QString::operator==
    // s'arrete au premier octet different, ce qui n'est pas le cas ici.
    const QByteArray computed = hash(password, salt).toLatin1();
    const QByteArray expected = expectedHash.toLatin1();

    if (computed.size() != expected.size())
        return false;

    int diff = 0;
    for (int i = 0; i < computed.size(); ++i)
        diff |= (computed.at(i) ^ expected.at(i));

    return diff == 0;
}

} // namespace core