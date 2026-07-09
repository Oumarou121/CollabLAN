#ifndef NETWORK_SECURITYSERVICE_H
#define NETWORK_SECURITYSERVICE_H

#include <QString>
#include <QByteArray>
#include <QDateTime>

// Forward declarations OpenSSL (evite d'exposer <openssl/...> dans ce header).
typedef struct evp_pkey_st EVP_PKEY;
typedef struct x509_st X509;

namespace network {

/**
 * @brief Identite cryptographique locale (paire cle privee / certificat X.509).
 */
struct LocalIdentity {
    bool valid = false;           ///< true si cle + certificat charges/generes avec succes
    bool wasGenerated = false;    ///< true si une nouvelle paire a ete generee (false = chargee depuis le disque)
    QString subjectCommonName;    ///< CN du certificat (identifiant du poste)
    QString fingerprintSha256;    ///< Empreinte SHA-256 du certificat, hex, pour verification manuelle/pinning
    QDateTime notBefore;          ///< Debut de validite du certificat
    QDateTime notAfter;           ///< Fin de validite du certificat
};

/**
 * @brief Authentification et chiffrement des communications via OpenSSL.
 *
 * Au demarrage de l'application, chaque poste doit disposer d'une identite
 * cryptographique (paire cle privee / certificat X.509 auto-signe) utilisee
 * pour authentifier et chiffrer ses communications avec les autres postes
 * du reseau local (TLS sur les sockets TCP/WebSocket, DTLS pour WebRTC, etc.).
 *
 * Principe (voir issue #11) :
 *  - Au premier lancement (ou si les fichiers sont absents/corrompus), une
 *    nouvelle paire cle/certificat est generee et stockee localement.
 *  - Aux lancements suivants, la paire existante est chargee depuis le
 *    disque et reutilisee, tant qu'elle est valide (cle/certificat
 *    lisibles, certificat non expire, cle publique correspondant a la
 *    cle privee).
 *  - Les fichiers sont stockes dans le repertoire de donnees applicatif de
 *    l'utilisateur (QStandardPaths::AppDataLocation/security), avec des
 *    permissions restreintes au proprietaire pour la cle privee.
 */
class SecurityService
{
public:
    explicit SecurityService(const QString &storageDirOverride = QString());
    ~SecurityService();

    /// Charge l'identite existante si elle est valide, sinon en genere une nouvelle.
    /// Idempotent : peut etre appele plusieurs fois sans effet de bord.
    bool initialize();

    /// true si une identite valide (cle + certificat) est chargee en memoire.
    bool isReady() const;

    /// Informations publiques sur l'identite locale courante.
    LocalIdentity identity() const;

    /// Repertoire de stockage utilise pour la cle privee et le certificat.
    QString storageDir() const;

    /// Chemin du fichier de cle privee (PEM).
    QString privateKeyPath() const;

    /// Chemin du fichier de certificat (PEM).
    QString certificatePath() const;

    /// Certificat au format PEM (vide si aucune identite chargee).
    QByteArray certificatePem() const;

    /// Force la regeneration d'une nouvelle paire cle/certificat,
    /// meme si une identite valide existe deja sur le disque.
    bool regenerate();

    /// Nom commun (CN) utilise pour le certificat genere (hostname par defaut).
    QString subjectName() const;
    void setSubjectName(const QString &name);

    /// Duree de validite (en jours) d'un certificat nouvellement genere (3650 = 10 ans par defaut).
    int validityDays() const;
    void setValidityDays(int days);

private:
    bool loadExisting();
    bool generateAndStore();
    bool writePemFiles(EVP_PKEY *pkey, X509 *cert) const;
    void applyRestrictivePermissions(const QString &filePath) const;
    static bool isCertificateCurrentlyValid(X509 *cert);
    void refreshIdentityFromLoadedState(bool wasGenerated);
    void reset();

    QString m_storageDir;
    QString m_subjectName;
    int m_validityDays = 3650;

    EVP_PKEY *m_pkey = nullptr;
    X509 *m_cert = nullptr;

    LocalIdentity m_identity;
};

} // namespace network

#endif // NETWORK_SECURITYSERVICE_H
