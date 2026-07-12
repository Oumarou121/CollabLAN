#include "SyncProtocol.h"

#include <QJsonArray>
#include <QJsonDocument>

namespace network {
namespace SyncProtocol {

namespace {
constexpr const char *kTypeKey = "type";
}

QString messageTypeToString(MessageType type)
{
    switch (type) {
    case MessageType::Hello:
        return QStringLiteral("HELLO");
    case MessageType::SyncRequest:
        return QStringLiteral("SYNC_REQUEST");
    case MessageType::SyncResponse:
        return QStringLiteral("SYNC_RESPONSE");
    case MessageType::FileInfo:
        return QStringLiteral("FILE_INFO");
    case MessageType::FileRequest:
        return QStringLiteral("FILE_REQUEST");
    case MessageType::FileChunk:
        return QStringLiteral("FILE_CHUNK");
    case MessageType::DeleteFile:
        return QStringLiteral("DELETE_FILE");
    case MessageType::RenameFile:
        return QStringLiteral("RENAME_FILE");
    case MessageType::SyncFinished:
        return QStringLiteral("SYNC_FINISHED");
    case MessageType::Unknown:
        break;
    }
    return QStringLiteral("UNKNOWN");
}

MessageType messageTypeFromString(const QString &value)
{
    if (value == QStringLiteral("HELLO")) return MessageType::Hello;
    if (value == QStringLiteral("SYNC_REQUEST")) return MessageType::SyncRequest;
    if (value == QStringLiteral("SYNC_RESPONSE")) return MessageType::SyncResponse;
    if (value == QStringLiteral("FILE_INFO")) return MessageType::FileInfo;
    if (value == QStringLiteral("FILE_REQUEST")) return MessageType::FileRequest;
    if (value == QStringLiteral("FILE_CHUNK")) return MessageType::FileChunk;
    if (value == QStringLiteral("DELETE_FILE")) return MessageType::DeleteFile;
    if (value == QStringLiteral("RENAME_FILE")) return MessageType::RenameFile;
    if (value == QStringLiteral("SYNC_FINISHED")) return MessageType::SyncFinished;
    return MessageType::Unknown;
}

QJsonObject makeHello(const QString &machineId, const QString &machineName)
{
    return QJsonObject{
        {kTypeKey, messageTypeToString(MessageType::Hello)},
        {QStringLiteral("machineId"), machineId},
        {QStringLiteral("machineName"), machineName},
    };
}

QJsonObject makeSyncRequest(const QString &folder)
{
    return QJsonObject{
        {kTypeKey, messageTypeToString(MessageType::SyncRequest)},
        {QStringLiteral("folder"), folder},
    };
}

QJsonObject makeSyncResponse(const QString &folder, const QJsonArray &files)
{
    return QJsonObject{
        {kTypeKey, messageTypeToString(MessageType::SyncResponse)},
        {QStringLiteral("folder"), folder},
        {QStringLiteral("files"), files},
    };
}

QJsonObject makeFileInfo(const QString &folder,
                         const QString &path,
                         const QString &hash,
                         qint64 size,
                         int version)
{
    return QJsonObject{
        {kTypeKey, messageTypeToString(MessageType::FileInfo)},
        {QStringLiteral("folder"), folder},
        {QStringLiteral("path"), path},
        {QStringLiteral("hash"), hash},
        {QStringLiteral("size"), size},
        {QStringLiteral("version"), version},
    };
}

QJsonObject makeFileRequest(const QString &folder, const QString &path, qint64 offset)
{
    return QJsonObject{
        {kTypeKey, messageTypeToString(MessageType::FileRequest)},
        {QStringLiteral("folder"), folder},
        {QStringLiteral("path"), path},
        {QStringLiteral("offset"), offset},
    };
}

QJsonObject makeFileChunk(const QString &folder,
                          const QString &path,
                          qint64 offset,
                          const QByteArray &data,
                          bool isLast)
{
    return QJsonObject{
        {kTypeKey, messageTypeToString(MessageType::FileChunk)},
        {QStringLiteral("folder"), folder},
        {QStringLiteral("path"), path},
        {QStringLiteral("offset"), offset},
        {QStringLiteral("data"), QString::fromLatin1(data.toBase64())},
        {QStringLiteral("isLast"), isLast},
    };
}

QJsonObject makeDeleteFile(const QString &folder, const QString &path, int version)
{
    return QJsonObject{
        {kTypeKey, messageTypeToString(MessageType::DeleteFile)},
        {QStringLiteral("folder"), folder},
        {QStringLiteral("path"), path},
        {QStringLiteral("version"), version},
    };
}

QJsonObject makeRenameFile(const QString &folder,
                           const QString &oldPath,
                           const QString &newPath,
                           int version)
{
    return QJsonObject{
        {kTypeKey, messageTypeToString(MessageType::RenameFile)},
        {QStringLiteral("folder"), folder},
        {QStringLiteral("oldPath"), oldPath},
        {QStringLiteral("newPath"), newPath},
        {QStringLiteral("version"), version},
    };
}

QJsonObject makeSyncFinished(const QString &folder)
{
    return QJsonObject{
        {kTypeKey, messageTypeToString(MessageType::SyncFinished)},
        {QStringLiteral("folder"), folder},
    };
}

QByteArray serialize(const QJsonObject &message)
{
    QByteArray line = QJsonDocument(message).toJson(QJsonDocument::Compact);
    line.append('\n');
    return line;
}

std::optional<QJsonObject> takeNextMessage(QByteArray &buffer)
{
    const int newlineIndex = buffer.indexOf('\n');
    if (newlineIndex < 0) {
        return std::nullopt;
    }

    const QByteArray line = buffer.left(newlineIndex);
    buffer.remove(0, newlineIndex + 1);

    QJsonParseError error;
    const QJsonDocument doc = QJsonDocument::fromJson(line, &error);
    if (error.error != QJsonParseError::NoError || !doc.isObject()) {
        return QJsonObject();
    }
    return doc.object();
}

} // namespace SyncProtocol
} // namespace network
