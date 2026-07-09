#ifndef CORE_PASSWORDHASHER_H
#define CORE_PASSWORDHASHER_H

#include <QString>

namespace core {

/**
 * @brief Hachage/verification des mots de passe des comptes locaux.
 *
 * Format de stockage (colonne `Users.password_hash`) : "<salt_hex>:<hash_hex>",
 * avec hash = SHA-256(salt + mot de passe). Le salt est genere aleatoirement
 * par utilisateur afin d'eviter les attaques par table arc-en-ciel.
 *
 * Note : ceci reste volontairement une dependance-free (Qt Core uniquement)
 * pour un prototype LAN. Le chiffrement des communications inter-postes
 * (TLS) est gere separement par network/Security.
 */
class PasswordHasher {
public:
    // Genere un salt aleatoire puis hash le mot de passe : a utiliser
    // lors de la creation d'un compte.
    static QString hash(const QString &password);

    // Verifie qu'un mot de passe correspond a un hash stocke au format
    // "<salt_hex>:<hash_hex>". Retourne false si le format est invalide.
    static bool verify(const QString &password, const QString &storedHash);

private:
    static QString computeHash(const QString &password, const QString &saltHex);
    static QString generateSaltHex();
};

} // namespace core

#endif // CORE_PASSWORDHASHER_H
