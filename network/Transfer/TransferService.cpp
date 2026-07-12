#include "TransferService.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>

namespace network {

TransferService::TransferService(QObject *parent)
    : QObject(parent)
{
}

TransferService::~TransferService() = default;

bool TransferService::sendFileInChunks(const QString &filePath,
                                       const ChunkSender &chunkSender,
                                       qint64 startOffset,
                                       qint64 chunkSize)
{
    QFile file(filePath);
    if (!file.open(QIODevice::ReadOnly)) {
        m_lastError = QStringLiteral("Impossible d'ouvrir le fichier pour l'envoi : %1").arg(filePath);
        return false;
    }

    const qint64 totalSize = file.size();
    if (startOffset > 0 && !file.seek(startOffset)) {
        m_lastError = QStringLiteral("Impossible de reprendre a l'offset %1 pour %2").arg(startOffset).arg(filePath);
        return false;
    }

    // Fichier vide : un unique morceau vide marque la fin du transfert.
    if (totalSize == 0) {
        if (!chunkSender(QByteArray(), 0, true)) {
            m_lastError = QStringLiteral("Envoi interrompu par le destinataire.");
            return false;
        }
        emit progressChanged(filePath, 0, 0);
        return true;
    }

    qint64 offset = startOffset;
    while (offset < totalSize) {
        const QByteArray data = file.read(chunkSize);
        if (data.isEmpty()) {
            break;
        }
        offset += data.size();
        const bool isLast = offset >= totalSize;

        if (!chunkSender(data, offset - data.size(), isLast)) {
            m_lastError = QStringLiteral("Envoi interrompu par le destinataire.");
            return false;
        }
        emit progressChanged(filePath, offset, totalSize);
    }

    return true;
}

bool TransferService::receiveChunk(const QString &destFilePath, qint64 offset, const QByteArray &data)
{
    const QFileInfo info(destFilePath);
    QDir parentDir = info.dir();
    if (!parentDir.exists() && !parentDir.mkpath(QStringLiteral("."))) {
        m_lastError = QStringLiteral("Impossible de creer le dossier de destination : %1").arg(parentDir.path());
        return false;
    }

    QFile file(destFilePath);
    // QIODevice::ReadWrite conserve le contenu existant (necessaire pour
    // ecrire a un offset > 0 lors d'une reprise) ; Truncate uniquement
    // au tout premier morceau (offset == 0).
    QIODevice::OpenMode mode = QIODevice::ReadWrite;
    if (offset == 0) {
        mode |= QIODevice::Truncate;
    }
    if (!file.open(mode)) {
        m_lastError = QStringLiteral("Impossible d'ecrire le fichier de destination : %1").arg(destFilePath);
        return false;
    }

    if (!file.seek(offset)) {
        m_lastError = QStringLiteral("Impossible de se positionner a l'offset %1 dans %2").arg(offset).arg(destFilePath);
        return false;
    }

    if (!data.isEmpty() && file.write(data) != data.size()) {
        m_lastError = QStringLiteral("Ecriture incomplete pour %1").arg(destFilePath);
        return false;
    }

    return true;
}

qint64 TransferService::fileSize(const QString &filePath)
{
    return QFileInfo(filePath).size();
}

QString TransferService::lastError() const
{
    return m_lastError;
}

} // namespace network
