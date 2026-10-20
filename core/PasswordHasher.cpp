#include "PasswordHasher.h"

#include <QCryptographicHash>
#include <QRandomGenerator>
#include <QStringList>

#include <openssl/evp.h>

namespace core {

namespace {
constexpr int kSaltByteLength = 16;
constexpr int kPbkdf2Iterations = 100000;
constexpr int kPbkdf2KeyLength = 32;
const QString kPbkdf2Prefix = QStringLiteral("pbkdf2$sha256$");

// PBKDF2-HMAC-SHA256 standard (OpenSSL, deja utilise pour TLS : rapide meme en build Debug).
QByteArray pbkdf2(const QString &password, const QString &salt, int iterations)
{
    const QByteArray pass = password.toUtf8();
    const QByteArray saltBytes = salt.toUtf8();
    QByteArray key(kPbkdf2KeyLength, Qt::Uninitialized);
    if (PKCS5_PBKDF2_HMAC(pass.constData(), static_cast<int>(pass.size()),
                          reinterpret_cast<const unsigned char *>(saltBytes.constData()), static_cast<int>(saltBytes.size()),
                          iterations, EVP_sha256(), kPbkdf2KeyLength,
                          reinterpret_cast<unsigned char *>(key.data())) != 1)
        return QByteArray(); // echec : aucune empreinte ne correspondra
    return key;
}

bool constantTimeEquals(const QByteArray &a, const QByteArray &b)
{
    if (a.size() != b.size())
        return false;
    int diff = 0;
    for (int i = 0; i < a.size(); ++i)
        diff |= (a.at(i) ^ b.at(i));
    return diff == 0;
}
} // namespace

QString PasswordHasher::generateSalt()
{
    QByteArray salt(kSaltByteLength, Qt::Uninitialized);
    for (int i = 0; i < kSaltByteLength; ++i) {
        salt[i] = static_cast<char>(QRandomGenerator::system()->bounded(256));
    }
    return QString::fromLatin1(salt.toHex());
}

QString PasswordHasher::hashPassword(const QString &password, const QString &salt)
{
    return kPbkdf2Prefix + QString::number(kPbkdf2Iterations) + QLatin1Char('$')
        + QString::fromLatin1(pbkdf2(password, salt, kPbkdf2Iterations).toHex());
}

bool PasswordHasher::needsRehash(const QString &storedHash)
{
    if (!storedHash.startsWith(kPbkdf2Prefix))
        return true;
    const QStringList parts = storedHash.split(QLatin1Char('$'));
    return parts.size() != 4 || parts.at(2).toInt() < kPbkdf2Iterations;
}

QString PasswordHasher::hash(const QString &password, const QString &salt)
{
    const QByteArray data = (salt + password).toUtf8();
    return QString::fromLatin1(QCryptographicHash::hash(data, QCryptographicHash::Sha256).toHex());
}

bool PasswordHasher::verify(const QString &password, const QString &salt, const QString &expectedHash)
{
    if (expectedHash.startsWith(kPbkdf2Prefix)) {
        const QStringList parts = expectedHash.split(QLatin1Char('$'));
        bool ok = false;
        const int iterations = parts.size() == 4 ? parts.at(2).toInt(&ok) : 0;
        // Borne haute : une valeur aberrante recue du reseau ne doit pas bloquer le poste.
        if (!ok || iterations < 1 || iterations > 10000000)
            return false;
        return constantTimeEquals(pbkdf2(password, salt, iterations).toHex(), parts.at(3).toLatin1());
    }
    return constantTimeEquals(hash(password, salt).toLatin1(), expectedHash.toLatin1());
}

} // namespace core
