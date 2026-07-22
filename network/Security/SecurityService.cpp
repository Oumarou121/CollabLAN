#include "SecurityService.h"
#include <QCryptographicHash>

#include <QStandardPaths>
#include <QDir>
#include <QFile>
#include <QFileDevice>
#include <QHostInfo>
#include <QDebug>

#include <openssl/evp.h>
#include <openssl/x509.h>
#include <openssl/pem.h>
#include <openssl/bio.h>
#include <openssl/rand.h>
#include <openssl/err.h>
#include <openssl/asn1.h>

namespace network {

namespace {
constexpr const char *kKeyFileName = "device.key.pem";
constexpr const char *kCertFileName = "device.cert.pem";
constexpr int kRsaKeyBits = 2048;

QString opensslLastError()
{
    unsigned long code = ERR_get_error();
    if (code == 0)
        return QStringLiteral("erreur OpenSSL inconnue");
    char buf[256];
    ERR_error_string_n(code, buf, sizeof(buf));
    return QString::fromLatin1(buf);
}

QDateTime asnTimeToQDateTime(const ASN1_TIME *asnTime)
{
    if (!asnTime)
        return QDateTime();

    tm tmStruct{};
    if (ASN1_TIME_to_tm(asnTime, &tmStruct) != 1)
        return QDateTime();

    QDate date(tmStruct.tm_year + 1900, tmStruct.tm_mon + 1, tmStruct.tm_mday);
    QTime time(tmStruct.tm_hour, tmStruct.tm_min, tmStruct.tm_sec);
    return QDateTime(date, time, Qt::UTC);
}

QString sha256FingerprintHex(X509 *cert)
{
    if (!cert)
        return QString();

    unsigned char digest[EVP_MAX_MD_SIZE];
    unsigned int digestLen = 0;
    if (X509_digest(cert, EVP_sha256(), digest, &digestLen) != 1)
        return QString();

    const QByteArray raw(reinterpret_cast<const char *>(digest), static_cast<int>(digestLen));
    return QString::fromLatin1(raw.toHex());
}
} // namespace

SecurityService::SecurityService(const QString &storageDirOverride)
{
    m_storageDir = !storageDirOverride.isEmpty()
        ? storageDirOverride
        : QDir(QStandardPaths::writableLocation(QStandardPaths::AppDataLocation))
              .filePath(QStringLiteral("security"));

    m_subjectName = QHostInfo::localHostName();
    if (m_subjectName.isEmpty())
        m_subjectName = QStringLiteral("collablan-device");
}

SecurityService::~SecurityService()
{
    reset();
}

QString SecurityService::certificateFingerprint(const QSslCertificate &certificate)
{
    if (certificate.isNull()) return QString();
    return QString::fromLatin1(certificate.digest(QCryptographicHash::Sha256).toHex());
}

void SecurityService::reset()
{
    if (m_pkey) {
        EVP_PKEY_free(m_pkey);
        m_pkey = nullptr;
    }
    if (m_cert) {
        X509_free(m_cert);
        m_cert = nullptr;
    }
    m_identity = LocalIdentity();
}

QString SecurityService::storageDir() const
{
    return m_storageDir;
}

QString SecurityService::privateKeyPath() const
{
    return QDir(m_storageDir).filePath(QString::fromLatin1(kKeyFileName));
}

QString SecurityService::certificatePath() const
{
    return QDir(m_storageDir).filePath(QString::fromLatin1(kCertFileName));
}

QString SecurityService::subjectName() const
{
    return m_subjectName;
}

void SecurityService::setSubjectName(const QString &name)
{
    if (!name.isEmpty())
        m_subjectName = name;
}

int SecurityService::validityDays() const
{
    return m_validityDays;
}

void SecurityService::setValidityDays(int days)
{
    if (days > 0)
        m_validityDays = days;
}

bool SecurityService::isReady() const
{
    return m_identity.valid;
}

LocalIdentity SecurityService::identity() const
{
    return m_identity;
}

QByteArray SecurityService::certificatePem() const
{
    if (!m_cert)
        return QByteArray();

    BIO *bio = BIO_new(BIO_s_mem());
    if (!bio)
        return QByteArray();

    QByteArray pem;
    if (PEM_write_bio_X509(bio, m_cert) == 1) {
        char *data = nullptr;
        const long len = BIO_get_mem_data(bio, &data);
        if (len > 0 && data)
            pem = QByteArray(data, static_cast<int>(len));
    }
    BIO_free(bio);
    return pem;
}

bool SecurityService::initialize()
{
    // Deja initialise avec une identite valide : rien a faire (idempotent).
    if (m_identity.valid)
        return true;

    QDir().mkpath(m_storageDir);

    // 1. Tenter de charger une identite existante.
    if (loadExisting()) {
        refreshIdentityFromLoadedState(/*wasGenerated=*/false);
        return true;
    }

    // 2. Sinon, generer et stocker une nouvelle identite.
    reset();
    if (!generateAndStore()) {
        qWarning() << "SecurityService: echec de generation de l'identite cryptographique locale.";
        return false;
    }

    refreshIdentityFromLoadedState(/*wasGenerated=*/true);
    return true;
}

bool SecurityService::regenerate()
{
    reset();
    if (!generateAndStore())
        return false;

    refreshIdentityFromLoadedState(/*wasGenerated=*/true);
    return true;
}

void SecurityService::refreshIdentityFromLoadedState(bool wasGenerated)
{
    LocalIdentity id;
    id.valid = (m_pkey != nullptr && m_cert != nullptr);
    id.wasGenerated = wasGenerated;

    if (id.valid) {
        char *subjectCStr = X509_NAME_oneline(X509_get_subject_name(m_cert), nullptr, 0);
        if (subjectCStr) {
            id.subjectCommonName = QString::fromUtf8(subjectCStr);
            OPENSSL_free(subjectCStr);
        }
        id.fingerprintSha256 = sha256FingerprintHex(m_cert);
        id.notBefore = asnTimeToQDateTime(X509_get0_notBefore(m_cert));
        id.notAfter = asnTimeToQDateTime(X509_get0_notAfter(m_cert));
    }

    m_identity = id;
}

bool SecurityService::isCertificateCurrentlyValid(X509 *cert)
{
    if (!cert)
        return false;

    // X509_cmp_current_time renvoie <0 si la date est passee, >0 si future/ok.
    const int notBeforeCmp = X509_cmp_current_time(X509_get0_notBefore(cert));
    const int notAfterCmp = X509_cmp_current_time(X509_get0_notAfter(cert));

    // notBefore doit etre dans le passe (cmp < 0) et notAfter dans le futur (cmp > 0).
    return notBeforeCmp < 0 && notAfterCmp > 0;
}

bool SecurityService::loadExisting()
{
    const QString keyPath = privateKeyPath();
    const QString certPath = certificatePath();

    if (!QFile::exists(keyPath) || !QFile::exists(certPath))
        return false;

    QFile keyFile(keyPath);
    QFile certFile(certPath);
    if (!keyFile.open(QIODevice::ReadOnly) || !certFile.open(QIODevice::ReadOnly))
        return false;

    const QByteArray keyData = keyFile.readAll();
    const QByteArray certData = certFile.readAll();
    keyFile.close();
    certFile.close();

    if (keyData.isEmpty() || certData.isEmpty())
        return false;

    BIO *keyBio = BIO_new_mem_buf(keyData.constData(), keyData.size());
    EVP_PKEY *pkey = keyBio ? PEM_read_bio_PrivateKey(keyBio, nullptr, nullptr, nullptr) : nullptr;
    if (keyBio)
        BIO_free(keyBio);

    BIO *certBio = BIO_new_mem_buf(certData.constData(), certData.size());
    X509 *cert = certBio ? PEM_read_bio_X509(certBio, nullptr, nullptr, nullptr) : nullptr;
    if (certBio)
        BIO_free(certBio);

    // Fichiers illisibles/corrompus -> on considere l'identite absente.
    if (!pkey || !cert) {
        if (pkey) EVP_PKEY_free(pkey);
        if (cert) X509_free(cert);
        qWarning() << "SecurityService: cle/certificat illisibles, une nouvelle identite sera generee.";
        return false;
    }

    // Certificat expire ou pas encore valide -> regeneration.
    if (!isCertificateCurrentlyValid(cert)) {
        EVP_PKEY_free(pkey);
        X509_free(cert);
        qWarning() << "SecurityService: certificat existant expire ou invalide, regeneration.";
        return false;
    }

    // La cle publique du certificat doit correspondre a la cle privee chargee.
    if (X509_check_private_key(cert, pkey) != 1) {
        EVP_PKEY_free(pkey);
        X509_free(cert);
        qWarning() << "SecurityService: la cle privee ne correspond pas au certificat, regeneration.";
        return false;
    }

    m_pkey = pkey;
    m_cert = cert;
    return true;
}

bool SecurityService::generateAndStore()
{
    // Generation de la paire de cles RSA 2048 bits (API OpenSSL 3.x).
    EVP_PKEY *pkey = EVP_RSA_gen(kRsaKeyBits);
    if (!pkey) {
        qWarning() << "SecurityService: EVP_RSA_gen a echoue:" << opensslLastError();
        return false;
    }

    X509 *cert = X509_new();
    if (!cert) {
        EVP_PKEY_free(pkey);
        return false;
    }

    // Numero de serie aleatoire (64 bits) pour eviter toute collision.
    unsigned char serialBytes[8];
    if (RAND_bytes(serialBytes, sizeof(serialBytes)) != 1) {
        X509_free(cert);
        EVP_PKEY_free(pkey);
        qWarning() << "SecurityService: generation du numero de serie impossible:" << opensslLastError();
        return false;
    }
    long serial = 0;
    for (unsigned char b : serialBytes)
        serial = (serial << 8) | (b & 0x7F); // reste positif
    ASN1_INTEGER_set(X509_get_serialNumber(cert), serial != 0 ? serial : 1);

    X509_set_version(cert, 2); // X.509 v3

    X509_gmtime_adj(X509_getm_notBefore(cert), 0);
    X509_gmtime_adj(X509_getm_notAfter(cert), static_cast<long>(m_validityDays) * 24 * 60 * 60);

    X509_set_pubkey(cert, pkey);

    X509_NAME *name = X509_NAME_new();
    if (!name) {
        X509_free(cert);
        EVP_PKEY_free(pkey);
        qWarning() << "SecurityService: X509_NAME_new a echoue:" << opensslLastError();
        return false;
    }

    const QByteArray cnUtf8 = m_subjectName.toUtf8();
    X509_NAME_add_entry_by_txt(name, "O", MBSTRING_ASC,
                                reinterpret_cast<const unsigned char *>("CollabLAN"), -1, -1, 0);
    X509_NAME_add_entry_by_txt(name, "CN", MBSTRING_ASC,
                                reinterpret_cast<const unsigned char *>(cnUtf8.constData()), -1, -1, 0);

    // Certificat auto-signe : l'emetteur est le poste lui-meme.
    // X509_set_*_name() duplique en interne le X509_NAME fourni, donc on
    // peut liberer notre copie locale juste apres.
    X509_set_subject_name(cert, name);
    X509_set_issuer_name(cert, name);
    X509_NAME_free(name);

    if (X509_sign(cert, pkey, EVP_sha256()) == 0) {
        qWarning() << "SecurityService: signature du certificat echouee:" << opensslLastError();
        X509_free(cert);
        EVP_PKEY_free(pkey);
        return false;
    }

    if (!writePemFiles(pkey, cert)) {
        X509_free(cert);
        EVP_PKEY_free(pkey);
        return false;
    }

    m_pkey = pkey;
    m_cert = cert;
    return true;
}

bool SecurityService::writePemFiles(EVP_PKEY *pkey, X509 *cert) const
{
    QDir().mkpath(m_storageDir);

    BIO *keyBio = BIO_new(BIO_s_mem());
    BIO *certBio = BIO_new(BIO_s_mem());
    if (!keyBio || !certBio) {
        if (keyBio) BIO_free(keyBio);
        if (certBio) BIO_free(certBio);
        return false;
    }

    // Cle privee non chiffree sur disque : la confidentialite du fichier
    // repose sur les permissions restrictives appliquees ci-dessous
    // (proprietaire uniquement), le repertoire de donnees applicatif
    // n'etant lui-meme accessible qu'a l'utilisateur courant.
    const bool keyOk = PEM_write_bio_PrivateKey(keyBio, pkey, nullptr, nullptr, 0, nullptr, nullptr) == 1;
    const bool certOk = PEM_write_bio_X509(certBio, cert) == 1;

    bool written = false;
    if (keyOk && certOk) {
        char *keyData = nullptr;
        char *certData = nullptr;
        const long keyLen = BIO_get_mem_data(keyBio, &keyData);
        const long certLen = BIO_get_mem_data(certBio, &certData);

        QFile keyFile(privateKeyPath());
        QFile certFile(certificatePath());

        if (keyLen > 0 && certLen > 0
            && keyFile.open(QIODevice::WriteOnly | QIODevice::Truncate)
            && certFile.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
            keyFile.write(keyData, keyLen);
            certFile.write(certData, certLen);
            keyFile.close();
            certFile.close();
            written = true;
        }
    }

    BIO_free(keyBio);
    BIO_free(certBio);

    if (!written) {
        qWarning() << "SecurityService: ecriture des fichiers cle/certificat impossible dans" << m_storageDir;
        return false;
    }

    // Stockage securise local : la cle privee ne doit etre lisible/ecrivable
    // que par le proprietaire du fichier.
    applyRestrictivePermissions(privateKeyPath());
    applyRestrictivePermissions(certificatePath());

    return true;
}

void SecurityService::applyRestrictivePermissions(const QString &filePath) const
{
    // Sur Linux/macOS, ceci retire effectivement les droits groupe/autre
    // (permissions POSIX classiques : seul le proprietaire garde
    // lecture/ecriture). Sur Windows, NTFS n'a pas de notion
    // owner/group/other : Qt traduit au mieux vers les ACL NTFS, mais la
    // protection reelle contre les autres comptes Windows necessiterait de
    // manipuler les ACL directement (hors perimetre de cette issue). La
    // confidentialite y repose surtout sur le fait que le dossier de
    // donnees applicatif (AppDataLocation) est deja prive a l'utilisateur
    // Windows courant par defaut.
    QFile file(filePath);
    file.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner);
}

} // namespace network
