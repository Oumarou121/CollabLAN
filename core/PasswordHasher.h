#ifndef CORE_PASSWORDHASHER_H
#define CORE_PASSWORDHASHER_H

#include <QString>

namespace core {

/**
 * @brief Hachage de mot de passe (SHA-256 sale).
 *
 * Le sel est genere aleatoirement par utilisateur et stocke a part
 * (models::User::passwordSalt) : deux utilisateurs avec le meme mot
 * de passe n'auront jamais le meme hash.
 */
class PasswordHasher {
public:
    static QString generateSalt();
    static QString hash(const QString &password, const QString &salt);
    static bool verify(const QString &password, const QString &salt, const QString &expectedHash);
};

} // namespace core

#endif // CORE_PASSWORDHASHER_H