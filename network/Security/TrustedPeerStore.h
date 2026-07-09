#ifndef NETWORK_TRUSTEDPEERSTORE_H
#define NETWORK_TRUSTEDPEERSTORE_H

#include <QString>
#include <QStringList>
#include <QDateTime>
#include <QHash>

namespace network {

/**
 * @brief Entree de la liste des machines autorisees a etablir une session TLS.
 */
struct TrustedPeer {
    QString fingerprintSha256; ///< Empreinte SHA-256 (hex) du certificat X.509 du poste distant
    QString label;             ///< Nom lisible optionnel (hostname, alias...)
    QDateTime trustedAt;       ///< Date d'ajout a la liste des machines autorisees
};

/**
 * @brief Liste blanche persistante des machines autorisees du reseau local.
 *
 * Un poste distant est considere "autorise" (voir issue #12) si l'empreinte
 * SHA-256 de son certificat presente lors de la poignee de main TLS figure
 * dans cette liste. La liste est stockee en JSON dans le repertoire de
 * securite du poste (le meme que celui utilise par SecurityService) et
 * survit donc aux redemarrages de l'application.
 *
 * Remarque : l'ajout d'un poste a la liste (premiere confiance accordee)
 * reste une decision explicite de l'utilisateur/administrateur (ex. via
 * l'UI ou un appel a trust()) ; ce composant ne fait aucune confiance
 * automatique (pas de "trust on first use" implicite).
 */
class TrustedPeerStore
{
public:
    explicit TrustedPeerStore(const QString &storageDir);

    /// Charge la liste depuis le disque (silencieux si le fichier n'existe pas encore).
    bool load();

    /// Sauvegarde la liste courante sur le disque.
    bool save() const;

    /// Chemin du fichier JSON utilise pour la persistance.
    QString filePath() const;

    /// true si le fingerprint fourni fait partie des machines autorisees.
    bool isTrusted(const QString &fingerprintSha256) const;

    /// Ajoute (ou met a jour le label d') un poste a la liste des machines autorisees.
    void trust(const QString &fingerprintSha256, const QString &label = QString());

    /// Retire un poste de la liste des machines autorisees.
    void revoke(const QString &fingerprintSha256);

    /// Liste des fingerprints actuellement autorises.
    QStringList fingerprints() const;

    /// Details complets des postes autorises.
    QList<TrustedPeer> peers() const;

private:
    QString m_storageDir;
    QHash<QString, TrustedPeer> m_peers; // cle = fingerprint normalise (minuscules)
};

} // namespace network

#endif // NETWORK_TRUSTEDPEERSTORE_H
