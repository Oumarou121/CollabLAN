#include "TrustedPeerStore.h"

#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>

namespace network {

namespace {
constexpr char kFileName[] = "trusted_peers.json";

QString normalizeFingerprint(const QString &fingerprint)
{
    return fingerprint.trimmed().toLower();
}
} // namespace

TrustedPeerStore::TrustedPeerStore(const QString &storageDir)
    : m_storageDir(storageDir)
{
}

QString TrustedPeerStore::filePath() const
{
    return QDir(m_storageDir).filePath(QString::fromLatin1(kFileName));
}

bool TrustedPeerStore::load()
{
    m_peers.clear();

    QFile file(filePath());
    if (!file.exists()) {
        // Aucune machine autorisee pour l'instant : etat initial valide.
        return true;
    }

    if (!file.open(QIODevice::ReadOnly))
        return false;

    const QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
    file.close();

    if (!doc.isArray())
        return false;

    for (const QJsonValue &value : doc.array()) {
        const QJsonObject obj = value.toObject();
        const QString fingerprint = normalizeFingerprint(obj.value(QStringLiteral("fingerprint")).toString());
        if (fingerprint.isEmpty())
            continue;

        TrustedPeer peer;
        peer.fingerprintSha256 = fingerprint;
        peer.label = obj.value(QStringLiteral("label")).toString();
        peer.trustedAt = QDateTime::fromString(obj.value(QStringLiteral("trustedAt")).toString(), Qt::ISODate);

        m_peers.insert(fingerprint, peer);
    }

    return true;
}

bool TrustedPeerStore::save() const
{
    QDir().mkpath(m_storageDir);

    QJsonArray array;
    for (const TrustedPeer &peer : m_peers) {
        QJsonObject obj;
        obj.insert(QStringLiteral("fingerprint"), peer.fingerprintSha256);
        obj.insert(QStringLiteral("label"), peer.label);
        obj.insert(QStringLiteral("trustedAt"), peer.trustedAt.toString(Qt::ISODate));
        array.append(obj);
    }

    QFile file(filePath());
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate))
        return false;

    file.write(QJsonDocument(array).toJson(QJsonDocument::Indented));
    file.close();
    return true;
}

bool TrustedPeerStore::isTrusted(const QString &fingerprintSha256) const
{
    return m_peers.contains(normalizeFingerprint(fingerprintSha256));
}

void TrustedPeerStore::trust(const QString &fingerprintSha256, const QString &label)
{
    const QString key = normalizeFingerprint(fingerprintSha256);
    if (key.isEmpty())
        return;

    TrustedPeer peer = m_peers.value(key);
    peer.fingerprintSha256 = key;
    peer.label = label;
    if (!peer.trustedAt.isValid())
        peer.trustedAt = QDateTime::currentDateTimeUtc();

    m_peers.insert(key, peer);
    save();
}

void TrustedPeerStore::revoke(const QString &fingerprintSha256)
{
    if (m_peers.remove(normalizeFingerprint(fingerprintSha256)))
        save();
}

QStringList TrustedPeerStore::fingerprints() const
{
    return m_peers.keys();
}

QList<TrustedPeer> TrustedPeerStore::peers() const
{
    return m_peers.values();
}

} // namespace network
