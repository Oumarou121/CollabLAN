#ifndef CORE_PASSWORDHASHER_H
#define CORE_PASSWORDHASHER_H

#include <QString>

namespace core {

/**
 * @brief Hachage des mots de passe et des jetons.
 *
 * Mots de passe : PBKDF2-HMAC-SHA256 (100 000 iterations, sel aleatoire par utilisateur stocke a
 * part dans models::User::passwordSalt), au format "pbkdf2$sha256$<iterations>$<hex>". Les
 * empreintes sont repliquees sur chaque poste (connexion locale hors ligne) : un hachage lent
 * rend une attaque par dictionnaire hors ligne beaucoup plus couteuse qu'un simple SHA-256.
 * Les anciennes empreintes (SHA-256 sale) restent acceptees et sont converties a la premiere
 * connexion reussie (needsRehash).
 *
 * Jetons de session (valeurs aleatoires de 128 bits, recherchees par empreinte) : hash(),
 * SHA-256 deterministe, suffisant pour une valeur deja impossible a deviner.
 */
class PasswordHasher {
public:
    static QString generateSalt();

    /// Empreinte d'un mot de passe (PBKDF2).
    static QString hashPassword(const QString &password, const QString &salt);

    /// Vrai si l'empreinte stockee utilise un ancien format (a regenerer apres connexion).
    static bool needsRehash(const QString &storedHash);

    /// SHA-256 sale, deterministe : jetons de session et anciennes empreintes de mots de passe.
    static QString hash(const QString &password, const QString &salt);

    /// Verifie un mot de passe contre une empreinte PBKDF2 ou ancienne (comparaison a temps constant).
    static bool verify(const QString &password, const QString &salt, const QString &expectedHash);
};

} // namespace core

#endif // CORE_PASSWORDHASHER_H
